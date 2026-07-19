import '../../../core/domain/domain_validation.dart';
import '../../../core/domain/sync_metadata.dart';

/// A local draft of one subscription tier's commercial terms. The server-owned
/// plan catalog remains authoritative; drafts sync as proposed configuration
/// and never grant entitlements by themselves.
final class SubscriptionPlanDraft {
  SubscriptionPlanDraft({
    required this.id,
    required this.tier,
    required this.tagline,
    required this.monthlyPriceMinor,
    required this.unitLimit,
    required this.staffLabel,
    required this.listingsLabel,
    required this.support,
    required this.subscribers,
    required this.recommended,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
    required this.syncMetadata,
  }) {
    validate();
  }

  final String id;

  /// Tier name such as `Starter`, `Pro`, `Premium`, or `Enterprise`.
  final String tier;
  final String tagline;

  /// Zero represents custom, contract-based pricing.
  final int monthlyPriceMinor;
  final int unitLimit;
  final String staffLabel;
  final String listingsLabel;
  final String support;

  /// Subscriber count carried on a plan draft; server-owned in practice.
  final int subscribers;
  final bool recommended;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncMetadata syncMetadata;

  void validate() {
    DomainValidation.check(<String, String?>{
      'tier': DomainValidation.requiredText(tier, maxLength: 40),
      'tagline': DomainValidation.requiredText(tagline, maxLength: 120),
      'monthlyPriceMinor': DomainValidation.positiveMinorUnits(
        monthlyPriceMinor,
        allowZero: true,
      ),
      'unitLimit': unitLimit < 1 ? 'must allow at least one unit' : null,
      'staffLabel': DomainValidation.requiredText(staffLabel, maxLength: 80),
      'listingsLabel': DomainValidation.requiredText(
        listingsLabel,
        maxLength: 80,
      ),
      'support': DomainValidation.requiredText(support, maxLength: 80),
      'subscribers': DomainValidation.nonNegativeInt(subscribers),
    });
  }

  SubscriptionPlanDraft copyWith({
    int? monthlyPriceMinor,
    int? unitLimit,
    bool? enabled,
    DateTime? updatedAt,
    SyncMetadata? syncMetadata,
  }) => SubscriptionPlanDraft(
    id: id,
    tier: tier,
    tagline: tagline,
    monthlyPriceMinor: monthlyPriceMinor ?? this.monthlyPriceMinor,
    unitLimit: unitLimit ?? this.unitLimit,
    staffLabel: staffLabel,
    listingsLabel: listingsLabel,
    support: support,
    subscribers: subscribers,
    recommended: recommended,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    syncMetadata: syncMetadata ?? this.syncMetadata,
  );
}

final class CreatePlanDraftInput {
  const CreatePlanDraftInput({
    required this.tier,
    required this.tagline,
    required this.monthlyPriceMinor,
    required this.unitLimit,
    required this.staffLabel,
    required this.listingsLabel,
    required this.support,
    this.subscribers = 0,
    this.recommended = false,
    this.enabled = true,
  });

  final String tier;
  final String tagline;
  final int monthlyPriceMinor;
  final int unitLimit;
  final String staffLabel;
  final String listingsLabel;
  final String support;
  final int subscribers;
  final bool recommended;
  final bool enabled;
}

final class UpdatePlanDraftInput {
  const UpdatePlanDraftInput({
    required this.planId,
    this.monthlyPriceMinor,
    this.unitLimit,
    this.enabled,
  });

  final String planId;
  final int? monthlyPriceMinor;
  final int? unitLimit;
  final bool? enabled;
}
