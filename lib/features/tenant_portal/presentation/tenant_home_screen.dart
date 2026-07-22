import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/localization/app_localizations_adapter.dart';
import '../../../core/offline/aggregate_sync_status.dart';
import '../../../core/offline/offline_entity.dart';
import '../../../core/offline/outbox_entry.dart';
import '../../../core/presentation/status_message.dart';
import '../../../core/presentation/surface.dart';
import '../../auth/application/session_controller.dart';
import '../../finance/application/billing_providers.dart';
import '../../finance/domain/rent_payment.dart';
import '../../maintenance/application/maintenance_providers.dart';
import '../../maintenance/domain/maintenance_request.dart';
import '../../notices/application/notice_providers.dart';
import '../../notices/domain/notice.dart';
import '../../tenants/application/tenancy_providers.dart';
import '../../tenants/domain/tenancy.dart';
import 'widgets/tenant_components.dart';

/// The tenant landing page, derived entirely from this device's records.
///
/// Every figure comes from the local mirror: the tenancy this account is
/// linked to, payments recorded against it, maintenance this tenant reported,
/// and notices held locally. An account with no linked tenancy sees that
/// stated plainly — this page previously rendered an invented household
/// ("Brian", UGX 1,200,000, a fake receipt trail) and even pretended to take
/// a payment, which is exactly the kind of lie an offline-first app must
/// never tell.
class TenantHomeScreen extends ConsumerWidget {
  const TenantHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final tenantId = session?.userId ?? '';
    final firstName = session?.firstName ?? 'there';
    final tenancyValue = ref.watch(myTenancyProvider(tenantId));

    return tenancyValue.when(
      loading: () => TenantPage(
        title: 'Hello, $firstName',
        description: 'Here is what is happening with your home.',
        children: const [
          Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
      error: (error, stack) => TenantPage(
        title: 'Hello, $firstName',
        description: 'Here is what is happening with your home.',
        children: [
          NyumbaStatusMessage.fromError(
            error,
            subject: 'your home',
            onRetry: () => ref.invalidate(myTenancyProvider(tenantId)),
          ),
        ],
      ),
      data: (tenancy) => tenancy == null
          ? _NoTenancyHome(firstName: firstName)
          : _TenantHomeLoaded(
              firstName: firstName,
              tenantId: tenantId,
              tenancy: tenancy,
            ),
    );
  }
}

/// Honest landing state for an account no landlord has linked yet.
class _NoTenancyHome extends StatelessWidget {
  const _NoTenancyHome({required this.firstName});

  final String firstName;

  @override
  Widget build(BuildContext context) {
    return TenantPage(
      title: 'Hello, $firstName',
      description: 'Here is what is happening with your home.',
      children: [
        const NyumbaSurface(
          child: TenantEmptyState(
            title: 'No tenancy on this device yet',
            message:
                'Your home, balance, and documents will appear after your '
                'landlord links this account to a rental space. If you were '
                'invited by email, signing in with that address links it '
                'automatically.',
            icon: Icons.home_outlined,
          ),
        ),
        const SizedBox(height: 18),
        TenantQuickAction(
          label: 'Report a problem',
          caption: 'Maintenance requests work while offline',
          icon: Icons.home_repair_service_outlined,
          color: context.nyumba.terracottaDark,
          onTap: () => context.go('/tenant/maintenance'),
        ),
      ],
    );
  }
}

class _TenantHomeLoaded extends ConsumerWidget {
  const _TenantHomeLoaded({
    required this.firstName,
    required this.tenantId,
    required this.tenancy,
  });

  final String firstName;
  final String tenantId;
  final Tenancy tenancy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paid = !tenancy.balanceDue;
    final payments =
        ref.watch(tenancyPaymentsProvider(tenancy.id)).value ??
        const <RentPayment>[];
    final requests =
        ref.watch(tenantMaintenanceRequestsProvider(tenantId)).value ??
        const <MaintenanceRequest>[];
    final notices = ref.watch(noticesProvider).value ?? const <Notice>[];
    final outbox =
        ref.watch(outboxEntriesProvider).value ?? const <OutboxEntry>[];
    final pendingChanges = outbox.length;

