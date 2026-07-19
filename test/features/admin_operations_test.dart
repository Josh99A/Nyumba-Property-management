import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/aggregate_sync_status.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/features/subscriptions/data/sembast_subscription_plan_repository.dart';
import 'package:nyumba_property_management/features/subscriptions/domain/subscription_plan_draft.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  Future<OfflineDatabase> openDatabase(String name) async {
    final database = OfflineDatabase(
      await databaseFactoryMemory.openDatabase(name),
    );
    await database.initialize();
    return database;
  }

  test('a local-only record never reports itself as synced', () {
    // With no outbox entry and no failure, a local-only record takes the same
    // path as a fully acknowledged one. Reporting `synced` there would claim
    // the server holds a record that was never sent anywhere — a worse lie than
    // the permanent "pending" this replaced.
    final status = resolveAggregateSyncStatus(
      entityType: OfflineEntityType.subscriptionPlan,
      entityId: 'plan-1',
      outbox: const <OutboxEntry>[],
      syncMetadata: const SyncMetadata.local(),
    );
    expect(status, AggregateSyncStatus.localOnly);
    expect(status, isNot(AggregateSyncStatus.synced));
  });

  test('plan drafts are local admin working state, not a sync intent', () async {
    final database = await openDatabase('plan-drafts.db');
    addTearDown(database.close);
    final plans = SembastSubscriptionPlanRepository(database: database);

    final starter = await plans.create(
      const CreatePlanDraftInput(
        tier: 'Starter',
        tagline: 'Individual landlords and small portfolios',
        monthlyPriceMinor: 8000000,
        unitLimit: 10,
        staffLabel: '1 landlord account',
        listingsLabel: 'Up to 3 active public listings',
        support: 'Email and help centre',
      ),
    );
    final updated = await plans.update(
      UpdatePlanDraftInput(planId: starter.id, unitLimit: 15, enabled: false),
    );

    expect(updated.unitLimit, 15);
    expect(updated.enabled, isFalse);
    // planCatalog is server-owned and denies every client write, so there is no
    // command these drafts could ever reach.
    expect(updated.syncMetadata.state, EntitySyncState.localOnly);
    expect(updated.syncMetadata.needsSync, isFalse);
    expect(await database.outboxCount(), 0);
  });
}
