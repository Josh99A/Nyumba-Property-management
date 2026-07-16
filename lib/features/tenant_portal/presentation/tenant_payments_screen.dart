import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/documents/nyumba_document_service.dart';
import '../../../core/offline/aggregate_sync_status.dart';
import '../../../core/offline/offline_entity.dart';
import '../../../core/offline/outbox_entry.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import '../../auth/application/session_controller.dart';
import '../../finance/application/billing_providers.dart';
import '../../finance/domain/rent_payment.dart';
import '../../tenants/application/tenancy_providers.dart';
import '../../tenants/domain/tenancy.dart';
import 'widgets/tenant_components.dart';

String _paymentStatusLabel(AggregateSyncStatus status) => switch (status) {
  AggregateSyncStatus.synced => 'Paid',
  AggregateSyncStatus.pending || AggregateSyncStatus.syncing => 'Awaiting sync',
  AggregateSyncStatus.rejected => 'Rejected',
  AggregateSyncStatus.blocked => 'Blocked',
  AggregateSyncStatus.conflicted => 'Conflicted',
  // A payment always carries a sync intent, so this is unreachable in practice
  // — but it must never fall into the 'Paid' branch if that ever changes.
  AggregateSyncStatus.localOnly => 'On this device',
};

class TenantPaymentsScreen extends ConsumerStatefulWidget {
  const TenantPaymentsScreen({super.key});

  @override
  ConsumerState<TenantPaymentsScreen> createState() =>
      _TenantPaymentsScreenState();
}

class _TenantPaymentsScreenState extends ConsumerState<TenantPaymentsScreen> {
  String _filter = 'All';
  String _defaultMethod = 'MTN MoMo ••• 0841';

  String get _tenantId => ref.read(sessionControllerProvider)?.userId ?? '';

