import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/page_header.dart';
import '../../../core/presentation/responsive.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import '../../dashboard/application/dashboard_snapshot.dart';
import '../../dashboard/presentation/widgets/dashboard_cards.dart';

class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key});

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(dashboardSnapshotProvider);
    final payments = dashboard.recentPayments.where((payment) {
      return switch (_filter) {
        'Paid' => payment.state == PaymentState.paid,
        'Pending' => payment.state == PaymentState.pending,
        'Overdue' => payment.state == PaymentState.overdue,
        _ => true,
      };
    }).toList();

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
                    'Track rent, generate invoices, and keep every receipt accounted for.',
                primaryAction: FilledButton.icon(
                  onPressed: () => _showGenerateInvoices(context),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Generate invoices'),
                ),
                secondaryAction: OutlinedButton.icon(
                  onPressed: () => _showRecordPayment(context),
                  icon: const Icon(Icons.add_card_outlined),
                  label: const Text('Record payment'),
                ),
              ),
              const SizedBox(height: 24),
              _FinanceSummary(snapshot: dashboard),
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
                                onChanged: (_) => setState(() {}),
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
                            'Paid',
                            'Pending',
                            'Overdue',
                          ])
                            ChoiceChip(
                              label: Text(filter),
                              selected: _filter == filter,
                              onSelected: (_) =>
                                  setState(() => _filter = filter),
                            ),
                        ],
                      ),
                    ),
                    const Divider(),
                    if (payments.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(36),
                        child: Center(
                          child: Text('No payments match this filter.'),
                        ),
                      )
                    else if (context.isCompact)
                      for (final payment in payments)
                        _CompactFinanceRow(payment: payment)
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
                            rows: payments
                                .map(
                                  (payment) => DataRow(
                                    cells: [
                                      DataCell(
                                        Text('#${payment.id.toUpperCase()}'),
                                      ),
                                      DataCell(Text(payment.tenant)),
                                      DataCell(
                                        Text(
                                          '${payment.unit} · ${payment.property}',
                                        ),
                                      ),
                                      DataCell(
                                        Text(formatKes(payment.amountMinor)),
                                      ),
                                      DataCell(
                                        Text(
                                          DateFormat(
                                            'd MMM y',
                                          ).format(payment.date),
                                        ),
                                      ),
                                      const DataCell(Text('M-Pesa')),
                                      DataCell(
                                        _FinancePaymentBadge(
                                          state: payment.state,
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
                        child: TextButton.icon(
                          onPressed: () =>
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'CSV export queued for generation.',
                                  ),
                                ),
                              ),
                          icon: const Icon(Icons.download_outlined, size: 18),
                          label: const Text('Export report'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FinanceSummary extends StatelessWidget {
  const _FinanceSummary({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final summaries = [
      (
        'Collected this month',
        formatKes(snapshot.rentCollectedMinor),
        Icons.trending_up_rounded,
        NyumbaColors.sageDark,
        '87.8% of rent due',
      ),
      (
        'Outstanding',
        formatKes(snapshot.rentOutstandingMinor),
        Icons.schedule_rounded,
        NyumbaColors.terracottaDark,
        '7 invoices open',
      ),
      (
        'Overdue',
        'KES 62,500',
        Icons.error_outline_rounded,
        NyumbaColors.danger,
        '3 tenants require follow-up',
      ),
      (
        'Next payout',
        'KES 294,000',
        Icons.account_balance_outlined,
        NyumbaColors.midnightNavy,
        'Expected 28 May',
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
  const _CompactFinanceRow({required this.payment});

  final RecentPayment payment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEDE9E2))),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 18,
            backgroundColor: NyumbaColors.sageTint,
            child: Icon(
              Icons.south_west_rounded,
              size: 18,
              color: NyumbaColors.sageDark,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payment.tenant,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  '${payment.unit} · ${DateFormat('d MMM').format(payment.date)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatKes(payment.amountMinor),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              _FinancePaymentBadge(state: payment.state),
            ],
          ),
        ],
      ),
    );
  }
}

class _FinancePaymentBadge extends StatelessWidget {
  const _FinancePaymentBadge({required this.state});

  final PaymentState state;

  @override
  Widget build(BuildContext context) => switch (state) {
    PaymentState.paid => const StatusBadge(
      label: 'Paid',
      tone: BadgeTone.success,
    ),
    PaymentState.pending => const StatusBadge(
      label: 'Pending',
      tone: BadgeTone.warning,
    ),
    PaymentState.overdue => const StatusBadge(
      label: 'Overdue',
      tone: BadgeTone.danger,
    ),
  };
}

Future<void> _showGenerateInvoices(BuildContext context) async {
  var selectedMonth = DateTime.now().month;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Generate rent invoices'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Create draft invoices for every active lease. You can review them before sending.',
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<int>(
                initialValue: selectedMonth,
                decoration: const InputDecoration(labelText: 'Billing month'),
                items: [
                  for (var month = 1; month <= 12; month++)
                    DropdownMenuItem(
                      value: month,
                      child: Text(
                        DateFormat('MMMM').format(DateTime(2026, month)),
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selectedMonth = value);
                  }
                },
              ),
              const SizedBox(height: 14),
              const StatusBadge(
                label: '20 active leases · KES 960,000 total',
                tone: BadgeTone.info,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${DateFormat('MMMM').format(DateTime(2026, selectedMonth))} invoices created locally and queued to sync.',
                  ),
                ),
              );
            },
            child: const Text('Generate drafts'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showRecordPayment(BuildContext context) async {
  final formKey = GlobalKey<FormState>();
  final amount = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Record payment'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: 'Brian Otieno · B4',
                decoration: const InputDecoration(labelText: 'Tenant and unit'),
                items: const [
                  DropdownMenuItem(
                    value: 'Brian Otieno · B4',
                    child: Text('Brian Otieno · B4'),
                  ),
                  DropdownMenuItem(
                    value: 'Grace Wanjiku · D1',
                    child: Text('Grace Wanjiku · D1'),
                  ),
                ],
                onChanged: (_) {},
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: 'KES ',
                ),
                validator: (value) {
                  final parsed = int.tryParse(value?.replaceAll(',', '') ?? '');
                  return parsed == null || parsed <= 0
                      ? 'Enter a valid amount'
                      : null;
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: 'M-Pesa',
                decoration: const InputDecoration(labelText: 'Payment method'),
                items: const [
                  DropdownMenuItem(value: 'M-Pesa', child: Text('M-Pesa')),
                  DropdownMenuItem(
                    value: 'Bank transfer',
                    child: Text('Bank transfer'),
                  ),
                  DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                ],
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Payment saved locally. Receipt is ready to print after sync confirmation.',
                ),
              ),
            );
          },
          child: const Text('Save payment'),
        ),
      ],
    ),
  );
  amount.dispose();
}
