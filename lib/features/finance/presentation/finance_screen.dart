import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/offline/aggregate_sync_status.dart';
import '../../../core/offline/offline_entity.dart';
import '../../../core/offline/outbox_entry.dart';
import '../../../core/presentation/metric_grid.dart';
import '../../../core/presentation/operational_actions.dart';
import '../../../core/presentation/page_header.dart';
import '../../../core/presentation/responsive.dart';
import '../../../core/presentation/surface.dart';
import '../../../core/presentation/sync_state_badge.dart';
import '../../auth/domain/auth_failure.dart';
import '../../tenants/application/tenancy_providers.dart';
import '../../tenants/domain/tenancy.dart';
import '../application/billing_providers.dart';
import '../domain/rent_payment.dart';

final _ugx = NumberFormat.currency(
  locale: 'en_UG',
  symbol: 'UGX ',
  decimalDigits: 0,
);

String _formatMinor(int amountMinor) => _ugx.format(amountMinor / 100);

/// Turns a rejection code into readable text, e.g. `PAYMENT_NOT_RECEIVED`
/// into "Payment not received".
String _rejectReasonLabel(String code) {
  final words = code.toLowerCase().split('_');
  if (words.isEmpty) return code;
  return [
    words.first[0].toUpperCase() + words.first.substring(1),
    ...words.skip(1),
  ].join(' ');
}

/// Payments tenants reported that are waiting on this landlord's decision.
///
/// Hidden entirely when the queue is empty: an always-present empty panel on
/// the main finance screen would be noise for landlords who record every
/// payment themselves.
class _DeclaredPaymentsPanel extends StatelessWidget {
  const _DeclaredPaymentsPanel({
    required this.payments,
    required this.onConfirm,
    required this.onReject,
  });

  final AsyncValue<List<DeclaredPayment>> payments;
  final ValueChanged<DeclaredPayment> onConfirm;
  final ValueChanged<DeclaredPayment> onReject;

  @override
  Widget build(BuildContext context) {
    final items = payments.value ?? const <DeclaredPayment>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: NyumbaSurface(
        borderColor: context.nyumba.goldBorder,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.fact_check_outlined,
                  color: context.nyumba.terracottaDark,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.localized(
                    'Payments reported by tenants',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text.localized(
              'Check each reference against your records. Confirming settles '
              'the payment and issues a receipt; nothing changes until you do.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.nyumba.mutedInk,
              ),
            ),
            const SizedBox(height: 14),
            for (final (index, payment) in items.indexed) ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  final details = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.localized(
                        '${_formatMinor(payment.amountMinor)} · '
                        '${payment.period}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 2),
                      Text.localized(
                        'Reference: ${payment.reference}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (payment.note case final note?
                          when note.trim().isNotEmpty)
                        Text.localized(
                          note,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: context.nyumba.mutedInk),
                        ),
                    ],
                  );
                  final actions = Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => onReject(payment),
                        icon: const Icon(Icons.block_outlined, size: 18),
                        label: const Text.localized('Reject'),
                      ),
                      FilledButton.icon(
                        onPressed: () => onConfirm(payment),
                        icon: const Icon(Icons.price_check_rounded, size: 18),
                        label: const Text.localized('Confirm'),
                      ),
                    ],
                  );
                  if (constraints.maxWidth < 560) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [details, const SizedBox(height: 10), actions],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: details),
                      const SizedBox(width: 16),
                      actions,
                    ],
                  );
                },
              ),
              if (index < items.length - 1) const Divider(height: 24),
            ],
          ],
        ),
      ),
    );
  }
}

