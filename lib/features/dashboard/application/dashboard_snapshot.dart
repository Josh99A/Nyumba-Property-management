import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
}

final dashboardSnapshotProvider = Provider<DashboardSnapshot>((ref) {
  final now = DateTime.now();
  return DashboardSnapshot(
    totalUnits: 24,
    occupiedUnits: 20,
    rentCollectedMinor: 84250000,
    rentOutstandingMinor: 11750000,
    openRequests: 6,
    collectionTrend: const [.08, .24, .33, .47, .60, .66, .74, .78, .83, .84],
    outstandingTrend: const [
      .08,
      .09,
      .10,
      .11,
      .105,
      .112,
      .115,
      .116,
      .117,
      .1175,
    ],
    recentPayments: [
      RecentPayment(
        id: 'pay-1',
        tenant: 'Brian Otieno',
        unit: 'B4',
        property: 'Sunset Apartments',
        amountMinor: 4500000,
        date: DateTime(now.year, now.month, 24),
        state: PaymentState.paid,
      ),
      RecentPayment(
        id: 'pay-2',
        tenant: 'Grace Wanjiku',
        unit: 'D1',
        property: 'Riverside Heights',
        amountMinor: 5000000,
        date: DateTime(now.year, now.month, 24),
        state: PaymentState.paid,
      ),
      RecentPayment(
        id: 'pay-3',
        tenant: 'Peter Mwangi',
        unit: 'A1',
        property: 'Greenview Court',
        amountMinor: 4000000,
        date: DateTime(now.year, now.month, 23),
        state: PaymentState.paid,
      ),
      RecentPayment(
        id: 'pay-4',
        tenant: 'Mary Muthoni',
        unit: 'C2',
        property: 'Nyumbani Gardens',
        amountMinor: 4750000,
        date: DateTime(now.year, now.month, 22),
        state: PaymentState.paid,
      ),
      RecentPayment(
        id: 'pay-5',
        tenant: 'James Kariuki',
        unit: 'B2',
        property: 'Sunset Apartments',
        amountMinor: 4500000,
        date: DateTime(now.year, now.month, 21),
        state: PaymentState.paid,
      ),
    ],
    maintenance: [
      MaintenanceSummary(
        id: 'maintenance-1',
        title: 'Leaking tap in kitchen',
        unit: 'A2',
        property: 'Greenview Court',
        reportedBy: 'Alice Njeri',
        reportedAt: now.subtract(const Duration(hours: 1)),
        priority: MaintenancePriority.urgent,
      ),
      MaintenanceSummary(
        id: 'maintenance-2',
        title: 'No power in the living room',
        unit: 'D3',
        property: 'Riverside Heights',
        reportedBy: 'John M.',
        reportedAt: now.subtract(const Duration(hours: 3)),
        priority: MaintenancePriority.high,
      ),
      MaintenanceSummary(
        id: 'maintenance-3',
        title: 'Water not draining in bathroom',
        unit: 'B1',
        property: 'Sunset Apartments',
        reportedBy: 'Sarah W.',
        reportedAt: now.subtract(const Duration(hours: 5)),
        priority: MaintenancePriority.high,
      ),
    ],
    activity: [
      ActivitySummary(
        icon: Icons.check_rounded,
        title: 'Rent received from Brian Otieno',
        detail: 'Unit B4 · Sunset Apartments',
        at: now.subtract(const Duration(minutes: 20)),
        tone: const Color(0xFF367248),
      ),
      ActivitySummary(
        icon: Icons.build_outlined,
        title: 'New maintenance request',
        detail: 'Leaking tap · Unit A2',
        at: now.subtract(const Duration(hours: 1)),
        tone: const Color(0xFFC64B2F),
      ),
      ActivitySummary(
        icon: Icons.description_outlined,
        title: 'Lease signed by David Kamau',
        detail: 'Unit C3 · Nyumbani Gardens',
        at: now.subtract(const Duration(hours: 3)),
        tone: const Color(0xFF123A6F),
      ),
      ActivitySummary(
        icon: Icons.payments_outlined,
        title: 'Payment overdue',
        detail: 'Unit B5 · Sunset Apartments',
        at: now.subtract(const Duration(hours: 5)),
        tone: const Color(0xFFC98B2E),
      ),
    ],
    lastSyncedAt: now.subtract(const Duration(seconds: 22)),
  );
});
