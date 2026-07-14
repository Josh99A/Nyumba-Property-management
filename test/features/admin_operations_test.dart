import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
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

  test(
    'audit records are ordered after the account change they describe',
    () async {
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
      final record = await audit.append(
        action: 'Suspended account',
        targetUserId: user.id,
        targetName: user.name,
        performedBy: 'Nyumba Admin',
      );

      final outbox = await database.readOutbox();
      final auditEntry = outbox.singleWhere(
        (entry) => entry.entityType == OfflineEntityType.adminAction,
      );
      final userMutationIds = outbox
          .where((entry) => entry.entityType == OfflineEntityType.userProfile)
          .map((entry) => entry.id)
          .toSet();
      expect(auditEntry.entityId, record.id);
      expect(
        auditEntry.dependencyIds.toSet().intersection(userMutationIds),
        isNotEmpty,
        reason:
            'audit history must never arrive before the change it describes',
      );

      final stored = await users.getById(user.id);
      expect(stored?.status, ManagedUserStatus.suspended);
    },
  );

  test(
    'plan draft updates persist atomically with their outbox command',
    () async {
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
      expect(updated.syncMetadata.needsSync, isTrue);
      expect(await database.outboxCount(), 2);
    },
  );
}
