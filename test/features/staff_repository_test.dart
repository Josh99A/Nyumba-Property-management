import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/features/staff/data/sembast_staff_repository.dart';
import 'package:nyumba_property_management/features/staff/domain/staff_permission.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  late OfflineDatabase database;
  late SembastStaffRepository repository;

  setUp(() async {
    database = OfflineDatabase(
      await databaseFactoryMemory.openDatabase('staff-repository.db'),
    );
    await database.initialize();
    repository = SembastStaffRepository(database);
  });

  tearDown(() => database.close());

  test(
    'reads current invites from the local projection newest first',
    () async {
      await _putInvite(
        database,
        id: 'older',
        email: 'older@example.test',
        createdAt: DateTime.utc(2026, 7, 20),
        permissions: const ['manageProperties'],
      );
      await _putInvite(
        database,
        id: 'newer',
        email: 'newer@example.test',
        createdAt: DateTime.utc(2026, 7, 21),
        permissions: const ['manageBilling', 'unknownPermission'],
        memberUid: 'staff-2',
      );
      await _putInvite(
        database,
        id: 'revoked',
        email: 'revoked@example.test',
        createdAt: DateTime.utc(2026, 7, 22),
        state: 'revoked',
      );

      final invites = await repository.watchInvites().first;
      expect(invites.map((invite) => invite.id), ['newer', 'older']);
      expect(invites.first.linked, isTrue);
      expect(invites.first.permissions, {StaffPermission.manageBilling});
    },
  );

  test('reads plan entitlements from the local public catalog', () async {
    await database.mergeRemoteEntity(
      entityType: OfflineEntityType.planCatalog,
      entityId: 'premium',
      entity: const <String, Object?>{
        'id': 'premium',
        'version': 4,
        'staffSeatLimit': 9,
        'customStaffRoles': true,
      },
    );

    final plan = await repository.watchPlan('premium').first;
    expect(plan, isNotNull);
    expect(plan!.seatLimit, 9);
    expect(plan.customRoles, isTrue);
    expect(await repository.watchPlan('starter').first, isNull);
  });

  test('rejects a fractional server seat limit', () async {
    await database.mergeRemoteEntity(
      entityType: OfflineEntityType.planCatalog,
      entityId: 'malformed',
      entity: const <String, Object?>{
        'id': 'malformed',
        'version': 1,
        'staffSeatLimit': 9.5,
        'customStaffRoles': true,
      },
    );

    expect(await repository.watchPlan('malformed').first, isNull);
  });
}

Future<void> _putInvite(
  OfflineDatabase database, {
  required String id,
  required String email,
  required DateTime createdAt,
  List<String> permissions = const [],
  String state = 'pending',
  String? memberUid,
}) => database.mergeRemoteEntity(
  entityType: OfflineEntityType.staffInvite,
  entityId: id,
  entity: <String, Object?>{
    'id': id,
    'version': 1,
    'email': email,
    'permissions': permissions,
    'inviteState': state,
    'memberUid': memberUid,
    'createdAt': createdAt.toIso8601String(),
  },
);
