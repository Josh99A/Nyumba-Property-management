// ignore_for_file: prefer_initializing_formals

import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/core/domain/id_generator.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/core/offline/uuid_id_generator.dart';
import 'package:nyumba_property_management/features/subscriptions/data/mappers/subscription_plan_mapper.dart';
import 'package:nyumba_property_management/features/subscriptions/domain/subscription_plan_draft.dart';
import 'package:nyumba_property_management/features/subscriptions/domain/subscription_plan_repository.dart';

final class SembastSubscriptionPlanRepository
    implements SubscriptionPlanRepository {
  SembastSubscriptionPlanRepository({
    required OfflineDatabase database,
    IdGenerator? idGenerator,
    Clock clock = const SystemClock(),
  }) : _database = database,
       _idGenerator = idGenerator ?? UuidIdGenerator(),
       _clock = clock;

  final OfflineDatabase _database;
  final IdGenerator _idGenerator;
  final Clock _clock;

  static const _tierOrder = ['Starter', 'Pro', 'Premium', 'Enterprise'];

  @override
  Future<SubscriptionPlanDraft> create(CreatePlanDraftInput input) async {
    final now = _clock.now().toUtc();
    final plan = SubscriptionPlanDraft(
      id: _idGenerator.generate(),
      tier: input.tier.trim(),
      tagline: input.tagline.trim(),
      monthlyPriceMinor: input.monthlyPriceMinor,
      unitLimit: input.unitLimit,
      staffLabel: input.staffLabel.trim(),
      listingsLabel: input.listingsLabel.trim(),
      support: input.support.trim(),
      subscribers: input.subscribers,
      recommended: input.recommended,
      enabled: input.enabled,
      createdAt: now,
      updatedAt: now,
      syncMetadata: const SyncMetadata.pending(),
    );
    await _database.putEntityAndEnqueue(
      entityType: OfflineEntityType.subscriptionPlan,
      entityId: plan.id,
      entity: SubscriptionPlanMapper.toJson(plan),
      mutationId: _idGenerator.generate(),
      operation: OutboxOperation.create,
      createdAt: now,
      createOnly: true,
    );
    return plan;
  }

  @override
  Future<SubscriptionPlanDraft> update(UpdatePlanDraftInput input) async {
    final current = await getById(input.planId);
    if (current == null) {
      throw EntityNotFoundException('subscription plan', input.planId);
    }
    final now = _clock.now().toUtc();
    final updated = current.copyWith(
      monthlyPriceMinor: input.monthlyPriceMinor,
      unitLimit: input.unitLimit,
      enabled: input.enabled,
      updatedAt: now,
      syncMetadata: current.syncMetadata.markPending(),
    );
    await _database.putEntityAndEnqueue(
      entityType: OfflineEntityType.subscriptionPlan,
      entityId: updated.id,
      entity: SubscriptionPlanMapper.toJson(updated),
      mutationId: _idGenerator.generate(),
      operation: OutboxOperation.update,
      createdAt: now,
    );
    return updated;
  }

  @override
  Future<List<SubscriptionPlanDraft>> getAll() async => _sort(
    (await _database.readEntities(
      OfflineEntityType.subscriptionPlan,
    )).map(SubscriptionPlanMapper.fromJson),
  );

  @override
  Future<SubscriptionPlanDraft?> getById(String id) async {
    final json = await _database.readEntity(
      OfflineEntityType.subscriptionPlan,
      id,
    );
    return json == null ? null : SubscriptionPlanMapper.fromJson(json);
  }

  @override
  Stream<List<SubscriptionPlanDraft>> watchAll() => _database
      .watchEntities(OfflineEntityType.subscriptionPlan)
      .map((items) => _sort(items.map(SubscriptionPlanMapper.fromJson)));

  static List<SubscriptionPlanDraft> _sort(
    Iterable<SubscriptionPlanDraft> items,
  ) {
    final result = items.toList(growable: false);
    result.sort((left, right) {
      final leftIndex = _tierOrder.indexOf(left.tier);
      final rightIndex = _tierOrder.indexOf(right.tier);
      return (leftIndex < 0 ? _tierOrder.length : leftIndex).compareTo(
        rightIndex < 0 ? _tierOrder.length : rightIndex,
      );
    });
    return result;
  }
}
