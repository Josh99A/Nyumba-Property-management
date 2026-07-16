import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../core/offline/aggregate_sync_status.dart';
import '../../../core/offline/offline_entity.dart';
import '../../../core/offline/outbox_entry.dart';
import '../../finance/application/billing_providers.dart';
import '../../finance/domain/rent_payment.dart';
import '../../maintenance/application/maintenance_providers.dart';
import '../../maintenance/domain/maintenance_request.dart'
    as maintenance_domain;
import '../../portfolio/domain/unit.dart';
import '../../tenants/application/tenancy_providers.dart';
import '../../tenants/domain/tenancy.dart';

enum PaymentState { paid, pending, overdue }

class RecentPayment {
  const RecentPayment({
    required this.id,
    required this.tenant,
    required this.unit,
    required this.property,
    required this.amountMinor,
    required this.date,
    required this.state,
  });

  final String id;
  final String tenant;
  final String unit;
  final String property;
  final int amountMinor;
  final DateTime date;
  final PaymentState state;
}

enum MaintenancePriority { normal, high, urgent }

class MaintenanceSummary {
  const MaintenanceSummary({
    required this.id,
    required this.title,
    required this.unit,
    required this.property,
    required this.reportedBy,
    required this.reportedAt,
    required this.priority,
  });

  final String id;
  final String title;
  final String unit;
  final String property;
  final String reportedBy;
  final DateTime reportedAt;
  final MaintenancePriority priority;
}

class ActivitySummary {
  const ActivitySummary({
    required this.icon,
    required this.title,
    required this.detail,
    required this.at,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String detail;
  final DateTime at;
  final Color tone;
}

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.totalUnits,
    required this.occupiedUnits,
    required this.rentCollectedMinor,
    required this.rentOutstandingMinor,
    required this.openRequests,
    required this.collectionTrend,
    required this.outstandingTrend,
    required this.recentPayments,
    required this.maintenance,
    required this.activity,
    required this.lastSyncedAt,
    this.pendingChanges = 0,
  });

  final int totalUnits;
  final int occupiedUnits;
  final int rentCollectedMinor;
  final int rentOutstandingMinor;
  final int openRequests;
  final List<double> collectionTrend;
  final List<double> outstandingTrend;
  final List<RecentPayment> recentPayments;
  final List<MaintenanceSummary> maintenance;
  final List<ActivitySummary> activity;
  final DateTime lastSyncedAt;
  final int pendingChanges;

  double get occupancyRate => totalUnits == 0 ? 0 : occupiedUnits / totalUnits;

  static final empty = DashboardSnapshot(
    totalUnits: 0,
    occupiedUnits: 0,
    rentCollectedMinor: 0,
    rentOutstandingMinor: 0,
    openRequests: 0,
    collectionTrend: const <double>[],
    outstandingTrend: const <double>[],
    recentPayments: const <RecentPayment>[],
    maintenance: const <MaintenanceSummary>[],
    activity: const <ActivitySummary>[],
    lastSyncedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

/// How many months of history the rent sparkline shows.
const _trendMonths = 10;

/// The landlord dashboard, derived entirely from the local mirror.
///
/// Every figure is computed from this landlord's own records, so an account
/// with no properties honestly reports zeroes instead of illustrative totals.
/// This is a per-landlord view of data they already hold, not a platform
/// aggregate: cross-tenant reporting stays server-derived by design.
final dashboardSnapshotProvider = Provider<DashboardSnapshot>((ref) {
  return buildDashboardSnapshot(
    units: ref.watch(portfolioUnitsProvider).value ?? const <Unit>[],
    payments: ref.watch(rentPaymentsProvider).value ?? const <RentPayment>[],
    tenancies: ref.watch(tenanciesProvider).value ?? const <Tenancy>[],
    requests:
        ref.watch(maintenanceRequestsProvider).value ??
        const <maintenance_domain.MaintenanceRequest>[],
    outbox: ref.watch(outboxEntriesProvider).value ?? const <OutboxEntry>[],
    now: DateTime.now(),
  );
});

/// Pure derivation of the dashboard from a landlord's records.
///
/// Kept free of Riverpod and of `DateTime.now()` so the arithmetic can be
/// exercised directly against fixed inputs.
@visibleForTesting
DashboardSnapshot buildDashboardSnapshot({
  required List<Unit> units,
  required List<RentPayment> payments,
  required List<Tenancy> tenancies,
  required List<maintenance_domain.MaintenanceRequest> requests,
  required List<OutboxEntry> outbox,
  required DateTime now,
}) {
  final propertyNameByPayment = <String, String>{};
  for (final payment in payments) {
    propertyNameByPayment[payment.id] = payment.propertyName;
  }

  final collectedThisMonth = payments
      .where((p) => p.paidOn.year == now.year && p.paidOn.month == now.month)
      .fold<int>(0, (total, p) => total + p.amountMinor);

  // Tenancy.validate() guarantees balanceMinor is never negative.
  final outstanding = tenancies
      .where((t) => t.status != TenancyStatus.ended)
      .fold<int>(0, (total, t) => total + t.balanceMinor);

  final openRequests = requests
      .where(
        (r) =>
            r.status != maintenance_domain.MaintenanceStatus.resolved &&
            r.status != maintenance_domain.MaintenanceStatus.cancelled,
      )
      .toList(growable: false);

  final recentPayments = [...payments]
    ..sort((a, b) => b.paidOn.compareTo(a.paidOn));
  final recentOpen = [...openRequests]
    ..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));

  return DashboardSnapshot(
    totalUnits: units.length,
    occupiedUnits: units.where((u) => u.status == UnitStatus.occupied).length,
    rentCollectedMinor: collectedThisMonth,
    rentOutstandingMinor: outstanding,
    openRequests: openRequests.length,
    collectionTrend: _monthlyTrend(payments, now),
    outstandingTrend: _outstandingTrend(payments, tenancies, now),
    recentPayments: recentPayments
        .take(5)
        .map(
          (p) => RecentPayment(
            id: p.id,
            tenant: p.tenantName,
            unit: p.unitLabel,
            property: propertyNameByPayment[p.id] ?? p.propertyName,
            amountMinor: p.amountMinor,
            date: p.paidOn,
            // A receipt the server has not confirmed is not yet money in the
            // bank, so it must not render as settled.
            state:
                resolveAggregateSyncStatus(
                      entityType: OfflineEntityType.payment,
                      entityId: p.id,
                      outbox: outbox,
                      syncMetadata: p.syncMetadata,
                    ) ==
                    AggregateSyncStatus.synced
                ? PaymentState.paid
                : PaymentState.pending,
          ),
        )
        .toList(growable: false),
    maintenance: recentOpen
        .take(3)
        .map(
          (r) => MaintenanceSummary(
            id: r.id,
            title: r.title,
            unit: r.location,
            property: r.category,
            reportedBy: r.reporterName,
            reportedAt: r.reportedAt,
            priority: switch (r.priority) {
              maintenance_domain.MaintenancePriority.urgent =>
                MaintenancePriority.urgent,
              maintenance_domain.MaintenancePriority.high =>
                MaintenancePriority.high,
              maintenance_domain.MaintenancePriority.normal =>
                MaintenancePriority.normal,
            },
          ),
        )
        .toList(growable: false),
    activity: _activity(recentPayments, recentOpen),
    lastSyncedAt: _lastSyncedAt(payments, units) ?? now,
    pendingChanges: outbox.length,
  );
}

