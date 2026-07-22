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
  // Only landlords hold a subscription at all, and there is nothing to read
  // without a configured Firebase project.
  if (session == null ||
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

/// When the current paid period ends, and — once it has lapsed — when the
/// grace window closes and the workspace locks.
///
/// An overdue subscription deliberately stays `active` through the grace
/// window, so this rides alongside the entitlement rather than replacing it:
/// the landlord keeps working while the deadline is shown.
final class SubscriptionRenewalState {
  const SubscriptionRenewalState({this.renewalDueAt, this.graceEndsAt});

  final DateTime? renewalDueAt;

  /// Non-null only while a payment is overdue.
  final DateTime? graceEndsAt;

  bool get isOverdue => graceEndsAt != null;

  /// Whole days until the workspace locks; negative once the deadline passes.
  int? get daysUntilLock => graceEndsAt == null
      ? null
      : graceEndsAt!.difference(DateTime.now()).inHours ~/ 24;
}

/// The signed-in landlord's renewal deadline, read live from the server-owned
/// subscription document. Empty for everyone else.
final subscriptionRenewalProvider = StreamProvider<SubscriptionRenewalState>((
  ref,
) async* {
  final session = ref.watch(sessionControllerProvider);
  if (session == null ||
      session.role != AppRole.landlord ||
      Firebase.apps.isEmpty) {
    yield const SubscriptionRenewalState();
    return;
  }
  try {
    await for (final snapshot
        in FirebaseFirestore.instance
            .collection('subscriptions')
            .doc(session.userId)
            .snapshots()) {
      final data = snapshot.data();
      yield SubscriptionRenewalState(
        renewalDueAt: (data?['renewalDueAt'] as Timestamp?)?.toDate(),
        graceEndsAt: (data?['graceEndsAt'] as Timestamp?)?.toDate(),
      );
    }
  } on FirebaseException {
    // A deadline we cannot read is one we must not assert.
    yield const SubscriptionRenewalState();
  }
});

/// One benefit line on a plan card. `implemented: false` marks a benefit the
/// plan is sold with but that has not shipped yet — the UI greys it out
/// instead of hiding it, so nobody pays for a promise they did not see.
final class PublicPlanFeature {
  const PublicPlanFeature({
    required this.id,
    required this.label,
    required this.implemented,
  });

  final String id;
  final String label;
  final bool implemented;
}

/// Public plan facts for the pre-payment subscription screen.
///
/// Read from `planCatalog/{tier}` — server-owned, exposed by rule only while
/// `isPublic == true`. Limits, prices, and benefit lists are never invented
/// on-device: a tier with no catalog entry renders without numbers rather
/// than with guessed ones.
final class PublicPlanFacts {
  const PublicPlanFacts({
    required this.tier,
    required this.displayName,
    required this.unitLimit,
    required this.activeListingLimit,
    required this.version,
    this.tagline,
    this.capacityLabel,
    this.monthlyPriceMinor,
    this.yearlyPriceMinor,
    this.includesTier,
    this.features = const <PublicPlanFeature>[],
  });

  final String tier;
  final String displayName;
  final int unitLimit;
  final int activeListingLimit;

  /// Catalog document version — the concurrency token `plan.update` checks.
  final int version;

  final String? tagline;

  /// Server-owned wording that replaces the numeric capacity line, e.g.
  /// Enterprise's custom limits.
  final String? capacityLabel;

  /// UGX minor units (x100); absent until the catalog is seeded with prices.
  final int? monthlyPriceMinor;
  final int? yearlyPriceMinor;

  /// Tier whose benefits this plan inherits ("Everything in X, plus").
  final String? includesTier;

  final List<PublicPlanFeature> features;

  /// Whole-percent saving of yearly billing against twelve monthly payments,
  /// or null when either price is missing or there is no saving to claim.
  int? get yearlySavingsPercent {
    final monthly = monthlyPriceMinor;
    final yearly = yearlyPriceMinor;
    if (monthly == null || yearly == null || monthly <= 0) return null;
    final saving = 100 - (yearly * 100 / (monthly * 12));
    final rounded = saving.round();
    return rounded > 0 ? rounded : null;
  }
}

List<PublicPlanFeature> _parsePlanFeatures(Object? raw) {
  if (raw is! List) return const <PublicPlanFeature>[];
  final features = <PublicPlanFeature>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final id = entry['id'];
    final label = entry['label'];
    if (id is! String || id.isEmpty || label is! String || label.isEmpty) {
      continue;
    }
    features.add(
      PublicPlanFeature(
        id: id,
        label: label,
        implemented: entry['implemented'] == true,
      ),
    );
  }
  return features;
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
        final version = data['version'];
        final monthlyPriceMinor = data['monthlyPriceMinor'];
        final yearlyPriceMinor = data['yearlyPriceMinor'];
        final includesTier = data['includesTier'];
        plans[document.id] = PublicPlanFacts(
          tier: document.id,
          displayName: displayName,
          unitLimit: unitLimit,
          activeListingLimit: activeListingLimit,
          version: version is int && version > 0 ? version : 1,
          tagline: tagline is String && tagline.isNotEmpty ? tagline : null,
          capacityLabel: capacityLabel is String && capacityLabel.isNotEmpty
              ? capacityLabel
              : null,
          monthlyPriceMinor: monthlyPriceMinor is int && monthlyPriceMinor >= 0
              ? monthlyPriceMinor
              : null,
          yearlyPriceMinor: yearlyPriceMinor is int && yearlyPriceMinor >= 0
              ? yearlyPriceMinor
              : null,
          includesTier: includesTier is String && includesTier.isNotEmpty
              ? includesTier
              : null,
          features: _parsePlanFeatures(data['features']),
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
    if (session == null || session.role != AppRole.landlord) {
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

final requestPlanUpgradeProvider = Provider<RequestPlanUpgrade>(
  RequestPlanUpgrade.new,
);

/// How a landlord chooses to pay for a plan change. Cash is verified by an
/// administrator; mobile money and card are electronic and auto-confirm the
/// moment a payment aggregator is connected (they fail closed until then).
enum UpgradeBillingChannel {
  mobileMoney('mobile_money'),
  card('card'),
  cash('cash');

  const UpgradeBillingChannel(this.wire);

  /// The value the `subscription.requestUpgrade` command expects.
  final String wire;

  bool get isElectronic => this != UpgradeBillingChannel.cash;
}

/// Records which tier an active landlord wants to move to and how they intend
/// to pay, through the server-authoritative `subscription.requestUpgrade`
/// command.
///
/// The paid-side mirror of [SelectSubscriptionPlan]: it never grants
/// entitlements. Cash parks the request for an administrator to activate after
/// verifying the money; mobile money and card are electronic and auto-confirm
/// through the aggregator's webhook — and fail closed with
/// `PAYMENT_PROVIDER_UNAVAILABLE` until one is connected, so a plan is never
/// upgraded against money that never moved.
class RequestPlanUpgrade {
  const RequestPlanUpgrade(this._ref);

  final Ref _ref;

  Future<void> call(String tier, UpgradeBillingChannel channel) async {
    final session = _ref.read(sessionControllerProvider);
    if (session == null || session.role != AppRole.landlord) {
      throw StateError('Sign in as a landlord to request an upgrade.');
    }
    if (Firebase.apps.isEmpty) {
      throw StateError('Connect to the internet to request an upgrade.');
    }
    final subscription = await FirebaseFirestore.instance
        .collection('subscriptions')
        .doc(session.userId)
        .get(const GetOptions(source: Source.server));
    final version = (subscription.data()?['version'] as num?)?.toInt();
    if (version == null) {
      throw StateError('Your subscription record could not be read.');
    }
    final gateway = await _ref.read(authCommandGatewayProvider.future);
    await gateway.sendCommand(
      type: 'subscription.requestUpgrade',
      aggregateId: session.userId,
      expectedVersion: version,
      payload: <String, Object?>{'tier': tier, 'billingChannel': channel.wire},
    );
  }
}

final updatePlanCatalogProvider = Provider<UpdatePlanCatalog>(
  UpdatePlanCatalog.new,
);

/// Super-admin editing of the server-owned plan catalog through the audited
/// `plan.update` command: prices, capacity limits, and which benefits are
/// flagged as implemented. Nothing changes locally — the catalog stream
/// re-emits once the server has accepted the edit.
class UpdatePlanCatalog {
  const UpdatePlanCatalog(this._ref);

  final Ref _ref;

  Future<void> call({
    required PublicPlanFacts current,
    int? monthlyPriceMinor,
    int? yearlyPriceMinor,
    int? unitLimit,
    int? activeListingLimit,
    String? tagline,
    List<PublicPlanFeature>? features,
  }) async {
    final session = _ref.read(sessionControllerProvider);
    if (session?.role != AppRole.superAdmin) {
      throw StateError('Only a super administrator can edit plans.');
    }
    final payload = <String, Object?>{
      'tier': current.tier,
      'expectedCatalogVersion': current.version,
      'monthlyPriceMinor': ?monthlyPriceMinor,
      'yearlyPriceMinor': ?yearlyPriceMinor,
      'unitLimit': ?unitLimit,
      'activeListingLimit': ?activeListingLimit,
      if (tagline != null && tagline.trim().isNotEmpty) 'tagline': tagline.trim(),
      if (features != null)
        'features': <Object?>[
          for (final feature in features)
            <String, Object?>{
              'id': feature.id,
              'label': feature.label,
              'implemented': feature.implemented,
            },
        ],
    };
    if (payload.length <= 2) {
      throw StateError('Change at least one plan detail before saving.');
    }
    final gateway = await _ref.read(authCommandGatewayProvider.future);
    await gateway.sendCommand(type: 'plan.update', payload: payload);
  }
}

final updatePlanDraftProvider = Provider<UpdatePlanDraft>(UpdatePlanDraft.new);

class UpdatePlanDraft {
  const UpdatePlanDraft(this._ref);

  final Ref _ref;

  Future<SubscriptionPlanDraft> call(UpdatePlanDraftInput input) async {
    final session = _ref.read(sessionControllerProvider);
    if (session == null ||
        !AuthorizationPolicy.allowsSession(
          session,
          AppResource.planCatalog,
          CrudOperation.update,
        )) {
      throw StateError('Administrator permission is required.');
    }
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.subscriptionPlans.update(input);
  }
}
