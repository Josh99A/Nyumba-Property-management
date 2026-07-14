// ignore_for_file: prefer_initializing_formals

import 'package:intl/intl.dart';
import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/id_generator.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/core/offline/uuid_id_generator.dart';
import 'package:nyumba_property_management/features/finance/data/mappers/rent_payment_mapper.dart';
import 'package:nyumba_property_management/features/finance/domain/rent_payment.dart';
import 'package:nyumba_property_management/features/finance/domain/rent_payment_repository.dart';
import 'package:nyumba_property_management/features/tenants/domain/tenancy.dart';

final class SembastRentPaymentRepository implements RentPaymentRepository {
  SembastRentPaymentRepository({
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
  Future<RentPayment> record({
    required Tenancy tenancy,
    required RecordRentPaymentInput input,
  }) async {
    final now = _clock.now().toUtc();
    final payment = RentPayment(
      id: _idGenerator.generate(),
      receiptNumber: 'NYB-RCP-${now.millisecondsSinceEpoch % 100000}',
      landlordId: tenancy.landlordId,
      tenancyId: tenancy.id,
      tenantName: tenancy.tenantName,
      unitLabel: tenancy.unitLabel,
      propertyName: tenancy.propertyName,
      amountMinor: input.amountMinor,
      method: input.method.trim(),
      period: input.period?.trim().isNotEmpty == true
          ? input.period!.trim()
          : DateFormat('MMMM y').format(now),
      paidOn: now,
      createdAt: now,
      updatedAt: now,
      syncMetadata: const SyncMetadata.pending(),
    );
    await _database.putEntityAndEnqueue(
      entityType: OfflineEntityType.payment,
      entityId: payment.id,
      entity: RentPaymentMapper.toJson(payment),
      mutationId: _idGenerator.generate(),
      operation: OutboxOperation.create,
      createdAt: now,
      createOnly: true,
      dependsOn: [
        AggregateReference(type: OfflineEntityType.tenancy, id: tenancy.id),
      ],
    );
    return payment;
  }

  @override
  Future<List<RentPayment>> getAll({
    String? landlordId,
    String? tenancyId,
  }) async => _filterAndSort(
    (await _database.readEntities(
      OfflineEntityType.payment,
    )).map(RentPaymentMapper.fromJson),
    landlordId,
    tenancyId,
  );

  @override
  Future<RentPayment?> getById(String id) async {
    final json = await _database.readEntity(OfflineEntityType.payment, id);
    return json == null ? null : RentPaymentMapper.fromJson(json);
  }

  @override
  Stream<List<RentPayment>> watchAll({
    String? landlordId,
    String? tenancyId,
  }) => _database
      .watchEntities(OfflineEntityType.payment)
      .map(
        (items) => _filterAndSort(
          items.map(RentPaymentMapper.fromJson),
          landlordId,
          tenancyId,
        ),
      );

  static List<RentPayment> _filterAndSort(
    Iterable<RentPayment> items,
    String? landlordId,
    String? tenancyId,
  ) {
    final result = items
        .where(
          (payment) =>
              (landlordId == null || payment.landlordId == landlordId) &&
              (tenancyId == null || payment.tenancyId == tenancyId),
        )
        .toList(growable: false);
    result.sort((left, right) => right.paidOn.compareTo(left.paidOn));
    return result;
  }
}
