import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/features/finance/data/sembast_rent_payment_repository.dart';
import 'package:nyumba_property_management/features/finance/domain/rent_payment.dart';
import 'package:nyumba_property_management/features/tenants/data/sembast_tenancy_repository.dart';
import 'package:nyumba_property_management/features/tenants/domain/tenancy.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  test('recording a payment orders it after its tenancy and never drops the '
      'balance below zero', () async {
    final database = OfflineDatabase(
      await databaseFactoryMemory.openDatabase('billing.db'),
    );
    addTearDown(database.close);
    await database.initialize();
    final tenancies = SembastTenancyRepository(database: database);
    final payments = SembastRentPaymentRepository(database: database);

    final tenancy = await tenancies.create(
      CreateTenancyInput(
        landlordId: 'landlord-1',
        tenantName: 'Amina Kamau',
        email: 'amina@example.com',
        unitLabel: 'B4',
        propertyName: 'Sunset Apartments',
        monthlyRentMinor: 120000000,
        openingBalanceMinor: 120000000,
        leaseStart: DateTime.utc(2026, 1, 1),
        leaseEnd: DateTime.utc(2027, 1, 1),
      ),
    );

    final payment = await payments.record(
      tenancy: tenancy,
      input: RecordRentPaymentInput(
        tenancyId: tenancy.id,
        amountMinor: 120000000,
        method: 'MTN Mobile Money',
      ),
    );
    final adjusted = await tenancies.adjustBalance(
      tenancyId: tenancy.id,
      deltaMinor: -payment.amountMinor,
    );

    expect(adjusted.balanceMinor, 0);

    final outbox = await database.readOutbox();
    final paymentEntry = outbox.singleWhere(
      (entry) => entry.entityType == OfflineEntityType.payment,
    );
    final tenancyCreate = outbox.firstWhere(
      (entry) =>
          entry.entityType == OfflineEntityType.tenancy &&
          entry.entityId == tenancy.id,
    );
    expect(
      paymentEntry.dependencyIds,
      contains(tenancyCreate.id),
      reason: 'the payment must never reach the server before its tenancy',
    );

    final overpaid = await tenancies.adjustBalance(
      tenancyId: tenancy.id,
      deltaMinor: -50000000,
    );
    expect(overpaid.balanceMinor, 0);
  });
}
