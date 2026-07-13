import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import 'widgets/tenant_components.dart';

class TenantPaymentsScreen extends StatefulWidget {
  const TenantPaymentsScreen({super.key});

  @override
  State<TenantPaymentsScreen> createState() => _TenantPaymentsScreenState();
}

class _TenantPaymentsScreenState extends State<TenantPaymentsScreen> {
  int _balance = 45000;
  String _filter = 'All';
  String _defaultMethod = 'M-PESA ••• 2841';
  final List<_TenantPayment> _payments = [..._seedPayments];

  List<_TenantPayment> get _filteredPayments {
    if (_filter == 'All') return _payments;
    return _payments.where((payment) => payment.status == _filter).toList();
  }

  int get _paidThisYear => _payments
      .where((payment) => payment.status == 'Paid')
      .fold(0, (sum, payment) => sum + payment.amount);

  @override
  Widget build(BuildContext context) {
    final paid = _balance == 0;
    final filtered = _filteredPayments;
    return TenantPage(
      title: 'Payments',
      description: 'Manage rent, invoices, receipts, and your payment history.',
      secondaryAction: OutlinedButton.icon(
        onPressed: () => showTenantMessage(
          context,
          'Your 2026 rent statement is ready to print.',
        ),
        icon: const Icon(Icons.print_outlined),
        label: const Text('Print statement'),
      ),
      primaryAction: FilledButton.icon(
        onPressed: paid ? _showCurrentReceipt : _payRent,
        icon: Icon(
          paid ? Icons.receipt_long_outlined : Icons.payments_outlined,
        ),
        label: Text(paid ? 'Latest receipt' : 'Pay rent'),
      ),
      children: [
        TenantBalanceHero(
          amount: _balance,
          dueLabel: 'Invoice NYB-INV-2608 • due 5 Aug 2026',
          paid: paid,
          onPay: paid ? _showCurrentReceipt : _payRent,
        ),
        const SizedBox(height: 18),
        TenantMetricGrid(
          children: [
            TenantMetricCard(
              label: 'Paid in 2026',
              value: formatTenantKes(_paidThisYear),
              caption:
                  '${_payments.where((item) => item.status == 'Paid').length} confirmed payments',
              icon: Icons.savings_outlined,
              color: NyumbaColors.sageDark,
            ),
            const TenantMetricCard(
              label: 'Monthly rent',
              value: 'KES 45,000',
              caption: 'Due on the 5th of each month',
              icon: Icons.calendar_month_outlined,
              color: NyumbaColors.midnightNavy,
            ),
            TenantMetricCard(
              label: 'Saved payment method',
              value: _defaultMethod,
              caption: 'Used only after confirmation',
              icon: Icons.account_balance_wallet_outlined,
              color: NyumbaColors.terracottaDark,
            ),
          ],
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final invoice = _InvoicePanel(
              balance: _balance,
              onPay: paid ? _showCurrentReceipt : _payRent,
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
                          'Processing',
                          'Overdue',
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
                              onReceipt: () => _showReceipt(filtered[index]),
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
                                  DataCell(Text(payment.reference)),
                                  DataCell(Text(payment.date)),
                                  DataCell(Text(payment.method)),
                                  DataCell(
                                    Text(formatTenantKes(payment.amount)),
                                  ),
                                  DataCell(
                                    TenantStatusBadge(status: payment.status),
                                  ),
                                  DataCell(
                                    IconButton(
                                      tooltip: payment.status == 'Paid'
                                          ? 'View receipt'
                                          : 'View details',
                                      onPressed: () => _showReceipt(payment),
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

  Future<void> _payRent() async {
    var method = _defaultMethod.startsWith('M-PESA') ? 'M-PESA' : 'Bank';
    final paid = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Pay August rent'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: NyumbaColors.navyTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Expanded(child: Text('Amount payable')),
                      Text(
                        formatTenantKes(_balance),
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
                for (final item in const ['M-PESA', 'Bank', 'Card'])
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
                                ? NyumbaColors.midnightNavy
                                : NyumbaColors.outline,
                          ),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              item == 'M-PESA'
                                  ? Icons.phone_android_rounded
                                  : item == 'Bank'
                                  ? Icons.account_balance_outlined
                                  : Icons.credit_card_outlined,
                              color: NyumbaColors.midnightNavy,
                            ),
                            const SizedBox(width: 11),
                            Expanded(child: Text(item)),
                            if (method == item)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: NyumbaColors.sageDark,
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
    if (paid != true || !mounted) return;
    final now = DateTime.now();
    setState(() {
      _balance = 0;
      _payments.insert(
        0,
        _TenantPayment(
          period: 'August 2026',
          reference: 'NYB-RCP-00896',
          date: DateFormat('d MMM 2026').format(now),
          method: method,
          amount: 45000,
          status: 'Paid',
        ),
      );
    });
    showTenantMessage(context, 'Payment confirmed and receipt saved offline.');
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
                  'M-PESA ••• 2841',
                  'KCB Bank ••• 7810',
                ])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: NyumbaColors.navyTint,
                      child: Icon(
                        item.startsWith('M-PESA')
                            ? Icons.phone_android_rounded
                            : Icons.account_balance_outlined,
                        color: NyumbaColors.midnightNavy,
                      ),
                    ),
                    title: Text(item),
                    subtitle: Text(
                      selected == item ? 'Default method' : 'Available method',
                    ),
                    trailing: selected == item
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: NyumbaColors.sageDark,
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

  Future<void> _showCurrentReceipt() {
    final payment = _payments.firstWhere(
      (item) => item.status == 'Paid',
      orElse: () => _seedPayments.first,
    );
    return _showReceipt(payment);
  }

  Future<void> _showReceipt(_TenantPayment payment) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          payment.status == 'Paid' ? 'Payment receipt' : 'Payment details',
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: TenantStatusBadge(status: payment.status)),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  formatTenantKes(payment.amount),
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
                value: payment.reference,
              ),
              const SizedBox(height: 12),
              TenantInfoRow(
                icon: Icons.payments_outlined,
                label: 'Payment',
                value: '${payment.date} • ${payment.method}',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          if (payment.status == 'Paid')
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                showTenantMessage(
                  context,
                  '${payment.reference} is ready to print.',
                );
              },
              icon: const Icon(Icons.print_outlined),
              label: const Text('Print receipt'),
            ),
        ],
      ),
    );
  }
}

