import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/features/finance/data/sembast_rent_payment_repository.dart';
import 'package:nyumba_property_management/features/tenants/data/sembast_tenancy_repository.dart';
import 'package:nyumba_property_management/features/tenants/domain/tenancy.dart';
import 'package:sembast/sembast_memory.dart';

/// A `landlordPortals/{uid}/tenancies/{id}` document, exactly as
/// `landlordTenancyProjection` in firebase/functions/src/shared/projections.ts
/// writes it, after FirestoreRemotePullGateway normalizes Timestamps to ISO
/// strings.
///
/// Hand-written on purpose: the point is to fail when the TypeScript projection
/// and the Dart mapper drift apart, and a fixture derived from either side
/// could not do that. No `syncMetadata` — the server does not send one, and
/// mergeRemoteEntity is what supplies it.
Map<String, Object?> tenancyProjection() => <String, Object?>{
  'id': 'lease-1',
  'version': 3,
  'landlordId': 'landlord-1',
  'tenantUserId': null,
  'propertyId': 'property-1',
  'unitId': 'unit-1',
  'tenantName': 'Sandra Nakato',
  'email': 'sandra@example.ug',
  'phone': '+256700000001',
  'unitLabel': 'Apartment 2B',
  'propertyName': 'Acacia Court',
  'monthlyRentMinor': 90000000,
  'balanceMinor': 0,
  'leaseStart': '2026-01-01T00:00:00.000Z',
  'leaseEnd': '2026-12-31T00:00:00.000Z',
  'status': 'active',
  'createdAt': '2026-01-01T00:00:00.000Z',
  'updatedAt': '2026-07-16T00:00:00.000Z',
};

/// A `landlordPortals/{uid}/payments/{id}` document, as
/// `landlordPaymentProjection` writes it.
Map<String, Object?> paymentProjection() => <String, Object?>{
  'id': 'payment-1',
  'version': 1,
  'landlordId': 'landlord-1',
  'tenancyId': 'lease-1',
  'receiptNumber': 'NYB-RCP-00042',
  'tenantName': 'Sandra Nakato',
  'unitLabel': 'Apartment 2B',
  'propertyName': 'Acacia Court',
  'amountMinor': 90000000,
  'method': 'mtn_momo',
  'period': 'July 2026',
  'paidOn': '2026-07-16T00:00:00.000Z',
  'createdAt': '2026-07-16T00:00:00.000Z',
  'updatedAt': '2026-07-16T00:00:00.000Z',
};

void main() {
  var databaseCount = 0;
  Future<OfflineDatabase> openDatabase() async {
    final database = OfflineDatabase(
      await databaseFactoryMemory.openDatabase(
        'projection-${databaseCount++}.db',
      ),
    );
    await database.initialize();
    return database;
  }

  group('landlord portal projections rehydrate the client aggregates', () {
    // This is the whole point of the landlordPortals read models: a landlord
    // signing in on a second device has recorded nothing locally, so every row
    // they see arrives through exactly this path.
    test('a pulled tenancy becomes a readable Tenancy', () async {
      final database = await openDatabase();
      addTearDown(database.close);
      final tenancies = SembastTenancyRepository(database: database);

      final applied = await database.mergeRemoteEntity(
        entityType: OfflineEntityType.tenancy,
        entityId: 'lease-1',
        entity: tenancyProjection(),
      );
      expect(applied, RemoteMergeResult.applied);

      final tenancy = await tenancies.getById('lease-1');
      expect(tenancy, isNotNull);
      expect(tenancy!.tenantName, 'Sandra Nakato');
      expect(tenancy.unitLabel, 'Apartment 2B');
      expect(tenancy.propertyName, 'Acacia Court');
      expect(tenancy.monthlyRentMinor, 90000000);
      expect(tenancy.status, TenancyStatus.active);
      expect(tenancy.leaseStart, DateTime.utc(2026));
      // mergeRemoteEntity records the server version it applied, so a replay of
      // the same snapshot is recognized as stale rather than reapplied.
      expect(tenancy.syncMetadata.serverRevision, '3');
      expect(tenancy.syncMetadata.needsSync, isFalse);
    });

    test('a pulled payment becomes a readable RentPayment', () async {
      final database = await openDatabase();
      addTearDown(database.close);
      final payments = SembastRentPaymentRepository(database: database);

      await database.mergeRemoteEntity(
        entityType: OfflineEntityType.payment,
        entityId: 'payment-1',
        entity: paymentProjection(),
      );

      final stored = await payments.getAll();
      expect(stored, hasLength(1));
      final payment = stored.single;
      expect(payment.tenancyId, 'lease-1');
      expect(payment.tenantName, 'Sandra Nakato');
      expect(payment.amountMinor, 90000000);
      // The server issued this number; the device never authors one.
      expect(payment.receiptNumber, 'NYB-RCP-00042');
      expect(payment.hasIssuedReceipt, isTrue);
    });

    test('a renamed projection field fails at the read', () async {
      final database = await openDatabase();
      addTearDown(database.close);
      final tenancies = SembastTenancyRepository(database: database);

      // The drift this file exists to catch: rename a field in the TypeScript
      // projection and the Dart mapper throws deep inside a screen instead of
      // at the boundary. Nothing type-checks across the two languages, so this
      // assertion is the only thing holding the contract.
      final renamed = tenancyProjection()
        ..remove('unitLabel')
        ..['unit_label'] = 'Apartment 2B';
      await database.mergeRemoteEntity(
        entityType: OfflineEntityType.tenancy,
        entityId: 'lease-1',
        entity: renamed,
      );

      expect(
        () => tenancies.getById('lease-1'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
