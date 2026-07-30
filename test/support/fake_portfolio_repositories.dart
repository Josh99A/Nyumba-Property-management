import 'dart:async';

import 'package:nyumba_property_management/core/cloud/cloud_command.dart';
import 'package:nyumba_property_management/core/cloud/cloud_data.dart';
import 'package:nyumba_property_management/core/domain/uuid_id_generator.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property_repository.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit_repository.dart';

/// In-memory portfolio repositories for tests whose subject is something else.
///
/// These stand in for the server where a *listing* test needs a property and a
/// unit to exist. They are not a local database and are not a substitute for
/// `CloudPropertyRepository` — tests about portfolio reads and writes drive the
/// real repository against `FakeCloudReadGateway`/`RecordingCommandGateway`.
///
/// Records land already carrying a `serverVersion`, because everything these
/// hand back is meant to represent something the server has already accepted.
final class FakePropertyRepository implements PropertyRepository {
  final Map<String, Property> records = <String, Property>{};
  final _ids = const UuidIdGenerator();
  DateTime retrievedAt = DateTime.utc(2026, 7, 29, 9);

  /// Set to make reads fail, so a caller's handling of an unreadable record can
  /// be exercised without a real outage.
  CloudReadError? readError;

  Property put(Property property) => records[property.id] = property;

  /// Creates and hands back the stored record.
  ///
  /// Test-only convenience. The real repository deliberately returns proof of
  /// commit rather than an entity, because the authoritative copy arrives on
  /// the listener — but a test setting up a fixture needs the object it just
  /// made, and re-reading it every time would only add noise.
  Future<Property> createReturning(CreatePropertyInput input) async {
    final result = await create(input);
    return records[result.aggregateId]!;
  }

  @override
  Future<MutationResult> create(CreatePropertyInput input) async {
    input.validate();
    final now = DateTime.utc(2026, 7, 29, 9);
    final property = Property(
      id: _ids.generate(),
      landlordId: input.landlordId.trim(),
      name: input.name.trim(),
      addressLine: input.addressLine.trim(),
      city: input.city.trim(),
      country: input.country.trim(),
      description: input.description,
      location: input.location,
      imageUrls: input.imageUrls,
      createdAt: now,
      updatedAt: now,
      serverVersion: 1,
    );
    records[property.id] = property;
    return MutationResult(
      aggregateId: property.id,
      outcome: CommandOutcome(committedAt: now, serverVersion: '1'),
    );
  }

  @override
  Future<MutationResult> update(Property property) async {
    records[property.id] = property;
    return MutationResult(
      aggregateId: property.id,
      outcome: CommandOutcome(committedAt: retrievedAt),
    );
  }

  @override
  Future<MutationResult> archive(Property property) async {
    records[property.id] = property.copyWith(
      isArchived: true,
      archivedAt: retrievedAt,
    );
    return MutationResult(
      aggregateId: property.id,
      outcome: CommandOutcome(committedAt: retrievedAt),
    );
  }

  List<Property> _visible({String? landlordId, required bool includeArchived}) {
    final result =
        records.values
            .where(
              (property) =>
                  (includeArchived || !property.isArchived) &&
                  (landlordId == null || property.landlordId == landlordId),
            )
            .toList(growable: false)
          ..sort((left, right) => left.name.compareTo(right.name));
    return result;
  }

  CloudData<T> _wrap<T>(T value, {required bool isEmpty}) {
    final error = readError;
    if (error != null) return CloudData<T>.failure(error);
    return isEmpty
        ? CloudData<T>.empty(value, retrievedAt: retrievedAt)
        : CloudData<T>.live(value, retrievedAt: retrievedAt);
  }

  @override
  Future<CloudData<List<Property>>> getAll({
    String? landlordId,
    bool includeArchived = false,
    bool forceRefresh = false,
  }) async {
    final items = _visible(
      landlordId: landlordId,
      includeArchived: includeArchived,
    );
    return _wrap(items, isEmpty: items.isEmpty);
  }

