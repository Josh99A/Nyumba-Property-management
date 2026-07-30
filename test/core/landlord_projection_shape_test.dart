import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/features/finance/data/mappers/rent_payment_mapper.dart';
import 'package:nyumba_property_management/features/tenants/data/mappers/tenancy_mapper.dart';
import 'package:nyumba_property_management/features/tenants/domain/tenancy.dart';

/// A `landlordPortals/{uid}/tenancies/{id}` document, exactly as
/// `landlordTenancyProjection` in firebase/functions/src/shared/projections.ts
/// writes it, after `FirestoreCloudReadGateway.toClientShape` normalizes
/// Timestamps to ISO strings.
///
/// Hand-written on purpose: the point is to fail when the TypeScript projection
/// and the Dart mapper drift apart, and a fixture derived from either side
/// could not do that.
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
  // Asserted straight through the mappers now, rather than via a local database
  // and a repository. That is the boundary this file is actually about — a
  // server document meeting the Dart code that reads it — and routing through a
  // mirror only added a step that could mask a mismatch.
  group('landlord portal projections decode into the client aggregates', () {
    // This is the whole point of the landlordPortals read models: a landlord
    // signing in on a second device has recorded nothing locally, so every row
    // they see arrives through exactly this path.
    test('a projected tenancy becomes a readable Tenancy', () {
      final tenancy = TenancyMapper.fromJson(tenancyProjection());

      expect(tenancy.tenantName, 'Sandra Nakato');
      expect(tenancy.unitLabel, 'Apartment 2B');
      expect(tenancy.propertyName, 'Acacia Court');
      expect(tenancy.monthlyRentMinor, 90000000);
      expect(tenancy.status, TenancyStatus.active);
      expect(tenancy.leaseStart, DateTime.utc(2026));
      // The server's own counter, carried back on the next edit as
      // `expectedVersion` so a stale write is refused.
      expect(tenancy.serverVersion, 3);
    });

    test('a projected payment becomes a readable RentPayment', () {
      final payment = RentPaymentMapper.fromJson(paymentProjection());

      expect(payment.tenancyId, 'lease-1');
      expect(payment.tenantName, 'Sandra Nakato');
      expect(payment.amountMinor, 90000000);
      // The server issued this number; the device never authors one.
      expect(payment.receiptNumber, 'NYB-RCP-00042');
      expect(payment.hasIssuedReceipt, isTrue);
      expect(payment.serverVersion, 1);
    });

    test('a renamed tenancy field fails at the boundary', () {
      // The drift this file exists to catch: rename a field in the TypeScript
      // projection and the Dart mapper throws deep inside a screen instead of
      // at the boundary. Nothing type-checks across the two languages, so this
      // assertion is the only thing holding the contract.
      final renamed = tenancyProjection()
        ..remove('unitLabel')
        ..['unit_label'] = 'Apartment 2B';

      expect(() => TenancyMapper.fromJson(renamed), throwsFormatException);
    });

    test('a renamed payment field fails at the boundary too', () {
      final renamed = paymentProjection()
        ..remove('amountMinor')
        ..['amount_minor'] = 90000000;

      expect(() => RentPaymentMapper.fromJson(renamed), throwsFormatException);
    });
  });
}
