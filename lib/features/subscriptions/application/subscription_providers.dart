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
      if (status != 'active' && status != 'trialing') {
        yield EntitlementUnavailable('This subscription is $status.');
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
