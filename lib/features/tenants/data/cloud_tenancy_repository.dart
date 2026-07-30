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
import 'package:nyumba_property_management/features/tenants/data/mappers/tenancy_mapper.dart';
import 'package:nyumba_property_management/features/tenants/domain/tenancy.dart';
import 'package:nyumba_property_management/features/tenants/domain/tenancy_repository.dart';

/// Tenancies read from the server and established through the command router.
///
/// A `Tenancy` is one client aggregate over three server ones — the tenant
/// record, the lease, and its activation — which is why reads come from the
/// joined `landlordPortals/{uid}/tenancies` projection and writes go through
/// the single composite `tenancy.establish` command. Neither side can be
/// rebuilt from the other.
final class CloudTenancyRepository implements TenancyRepository {
  CloudTenancyRepository({
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
  Stream<CloudData<List<Tenancy>>> watchAll({
    String? landlordId,
    String? tenantUserId,
  }) => _reader
      .watch(CommandAggregate.tenancy, _scope, decode: TenancyMapper.fromJson)
      .map(
        (data) => data.map(
          (items) => _filterAndSort(items, landlordId, tenantUserId),
        ),
      );

  @override
  Future<CloudData<List<Tenancy>>> getAll({
    String? landlordId,
    String? tenantUserId,
    bool forceRefresh = false,
  }) async {
    final data = await _reader.fetch(
      CommandAggregate.tenancy,
      _scope,
      decode: TenancyMapper.fromJson,
      allowCached: !forceRefresh,
    );
    return data.map((items) => _filterAndSort(items, landlordId, tenantUserId));
  }

  @override
  Future<CloudData<Tenancy?>> getById(
    String id, {
    bool forceRefresh = false,
  }) async {
    final data = await getAll(forceRefresh: forceRefresh);
    return data.map((items) => _firstOrNull(items, id));
  }

  @override
  Future<MutationResult> create(CreateTenancyInput input) async {
    // The server keys the whole composite off the unit, so a tenancy with no
    // unit is not something it can establish. Refusing here names the missing
    // piece instead of letting the router reject an incomplete payload.
    final unitId = _optional(input.unitId);
    if (unitId == null) {
      throw DomainValidationException(<String, String>{
        'unitId': 'a tenancy must name the rental space it covers',
      });
    }
    final tenancyId = _idGenerator.generate();
    final outcome = await _commands.submit(
      CloudCommand(
        commandId: _idGenerator.generate(),
        type: 'tenancy.establish',
        aggregate: CommandAggregate.tenancy,
        aggregateId: tenancyId,
        operation: CommandOperation.create,
        // `unitLabel` and `propertyName` are deliberately absent: the client
        // carries them for display, but the server derives them from the unit
        // it already owns, and its payload schema is strict.
        payload: <String, Object?>{
          'unitId': unitId,
          'displayName': input.tenantName.trim(),
          'email': input.email.trim(),
          'phone': input.phone.trim(),
          'startDate': input.leaseStart.toUtc().toIso8601String(),
          'endDate': input.leaseEnd.toUtc().toIso8601String(),
          'monthlyRentMinor': input.monthlyRentMinor,
          if (input.openingBalanceMinor > 0)
            'openingBalanceMinor': input.openingBalanceMinor,
        },
        issuedAt: _clock.now().toUtc(),
        expectedVersion: 0,
      ),
    );
    _reader.invalidate(CommandAggregate.tenancy);
    // Establishing a tenancy occupies the unit, so the portfolio a screen is
    // holding is stale the moment this lands.
    _reader.invalidate(CommandAggregate.unit);
    return MutationResult(aggregateId: tenancyId, outcome: outcome);
  }

  static Tenancy? _firstOrNull(List<Tenancy> items, String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  static List<Tenancy> _filterAndSort(
    List<Tenancy> items,
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