  @override
  Widget build(BuildContext context) {
    final tenancyValue = ref.watch(myTenancyProvider(_tenantId));
    return tenancyValue.when(
      loading: () => const TenantPage(
        title: 'Payments',
        description:
            'Manage rent, invoices, receipts, and your payment history.',
        children: [
          Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
      error: (error, stack) => TenantPage(
        title: 'Payments',
        description:
            'Manage rent, invoices, receipts, and your payment history.',
        children: [
          NyumbaSurface(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load your tenancy: $error'),
            ),
          ),
        ],
      ),
      data: (tenancy) => tenancy == null
          ? const TenantPage(
              title: 'Payments',
              description:
                  'Manage rent, invoices, receipts, and your payment history.',
              children: [
                NyumbaSurface(
                  child: TenantEmptyState(
                    title: 'No tenancy on this device yet',
                    message:
                        'Your lease details will appear after your landlord '
                        'links this account to a rental space.',
                    icon: Icons.home_outlined,
                  ),
                ),
              ],
            )
          : _buildLoaded(context, tenancy),
    );
  }

  Widget _buildLoaded(BuildContext context, Tenancy tenancy) {
    final payments =
        ref.watch(tenancyPaymentsProvider(tenancy.id)).value ??
        const <RentPayment>[];
    final outbox =
        ref.watch(outboxEntriesProvider).value ?? const <OutboxEntry>[];
    String statusOf(RentPayment payment) => _paymentStatusLabel(
      resolveAggregateSyncStatus(
        entityType: OfflineEntityType.payment,
        entityId: payment.id,
        outbox: outbox,
        syncMetadata: payment.syncMetadata,
      ),
    );

    final paid = !tenancy.balanceDue;
    final balanceWhole = tenancy.balanceMinor ~/ 100;
    final rentWhole = tenancy.monthlyRentMinor ~/ 100;
    final filtered = payments.where((payment) {
      return switch (_filter) {
        'Paid' => statusOf(payment) == 'Paid',
        'Awaiting sync' => statusOf(payment) == 'Awaiting sync',
        _ => true,
      };
    }).toList();
    final paidThisYear = payments
        .where(
          (payment) => payment.paidOn.toLocal().year == DateTime.now().year,
        )
        .fold<int>(0, (sum, payment) => sum + payment.amountMinor);
    final now = DateTime.now();

    return TenantPage(
      title: 'Payments',
      description: 'Manage rent, invoices, receipts, and your payment history.',
      secondaryAction: OutlinedButton.icon(
        onPressed: () => _printStatement(tenancy, payments),
        icon: const Icon(Icons.print_outlined),
        label: const Text('Print statement'),
      ),
      primaryAction: FilledButton.icon(
        onPressed: paid
            ? () => _showCurrentReceipt(payments, statusOf)
            : () => _payRent(tenancy),
        icon: Icon(
          paid ? Icons.receipt_long_outlined : Icons.payments_outlined,
        ),
        label: Text(paid ? 'Latest receipt' : 'Pay rent'),
      ),
      children: [
        TenantBalanceHero(
          amount: balanceWhole,
          dueLabel: paid
              ? 'No balance outstanding'
              : '${DateFormat('MMMM y').format(now)} rent • due on the 5th',
          paid: paid,
          onPay: paid
              ? () => _showCurrentReceipt(payments, statusOf)
              : () => _payRent(tenancy),
        ),
        const SizedBox(height: 18),
        TenantMetricGrid(
          children: [
            TenantMetricCard(
              label: 'Paid in ${now.year}',
              value: formatTenantUgx(paidThisYear ~/ 100),
              caption:
                  '${payments.length} payment${payments.length == 1 ? '' : 's'} recorded',
              icon: Icons.savings_outlined,
              color: context.nyumba.sageDark,
            ),
            TenantMetricCard(
              label: 'Monthly rent',
              value: formatTenantUgx(rentWhole),
              caption: 'Due on the 5th of each month',
              icon: Icons.calendar_month_outlined,
              color: context.nyumba.midnightNavy,
            ),
            TenantMetricCard(
              label: 'Saved payment method',
              value: _defaultMethod,
              caption: 'Used only after confirmation',
              icon: Icons.account_balance_wallet_outlined,
              color: context.nyumba.terracottaDark,
            ),
          ],
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final invoice = _InvoicePanel(
              tenancy: tenancy,
              onPay: paid
                  ? () => _showCurrentReceipt(payments, statusOf)
                  : () => _payRent(tenancy),
            );
            final methods = _PaymentMethodsPanel(
              defaultMethod: _defaultMethod,
              onManage: _manageMethods,
            );
            if (constraints.maxWidth < 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [invoice, const SizedBox(height: 20), methods],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: invoice),
                const SizedBox(width: 20),
                Expanded(flex: 5, child: methods),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        NyumbaSurface(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payment history',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Receipts remain available on this device while offline.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in const [
                          'All',
                          'Paid',
                          'Awaiting sync',
                        ])
                          ChoiceChip(
                            label: Text(item),
                            selected: _filter == item,
                            showCheckmark: false,
                            onSelected: (_) => setState(() => _filter = item),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(),
              if (filtered.isEmpty)
                TenantEmptyState(
                  title: 'No $_filter payments',
                  message: 'Payment records with this status will appear here.',
                  action: OutlinedButton(
                    onPressed: () => setState(() => _filter = 'All'),
                    child: const Text('Show all payments'),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 780) {
                      return Column(
                        children: [
                          for (
                            var index = 0;
                            index < filtered.length;
                            index++
                          ) ...[
                            _PaymentCard(
                              payment: filtered[index],
                              status: statusOf(filtered[index]),
                              onReceipt: () => _showReceipt(
                                filtered[index],
                                statusOf(filtered[index]),
                              ),
                            ),
                            if (index < filtered.length - 1) const Divider(),
                          ],
                        ],
                      );
                    }
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                        ),
                        child: DataTable(
                          horizontalMargin: 20,
                          columnSpacing: 34,
                          headingRowHeight: 46,
                          dataRowMinHeight: 58,
                          dataRowMaxHeight: 68,
                          columns: const [
                            DataColumn(label: Text('Period')),
                            DataColumn(label: Text('Reference')),
                            DataColumn(label: Text('Paid on')),
                            DataColumn(label: Text('Method')),
                            DataColumn(label: Text('Amount')),
                            DataColumn(label: Text('Status')),
                            DataColumn(label: Text('')),
                          ],
                          rows: [
                            for (final payment in filtered)
                              DataRow(
                                cells: [
                                  DataCell(Text(payment.period)),
                                  DataCell(
                                    Text(
                                      payment.receiptNumber ??
                                          'Awaiting receipt',
                                      style: payment.hasIssuedReceipt
                                          ? null
                                          : TextStyle(
                                              fontStyle: FontStyle.italic,
                                              color: context.nyumba.mutedInk,
                                            ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      DateFormat(
                                        'd MMM y',
                                      ).format(payment.paidOn.toLocal()),
                                    ),
                                  ),
                                  DataCell(Text(payment.method)),
                                  DataCell(
                                    Text(
                                      formatTenantUgx(
                                        payment.amountMinor ~/ 100,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    TenantStatusBadge(
                                      status: statusOf(payment),
                                    ),
                                  ),
                                  DataCell(
                                    IconButton(
                                      tooltip: statusOf(payment) == 'Paid'
                                          ? 'View receipt'
                                          : 'View details',
                                      onPressed: () => _showReceipt(
                                        payment,
                                        statusOf(payment),
                                      ),
                                      icon: const Icon(
                                        Icons.chevron_right_rounded,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _payRent(Tenancy tenancy) async {
    var method = _defaultMethod.startsWith('MTN') ? 'MTN MoMo' : 'Card (Bank)';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Pay ${DateFormat('MMMM').format(DateTime.now())} rent'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.nyumba.navyTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Expanded(child: Text('Amount payable')),
                      Text(
                        formatTenantUgx(tenancy.balanceMinor ~/ 100),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 17),
                Text(
                  'Payment method',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                for (final item in const [
                  'Cash',
                  'MTN MoMo',
                  'Airtel Money',
                  'Card (Bank)',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () => setDialogState(() => method = item),
                      borderRadius: BorderRadius.circular(11),
                      child: Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: method == item
                                ? context.nyumba.midnightNavy
                                : context.nyumba.outline,
                          ),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              item == 'Cash'
                                  ? Icons.payments_outlined
                                  : item == 'Card (Bank)'
                                  ? Icons.credit_card_outlined
                                  : Icons.phone_android_rounded,
                              color: context.nyumba.midnightNavy,
                            ),
                            const SizedBox(width: 11),
                            Expanded(child: Text(item)),
                            if (method == item)
                              Icon(
                                Icons.check_circle_rounded,
                                color: context.nyumba.sageDark,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                const Text(
                  'You will review the provider confirmation before the '
                  'payment is finalized.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.lock_outline_rounded),
              label: Text('Continue with $method'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(recordRentPaymentProvider)(
        RecordRentPaymentInput(
          tenancyId: tenancy.id,
          amountMinor: tenancy.balanceMinor,
          method: method,
        ),
      );
      if (mounted) {
        showTenantMessage(
          context,
          'Payment recorded locally and queued to sync.',
        );
      }
    } on Object catch (error) {
      if (mounted) {
        showTenantMessage(context, 'Could not record the payment: $error');
      }
    }
  }

  Future<void> _manageMethods() async {
    var selected = _defaultMethod;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Payment methods'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in const [
                  'MTN MoMo ••• 0841',
                  'Airtel Money ••• 0522',
                  'Stanbic Bank ••• 7810',
                ])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: context.nyumba.navyTint,
                      child: Icon(
                        item.startsWith('Stanbic')
                            ? Icons.account_balance_outlined
                            : Icons.phone_android_rounded,
                        color: context.nyumba.midnightNavy,
                      ),
                    ),
                    title: Text(item),
                    subtitle: Text(
                      selected == item ? 'Default method' : 'Available method',
                    ),
                    trailing: selected == item
                        ? Icon(
                            Icons.check_circle_rounded,
                            color: context.nyumba.sageDark,
                          )
                        : null,
                    onTap: () => setDialogState(() => selected = item),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => showTenantMessage(
                    dialogContext,
                    'New payment methods are verified before saving.',
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add payment method'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: const Text('Set as default'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _defaultMethod = result);
    showTenantMessage(context, '$result is now your default method.');
  }

  Future<void> _showCurrentReceipt(
    List<RentPayment> payments,
    String Function(RentPayment) statusOf,
  ) {
    if (payments.isEmpty) {
      showTenantMessage(context, 'No payments recorded yet.');
      return Future<void>.value();
    }
    return _showReceipt(payments.first, statusOf(payments.first));
  }

  Future<void> _showReceipt(RentPayment payment, String status) {
    // Only a server-issued receipt may present itself as one; a payment the
    // device merely recorded stays framed as a pending payment record even
    // when its local status already reads as settled.
    final issued = payment.hasIssuedReceipt;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(issued ? 'Payment receipt' : 'Payment details'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: TenantStatusBadge(status: status)),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  formatTenantUgx(payment.amountMinor ~/ 100),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              const SizedBox(height: 18),
              TenantInfoRow(
                icon: Icons.calendar_month_outlined,
                label: 'Rent period',
                value: payment.period,
              ),
              const SizedBox(height: 12),
              TenantInfoRow(
                icon: Icons.tag_rounded,
                label: 'Reference',
                value: payment.receiptNumber ?? 'Issued once confirmed',
              ),
              const SizedBox(height: 12),
              TenantInfoRow(
                icon: Icons.payments_outlined,
                label: 'Payment',
                value:
                    '${DateFormat('d MMM y').format(payment.paidOn.toLocal())}'
                    ' • ${payment.method}',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          if (issued)
            FilledButton.icon(
              onPressed: () => _printReceipt(payment),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Print receipt'),
            ),
        ],
      ),
    );
  }

  Future<void> _printStatement(
    Tenancy tenancy,
    List<RentPayment> payments,
  ) async {
    final total = payments.fold<int>(0, (sum, item) => sum + item.amountMinor);
    try {
      await const PdfDocumentService().print(
        PrintableDocumentData(
          title: 'Rent statement',
          number: 'STM-${DateTime.now().year}-${tenancy.id.substring(0, 6)}',
          recipient: tenancy.tenantName,
          property: tenancy.propertyName,
          unit: tenancy.unitLabel,
          amountMinor: total,
          date: DateTime.now(),
          status:
              '${payments.length} recorded payment${payments.length == 1 ? '' : 's'}',
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        showTenantMessage(context, 'Could not print statement: $error');
      }
    }
  }

  Future<void> _printReceipt(RentPayment payment) async {
    try {
      await const PdfDocumentService().print(
        PrintableDocumentData(
          // Printing an unconfirmed payment as a "Receipt / Paid" would hand a
          // tenant a document asserting something the server has not agreed to.
          title: payment.hasIssuedReceipt ? 'Receipt' : 'Payment record',
          number: payment.receiptNumber ?? 'Not yet issued',
          recipient: payment.tenantName,
          property: payment.propertyName,
          unit: payment.unitLabel,
          amountMinor: payment.amountMinor,
          date: payment.paidOn,
          status: payment.hasIssuedReceipt ? 'Paid' : 'Awaiting confirmation',
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        showTenantMessage(context, 'Could not print receipt: $error');
      }
    }
  }
}

class _InvoicePanel extends StatelessWidget {
  const _InvoicePanel({required this.tenancy, required this.onPay});

  final Tenancy tenancy;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final paid = !tenancy.balanceDue;
    return TenantPanel(
      title: 'Current balance',
      subtitle: '${tenancy.unitLabel} · ${tenancy.propertyName}',
      trailing: TenantStatusBadge(status: paid ? 'Paid' : 'Pending'),
      child: Column(
        children: [
          _InvoiceLine(
            label: 'Monthly rent',
            amount: formatTenantUgx(tenancy.monthlyRentMinor ~/ 100),
          ),
          const SizedBox(height: 10),
          const _InvoiceLine(label: 'Service charges', amount: 'UGX 0'),
          const SizedBox(height: 10),
          const _InvoiceLine(label: 'Credits applied', amount: 'UGX 0'),
          const Divider(height: 27),
          _InvoiceLine(
            label: paid ? 'Amount outstanding' : 'Amount due',
            amount: formatTenantUgx(tenancy.balanceMinor ~/ 100),
            emphasized: true,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onPay,
              icon: Icon(
                paid ? Icons.receipt_long_outlined : Icons.lock_outline_rounded,
              ),
              label: Text(paid ? 'View receipt' : 'Pay balance'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceLine extends StatelessWidget {
  const _InvoiceLine({
    required this.label,
    required this.amount,
    this.emphasized = false,
  });

  final String label;
  final String amount;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(amount, style: style),
      ],
    );
  }
}

class _PaymentMethodsPanel extends StatelessWidget {
  const _PaymentMethodsPanel({
    required this.defaultMethod,
    required this.onManage,
  });

  final String defaultMethod;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return TenantPanel(
      title: 'Payment methods',
      subtitle: 'You always confirm before a charge',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: context.nyumba.sageTint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.nyumba.sageBorder),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Icon(
                    Icons.phone_android_rounded,
                    color: context.nyumba.sageDark,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        defaultMethod,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Text(
                        'Default payment method',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const StatusBadge(label: 'Verified', tone: BadgeTone.success),
              ],
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Icon(
                Icons.shield_outlined,
                size: 19,
                color: context.nyumba.sageDark,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Nyumba does not store your mobile money PIN or bank password.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          OutlinedButton.icon(
            onPressed: onManage,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Manage methods'),
          ),
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({
    required this.payment,
    required this.status,
    required this.onReceipt,
  });

  final RentPayment payment;
  final String status;
  final VoidCallback onReceipt;

  @override
  Widget build(BuildContext context) {
    final settled = status == 'Paid';
    return InkWell(
      onTap: onReceipt,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: settled
                    ? context.nyumba.sageTint
                    : context.nyumba.goldTint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                settled ? Icons.check_rounded : Icons.schedule_rounded,
                color: settled
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
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    '${payment.receiptNumber} • '
                    '${DateFormat('d MMM y').format(payment.paidOn.toLocal())}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatTenantUgx(payment.amountMinor ~/ 100),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                TenantStatusBadge(status: status),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
