import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/aggregate_sync_status.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/features/admin/data/sembast_admin_repository.dart';
import 'package:nyumba_property_management/features/admin/domain/managed_user.dart';
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

  test('the account directory stays on the device and admits it', () async {
    final database = await openDatabase('admin-ops.db');
    addTearDown(database.close);
    final users = SembastManagedUserRepository(database: database);
    final audit = SembastAdminActionRepository(database: database);

    final user = await users.invite(
      const InviteManagedUserInput(
        name: 'Sandra Nakato',
        email: 'sandra@acaciahomes.ug',
        role: 'Landlord',
      ),
    );
    await users.changeStatus(
      userId: user.id,
      status: ManagedUserStatus.suspended,
    );
    await audit.append(
      action: 'Suspended account',
      targetUserId: user.id,
      targetName: user.name,
      performedBy: 'Nyumba Admin',
    );

    // These records are keyed by a client UUID, while the server addresses
    // accounts by Firebase UID, so no command can accept them. Enqueueing them
    // anyway produced mutations that failed permanently and silently.
    expect(
      await database.outboxCount(),
      0,
      reason: 'a record no command can accept must not claim it will sync',
    );

    final stored = await users.getById(user.id);
    expect(stored?.status, ManagedUserStatus.suspended);
    expect(stored?.syncMetadata.state, EntitySyncState.localOnly);
    expect(
      stored?.syncMetadata.needsSync,
      isFalse,
      reason: 'local-only is a settled state, not a promise of a later sync',
    );
  });

  test('the account directory no longer collides with user settings', () async {
    final database = await openDatabase('admin-store-split.db');
    addTearDown(database.close);
    final users = SembastManagedUserRepository(database: database);

    await users.invite(
      const InviteManagedUserInput(
        name: 'Sandra Nakato',
        email: 'sandra@acaciahomes.ug',
        role: 'Landlord',
      ),
    );
    // The signed-in admin's own profile, which SembastUserSettingsRepository
    // writes under OfflineEntityType.userProfile. Both once shared the
    // `user_profiles` store, so reading the directory back parsed this record
    // as a ManagedUser and threw.
    await database.putLocalEntity(
      entityType: OfflineEntityType.userProfile,
      entityId: 'admin-uid',
      entity: const <String, Object?>{
        'userId': 'admin-uid',
        'displayName': 'Nyumba Admin',
        'email': 'admin@nyumba.ug',
      },
      reason: LocalOnlyReason.localWorkspaceOnly,
    );

    final directory = await users.getAll();
    expect(directory, hasLength(1));
    expect(directory.single.name, 'Sandra Nakato');
  });

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
