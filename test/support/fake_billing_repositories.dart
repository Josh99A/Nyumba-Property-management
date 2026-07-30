import 'dart:async';

import 'package:nyumba_property_management/core/cloud/cloud_command.dart';
import 'package:nyumba_property_management/core/cloud/cloud_data.dart';
import 'package:nyumba_property_management/core/domain/uuid_id_generator.dart';
import 'package:nyumba_property_management/features/finance/domain/rent_payment.dart';
import 'package:nyumba_property_management/features/finance/domain/rent_payment_repository.dart';
import 'package:nyumba_property_management/features/tenants/domain/tenancy.dart';
import 'package:nyumba_property_management/features/tenants/domain/tenancy_repository.dart';

/// In-memory tenancy and payment repositories for tests whose subject is
/// something else.
///
/// Tests *about* tenancy and payment behaviour drive the real cloud
/// repositories against `RecordingCommandGateway`, because which command a
/// payment becomes is the thing that protects money and a fake cannot assert it.
/// These exist so a listing or dashboard test can have a tenancy exist without
/// standing up a gateway.
///
/// Note there is no `adjustBalance`: the balance is the server's arithmetic,
/// and nothing in the client may move it.
final class FakeTenancyRepository implements TenancyRepository {
  final Map<String, Tenancy> records = <String, Tenancy>{};
  final _ids = const UuidIdGenerator();

  DateTime retrievedAt = DateTime.utc(2026, 7, 29, 9);
  CloudReadError? readError;

  /// Command types this repository was asked to send, in order.
  final List<String> sent = <String>[];

  Tenancy put(Tenancy tenancy) => records[tenancy.id] = tenancy;

  @override
  Future<MutationResult> create(CreateTenancyInput input) async {
    final id = _ids.generate();
    records[id] = Tenancy(
      id: id,
      landlordId: input.landlordId,
      tenantName: input.tenantName,
      email: input.email,
      phone: input.phone,
      unitLabel: input.unitLabel,
      propertyName: input.propertyName,
      monthlyRentMinor: input.monthlyRentMinor,
      balanceMinor: input.openingBalanceMinor,
      leaseStart: input.leaseStart,
      leaseEnd: input.leaseEnd,
      status: TenancyStatus.active,
      tenantUserId: input.tenantUserId,
      propertyId: input.propertyId,
      unitId: input.unitId,
      createdAt: retrievedAt,
      updatedAt: retrievedAt,
      serverVersion: 1,
    );
    sent.add('tenancy.establish');
    return MutationResult(
      aggregateId: id,
      outcome: CommandOutcome(committedAt: retrievedAt, serverVersion: '1'),
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
  Future<CloudData<List<Tenancy>>> getAll({
    String? landlordId,
    String? tenantUserId,
    bool forceRefresh = false,
  }) async {
    final items = records.values
        .where(
          (tenancy) =>
              (landlordId == null || tenancy.landlordId == landlordId) &&
              (tenantUserId == null || tenancy.tenantUserId == tenantUserId),
        )
        .toList(growable: false);
    return _wrap(items, isEmpty: items.isEmpty);
  }

  @override
  Future<CloudData<Tenancy?>> getById(
    String id, {
    bool forceRefresh = false,
  }) async => _wrap(records[id], isEmpty: !records.containsKey(id));

  @override
  Stream<CloudData<List<Tenancy>>> watchAll({
    String? landlordId,
    String? tenantUserId,
  }) async* {
    yield await getAll(landlordId: landlordId, tenantUserId: tenantUserId);
  }
}

final class FakeRentPaymentRepository implements RentPaymentRepository {
  final Map<String, RentPayment> records = <String, RentPayment>{};
  final _ids = const UuidIdGenerator();

  DateTime retrievedAt = DateTime.utc(2026, 7, 29, 9);
  CloudReadError? readError;

  /// Command types this repository was asked to send, in order. A test that
  /// cares *which* one should use the real repository instead.
  final List<String> sent = <String>[];

  RentPayment put(RentPayment payment) => records[payment.id] = payment;

  @override
  Future<MutationResult> record({
    required Tenancy tenancy,
    required RecordRentPaymentInput input,
  }) async {
    final id = _ids.generate();
    records[id] = RentPayment(
      id: id,
      landlordId: tenancy.landlordId,
      tenancyId: tenancy.id,
      tenantName: tenancy.tenantName,
      unitLabel: tenancy.unitLabel,
      propertyName: tenancy.propertyName,
      amountMinor: input.amountMinor,
      method: input.method,
      period: input.period ?? 'July 2026',
      reference: input.reference,
      declaredByTenant: input.declaredByTenant,
      paidOn: retrievedAt,
      createdAt: retrievedAt,
      updatedAt: retrievedAt,
      serverVersion: 1,
    );
    sent.add(
      input.declaredByTenant
          ? 'payment.declare'
          : 'payment.recordAgainstTenancy',
    );
    return MutationResult(
      aggregateId: id,
      outcome: CommandOutcome(committedAt: retrievedAt, serverVersion: '1'),
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
  Future<CloudData<List<RentPayment>>> getAll({
    String? landlordId,
    String? tenancyId,
    bool forceRefresh = false,
  }) async {
    final items = records.values
        .where(
          (payment) =>
              (landlordId == null || payment.landlordId == landlordId) &&
              (tenancyId == null || payment.tenancyId == tenancyId),
        )
        .toList(growable: false);
    return _wrap(items, isEmpty: items.isEmpty);
  }

  @override
  Future<CloudData<RentPayment?>> getById(
    String id, {
    bool forceRefresh = false,
  }) async => _wrap(records[id], isEmpty: !records.containsKey(id));

  @override
  Stream<CloudData<List<RentPayment>>> watchAll({
    String? landlordId,
    String? tenancyId,
  }) async* {
    yield await getAll(landlordId: landlordId, tenancyId: tenancyId);
  }
}
