// ignore_for_file: prefer_initializing_formals

import 'package:nyumba_property_management/core/cloud/cloud_command.dart';
import 'package:nyumba_property_management/core/cloud/cloud_data.dart';
import 'package:nyumba_property_management/core/cloud/cloud_read_gateway.dart';
import 'package:nyumba_property_management/core/cloud/cloud_reader.dart';
import 'package:nyumba_property_management/core/cloud/command_dispatcher.dart';
import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/core/domain/id_generator.dart';
import 'package:nyumba_property_management/core/domain/uuid_id_generator.dart';
import 'package:nyumba_property_management/features/portfolio/data/mappers/unit_mapper.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit_repository.dart';

/// Rentable units, read from the server and written through the command router.
final class CloudUnitRepository implements UnitRepository {
  CloudUnitRepository({
    required CloudReader reader,
    required CommandDispatcher commands,
    required CloudScope scope,
    IdGenerator? idGenerator,
    Clock clock = const SystemClock(),
  }) : _reader = reader,
       _commands = commands,
       _scope = scope,
       _idGenerator = idGenerator ?? const UuidIdGenerator(),
       _clock = clock;

  final CloudReader _reader;
  final CommandDispatcher _commands;
  final CloudScope _scope;
  final IdGenerator _idGenerator;
  final Clock _clock;

  @override
  Stream<CloudData<List<Unit>>> watchAll({
    String? propertyId,
    String? landlordId,
    bool includeArchived = false,
  }) => _reader
      .watch(CommandAggregate.unit, _scope, decode: UnitMapper.fromJson)
      .map(
        (data) => data.map(
          (items) => _filterAndSort(
            items,
            propertyId: propertyId,
            landlordId: landlordId,
            includeArchived: includeArchived,
          ),
        ),
      );

  @override
  Stream<CloudData<Unit?>> watchById(String id) => watchAll(
    includeArchived: true,
  ).map((data) => data.map((items) => _firstOrNull(items, id)));

  @override
  Future<CloudData<List<Unit>>> getAll({
    String? propertyId,
    String? landlordId,
    bool includeArchived = false,
    bool forceRefresh = false,
  }) async {
    final data = await _reader.fetch(
      CommandAggregate.unit,
      _scope,
      decode: UnitMapper.fromJson,
      allowCached: !forceRefresh,
    );
    return data.map(
      (items) => _filterAndSort(
        items,
        propertyId: propertyId,
        landlordId: landlordId,
        includeArchived: includeArchived,
      ),
    );
  }

  @override
  Future<CloudData<Unit?>> getById(
    String id, {
    bool forceRefresh = false,
  }) async {
    final data = await getAll(
      includeArchived: true,
      forceRefresh: forceRefresh,
    );
    return data.map((items) => _firstOrNull(items, id));
  }

  @override
  Future<MutationResult> create(CreateUnitInput input) async {
    input.validate();
    return _send(
      type: 'unit.create',
      aggregateId: _idGenerator.generate(),
      operation: CommandOperation.create,
      expectedVersion: 0,
      payload: <String, Object?>{
        'propertyId': input.propertyId.trim(),
        'label': input.label.trim(),
        'type': input.type.name,
        'monthlyRentMinor': input.monthlyRentMinor,
        'bedrooms': input.bedrooms,
        'bathrooms': input.bathrooms,
        'amenities': _amenities(input.amenities),
        // Only the availability states a landlord may set directly. Occupancy
        // is established by the tenancy command and the server refuses it here.
        if (_initialAvailability(input.status) != null)
          'occupancyStatus': _initialAvailability(input.status),
      },
    );
  }

  @override
  Future<MutationResult> update(Unit unit) async {
    unit.validate();
    if (unit.isArchived) {
      throw DomainValidationException(<String, String>{
        'unit': 'an archived rental space cannot be edited',
      });
    }
    return _send(
      type: 'unit.update',
      aggregateId: unit.id,
      operation: CommandOperation.update,
      expectedVersion: _requireVersion(unit.serverVersion, 'unit.update'),
      payload: <String, Object?>{
        'label': unit.label.trim(),
        'type': unit.type.name,
        'monthlyRentMinor': unit.monthlyRentMinor,
        'bedrooms': unit.bedrooms,
        'bathrooms': unit.bathrooms,
        'amenities': _amenities(unit.amenities),
        // Deliberately omitted when the space is occupied: that transition
        // belongs to the tenancy commands, and sending it here is rejected.
        if (_initialAvailability(unit.status) != null)
          'occupancyStatus': _initialAvailability(unit.status),
      },
    );
  }

  // `async` rather than an arrow: see the note on the property repository. A
  // guard that throws synchronously from a Future-returning method is invisible
  // to a caller that only catches on the future.
  @override
  Future<MutationResult> archive(Unit unit) async => _send(
    type: 'unit.archive',
    aggregateId: unit.id,
    operation: CommandOperation.delete,
    expectedVersion: _requireVersion(unit.serverVersion, 'unit.archive'),
    payload: const <String, Object?>{},
  );

  Future<MutationResult> _send({
    required String type,
    required String aggregateId,
    required CommandOperation operation,
    required Map<String, Object?> payload,
    int? expectedVersion,
  }) async {
    final outcome = await _commands.submit(
      CloudCommand(
        commandId: _idGenerator.generate(),
        type: type,
        aggregate: CommandAggregate.unit,
        aggregateId: aggregateId,
        operation: operation,
        payload: payload,
        issuedAt: _clock.now().toUtc(),
        expectedVersion: expectedVersion,
      ),
    );
    _reader.invalidate(CommandAggregate.unit);
    // A unit's availability feeds the property's occupancy summary, so the
    // property list a screen is holding is stale the moment this lands.
    _reader.invalidate(CommandAggregate.property);
    return MutationResult(aggregateId: aggregateId, outcome: outcome);
  }

  /// The four availability states a landlord may set directly, or null for
  /// [UnitStatus.occupied], which only a tenancy can produce.
  static String? _initialAvailability(UnitStatus status) => switch (status) {
    UnitStatus.vacant => 'vacant',
    UnitStatus.reserved => 'reserved',
    UnitStatus.maintenance => 'maintenance',
    UnitStatus.inactive => 'inactive',
    UnitStatus.occupied => null,
  };

  static List<String> _amenities(List<String> amenities) => amenities
      .map((amenity) => amenity.trim())
      .where((amenity) => amenity.isNotEmpty)
      .toList(growable: false);

  static int _requireVersion(int? version, String commandType) {
    if (version == null || version < 1) {
      throw DomainValidationException(<String, String>{
        'expectedVersion':
            '$commandType needs a record loaded from the server first',
      });
    }
    return version;
  }

  static Unit? _firstOrNull(List<Unit> items, String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  static List<Unit> _filterAndSort(
    List<Unit> items, {
    String? propertyId,
    String? landlordId,
    required bool includeArchived,
  }) {
    final result = items
        .where(
          (unit) =>
              (includeArchived || !unit.isArchived) &&
              (propertyId == null || unit.propertyId == propertyId) &&
              (landlordId == null || unit.landlordId == landlordId),
        )
        .toList(growable: false);
    result.sort((left, right) => left.label.compareTo(right.label));
    return result;
  }
}