/// Rent collected per month for the last [_trendMonths], normalised against the
/// best month so the sparkline is comparable. Returns empty when there is no
/// history: an empty chart is honest, an invented curve is not.
List<double> _monthlyTrend(List<RentPayment> payments, DateTime now) {
  if (payments.isEmpty) return const <double>[];
  final totals = List<int>.filled(_trendMonths, 0);
  for (final payment in payments) {
    final months =
        (now.year - payment.paidOn.year) * 12 +
        (now.month - payment.paidOn.month);
    if (months < 0 || months >= _trendMonths) continue;
    totals[_trendMonths - 1 - months] += payment.amountMinor;
  }
  final peak = totals.fold<int>(0, (max, value) => value > max ? value : max);
  if (peak == 0) return const <double>[];
  return totals.map((value) => value / peak).toList(growable: false);
}

/// Outstanding balance has no history in the local mirror, so the series is
/// flat at today's ratio rather than a fabricated curve.
List<double> _outstandingTrend(
  List<RentPayment> payments,
  List<Tenancy> tenancies,
  DateTime now,
) {
  final collected = _monthlyTrend(payments, now);
  if (collected.isEmpty) return const <double>[];
  final owed = tenancies
      .where((t) => t.status != TenancyStatus.ended)
      .fold<int>(0, (total, t) => total + t.balanceMinor);
  final billed = tenancies.fold<int>(
    0,
    (total, t) => total + t.monthlyRentMinor,
  );
  final ratio = billed == 0 ? 0.0 : (owed / billed).clamp(0.0, 1.0);
  return List<double>.filled(collected.length, ratio);
}

List<ActivitySummary> _activity(
  List<RentPayment> payments,
  List<maintenance_domain.MaintenanceRequest> requests,
) {
  final entries = <ActivitySummary>[
    for (final payment in payments.take(4))
      ActivitySummary(
        icon: Icons.check_rounded,
        title: 'Rent received from ${payment.tenantName}',
        detail: '${payment.unitLabel} · ${payment.propertyName}',
        at: payment.paidOn,
        tone: const Color(0xFF367248),
      ),
    for (final request in requests.take(4))
      ActivitySummary(
        icon: Icons.build_outlined,
        title: 'Maintenance: ${request.title}',
        detail: request.location,
        at: request.reportedAt,
        tone: const Color(0xFFC64B2F),
      ),
  ]..sort((a, b) => b.at.compareTo(a.at));
  return entries.take(5).toList(growable: false);
}

/// The newest server acknowledgement across the records the dashboard shows.
/// Null when nothing has ever synced, so the UI can avoid claiming otherwise.
DateTime? _lastSyncedAt(List<RentPayment> payments, List<Unit> units) {
  DateTime? newest;
  for (final at in [
    ...payments.map((p) => p.syncMetadata.lastSyncedAt),
    ...units.map((u) => u.syncMetadata.lastSyncedAt),
  ]) {
    if (at == null) continue;
    if (newest == null || at.isAfter(newest)) newest = at;
  }
  return newest;
}