class _InvoicePanel extends StatelessWidget {
  const _InvoicePanel({required this.balance, required this.onPay});

  final int balance;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final paid = balance == 0;
    return TenantPanel(
      title: 'Current invoice',
      subtitle: 'NYB-INV-2608 • August 2026',
      trailing: TenantStatusBadge(status: paid ? 'Paid' : 'Pending'),
      child: Column(
        children: [
          const _InvoiceLine(label: 'Monthly rent', amount: 'KES 45,000'),
          const SizedBox(height: 10),
          const _InvoiceLine(label: 'Service charges', amount: 'KES 0'),
          const SizedBox(height: 10),
          const _InvoiceLine(label: 'Credits applied', amount: 'KES 0'),
          const Divider(height: 27),
          _InvoiceLine(
            label: paid ? 'Amount paid' : 'Amount due',
            amount: paid ? 'KES 45,000' : formatTenantKes(balance),
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
              label: Text(paid ? 'View receipt' : 'Pay invoice'),
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
              color: NyumbaColors.sageTint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFCDE4D2)),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Icon(
                    Icons.phone_android_rounded,
                    color: NyumbaColors.sageDark,
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
          const Row(
            children: [
              Icon(
                Icons.shield_outlined,
                size: 19,
                color: NyumbaColors.sageDark,
              ),
              SizedBox(width: 8),
              Expanded(
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
  const _PaymentCard({required this.payment, required this.onReceipt});

  final _TenantPayment payment;
  final VoidCallback onReceipt;

  @override
  Widget build(BuildContext context) {
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
                color: payment.status == 'Paid'
                    ? NyumbaColors.sageTint
                    : NyumbaColors.goldTint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                payment.status == 'Paid'
                    ? Icons.check_rounded
                    : Icons.schedule_rounded,
                color: payment.status == 'Paid'
                    ? NyumbaColors.sageDark
                    : NyumbaColors.terracottaDark,
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
                    '${payment.reference} • ${payment.date}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  TenantStatusBadge(status: payment.status),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatTenantKes(payment.amount),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  payment.method,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TenantPayment {
  const _TenantPayment({
    required this.period,
    required this.reference,
    required this.date,
    required this.method,
    required this.amount,
    required this.status,
  });

  final String period;
  final String reference;
  final String date;
  final String method;
  final int amount;
  final String status;
}

const _seedPayments = [
  _TenantPayment(
    period: 'July 2026',
    reference: 'NYB-RCP-00842',
    date: '3 Jul 2026',
    method: 'M-PESA',
    amount: 45000,
    status: 'Paid',
  ),
  _TenantPayment(
    period: 'June 2026',
    reference: 'NYB-RCP-00791',
    date: '4 Jun 2026',
    method: 'M-PESA',
    amount: 45000,
    status: 'Paid',
  ),
  _TenantPayment(
    period: 'May 2026',
    reference: 'NYB-RCP-00744',
    date: '2 May 2026',
    method: 'Bank',
    amount: 45000,
    status: 'Paid',
  ),
  _TenantPayment(
    period: 'April 2026',
    reference: 'NYB-RCP-00693',
    date: '5 Apr 2026',
    method: 'M-PESA',
    amount: 45000,
    status: 'Paid',
  ),
  _TenantPayment(
    period: 'March 2026',
    reference: 'NYB-RCP-00648',
    date: '3 Mar 2026',
    method: 'Bank',
    amount: 45000,
    status: 'Paid',
  ),
  _TenantPayment(
    period: 'February 2026',
    reference: 'NYB-RCP-00596',
    date: '4 Feb 2026',
    method: 'M-PESA',
    amount: 45000,
    status: 'Paid',
  ),
  _TenantPayment(
    period: 'January 2026',
    reference: 'NYB-RCP-00541',
    date: '5 Jan 2026',
    method: 'M-PESA',
    amount: 45000,
    status: 'Paid',
  ),
];
