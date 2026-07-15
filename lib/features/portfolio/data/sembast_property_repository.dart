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
import 'package:nyumba_property_management/features/portfolio/domain/property.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property_repository.dart';

final class SembastPropertyRepository implements PropertyRepository {
  SembastPropertyRepository({
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
  Future<Property> create(CreatePropertyInput input) async {
    input.validate();
    final now = _clock.now().toUtc();
    final property = Property(
      id: _idGenerator.generate(),
      landlordId: input.landlordId.trim(),
      name: input.name.trim(),
      addressLine: input.addressLine.trim(),
      city: input.city.trim(),
      country: input.country.trim(),
      description: _optional(input.description),
      imageUrls: input.imageUrls.map((item) => item.trim()).toList(),
      createdAt: now,
      updatedAt: now,
      syncMetadata: const SyncMetadata.pending(),
    );
    await _database.putEntityAndEnqueue(
      entityType: OfflineEntityType.property,
      entityId: property.id,
      entity: PropertyMapper.toJson(property),
      mutationId: _idGenerator.generate(),
      operation: OutboxOperation.create,
      createdAt: now,
      createOnly: true,
    );
    return property;
  }

  @override
  Future<List<Property>> getAll({String? landlordId}) async => _filterAndSort(
    (await _database.readEntities(
      OfflineEntityType.property,
    )).map(PropertyMapper.fromJson),
    landlordId,
  );

  @override
  Future<Property?> getById(String id) async {
    final json = await _database.readEntity(OfflineEntityType.property, id);
    return json == null ? null : PropertyMapper.fromJson(json);
  }

  @override
  Future<Property> update(Property property) async {
    property.validate();
    final current = await getById(property.id);
    if (current == null) {
      throw EntityNotFoundException('property', property.id);
    }
    final now = _clock.now().toUtc();
    final updated = Property(
      id: current.id,
      landlordId: current.landlordId,
      name: property.name.trim(),
      addressLine: property.addressLine.trim(),
      city: property.city.trim(),
      country: property.country.trim(),
      description: _optional(property.description),
      imageUrls: property.imageUrls.map((item) => item.trim()).toList(),
      createdAt: current.createdAt,
      updatedAt: now,
      syncMetadata: current.syncMetadata.markPending(),
    );
    await _database.putEntityAndEnqueue(
      entityType: OfflineEntityType.property,
      entityId: updated.id,
      entity: PropertyMapper.toJson(updated),
      mutationId: _idGenerator.generate(),
      operation: OutboxOperation.update,
      createdAt: now,
    );
    return updated;
  }

  @override
  Stream<List<Property>> watchAll({String? landlordId}) => _database
      .watchEntities(OfflineEntityType.property)
      .map(
        (items) =>
            _filterAndSort(items.map(PropertyMapper.fromJson), landlordId),
      );

  @override
  Stream<Property?> watchById(String id) => _database
      .watchEntity(OfflineEntityType.property, id)
      .map((json) => json == null ? null : PropertyMapper.fromJson(json));

  static List<Property> _filterAndSort(
    Iterable<Property> items,
    String? landlordId,
  ) {
    final result = items
        .where(
          (property) => landlordId == null || property.landlordId == landlordId,
        )
        .toList(growable: false);
    result.sort((left, right) => left.name.compareTo(right.name));
    return result;
  }

  static String? _optional(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
