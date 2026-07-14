import 'package:nyumba_property_management/core/offline/json_reader.dart';
import 'package:nyumba_property_management/core/offline/sync_metadata_mapper.dart';
import 'package:nyumba_property_management/features/subscriptions/domain/subscription_plan_draft.dart';

final class SubscriptionPlanMapper {
  const SubscriptionPlanMapper._();

  static Map<String, Object?> toJson(SubscriptionPlanDraft plan) =>
      <String, Object?>{
        'id': plan.id,
        'tier': plan.tier,
        'tagline': plan.tagline,
        'monthlyPriceMinor': plan.monthlyPriceMinor,
        'unitLimit': plan.unitLimit,
        'staffLabel': plan.staffLabel,
        'listingsLabel': plan.listingsLabel,
        'support': plan.support,
        'subscribers': plan.subscribers,
        'recommended': plan.recommended,
        'enabled': plan.enabled,
        'createdAt': plan.createdAt.toUtc().toIso8601String(),
        'updatedAt': plan.updatedAt.toUtc().toIso8601String(),
        'syncMetadata': SyncMetadataMapper.toJson(plan.syncMetadata),
      };

  static SubscriptionPlanDraft fromJson(Map<String, Object?> json) {
    final reader = JsonReader(json);
    return SubscriptionPlanDraft(
      id: reader.requiredString('id'),
      tier: reader.requiredString('tier'),
      tagline: reader.requiredString('tagline'),
      monthlyPriceMinor: reader.requiredInt('monthlyPriceMinor'),
      unitLimit: reader.requiredInt('unitLimit'),
      staffLabel: reader.requiredString('staffLabel'),
      listingsLabel: reader.requiredString('listingsLabel'),
      support: reader.requiredString('support'),
      subscribers: reader.optionalInt('subscribers') ?? 0,
      recommended: reader.optionalBool('recommended'),
      enabled: reader.optionalBool('enabled', fallback: true),
      createdAt: reader.requiredDate('createdAt'),
      updatedAt: reader.requiredDate('updatedAt'),
      syncMetadata: SyncMetadataMapper.fromJson(json['syncMetadata']),
    );
  }
}
