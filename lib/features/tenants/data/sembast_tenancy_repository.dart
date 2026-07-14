// ignore_for_file: prefer_initializing_formals

import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/core/domain/id_generator.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/core/offline/uuid_id_generator.dart';
import 'package:nyumba_property_management/features/tenants/data/mappers/tenancy_mapper.dart';
import 'package:nyumba_property_management/features/tenants/domain/tenancy.dart';
import 'package:nyumba_property_management/features/tenants/domain/tenancy_repository.dart';

final class SembastTenancyRepository implements TenancyRepository {
  SembastTenancyRepository({
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
  Future<Tenancy> create(CreateTenancyInput input) async {
    final now = _clock.now().toUtc();
    final tenancy = Tenancy(
      id: _idGenerator.generate(),
      landlordId: input.landlordId.trim(),
      tenantUserId: _optional(input.tenantUserId),
      propertyId: _optional(input.propertyId),
      unitId: _optional(input.unitId),
      tenantName: input.tenantName.trim(),
      email: input.email.trim(),
      phone: input.phone.trim(),
      unitLabel: input.unitLabel.trim(),
      propertyName: input.propertyName.trim(),
      monthlyRentMinor: input.monthlyRentMinor,
      balanceMinor: input.openingBalanceMinor,
      leaseStart: input.leaseStart.toUtc(),
      leaseEnd: input.leaseEnd.toUtc(),
      status: TenancyStatus.active,
      createdAt: now,
      updatedAt: now,
      syncMetadata: const SyncMetadata.pending(),
    );
    await _database.putEntityAndEnqueue(
      entityType: OfflineEntityType.tenancy,
      entityId: tenancy.id,
      entity: TenancyMapper.toJson(tenancy),
      mutationId: _idGenerator.generate(),
      operation: OutboxOperation.create,
      createdAt: now,
      createOnly: true,
    );
    return tenancy;
  }

  @override
  Future<Tenancy> adjustBalance({
    required String tenancyId,
    required int deltaMinor,
  }) async {
    final current = await getById(tenancyId);
    if (current == null) {
      throw EntityNotFoundException('tenancy', tenancyId);
    }
    final now = _clock.now().toUtc();
    final next = (current.balanceMinor + deltaMinor).clamp(0, 1 << 62);
    final updated = current.copyWith(
      balanceMinor: next,
      updatedAt: now,
      syncMetadata: current.syncMetadata.markPending(),
    );
    await _database.putEntityAndEnqueue(
      entityType: OfflineEntityType.tenancy,
      entityId: updated.id,
      entity: TenancyMapper.toJson(updated),
      mutationId: _idGenerator.generate(),
      operation: OutboxOperation.update,
      createdAt: now,
    );
    return updated;
  }

  @override
  Future<List<Tenancy>> getAll({
    String? landlordId,
    String? tenantUserId,
  }) async => _filterAndSort(
    (await _database.readEntities(
      OfflineEntityType.tenancy,
    )).map(TenancyMapper.fromJson),
    landlordId,
    tenantUserId,
  );

  @override
  Future<Tenancy?> getById(String id) async {
    final json = await _database.readEntity(OfflineEntityType.tenancy, id);
    return json == null ? null : TenancyMapper.fromJson(json);
  }

  @override
  Stream<List<Tenancy>> watchAll({
    String? landlordId,
    String? tenantUserId,
  }) => _database
      .watchEntities(OfflineEntityType.tenancy)
      .map(
        (items) => _filterAndSort(
          items.map(TenancyMapper.fromJson),
          landlordId,
          tenantUserId,
        ),
      );

  static List<Tenancy> _filterAndSort(
    Iterable<Tenancy> items,
    String? landlordId,
    String? tenantUserId,
  ) {
    final result = items
        .where(
          (tenancy) =>
              (landlordId == null || tenancy.landlordId == landlordId) &&
              (tenantUserId == null || tenancy.tenantUserId == tenantUserId),
        )
        .toList(growable: false);
    result.sort((left, right) => left.tenantName.compareTo(right.tenantName));
    return result;
  }

  static String? _optional(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
