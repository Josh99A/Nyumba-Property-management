import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/features/dashboard/application/dashboard_snapshot.dart';
import 'package:nyumba_property_management/features/finance/domain/rent_payment.dart';
import 'package:nyumba_property_management/features/maintenance/domain/maintenance_request.dart'
    hide MaintenancePriority;
import 'package:nyumba_property_management/features/maintenance/domain/maintenance_request.dart'
    as maintenance_domain
    show MaintenancePriority;
import 'package:nyumba_property_management/features/portfolio/domain/unit.dart';
import 'package:nyumba_property_management/features/tenants/domain/tenancy.dart';

final _now = DateTime.now();

Unit _unit(String id, UnitStatus status) => Unit(
  id: id,
  propertyId: 'property-1',
  landlordId: 'landlord-1',
  label: id,
  type: UnitType.apartment,
  status: status,
  monthlyRentMinor: 100000000,
  currency: 'UGX',
  createdAt: _now,
  updatedAt: _now,
  syncMetadata: SyncMetadata.synced(lastSyncedAt: _now),
);

RentPayment _payment(String id, int amountMinor, DateTime paidOn) =>
    RentPayment(
      id: id,
      receiptNumber: 'RCPT-$id',
      landlordId: 'landlord-1',
      tenantName: 'Brian Okello',
      unitLabel: 'B4',
      propertyName: 'Sunset Apartments',
      amountMinor: amountMinor,
      method: 'MTN Mobile Money',
      period: '2026-07',
      paidOn: paidOn,
      createdAt: paidOn,
      updatedAt: paidOn,
      syncMetadata: SyncMetadata.synced(lastSyncedAt: paidOn),
    );

Tenancy _tenancy(String id, int balanceMinor, TenancyStatus status) => Tenancy(
  id: id,
  landlordId: 'landlord-1',
  tenantName: 'Brian Okello',
  email: 'brian@example.ug',
  phone: '+256772000100',
  unitLabel: 'B4',
  propertyName: 'Sunset Apartments',
  monthlyRentMinor: 100000000,
  balanceMinor: balanceMinor,
  leaseStart: _now.subtract(const Duration(days: 60)),
  leaseEnd: _now.add(const Duration(days: 300)),
  status: status,
  createdAt: _now,
  updatedAt: _now,
  syncMetadata: SyncMetadata.synced(lastSyncedAt: _now),
);

MaintenanceRequest _request(String id, MaintenanceStatus status) =>
    MaintenanceRequest(
      resolvedAt: status == MaintenanceStatus.resolved ? _now : null,
      id: id,
      reference: 'REQ-$id',
      landlordId: 'landlord-1',
      title: 'Leaking tap',
      description: 'Kitchen tap drips overnight.',
      location: 'B4',
      category: 'Plumbing',
      priority: maintenance_domain.MaintenancePriority.high,
      status: status,
      reporterName: 'Brian Okello',
      reportedAt: _now,
      createdAt: _now,
      updatedAt: _now,
      syncMetadata: SyncMetadata.synced(lastSyncedAt: _now),
    );

DashboardSnapshot _snapshotFor({
  List<Unit> units = const [],
  List<RentPayment> payments = const [],
  List<Tenancy> tenancies = const [],
  List<MaintenanceRequest> requests = const [],
}) => buildDashboardSnapshot(
  units: units,
  payments: payments,
  tenancies: tenancies,
  requests: requests,
  outbox: const <OutboxEntry>[],
  now: _now,
);

void main() {
  test('a landlord with no records sees zeroes, never illustrative totals', () {
    final snapshot = _snapshotFor();

    expect(snapshot.totalUnits, 0);
    expect(snapshot.occupiedUnits, 0);
    expect(snapshot.rentCollectedMinor, 0);
    expect(snapshot.rentOutstandingMinor, 0);
    expect(snapshot.openRequests, 0);
    expect(snapshot.occupancyRate, 0);
    expect(snapshot.recentPayments, isEmpty);
    expect(snapshot.maintenance, isEmpty);
    expect(snapshot.activity, isEmpty);
    expect(
      snapshot.collectionTrend,
      isEmpty,
      reason: 'An invented sparkline is a fabricated claim about history.',
    );
    expect(snapshot.outstandingTrend, isEmpty);
  });

  test('counts occupancy from real units', () {
    final snapshot = _snapshotFor(
      units: [
        _unit('A1', UnitStatus.occupied),
        _unit('A2', UnitStatus.occupied),
        _unit('A3', UnitStatus.vacant),
        _unit('A4', UnitStatus.maintenance),
      ],
    );

    expect(snapshot.totalUnits, 4);
    expect(snapshot.occupiedUnits, 2);
    expect(snapshot.occupancyRate, 0.5);
  });

  test('sums only the current month into rent collected', () {
    final snapshot = _snapshotFor(
      payments: [
        _payment('p1', 120000000, DateTime(_now.year, _now.month, 2)),
        _payment('p2', 80000000, DateTime(_now.year, _now.month, 9)),
        // Three months back: history, not this month's collection.
        _payment('p3', 500000000, DateTime(_now.year, _now.month - 3, 9)),
      ],
    );

    expect(snapshot.rentCollectedMinor, 200000000);
    expect(snapshot.recentPayments, hasLength(3));
    expect(snapshot.recentPayments.first.tenant, 'Brian Okello');
  });

  test('outstanding ignores ended tenancies', () {
    final snapshot = _snapshotFor(
      tenancies: [
        _tenancy('t1', 45000000, TenancyStatus.active),
        _tenancy('t2', 15000000, TenancyStatus.noticeGiven),
        _tenancy('t3', 99000000, TenancyStatus.ended),
      ],
    );

    expect(
      snapshot.rentOutstandingMinor,
      60000000,
      reason: 'Ended tenancies are settled and must not inflate arrears.',
    );
  });

  test('open requests exclude resolved and cancelled work', () {
    final snapshot = _snapshotFor(
      requests: [
        _request('r1', MaintenanceStatus.submitted),
        _request('r2', MaintenanceStatus.inProgress),
        _request('r3', MaintenanceStatus.resolved),
        _request('r4', MaintenanceStatus.cancelled),
      ],
    );

    expect(snapshot.openRequests, 2);
    expect(snapshot.maintenance, hasLength(2));
  });

  test('the collection trend reflects real payment history', () {
    final snapshot = _snapshotFor(
      payments: [
        _payment('p1', 100000000, DateTime(_now.year, _now.month, 4)),
        _payment('p2', 50000000, DateTime(_now.year, _now.month - 1, 4)),
      ],
    );

    // Normalised against the best month, most recent last.
    expect(snapshot.collectionTrend.last, 1.0);
    expect(snapshot.collectionTrend[snapshot.collectionTrend.length - 2], 0.5);
  });
}
