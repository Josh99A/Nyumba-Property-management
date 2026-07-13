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
  Future<List<Unit>> getAll({String? propertyId, String? landlordId}) async =>
      _filterAndSort(
        (await _database.readEntities(
          OfflineEntityType.unit,
        )).map(UnitMapper.fromJson),
        propertyId: propertyId,
        landlordId: landlordId,
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
  Stream<List<Unit>> watchAll({String? propertyId, String? landlordId}) =>
      _database
          .watchEntities(OfflineEntityType.unit)
          .map(
            (items) => _filterAndSort(
              items.map(UnitMapper.fromJson),
              propertyId: propertyId,
              landlordId: landlordId,
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
  }) {
    final result = units
        .where(
          (unit) =>
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
