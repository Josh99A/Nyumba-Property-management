// ignore_for_file: prefer_initializing_formals

import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/core/domain/id_generator.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/core/offline/uuid_id_generator.dart';
import 'package:nyumba_property_management/features/portfolio/data/mappers/property_mapper.dart';
import 'package:nyumba_property_management/features/portfolio/data/mappers/unit_mapper.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit_repository.dart';

final class SembastUnitRepository implements UnitRepository {
  SembastUnitRepository({
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
  Future<Unit> create(CreateUnitInput input) async {
    input.validate();
    final propertyJson = await _database.readEntity(
      OfflineEntityType.property,
      input.propertyId,
    );
    if (propertyJson == null) {
      throw EntityNotFoundException('property', input.propertyId);
    }
    final property = PropertyMapper.fromJson(propertyJson);
    if (property.isArchived) {
      throw DomainValidationException(<String, String>{
        'propertyId': 'must reference an active property',
      });
    }
    if (property.landlordId != input.landlordId) {
      throw DomainValidationException(<String, String>{
        'landlordId': 'must own the referenced property',
      });
    }

    final now = _clock.now().toUtc();
    final unit = Unit(
      id: _idGenerator.generate(),
      propertyId: input.propertyId,
      landlordId: input.landlordId,
      label: input.label.trim(),
      type: input.type,
      status: input.status,
      monthlyRentMinor: input.monthlyRentMinor,
      currency: input.currency,
      bedrooms: input.bedrooms,
      bathrooms: input.bathrooms,
      floor: input.floor,
      description: _optional(input.description),
      amenities: input.amenities.map((item) => item.trim()).toList(),
      createdAt: now,
      updatedAt: now,
      syncMetadata: const SyncMetadata.pending(),
    );
    await _database.putEntityAndEnqueue(
      entityType: OfflineEntityType.unit,
      entityId: unit.id,
      entity: UnitMapper.toJson(unit),
      mutationId: _idGenerator.generate(),
      operation: OutboxOperation.create,
      createdAt: now,
      createOnly: true,
      dependsOn: <AggregateReference>[
        AggregateReference(type: OfflineEntityType.property, id: property.id),
      ],
    );
    return unit;
  }

  @override
  Future<List<Unit>> getAll({
    String? propertyId,
    String? landlordId,
    bool includeArchived = false,
  }) async => _filterAndSort(
    (await _database.readEntities(
      OfflineEntityType.unit,
    )).map(UnitMapper.fromJson),
    propertyId: propertyId,
    landlordId: landlordId,
    includeArchived: includeArchived,
  );

  @override
  Future<Unit?> getById(String id) async {
    final json = await _database.readEntity(OfflineEntityType.unit, id);
    return json == null ? null : UnitMapper.fromJson(json);
  }

  @override
  Future<Unit> update(Unit unit) async {
    unit.validate();
    final current = await getById(unit.id);
    if (current == null) throw EntityNotFoundException('unit', unit.id);
    if (current.isArchived) {
      throw DomainValidationException(<String, String>{
        'unit': 'an archived rental space cannot be edited',
      });
    }
    final now = _clock.now().toUtc();
    final updated = Unit(
      id: current.id,
      propertyId: current.propertyId,
      landlordId: current.landlordId,
      label: unit.label.trim(),
      type: unit.type,
      status: unit.status,
      monthlyRentMinor: unit.monthlyRentMinor,
      currency: unit.currency,
      bedrooms: unit.bedrooms,
      bathrooms: unit.bathrooms,
      floor: unit.floor,
      description: _optional(unit.description),
      amenities: unit.amenities.map((item) => item.trim()).toList(),
      createdAt: current.createdAt,
      updatedAt: now,
      syncMetadata: current.syncMetadata.markPending(),
    );
    await _database.putEntityAndEnqueue(
      entityType: OfflineEntityType.unit,
      entityId: updated.id,
      entity: UnitMapper.toJson(updated),
      mutationId: _idGenerator.generate(),
      operation: OutboxOperation.update,
      createdAt: now,
      dependsOn: <AggregateReference>[
        AggregateReference(
          type: OfflineEntityType.property,
          id: current.propertyId,
        ),
      ],
    );
    return updated;
  }

  @override
  Future<Unit> archive(String unitId) async {
    final current = await getById(unitId);
    if (current == null) throw EntityNotFoundException('unit', unitId);
    if (current.isArchived) return current;
    if (current.status != UnitStatus.vacant) {
      throw DomainValidationException(<String, String>{
        'unit.status': 'only a vacant rental space can be archived',
      });
    }

    final now = _clock.now().toUtc();
    final archived = current.copyWith(
      isArchived: true,
      archivedAt: now,
      updatedAt: now,
      syncMetadata: current.syncMetadata.markPending(),
    );
    await _database.putEntityAndEnqueue(
      entityType: OfflineEntityType.unit,
      entityId: archived.id,
      entity: UnitMapper.toJson(archived),
      mutationId: _idGenerator.generate(),
      operation: OutboxOperation.delete,
      createdAt: now,
      dependsOn: <AggregateReference>[
        AggregateReference(
          type: OfflineEntityType.property,
          id: current.propertyId,
        ),
      ],
    );
    return archived;
  }

  @override
  Stream<List<Unit>> watchAll({
    String? propertyId,
    String? landlordId,
    bool includeArchived = false,
  }) => _database
      .watchEntities(OfflineEntityType.unit)
      .map(
        (items) => _filterAndSort(
          items.map(UnitMapper.fromJson),
          propertyId: propertyId,
          landlordId: landlordId,
          includeArchived: includeArchived,
        ),
      );

  @override
  Stream<Unit?> watchById(String id) => _database
      .watchEntity(OfflineEntityType.unit, id)
      .map((json) => json == null ? null : UnitMapper.fromJson(json));

  static List<Unit> _filterAndSort(
    Iterable<Unit> units, {
    String? propertyId,
    String? landlordId,
    bool includeArchived = false,
  }) {
    final result = units
        .where(
          (unit) =>
              (includeArchived ||
                  !unit.isArchived ||
                  unit.syncMetadata.state != EntitySyncState.synced) &&
              (propertyId == null || unit.propertyId == propertyId) &&
              (landlordId == null || unit.landlordId == landlordId),
        )
        .toList(growable: false);
    result.sort((left, right) => left.label.compareTo(right.label));
    return result;
  }

  static String? _optional(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
