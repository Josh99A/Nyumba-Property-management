// ignore_for_file: prefer_initializing_formals

import 'package:nyumba_property_management/core/cloud/cloud_command.dart';
import 'package:nyumba_property_management/core/cloud/cloud_data.dart';
import 'package:nyumba_property_management/core/cloud/cloud_read_gateway.dart';
import 'package:nyumba_property_management/core/cloud/cloud_reader.dart';
import 'package:nyumba_property_management/core/cloud/command_dispatcher.dart';
import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/coordinates.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/core/domain/id_generator.dart';
import 'package:nyumba_property_management/core/domain/uuid_id_generator.dart';
import 'package:nyumba_property_management/features/portfolio/data/mappers/property_mapper.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property_repository.dart';

/// Properties, read from the server and written through the command router.
///
/// Reads go through [CloudReader], so a screen is told whether what it is
/// showing is current, cached, or unvalidated. Writes go through
/// [CommandDispatcher], so nothing is stored for later and nothing returns
/// successfully until the server has said so.
final class CloudPropertyRepository implements PropertyRepository {
  CloudPropertyRepository({
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
  Stream<CloudData<List<Property>>> watchAll({
    String? landlordId,
    bool includeArchived = false,
  }) => _reader
      .watch(CommandAggregate.property, _scope, decode: PropertyMapper.fromJson)
      .map(
        (data) => data.map(
          (items) => _filterAndSort(
            items,
            landlordId,
            includeArchived: includeArchived,
          ),
        ),
      );

  @override
  Stream<CloudData<Property?>> watchById(String id) => watchAll(
    includeArchived: true,
  ).map((data) => data.map((items) => _firstOrNull(items, id)));

  @override
  Future<CloudData<List<Property>>> getAll({
    String? landlordId,
    bool includeArchived = false,
    bool forceRefresh = false,
  }) async {
    final data = await _reader.fetch(
      CommandAggregate.property,
      _scope,
      decode: PropertyMapper.fromJson,
      allowCached: !forceRefresh,
    );
    return data.map(
      (items) =>
          _filterAndSort(items, landlordId, includeArchived: includeArchived),
    );
  }

  @override
  Future<CloudData<Property?>> getById(
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
  Future<MutationResult> create(CreatePropertyInput input) async {
    // Validated before anything leaves the device, so an obviously bad payload
    // costs a round trip nobody needed. The server validates again regardless —
    // this check is a courtesy, never the authority.
    input.validate();
    final propertyId = _idGenerator.generate();
    return _send(
      type: 'property.create',
      aggregateId: propertyId,
      operation: CommandOperation.create,
      // `expectedVersion: 0` is how the router recognises a create.
      expectedVersion: 0,
      payload: <String, Object?>{
        if (input.landlordId.trim().isNotEmpty)
          'targetLandlordId': input.landlordId.trim(),
        'name': input.name.trim(),
        'addressLine': input.addressLine.trim(),
        'city': input.city.trim(),
        if (_optional(input.description) != null)
          'description': _optional(input.description),
        if (input.location != null) 'location': _pin(input.location!),
        'imageUrls': input.imageUrls
            .map((item) => item.trim())
            .toList(growable: false),
      },
    );
  }

  @override
  Future<MutationResult> update(Property property) async {
    property.validate();
    if (property.isArchived) {
      throw DomainValidationException(<String, String>{
        'property': 'an archived property cannot be edited',
      });
    }
    return _send(
      type: 'property.update',
      aggregateId: property.id,
      operation: CommandOperation.update,
      expectedVersion: _requireVersion(
        property.serverVersion,
        'property.update',
      ),
      payload: <String, Object?>{
        'name': property.name.trim(),
        'addressLine': property.addressLine.trim(),
        'city': property.city.trim(),
        'description': _optional(property.description),
        // Explicitly nullable on update, unlike create: an absent key means
        // "leave the pin alone", while a null is the landlord taking one back.
        // Without the distinction a placed pin could never be removed.
        'location': property.location == null ? null : _pin(property.location!),
        'imageUrls': property.imageUrls
            .map((item) => item.trim())
            .toList(growable: false),
      },
    );
  }

  // `async` rather than an arrow, so a missing version surfaces as a rejected
  // future like every other failure here. An expression body would evaluate
  // the guard eagerly and throw synchronously, which callers awaiting or
  // catching on the future would miss entirely.
  @override
  Future<MutationResult> archive(Property property) async => _send(
    type: 'property.archive',
    aggregateId: property.id,
    operation: CommandOperation.delete,
    expectedVersion: _requireVersion(
      property.serverVersion,
      'property.archive',
    ),
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
        aggregate: CommandAggregate.property,
        aggregateId: aggregateId,
        operation: operation,
        payload: payload,
        issuedAt: _clock.now().toUtc(),
        expectedVersion: expectedVersion,
      ),
    );
    // Only after the server confirmed. Invalidating before would leave the
    // cache empty on a rejected command and make a failure look like a change.
    _reader.invalidate(CommandAggregate.property);
    return MutationResult(aggregateId: aggregateId, outcome: outcome);
  }

  /// An edit needs the version its author was looking at.
  ///
  /// A missing one means this copy never came from the server, so there is
  /// nothing to guard against and the safe move is to refuse rather than send
  /// an unguarded write that could clobber a concurrent change.
  static int _requireVersion(int? version, String commandType) {
    if (version == null || version < 1) {
      throw DomainValidationException(<String, String>{
        'expectedVersion':
            '$commandType needs a record loaded from the server first',
      });
    }
    return version;
  }

  static Map<String, Object?> _pin(Coordinates location) => <String, Object?>{
    'lat': location.latitude,
    'lng': location.longitude,
  };

  static Property? _firstOrNull(List<Property> items, String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  static List<Property> _filterAndSort(
    List<Property> items,
    String? landlordId, {
    required bool includeArchived,
  }) {
    final result = items
        .where(
          (property) =>
              (includeArchived || !property.isArchived) &&
              (landlordId == null || property.landlordId == landlordId),
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
