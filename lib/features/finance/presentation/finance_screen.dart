import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/offline/aggregate_sync_status.dart';
import '../../../core/offline/offline_entity.dart';
import '../../../core/offline/outbox_entry.dart';
import '../../../core/presentation/coming_soon.dart';
import '../../../core/presentation/page_header.dart';
import '../../../core/presentation/responsive.dart';
import '../../../core/presentation/surface.dart';
import '../../../core/presentation/sync_state_badge.dart';
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
      padding: EdgeInsets.fromLTRB(
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
                  onPressed: () => _showRecordPayment(context),
                  icon: const Icon(Icons.add_card_outlined),
                  label: const Text('Record payment'),
                ),
                secondaryAction: ComingSoon(
                  message: 'Recurring invoices coming soon',
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: Icon(Icons.receipt_long_outlined),
                    label: Text('Generate invoices'),
                  ),
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
                    child: Text('Could not load payments: $error'),
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
          payment.receiptNumber.toLowerCase().contains(query) ||
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
        _FinanceSummary(payments: payments, tenancies: tenancies),
        const SizedBox(height: 22),
        NyumbaSurface(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Payment history',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (!context.isCompact)
                      SizedBox(
                        width: 240,
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: 'Search payments',
                            prefixIcon: Icon(Icons.search_rounded),
                            isDense: true,
                          ),
                          onChanged: (value) =>
                              setState(() => _query = value),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
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
                        label: Text(filter),
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
                  child: Center(child: Text('No payments match this filter.')),
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
                        DataColumn(label: Text('Receipt')),
                        DataColumn(label: Text('Tenant')),
                        DataColumn(label: Text('Unit')),
                        DataColumn(label: Text('Amount')),
                        DataColumn(label: Text('Date')),
                        DataColumn(label: Text('Method')),
                        DataColumn(label: Text('Status')),
                      ],
                      rows: filtered
                          .map(
                            (payment) => DataRow(
                              cells: [
                                DataCell(Text(payment.receiptNumber)),
                                DataCell(Text(payment.tenantName)),
                                DataCell(
                                  Text(
                                    '${payment.unitLabel} · ${payment.propertyName}',
                                  ),
                                ),
                                DataCell(
                                  Text(_formatMinor(payment.amountMinor)),
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
                  alignment: Alignment.centerRight,
                  child: ComingSoon(
                    message: 'Report export coming soon',
                    child: TextButton.icon(
                      onPressed: null,
                      icon: Icon(Icons.download_outlined, size: 18),
                      label: Text('Export report'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showRecordPayment(BuildContext context) async {
    final tenancies = ref.read(tenanciesProvider).value ?? const <Tenancy>[];
    if (tenancies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a tenant before recording a payment.'),
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
          title: const Text('Record payment'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selected.id,
                    decoration: const InputDecoration(
                      labelText: 'Tenant and unit',
                    ),
                    items: [
                      for (final tenancy in tenancies)
                        DropdownMenuItem(
                          value: tenancy.id,
                          child: Text(
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
                    alignment: Alignment.centerLeft,
                    child: Text(
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
                    decoration: const InputDecoration(
                      labelText: 'Amount',
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
                    decoration: const InputDecoration(
                      labelText: 'Payment method',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                      DropdownMenuItem(
                        value: 'MTN Mobile Money',
                        child: Text('MTN Mobile Money'),
                      ),
                      DropdownMenuItem(
                        value: 'Airtel Money',
                        child: Text('Airtel Money'),
                      ),
                      DropdownMenuItem(
                        value: 'Card (Bank)',
                        child: Text('Card (Bank)'),
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
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(context, true);
              },
              child: const Text('Save payment'),
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
              content: Text(
                'Payment recorded locally and queued to sync — awaiting confirmation.',
              ),
            ),
          );
        }
      } on Object catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(this.context).showSnackBar(
            SnackBar(content: Text('Could not record the payment: $error')),
          );
        }
      }
    }
    amount.dispose();
  }
}

class _FinanceSummary extends StatelessWidget {
  const _FinanceSummary({required this.payments, required this.tenancies});

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000 ? 4 : 2;
        const gap = 14.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in summaries)
              SizedBox(
                width: width,
                height: 136,
                child: NyumbaSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(item.$3, color: item.$4, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.$1,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FittedBox(
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.scaleDown,
                        child: Text(
                          item.$2,
                          style: Theme.of(
                            context,
                          ).textTheme.titleLarge?.copyWith(color: item.$4),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        item.$5,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
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
                Text(
                  payment.tenantName,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
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
              Text(
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