class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key});

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen> {
  String _filter = 'All';
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final paymentsValue = ref.watch(rentPaymentsProvider);
    final tenancies = ref.watch(tenanciesProvider).value ?? const <Tenancy>[];
    final outbox =
        ref.watch(outboxEntriesProvider).value ?? const <OutboxEntry>[];

    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.fromSTEB(
        context.pageGutter,
        26,
        context.pageGutter,
        40,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Finances',
                description:
                    'Track rent, record receipts, and keep every balance honest.',
                primaryAction: FilledButton.icon(
                  onPressed: () => _showRecordPayment(context, tenancies),
                  icon: const Icon(Icons.add_card_outlined),
                  label: const Text.localized('Record payment'),
                ),
                secondaryAction: OutlinedButton.icon(
                  onPressed: () => context.go('/documents'),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text.localized('Generate invoices'),
                ),
              ),
              const SizedBox(height: 24),
              paymentsValue.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stack) => NyumbaSurface(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text.localized('Could not load payments: $error'),
                  ),
                ),
                data: (payments) =>
                    _buildLoaded(context, payments, tenancies, outbox),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoaded(
    BuildContext context,
    List<RentPayment> payments,
    List<Tenancy> tenancies,
    List<OutboxEntry> outbox,
  ) {
    AggregateSyncStatus statusOf(RentPayment payment) =>
        resolveAggregateSyncStatus(
          entityType: OfflineEntityType.payment,
          entityId: payment.id,
          outbox: outbox,
          syncMetadata: payment.syncMetadata,
        );

    final query = _query.trim().toLowerCase();
    final filtered = payments.where((payment) {
      final matchesQuery =
          query.isEmpty ||
          payment.tenantName.toLowerCase().contains(query) ||
          (payment.receiptNumber?.toLowerCase().contains(query) ?? false) ||
          payment.propertyName.toLowerCase().contains(query);
      final matchesFilter = switch (_filter) {
        'Confirmed' => statusOf(payment) == AggregateSyncStatus.synced,
        'Awaiting sync' => statusOf(payment) != AggregateSyncStatus.synced,
        _ => true,
      };
      return matchesQuery && matchesFilter;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FinanceSummary(payments: payments, tenancies: tenancies),
        const SizedBox(height: 22),
        _DeclaredPaymentsPanel(
          payments: ref.watch(declaredPaymentsProvider),
          onConfirm: _confirmDeclared,
          onReject: _rejectDeclared,
        ),
        NyumbaSurface(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 20, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.localized(
                        'Payment history',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (!context.isCompact)
                      SizedBox(
                        width: 240,
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: context.tr('Search payments'),
                            prefixIcon: Icon(Icons.search_rounded),
                            isDense: true,
                          ),
                          onChanged: (value) => setState(() => _query = value),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 14),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final filter in const [
                      'All',
                      'Confirmed',
                      'Awaiting sync',
                    ])
                      ChoiceChip(
                        label: Text.localized(filter),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                  ],
                ),
              ),
              const Divider(),
              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(36),
                  child: Center(
                    child: Text.localized('No payments match this filter.'),
                  ),
                )
              else if (context.isCompact)
                for (final payment in filtered)
                  _CompactFinanceRow(
                    payment: payment,
                    syncStatus: statusOf(payment),
                  )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 900),
                    child: DataTable(
                      horizontalMargin: 20,
                      columnSpacing: 36,
                      columns: const [
                        DataColumn(label: Text.localized('Receipt')),
                        DataColumn(label: Text.localized('Tenant')),
                        DataColumn(label: Text.localized('Rental space')),
                        DataColumn(label: Text.localized('Amount')),
                        DataColumn(label: Text.localized('Date')),
                        DataColumn(label: Text.localized('Method')),
                        DataColumn(label: Text.localized('Status')),
                      ],
                      rows: filtered
                          .map(
                            (payment) => DataRow(
                              cells: [
                                // No number until the server issues the
                                // receipt, so say so rather than inventing one.
                                DataCell(
                                  payment.receiptNumber == null
                                      ? Text.localized(
                                          'Awaiting receipt',
                                          style: TextStyle(
                                            fontStyle: FontStyle.italic,
                                            color: context.nyumba.mutedInk,
                                          ),
                                        )
                                      : Text.localized(payment.receiptNumber!),
                                ),
                                DataCell(Text.localized(payment.tenantName)),
                                DataCell(
                                  Text.localized(
                                    '${payment.unitLabel} · ${payment.propertyName}',
                                  ),
                                ),
                                DataCell(
                                  Text.localized(
                                    _formatMinor(payment.amountMinor),
                                  ),
                                ),
                                DataCell(
                                  Text.localized(
                                    DateFormat(
                                      'd MMM y',
                                    ).format(payment.paidOn.toLocal()),
                                  ),
                                ),
                                DataCell(Text.localized(payment.method)),
                                DataCell(
                                  SyncStateBadge(
                                    status: statusOf(payment),
                                    compact: false,
                                  ),
                                ),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    onPressed: () => _exportPayments(payments),
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text.localized('Export report'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Accepts a payment the tenant reported: the server settles it against
  /// their invoices and issues the receipt.
  Future<void> _confirmDeclared(DeclaredPayment payment) async {
    try {
      await ref.read(reviewDeclaredPaymentProvider).confirm(payment);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text.localized(
              'Payment confirmed. A receipt has been issued to your tenant.',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text.localized(
              'Could not confirm: ${describeAuthFailure(error)}',
            ),
          ),
        );
      }
    }
  }

  /// Refuses a reported payment with a reason the tenant will see. Nothing
  /// financial unwinds, because a declaration never settled anything.
  Future<void> _rejectDeclared(DeclaredPayment payment) async {
    var reasonCode = declaredPaymentRejectReasons.first;
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text.localized('Reject this reported payment?'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.localized(
                  'Your tenant is told why, and their balance stays exactly '
                  'as it is — nothing was settled by the report.',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: reasonCode,
                  decoration: InputDecoration(
                    labelText: dialogContext.tr('Reason'),
                  ),
                  items: [
                    for (final code in declaredPaymentRejectReasons)
                      DropdownMenuItem(
                        value: code,
                        child: Text.localized(_rejectReasonLabel(code)),
                      ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => reasonCode = value ?? declaredPaymentRejectReasons.first,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: dialogContext.tr('Note to tenant (optional)'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text.localized('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text.localized('Reject payment'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await ref
            .read(reviewDeclaredPaymentProvider)
            .reject(
              payment,
              reasonCode: reasonCode,
              note: noteController.text,
            );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text.localized(
                'Payment rejected. Your tenant has been told why.',
              ),
            ),
          );
        }
      } on Object catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text.localized(
                'Could not reject: ${describeAuthFailure(error)}',
              ),
            ),
          );
        }
      }
    }
    noteController.dispose();
  }

  Future<void> _exportPayments(List<RentPayment> payments) async {
    final rows = <String>[
      'receipt,tenant,unit,property,amount_minor,date,method',
      for (final payment in payments)
        [
          payment.receiptNumber,
          payment.tenantName,
          payment.unitLabel,
          payment.propertyName,
          payment.amountMinor,
          payment.paidOn.toUtc().toIso8601String(),
          payment.method,
        ].map(csvCell).join(','),
    ];
    try {
      final saved = await exportTextFile(
        fileName: 'nyumba-payments.csv',
        contents: rows.join('\n'),
      );
      if (mounted && saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text.localized('Payment report exported.')),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text.localized('Could not export report: $error')),
        );
      }
    }
  }

  Future<void> _showRecordPayment(
    BuildContext context,
    List<Tenancy> tenancies,
  ) async {
    if (tenancies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text.localized('Add a tenant before recording a payment.'),
        ),
      );
      return;
    }
    final formKey = GlobalKey<FormState>();
    final amount = TextEditingController();
    var selected = tenancies.first;
    var method = 'MTN Mobile Money';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text.localized('Record payment'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selected.id,
                    decoration: InputDecoration(
                      labelText: context.tr('Tenant and rental space'),
                    ),
                    items: [
                      for (final tenancy in tenancies)
                        DropdownMenuItem(
                          value: tenancy.id,
                          child: Text.localized(
                            '${tenancy.tenantName} · ${tenancy.unitLabel}',
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      final match = tenancies.where(
                        (tenancy) => tenancy.id == value,
                      );
                      if (match.isNotEmpty) {
                        setDialogState(() => selected = match.first);
                      }
                    },
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text.localized(
                      selected.balanceDue
                          ? 'Outstanding: ${_formatMinor(selected.balanceMinor)}'
                          : 'No outstanding balance',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: amount,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.tr('Amount'),
                      prefixText: 'UGX ',
                    ),
                    validator: (value) {
                      final parsed = int.tryParse(
                        value?.replaceAll(',', '') ?? '',
                      );
                      return parsed == null || parsed <= 0
                          ? 'Enter a valid amount'
                          : null;
                    },
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: method,
                    decoration: InputDecoration(
                      labelText: context.tr('Payment method'),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Cash',
                        child: Text.localized('Cash'),
                      ),
                      DropdownMenuItem(
                        value: 'MTN Mobile Money',
                        child: Text.localized('MTN Mobile Money'),
                      ),
                      DropdownMenuItem(
                        value: 'Airtel Money',
                        child: Text.localized('Airtel Money'),
                      ),
                      DropdownMenuItem(
                        value: 'Card (Bank)',
                        child: Text.localized('Card (Bank)'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => method = value);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text.localized('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(context, true);
              },
              child: const Text.localized('Save payment'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      try {
        await ref.read(recordRentPaymentProvider)(
          RecordRentPaymentInput(
            tenancyId: selected.id,
            amountMinor:
                int.parse(amount.text.replaceAll(',', '').trim()) * 100,
            method: method,
          ),
        );
        if (mounted) {
          ScaffoldMessenger.of(this.context).showSnackBar(
            const SnackBar(
              content: Text.localized(
                'Payment recorded locally and queued to sync — awaiting confirmation.',
              ),
            ),
          );
        }
      } on Object catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(this.context).showSnackBar(
            SnackBar(
              content: Text.localized('Could not record the payment: $error'),
            ),
          );
        }
      }
    }
    amount.dispose();
  }
}

