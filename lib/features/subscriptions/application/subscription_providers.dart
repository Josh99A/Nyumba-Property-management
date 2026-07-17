import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/authorization_policy.dart';
import '../../auth/domain/user_session.dart';
import '../domain/landlord_entitlement.dart';
import '../domain/subscription_plan_draft.dart';

final subscriptionPlansProvider = StreamProvider<List<SubscriptionPlanDraft>>((
  ref,
) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.subscriptionPlans.watchAll();
});

/// The signed-in landlord's plan, read live from server-owned documents.
///
/// Reads rather than syncs: `subscriptions/{uid}` and `planCatalog/{tier}` are
/// server-written and client-read-only by rule, so there is nothing to mirror
/// into the outbox. Both documents are readable by their owner under
/// `firestore.rules` — the subscription via `isSelf`, the catalog entry when
/// it is public.
///
/// Fails closed. A missing subscription, an unknown tier, or a malformed
/// catalog entry yields [EntitlementUnavailable] rather than a fallback plan;
/// the backend rejects those same cases with ENTITLEMENT_MISSING, and a client
/// that guessed a limit here would promise capacity the server then refuses.
final landlordEntitlementProvider = StreamProvider<EntitlementState>((
  ref,
) async* {
  final session = ref.watch(sessionControllerProvider);
  // Demo workspaces have no server documents behind them, and only landlords
  // hold a subscription at all.
  if (session == null ||
      session.isDemo ||
      session.role != AppRole.landlord ||
      Firebase.apps.isEmpty) {
    yield const EntitlementNotApplicable();
    return;
  }

  final firestore = FirebaseFirestore.instance;
  try {
    await for (final subscription
        in firestore
            .collection('subscriptions')
            .doc(session.userId)
            .snapshots()) {
      final data = subscription.data();
      if (!subscription.exists || data == null) {
        yield const EntitlementUnavailable(
          'No subscription on this account yet.',
        );
        continue;
      }
      final tier = data['tier'];
      final status = data['status'];
      if (tier is! String || tier.isEmpty || status is! String) {
        yield const EntitlementUnavailable('This subscription is incomplete.');
        continue;
      }
      if (status != 'active') {
        yield EntitlementUnavailable(switch (status) {
          'pending_payment' ||
          'trialing' => 'This subscription is awaiting payment confirmation.',
          'past_due' => 'This subscription payment is past due.',
          'canceled' => 'This subscription has been canceled.',
          'expired' => 'This subscription has expired.',
          _ => 'This subscription is not active.',
        });
        continue;
      }
      yield await _readPlan(firestore, tier: tier, status: status);
    }
  } on FirebaseException {
    // A denied or failed subscription stream fails closed, exactly like the
    // catalog read below: an AsyncError would leave screens with no
    // entitlement answer at all, and guessing a limit is not an option.
    yield const EntitlementUnavailable('Subscription status is unavailable.');
  }
});

Future<EntitlementState> _readPlan(
  FirebaseFirestore firestore, {
  required String tier,
  required String status,
}) async {
  try {
    final plan = await firestore.collection('planCatalog').doc(tier).get();
    final data = plan.data();
    if (!plan.exists || data == null) {
      return const EntitlementUnavailable('Plan details are unavailable.');
    }
    final unitLimit = data['unitLimit'];
    final activeListingLimit = data['activeListingLimit'];
    if (unitLimit is! int || activeListingLimit is! int) {
      return const EntitlementUnavailable('Plan details are unavailable.');
    }
    final displayName = data['displayName'];
    return EntitlementKnown(
      LandlordEntitlement(
        tier: tier,
        displayName: displayName is String && displayName.isNotEmpty
            ? displayName
            : tier,
        status: status,
        unitLimit: unitLimit,
        activeListingLimit: activeListingLimit,
      ),
    );
  } on FirebaseException {
    // A denied or offline catalog read is not a licence to invent a limit.
    return const EntitlementUnavailable('Plan details are unavailable.');
  }
}

/// Public plan facts for the pre-payment subscription screen.
///
/// Read from `planCatalog/{tier}` — server-owned, exposed by rule only while
/// `isPublic == true`. Limits are never invented on-device: a tier with no
/// catalog entry renders without numbers rather than with guessed ones.
final class PublicPlanFacts {
  const PublicPlanFacts({
    required this.tier,
    required this.displayName,
    required this.unitLimit,
    required this.activeListingLimit,
    this.tagline,
    this.capacityLabel,
  });