  @override
  Future<CloudData<Property?>> getById(
    String id, {
    bool forceRefresh = false,
  }) async => _wrap(records[id], isEmpty: !records.containsKey(id));

  @override
  Stream<CloudData<List<Property>>> watchAll({
    String? landlordId,
    bool includeArchived = false,
  }) async* {
    yield await getAll(
      landlordId: landlordId,
      includeArchived: includeArchived,
    );
  }

  @override
  Stream<CloudData<Property?>> watchById(String id) async* {
    yield await getById(id);
  }
}

final class FakeUnitRepository implements UnitRepository {
  final Map<String, Unit> records = <String, Unit>{};
  final _ids = const UuidIdGenerator();
  DateTime retrievedAt = DateTime.utc(2026, 7, 29, 9);
  CloudReadError? readError;

  Unit put(Unit unit) => records[unit.id] = unit;

  /// Creates and hands back the stored record. See [FakePropertyRepository].
  Future<Unit> createReturning(CreateUnitInput input) async {
    final result = await create(input);
    return records[result.aggregateId]!;
  }

  @override
  Future<MutationResult> create(CreateUnitInput input) async {
    input.validate();
    final now = DateTime.utc(2026, 7, 29, 9);
    final unit = Unit(
      id: _ids.generate(),
      propertyId: input.propertyId,
      landlordId: input.landlordId,
      label: input.label,
      type: input.type,
      status: input.status,
      monthlyRentMinor: input.monthlyRentMinor,
      currency: input.currency,
      bedrooms: input.bedrooms,
      bathrooms: input.bathrooms,
      floor: input.floor,
      description: input.description,
      amenities: input.amenities,
      createdAt: now,
      updatedAt: now,
      serverVersion: 1,
    );
    records[unit.id] = unit;
    return MutationResult(
      aggregateId: unit.id,
      outcome: CommandOutcome(committedAt: now, serverVersion: '1'),
    );
  }

  @override
  Future<MutationResult> update(Unit unit) async {
    records[unit.id] = unit;
    return MutationResult(
      aggregateId: unit.id,
      outcome: CommandOutcome(committedAt: retrievedAt),
    );
  }

  @override
  Future<MutationResult> archive(Unit unit) async {
    records[unit.id] = unit.copyWith(isArchived: true, archivedAt: retrievedAt);
    return MutationResult(
      aggregateId: unit.id,
      outcome: CommandOutcome(committedAt: retrievedAt),
    );
  }

  CloudData<T> _wrap<T>(T value, {required bool isEmpty}) {
    final error = readError;
    if (error != null) return CloudData<T>.failure(error);
    return isEmpty
        ? CloudData<T>.empty(value, retrievedAt: retrievedAt)
        : CloudData<T>.live(value, retrievedAt: retrievedAt);
  }

  @override
  Future<CloudData<List<Unit>>> getAll({
    String? propertyId,
    String? landlordId,
    bool includeArchived = false,
    bool forceRefresh = false,
  }) async {
    final items =
        records.values
            .where(
              (unit) =>
                  (includeArchived || !unit.isArchived) &&
                  (propertyId == null || unit.propertyId == propertyId) &&
                  (landlordId == null || unit.landlordId == landlordId),
            )
            .toList(growable: false)
          ..sort((left, right) => left.label.compareTo(right.label));
    return _wrap(items, isEmpty: items.isEmpty);
  }

  @override
  Future<CloudData<Unit?>> getById(
    String id, {
    bool forceRefresh = false,
  }) async => _wrap(records[id], isEmpty: !records.containsKey(id));

  @override
  Stream<CloudData<List<Unit>>> watchAll({
    String? propertyId,
    String? landlordId,
    bool includeArchived = false,
  }) async* {
    yield await getAll(
      propertyId: propertyId,
      landlordId: landlordId,
      includeArchived: includeArchived,
    );
  }

  @override
  Stream<CloudData<Unit?>> watchById(String id) async* {
    yield await getById(id);
  }
}