@visibleForTesting
class FinanceSummary extends StatelessWidget {
  const FinanceSummary({
    required this.payments,
    required this.tenancies,
    super.key,
  });

  final List<RentPayment> payments;
  final List<Tenancy> tenancies;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final collectedThisMonth = payments
        .where(
          (payment) =>
              payment.paidOn.toLocal().year == now.year &&
              payment.paidOn.toLocal().month == now.month,
        )
        .fold<int>(0, (sum, payment) => sum + payment.amountMinor);
    final outstanding = tenancies.fold<int>(
      0,
      (sum, tenancy) => sum + tenancy.balanceMinor,
    );
    final owingTenancies = tenancies.where((item) => item.balanceDue).length;
    final fullMonthBehind = tenancies
        .where((item) => item.balanceMinor >= item.monthlyRentMinor)
        .toList();
    final overdue = fullMonthBehind.fold<int>(
      0,
      (sum, tenancy) => sum + tenancy.balanceMinor,
    );
    final receiptsThisMonth = payments
        .where(
          (payment) =>
              payment.paidOn.toLocal().year == now.year &&
              payment.paidOn.toLocal().month == now.month,
        )
        .length;

    final summaries = [
      (
        'Collected this month',
        _formatMinor(collectedThisMonth),
        Icons.trending_up_rounded,
        context.nyumba.sageDark,
        '$receiptsThisMonth receipt${receiptsThisMonth == 1 ? '' : 's'} recorded',
      ),
      (
        'Outstanding',
        _formatMinor(outstanding),
        Icons.schedule_rounded,
        context.nyumba.terracottaDark,
        '$owingTenancies tenanc${owingTenancies == 1 ? 'y' : 'ies'} with a balance',
      ),
      (
        'A month or more behind',
        _formatMinor(overdue),
        Icons.error_outline_rounded,
        context.nyumba.danger,
        '${fullMonthBehind.length} tenant${fullMonthBehind.length == 1 ? '' : 's'} require follow-up',
      ),
      (
        'Active tenancies',
        '${tenancies.where((item) => item.status == TenancyStatus.active).length}',
        Icons.people_outline_rounded,
        context.nyumba.midnightNavy,
        'Across the portfolio',
      ),
    ];

    return MetricGrid(
      minRowHeight: 136,
      columnsForWidth: (width) => width >= 1000 ? 4 : 2,
      children: [
        for (final item in summaries)
          NyumbaSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(item.$3, color: item.$4, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.localized(
                        item.$1,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                FittedBox(
                  alignment: AlignmentDirectional.centerStart,
                  fit: BoxFit.scaleDown,
                  child: Text.localized(
                    item.$2,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: item.$4),
                  ),
                ),
                const Spacer(),
                Text.localized(
                  item.$5,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CompactFinanceRow extends StatelessWidget {
  const _CompactFinanceRow({required this.payment, required this.syncStatus});

  final RentPayment payment;
  final AggregateSyncStatus syncStatus;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.nyumba.divider)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: context.nyumba.sageTint,
            child: Icon(
              Icons.south_west_rounded,
              size: 18,
              color: context.nyumba.sageDark,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.localized(
                  payment.tenantName,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text.localized(
                  '${payment.unitLabel} · '
                  '${DateFormat('d MMM').format(payment.paidOn.toLocal())}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text.localized(
                _formatMinor(payment.amountMinor),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              SyncStateBadge(status: syncStatus, compact: false),
            ],
          ),
        ],
      ),
    );
  }
}
