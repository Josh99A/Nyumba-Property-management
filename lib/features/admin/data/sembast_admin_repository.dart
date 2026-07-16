// ignore_for_file: prefer_initializing_formals

import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/core/domain/id_generator.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/uuid_id_generator.dart';
import 'package:nyumba_property_management/features/admin/data/mappers/admin_mappers.dart';
import 'package:nyumba_property_management/features/admin/domain/admin_action.dart';
import 'package:nyumba_property_management/features/admin/domain/admin_repository.dart';
import 'package:nyumba_property_management/features/admin/domain/managed_user.dart';

/// The admin account directory.
///
/// Local-only, deliberately. Every record here is keyed by a client-generated
/// UUID, whereas the server identifies accounts by Firebase UID: `landlordId`
/// on every canonical document *is* the owner's UID, and the audited admin
/// commands (`landlord.approve` / `landlord.suspend` / `landlord.reinstate`)
/// take that UID as their aggregate ID. A UUID minted on this device names
/// nobody on the server, so these records cannot address a real account, and
/// there is no command at all for creating a user with an arbitrary role —
/// provisioning runs through the audited ops scripts in `firebase/functions/
/// scripts/`.
///
/// This previously enqueued outbox entries anyway, which failed permanently and
/// invisibly. Rebuilding the directory on pulled `users`/`landlordAccounts`
/// documents keyed by UID is the real fix; until then it must not pretend to
/// sync.
final class SembastManagedUserRepository implements ManagedUserRepository {
  SembastManagedUserRepository({
    required OfflineDatabase database,
    IdGenerator? idGenerator,
    Clock clock = const SystemClock(),
  }) : _database = database,
       _idGenerator = idGenerator ?? UuidIdGenerator(),
       _clock = clock;

  final OfflineDatabase _database;
  final IdGenerator _idGenerator;
  final Clock _clock;

  @override
  Future<ManagedUser> invite(InviteManagedUserInput input) async {
    final now = _clock.now().toUtc();
    final user = ManagedUser(
      id: _idGenerator.generate(),
      reference: 'USR-${now.millisecondsSinceEpoch % 10000}',
      name: input.name.trim(),
      email: input.email.trim(),
      role: input.role.trim(),
      location: input.location.trim(),
      status: ManagedUserStatus.invited,
      lastActiveLabel: 'Invitation pending',
      joinedLabel: 'Invited ${now.day}/${now.month}/${now.year}',
      createdAt: now,
      updatedAt: now,
      syncMetadata: const SyncMetadata.local(),
    );
    await _database.putLocalEntity(
      entityType: OfflineEntityType.managedUser,
      entityId: user.id,
      entity: ManagedUserMapper.toJson(user),
      reason: LocalOnlyReason.localWorkspaceOnly,
      createOnly: true,
    );
    return user;
  }

  @override
  Future<ManagedUser> changeStatus({
    required String userId,
    required ManagedUserStatus status,
  }) async {
    final current = await getById(userId);
    if (current == null) {
      throw EntityNotFoundException('user account', userId);
    }
    final now = _clock.now().toUtc();
    final updated = current.copyWith(
      status: status,
      updatedAt: now,
      syncMetadata: const SyncMetadata.local(),
    );
    await _database.putLocalEntity(
      entityType: OfflineEntityType.managedUser,
      entityId: updated.id,
      entity: ManagedUserMapper.toJson(updated),
      reason: LocalOnlyReason.localWorkspaceOnly,
    );
    return updated;
  }

  @override
  Future<List<ManagedUser>> getAll() async {
    final result = (await _database.readEntities(
      OfflineEntityType.managedUser,
    )).map(ManagedUserMapper.fromJson).toList(growable: false);
    result.sort((left, right) => left.name.compareTo(right.name));
    return result;
  }

  @override
  Future<ManagedUser?> getById(String id) async {
    final json = await _database.readEntity(OfflineEntityType.managedUser, id);
    return json == null ? null : ManagedUserMapper.fromJson(json);
  }

  @override
  Stream<List<ManagedUser>> watchAll() =>
      _database.watchEntities(OfflineEntityType.managedUser).map((items) {
        final result = items
            .map(ManagedUserMapper.fromJson)
            .toList(growable: false);
        result.sort((left, right) => left.name.compareTo(right.name));
        return result;
      });
}

/// The admin audit trail shown in-app.
///
/// Local-only for the same reason as [SembastManagedUserRepository]: it records
/// actions against UUID-keyed directory entries, and the server writes its own
/// authoritative `auditLogs` inside each admin command's transaction. That
/// server-side log is the real audit record — it is admin-read-only by rule and
/// cannot be authored from a device, which is the entire point of an audit log.
/// Shipping these entries would not add to it; it would only invent a second,
/// client-authored history of events that may never have happened.
final class SembastAdminActionRepository implements AdminActionRepository {
  SembastAdminActionRepository({
    required OfflineDatabase database,
    IdGenerator? idGenerator,
    Clock clock = const SystemClock(),
  }) : _database = database,
       _idGenerator = idGenerator ?? UuidIdGenerator(),
       _clock = clock;

  final OfflineDatabase _database;
  final IdGenerator _idGenerator;
  final Clock _clock;

  @override
  Future<AdminActionRecord> append({
    required String action,
    required String targetUserId,
    required String targetName,
    required String performedBy,
  }) async {
    final now = _clock.now().toUtc();
    final record = AdminActionRecord(
      id: _idGenerator.generate(),
      reference:
          'AUD-${now.year}-'
          '${(now.millisecondsSinceEpoch % 10000).toString().padLeft(4, '0')}',
      action: action.trim(),
      targetUserId: targetUserId,
      targetName: targetName.trim(),
      performedBy: performedBy.trim(),
      performedAt: now,
      createdAt: now,
      syncMetadata: const SyncMetadata.local(),
    );
    await _database.putLocalEntity(
      entityType: OfflineEntityType.adminAction,
      entityId: record.id,
      entity: AdminActionMapper.toJson(record),
      reason: LocalOnlyReason.localWorkspaceOnly,
      createOnly: true,
    );
    return record;
  }

  @override
  Future<List<AdminActionRecord>> getAll() async {
    final result = (await _database.readEntities(
      OfflineEntityType.adminAction,
    )).map(AdminActionMapper.fromJson).toList(growable: false);
    result.sort((left, right) => right.performedAt.compareTo(left.performedAt));
    return result;
  }

  @override
  Stream<List<AdminActionRecord>> watchAll() =>
      _database.watchEntities(OfflineEntityType.adminAction).map((items) {
        final result = items
            .map(AdminActionMapper.fromJson)
            .toList(growable: false);
        result.sort(
          (left, right) => right.performedAt.compareTo(left.performedAt),
        );
        return result;
      });
}