  final String tier;
  final String displayName;
  final int unitLimit;
  final int activeListingLimit;
  final String? tagline;

  /// Server-owned wording that replaces the numeric capacity line, e.g.
  /// Enterprise's custom limits.
  final String? capacityLabel;
}

/// The publicly advertised plans, keyed by tier ID. Empty while offline,
/// unseeded, or running without Firebase — the UI must say "unavailable"
/// instead of quoting a limit the server never published.
final publicPlanCatalogProvider = StreamProvider<Map<String, PublicPlanFacts>>((
  ref,
) async* {
  if (Firebase.apps.isEmpty) {
    yield const {};
    return;
  }
  try {
    // Rules permit a public list only when bounded to 20 documents.
    await for (final snapshot
        in FirebaseFirestore.instance
            .collection('planCatalog')
            .where('isPublic', isEqualTo: true)
            .limit(20)
            .snapshots()) {
      final plans = <String, PublicPlanFacts>{};
      for (final document in snapshot.docs) {
        final data = document.data();
        final displayName = data['displayName'];
        final unitLimit = data['unitLimit'];
        final activeListingLimit = data['activeListingLimit'];
        if (displayName is! String ||
            displayName.isEmpty ||
            unitLimit is! int ||
            activeListingLimit is! int) {
          continue;
        }
        final tagline = data['tagline'];
        final capacityLabel = data['capacityLabel'];
        plans[document.id] = PublicPlanFacts(
          tier: document.id,
          displayName: displayName,
          unitLimit: unitLimit,
          activeListingLimit: activeListingLimit,
          tagline: tagline is String && tagline.isNotEmpty ? tagline : null,
          capacityLabel: capacityLabel is String && capacityLabel.isNotEmpty
              ? capacityLabel
              : null,
        );
      }
      yield plans;
    }
  } on FirebaseException {
    yield const {};
  }
});

final selectSubscriptionPlanProvider = Provider<SelectSubscriptionPlan>(
  SelectSubscriptionPlan.new,
);

/// Records which plan the landlord intends to pay for, through the
/// server-authoritative `subscription.selectPlan` command.
///
/// Deliberately cannot touch status: only `subscription.confirmPayment`
/// (platform staff) or a future signed provider webhook opens a workspace,
/// so nothing on this path can be mistaken for payment.
class SelectSubscriptionPlan {
  const SelectSubscriptionPlan(this._ref);

  final Ref _ref;

  Future<void> call(String tier) async {
    final session = _ref.read(sessionControllerProvider);
    if (session == null || session.isDemo || session.role != AppRole.landlord) {
      throw StateError('Sign in as a landlord to choose a plan.');
    }
    if (Firebase.apps.isEmpty) {
      throw StateError('Connect to the internet to choose a plan.');
    }
    // The command is concurrency-checked against the server-owned subscription
    // document, which its owner may read.
    final subscription = await FirebaseFirestore.instance
        .collection('subscriptions')
        .doc(session.userId)
        .get(const GetOptions(source: Source.server));
    final version = (subscription.data()?['version'] as num?)?.toInt();
    if (version == null) {
      throw StateError(
        'Your subscription record is still being set up. Try again shortly.',
      );
    }
    final gateway = await _ref.read(authCommandGatewayProvider.future);
    await gateway.sendCommand(
      type: 'subscription.selectPlan',
      aggregateId: session.userId,
      expectedVersion: version,
      payload: <String, Object?>{'tier': tier},
    );
  }
}

final updatePlanDraftProvider = Provider<UpdatePlanDraft>(UpdatePlanDraft.new);

class UpdatePlanDraft {
  const UpdatePlanDraft(this._ref);

  final Ref _ref;

  Future<SubscriptionPlanDraft> call(UpdatePlanDraftInput input) async {
    final session = _ref.read(sessionControllerProvider);
    if (session == null ||
        !AuthorizationPolicy.allows(
          session.role,
          AppResource.planCatalog,
          CrudOperation.update,
        )) {
      throw StateError('Administrator permission is required.');
    }
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.subscriptionPlans.update(input);
  }
}
