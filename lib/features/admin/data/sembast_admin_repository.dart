// ignore_for_file: prefer_initializing_formals

import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/core/domain/id_generator.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/core/offline/uuid_id_generator.dart';
import 'package:nyumba_property_management/features/admin/data/mappers/admin_mappers.dart';
import 'package:nyumba_property_management/features/admin/domain/admin_action.dart';
import 'package:nyumba_property_management/features/admin/domain/admin_repository.dart';
import 'package:nyumba_property_management/features/admin/domain/managed_user.dart';

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
      syncMetadata: const SyncMetadata.pending(),
    );
    await _database.putEntityAndEnqueue(
      entityType: OfflineEntityType.userProfile,
      entityId: user.id,
      entity: ManagedUserMapper.toJson(user),
      mutationId: _idGenerator.generate(),
      operation: OutboxOperation.create,
      createdAt: now,
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
      syncMetadata: current.syncMetadata.markPending(),
    );
    await _database.putEntityAndEnqueue(
      entityType: OfflineEntityType.userProfile,
      entityId: updated.id,
      entity: ManagedUserMapper.toJson(updated),
      mutationId: _idGenerator.generate(),
      operation: OutboxOperation.update,
      createdAt: now,
    );
    return updated;
  }

  @override
  Future<List<ManagedUser>> getAll() async {
    final result = (await _database.readEntities(
      OfflineEntityType.userProfile,
    )).map(ManagedUserMapper.fromJson).toList(growable: false);
    result.sort((left, right) => left.name.compareTo(right.name));
    return result;
  }

  @override
  Future<ManagedUser?> getById(String id) async {
    final json = await _database.readEntity(OfflineEntityType.userProfile, id);
    return json == null ? null : ManagedUserMapper.fromJson(json);
  }

  @override
  Stream<List<ManagedUser>> watchAll() =>
      _database.watchEntities(OfflineEntityType.userProfile).map((items) {
        final result = items
            .map(ManagedUserMapper.fromJson)
            .toList(growable: false);
        result.sort((left, right) => left.name.compareTo(right.name));
        return result;
      });
}

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
      syncMetadata: const SyncMetadata.pending(),
    );
    await _database.putEntityAndEnqueue(
      entityType: OfflineEntityType.adminAction,
      entityId: record.id,
      entity: AdminActionMapper.toJson(record),
      mutationId: _idGenerator.generate(),
      operation: OutboxOperation.create,
      createdAt: now,
      createOnly: true,
      dependsOn: [
        AggregateReference(
          type: OfflineEntityType.userProfile,
          id: targetUserId,
        ),
      ],
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