    return TenantPage(
      title: 'Hello, $firstName',
      description: 'Here is what is happening with your home.',
      children: [
        TenantBalanceHero(
          amount: tenancy.balanceMinor ~/ 100,
          dueLabel:
              '${DateFormat('MMMM y').format(DateTime.now())} rent • '
              'due on the 5th',
          paid: paid,
          onPay: () => context.go('/tenant/payments'),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1000
                ? 3
                : constraints.maxWidth >= 560
                ? 3
                : 1;
            const spacing = 12.0;
            final width =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                SizedBox(
                  width: width,
                  child: TenantQuickAction(
                    label: paid ? 'Payments & receipts' : 'Pay rent',
                    caption: paid
                        ? 'History and statements'
                        : 'Record and track payments',
                    icon: Icons.payments_outlined,
                    color: context.nyumba.sageDark,
                    onTap: () => context.go('/tenant/payments'),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: TenantQuickAction(
                    label: 'Report a problem',
                    caption: 'Works while offline',
                    icon: Icons.home_repair_service_outlined,
                    color: context.nyumba.terracottaDark,
                    onTap: () => context.go('/tenant/maintenance'),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: TenantQuickAction(
                    label: 'Documents',
                    caption: 'Receipts and lease papers',
                    icon: Icons.folder_copy_outlined,
                    color: context.nyumba.midnightNavy,
                    onTap: () => context.go('/tenant/documents'),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final home = _HomeAndLeasePanel(tenancy: tenancy);
            final maintenance = _MaintenanceSummaryPanel(
              requests: requests,
              outbox: outbox,
            );
            if (constraints.maxWidth < 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [home, const SizedBox(height: 20), maintenance],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: home),
                const SizedBox(width: 20),
                Expanded(flex: 5, child: maintenance),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final noticesPanel = _NoticesPanel(notices: notices);
            final paymentsPanel = _RecentPaymentsPanel(
              payments: payments,
              outbox: outbox,
            );
            if (constraints.maxWidth < 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  noticesPanel,
                  const SizedBox(height: 20),
                  paymentsPanel,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: noticesPanel),
                const SizedBox(width: 20),
                Expanded(flex: 5, child: paymentsPanel),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          decoration: BoxDecoration(
            color: context.nyumba.sageTint,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.nyumba.sageBorder),
          ),
          child: Row(
            children: [
              Icon(
                Icons.offline_pin_outlined,
                size: 20,
                color: context.nyumba.sageDark,
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text.localized(
                  'Records saved on this device stay available offline.',
                ),
              ),
              TenantStatusBadge(
                status: pendingChanges == 0
                    ? 'Up to date'
                    : '$pendingChanges awaiting sync',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Small helper so error surfaces stay one-liners at the call site.
class NyumbaSurfaceMessage extends StatelessWidget {
  const NyumbaSurfaceMessage(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return NyumbaSurface(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text.localized(message),
      ),
    );
  }
}

class _HomeAndLeasePanel extends StatelessWidget {
  const _HomeAndLeasePanel({required this.tenancy});

  final Tenancy tenancy;

  @override
  Widget build(BuildContext context) {
    final leaseFormat = DateFormat('d MMM y');
    return TenantPanel(
      title: 'Your home',
      subtitle: tenancy.propertyName,
      trailing: TenantStatusBadge(
        status: switch (tenancy.status) {
          TenancyStatus.active => 'Active',
          TenancyStatus.noticeGiven => 'Notice given',
          TenancyStatus.ended => 'Ended',
        },
      ),
      child: Column(
        children: [
          TenantInfoRow(
            icon: Icons.meeting_room_outlined,
            label: 'Rental space',
            value: tenancy.unitLabel,
          ),
          const Divider(height: 25),
          TenantInfoRow(
            icon: Icons.calendar_month_outlined,
            label: 'Lease term',
            value:
                '${leaseFormat.format(tenancy.leaseStart.toLocal())} – '
                '${leaseFormat.format(tenancy.leaseEnd.toLocal())}',
          ),
          const Divider(height: 25),
          TenantInfoRow(
            icon: Icons.payments_outlined,
            label: 'Monthly rent',
            value: formatTenantUgx(tenancy.monthlyRentMinor ~/ 100),
          ),
          const Divider(height: 25),
          TenantInfoRow(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Current balance',
            value: tenancy.balanceDue
                ? formatTenantUgx(tenancy.balanceMinor ~/ 100)
                : 'Nothing outstanding',
          ),
        ],
      ),
    );
  }
}

class _MaintenanceSummaryPanel extends ConsumerWidget {
  const _MaintenanceSummaryPanel({
    required this.requests,
    required this.outbox,
  });

  final List<MaintenanceRequest> requests;
  final List<OutboxEntry> outbox;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = requests
        .where(
          (request) =>
              request.status != MaintenanceStatus.resolved &&
              request.status != MaintenanceStatus.cancelled,
        )
        .toList(growable: false);
    return TenantPanel(
      title: 'Maintenance',
      subtitle: open.isEmpty
          ? 'No open requests'
          : '${open.length} open request${open.length == 1 ? '' : 's'}',
      trailing: TextButton(
        onPressed: () => context.go('/tenant/maintenance'),
        child: const Text.localized('View all'),
      ),
      child: open.isEmpty
          ? const TenantEmptyState(
              title: 'Nothing needs attention',
              message:
                  'Report a problem any time — requests are saved on this '
                  'device and sent when you are connected.',
              icon: Icons.task_alt_rounded,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < open.length && index < 2; index++)
                  Padding(
                    padding: EdgeInsets.only(bottom: index == 0 ? 12 : 0),
                    child: _MaintenanceRow(
                      request: open[index],
                      syncStatus: resolveAggregateSyncStatus(
                        entityType: OfflineEntityType.maintenanceRequest,
                        entityId: open[index].id,
                        outbox: outbox,
                        syncMetadata: open[index].syncMetadata,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _MaintenanceRow extends StatelessWidget {
  const _MaintenanceRow({required this.request, required this.syncStatus});

  final MaintenanceRequest request;
  final AggregateSyncStatus syncStatus;

  @override
  Widget build(BuildContext context) {
    final statusLabel = switch (request.status) {
      MaintenanceStatus.submitted => 'Submitted',
      MaintenanceStatus.scheduled => 'Scheduled',
      MaintenanceStatus.inProgress => 'In progress',
      MaintenanceStatus.resolved => 'Resolved',
      MaintenanceStatus.cancelled => 'Cancelled',
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.nyumba.navyTint,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Icon(
            Icons.home_repair_service_outlined,
            color: context.nyumba.midnightNavy,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.localized(
                  request.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text.localized(
                  request.appointment ??
                      (syncStatus == AggregateSyncStatus.synced
                          ? 'Sent to your property manager'
                          : 'Saved on this device — will send when connected'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TenantStatusBadge(status: statusLabel),
        ],
      ),
    );
  }
}

class _NoticesPanel extends StatelessWidget {
  const _NoticesPanel({required this.notices});

  final List<Notice> notices;

  @override
  Widget build(BuildContext context) {
    final recent = [...notices]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return TenantPanel(
      title: 'Notices from your property',
      subtitle: 'Updates shared by your manager',
      child: recent.isEmpty
          ? const TenantEmptyState(
              title: 'No notices yet',
              message:
                  'Notices your property manager publishes will appear here.',
              icon: Icons.campaign_outlined,
            )
          : Column(
              children: [
                for (var index = 0; index < recent.length && index < 3; index++)
                  Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: context.nyumba.midnightNavy.withValues(
                                alpha: .1,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.campaign_outlined,
                              size: 20,
                              color: context.nyumba.midnightNavy,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text.localized(
                                  recent[index].title,
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                const SizedBox(height: 3),
                                Text.localized(
                                  recent[index].body,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text.localized(
                            DateFormat(
                              'd MMM',
                            ).format(recent[index].createdAt.toLocal()),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                      if (index < recent.length - 1 && index < 2)
                        const Divider(height: 25),
                    ],
                  ),
              ],
            ),
    );
  }
}

class _RecentPaymentsPanel extends StatelessWidget {
  const _RecentPaymentsPanel({required this.payments, required this.outbox});

  final List<RentPayment> payments;
  final List<OutboxEntry> outbox;

  @override
  Widget build(BuildContext context) {
    final recent = [...payments]..sort((a, b) => b.paidOn.compareTo(a.paidOn));
    return TenantPanel(
      title: 'Recent payments',
      subtitle: 'Recorded on this device or confirmed by the server',
      trailing: TextButton(
        onPressed: () => context.go('/tenant/payments'),
        child: const Text.localized('View all'),
      ),
      child: recent.isEmpty
          ? const TenantEmptyState(
              title: 'No payments recorded yet',
              message:
                  'Rent payments recorded against your tenancy will appear '
                  'here with their confirmation status.',
              icon: Icons.receipt_long_outlined,
            )
          : Column(
              children: [
                for (var index = 0; index < recent.length && index < 3; index++)
                  Column(
                    children: [
                      _PaymentRow(
                        payment: recent[index],
                        // An unacknowledged payment must never read as money
                        // the server has confirmed.
                        confirmed:
                            resolveAggregateSyncStatus(
                              entityType: OfflineEntityType.payment,
                              entityId: recent[index].id,
                              outbox: outbox,
                              syncMetadata: recent[index].syncMetadata,
                            ) ==
                            AggregateSyncStatus.synced,
                      ),
                      if (index < recent.length - 1 && index < 2)
                        const Divider(height: 25),
                    ],
                  ),
              ],
            ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment, required this.confirmed});

  final RentPayment payment;
  final bool confirmed;

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    final paidOn = DateFormat(
      'd MMM',
      Localizations.localeOf(context).toLanguageTag(),
    ).format(payment.paidOn.toLocal());
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: confirmed
              ? context.nyumba.sageTint
              : context.nyumba.goldTint,
          child: Icon(
            confirmed ? Icons.check_rounded : Icons.schedule_rounded,
            size: 19,
            color: confirmed
                ? context.nyumba.sageDark
                : context.nyumba.terracottaDark,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                payment.period,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Text(
                copy.paymentStatusDate(
                  paidOn,
                  confirmed ? copy.confirmed : copy.awaitingSync,
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Text.localized(
          formatTenantUgx(payment.amountMinor ~/ 100),
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ],
    );
  }
}
