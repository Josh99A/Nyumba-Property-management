import 'package:flutter/material.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/status_badge.dart';
import 'widgets/tenant_components.dart';

class TenantHomeScreen extends StatefulWidget {
  const TenantHomeScreen({super.key});

  @override
  State<TenantHomeScreen> createState() => _TenantHomeScreenState();
}

class _TenantHomeScreenState extends State<TenantHomeScreen> {
  int _balance = 45000;
  bool _maintenanceSubmitted = false;

  @override
  Widget build(BuildContext context) {
    final paid = _balance == 0;
    return TenantPage(
      title: 'Hello, Brian',
      description: 'Here is what is happening with your home.',
      primaryAction: OutlinedButton.icon(
        onPressed: _contactManager,
        icon: const Icon(Icons.support_agent_rounded),
        label: const Text('Contact manager'),
      ),
      children: [
        TenantBalanceHero(
          amount: _balance,
          dueLabel: 'Invoice NYB-INV-2608 • due 5 Aug 2026',
          paid: paid,
          onPay: paid ? _showLatestReceipt : _payRent,
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1000
                ? 4
                : constraints.maxWidth >= 560
                ? 2
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
                    label: paid ? 'View receipt' : 'Pay rent',
                    caption: paid
                        ? 'Latest confirmed payment'
                        : 'Secure checkout',
                    icon: Icons.payments_outlined,
                    color: NyumbaColors.sageDark,
                    onTap: paid ? _showLatestReceipt : _payRent,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: TenantQuickAction(
                    label: 'Report a problem',
                    caption: 'Works while offline',
                    icon: Icons.home_repair_service_outlined,
                    color: NyumbaColors.terracottaDark,
                    onTap: _reportProblem,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: TenantQuickAction(
                    label: 'Rent statement',
                    caption: 'View or print',
                    icon: Icons.receipt_long_outlined,
                    color: NyumbaColors.midnightNavy,
                    onTap: _showStatement,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: TenantQuickAction(
                    label: 'Lease documents',
                    caption: '3 shared files',
                    icon: Icons.folder_copy_outlined,
                    color: NyumbaColors.sageDark,
                    onTap: _showLeaseFiles,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            const home = _HomeAndLeasePanel();
            final maintenance = _MaintenanceSummaryPanel(
              submitted: _maintenanceSubmitted,
              onView: _showMaintenanceDetail,
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
                const Expanded(flex: 6, child: home),
                const SizedBox(width: 20),
                Expanded(flex: 5, child: maintenance),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            const notices = _NoticesPanel();
            final payments = _RecentPaymentsPanel(
              onReceipt: _showLatestReceipt,
            );
            if (constraints.maxWidth < 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [notices, const SizedBox(height: 20), payments],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(flex: 6, child: notices),
                const SizedBox(width: 20),
                Expanded(flex: 5, child: payments),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          decoration: BoxDecoration(
            color: NyumbaColors.sageTint,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFCDE4D2)),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.offline_pin_outlined,
                size: 20,
                color: NyumbaColors.sageDark,
              ),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Your latest home, balance, and documents are available offline.',
                ),
              ),
              StatusBadge(label: 'Synced', tone: BadgeTone.success),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _payRent() async {
    var method = 'M-PESA';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Pay rent securely'),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Amount due',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        formatTenantKes(_balance),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      const Text('Invoice NYB-INV-2608 • August 2026 rent'),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Choose payment method',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in const ['M-PESA', 'Bank', 'Card'])
                      ChoiceChip(
                        label: Text(item),
                        selected: method == item,
                        showCheckmark: false,
                        avatar: Icon(
                          item == 'M-PESA'
                              ? Icons.phone_android_rounded
                              : item == 'Bank'
                              ? Icons.account_balance_outlined
                              : Icons.credit_card_outlined,
                          size: 18,
                        ),
                        onSelected: (_) => setDialogState(() => method = item),
                      ),
                  ],
                ),
                const SizedBox(height: 15),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 18,
                      color: NyumbaColors.sageDark,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Payment confirmation and receipt will remain available '
                        'on this device after syncing.',
                      ),
                    ),
                  ],
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
              label: Text('Pay with $method'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _balance = 0);
    showTenantMessage(
      context,
      'Payment confirmed. Receipt NYB-RCP-00842 is ready.',
    );
  }

  Future<void> _reportProblem() async {
    final descriptionController = TextEditingController();
    var category = 'Plumbing';
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Report a maintenance issue'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Category', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in const [
                      'Plumbing',
                      'Electrical',
                      'Appliance',
                      'Other',
                    ])
                      ChoiceChip(
                        label: Text(item),
                        selected: category == item,
                        showCheckmark: false,
                        onSelected: (_) =>
                            setDialogState(() => category = item),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: descriptionController,
                  minLines: 3,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'What needs attention?',
                    alignLabelWithHint: true,
                    hintText:
                        'Describe where the issue is and when it started.',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'You can submit while offline. Nyumba will send the request '
                  'to your property manager when connected.',
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
              onPressed: () {
                if (descriptionController.text.trim().length < 8) {
                  showTenantMessage(
                    dialogContext,
                    'Add a short description of the issue.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.send_rounded),
              label: const Text('Submit request'),
            ),
          ],
        ),
      ),
    );
    descriptionController.dispose();
    if (submitted != true || !mounted) return;
    setState(() => _maintenanceSubmitted = true);
    showTenantMessage(context, '$category request saved and queued to sync.');
  }

  Future<void> _showStatement() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rent statement'),
        content: const SizedBox(
          width: 470,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StatementRow(
                month: 'July 2026',
                reference: 'NYB-RCP-00842',
                amount: 'KES 45,000',
                status: 'Paid',
              ),
              Divider(height: 25),
              _StatementRow(
                month: 'June 2026',
                reference: 'NYB-RCP-00791',
                amount: 'KES 45,000',
                status: 'Paid',
              ),
              Divider(height: 25),
              _StatementRow(
                month: 'May 2026',
                reference: 'NYB-RCP-00744',
                amount: 'KES 45,000',
                status: 'Paid',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              showTenantMessage(context, 'Printable rent statement prepared.');
            },
            icon: const Icon(Icons.print_outlined),
            label: const Text('Print statement'),
          ),
        ],
      ),
    );
  }

  Future<void> _showLatestReceipt() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Payment receipt'),
        content: const SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor: NyumbaColors.sageTint,
                  child: Icon(
                    Icons.check_rounded,
                    color: NyumbaColors.sageDark,
                    size: 30,
                  ),
                ),
              ),
              SizedBox(height: 14),
              Center(
                child: Text(
                  'KES 45,000',
                  style: TextStyle(
                    color: NyumbaColors.midnightNavy,
                    fontWeight: FontWeight.w700,
                    fontSize: 25,
                  ),
                ),
              ),
              SizedBox(height: 18),
              TenantInfoRow(
                icon: Icons.tag_rounded,
                label: 'Receipt',
                value: 'NYB-RCP-00842',
              ),
              SizedBox(height: 12),
              TenantInfoRow(
                icon: Icons.home_outlined,
                label: 'For',
                value: 'July 2026 rent • Unit A-12',
              ),
              SizedBox(height: 12),
              TenantInfoRow(
                icon: Icons.calendar_today_outlined,
                label: 'Paid',
                value: '3 Jul 2026 via M-PESA',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              showTenantMessage(context, 'Receipt ready to print.');
            },
            icon: const Icon(Icons.print_outlined),
            label: const Text('Print'),
          ),
        ],
      ),
    );
  }

  Future<void> _showLeaseFiles() {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Lease documents',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              for (final file in const [
                ('Signed tenancy agreement', 'PDF • 1.8 MB'),
                ('Move-in inspection report', 'PDF • 860 KB'),
                ('House rules', 'PDF • 320 KB'),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: NyumbaColors.navyTint,
                    child: Icon(
                      Icons.description_outlined,
                      color: NyumbaColors.midnightNavy,
                    ),
                  ),
                  title: Text(file.$1),
                  subtitle: Text(file.$2),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showTenantMessage(
                    context,
                    '${file.$1} is available offline.',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _contactManager() {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 28,
                backgroundColor: NyumbaColors.navyTint,
                child: Text('WM'),
              ),
              const SizedBox(height: 10),
              Text(
                'Wanjiku Mwangi',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text('Property manager • Acacia Heights'),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => showTenantMessage(
                        context,
                        'Calling is available on your mobile device.',
                      ),
                      icon: const Icon(Icons.call_outlined),
                      label: const Text('Call'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => showTenantMessage(
                        context,
                        'A secure message draft has been opened.',
                      ),
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      label: const Text('Message'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMaintenanceDetail() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _maintenanceSubmitted ? 'New request queued' : 'Kitchen tap leak',
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _maintenanceSubmitted
                ? const [
                    TenantTimelineStep(
                      title: 'Saved on this device',
                      detail: 'Ready to sync when connected',
                      complete: true,
                    ),
                    TenantTimelineStep(
                      title: 'Sent to property manager',
                      detail: 'Waiting for network connection',
                      complete: false,
                      last: true,
                    ),
                  ]
                : const [
                    TenantTimelineStep(
                      title: 'Request submitted',
                      detail: '8 Jul 2026 at 09:14',
                      complete: true,
                    ),
                    TenantTimelineStep(
                      title: 'Plumber assigned',
                      detail: 'Kamau Services • 8 Jul at 13:40',
                      complete: true,
                    ),
                    TenantTimelineStep(
                      title: 'Visit scheduled',
                      detail: '15 Jul 2026 • 10:00–12:00',
                      complete: false,
                      last: true,
                    ),
                  ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _HomeAndLeasePanel extends StatelessWidget {
  const _HomeAndLeasePanel();

  @override
  Widget build(BuildContext context) {
    return const TenantPanel(
      title: 'Your home',
      subtitle: 'Acacia Heights • Kilimani, Nairobi',
      trailing: TenantStatusBadge(status: 'Active'),
      child: Column(
        children: [
          TenantInfoRow(
            icon: Icons.meeting_room_outlined,
            label: 'Unit',
            value: 'A-12 • 2 bedroom apartment',
          ),
          Divider(height: 25),
          TenantInfoRow(
            icon: Icons.calendar_month_outlined,
            label: 'Lease term',
            value: '1 Jan – 31 Dec 2026',
          ),
          Divider(height: 25),
          TenantInfoRow(
            icon: Icons.payments_outlined,
            label: 'Monthly rent',
            value: 'KES 45,000 • due on the 5th',
          ),
          Divider(height: 25),
          TenantInfoRow(
            icon: Icons.person_outline_rounded,
            label: 'Property manager',
            value: 'Wanjiku Mwangi',
          ),
        ],
      ),
    );
  }
}

class _MaintenanceSummaryPanel extends StatelessWidget {
  const _MaintenanceSummaryPanel({
    required this.submitted,
    required this.onView,
  });

  final bool submitted;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return TenantPanel(
      title: 'Maintenance',
      subtitle: submitted
          ? '1 local change waiting to sync'
          : '1 active request',
      trailing: TenantStatusBadge(status: submitted ? 'Pending' : 'Scheduled'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: submitted ? NyumbaColors.goldTint : NyumbaColors.navyTint,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: [
                Icon(
                  submitted
                      ? Icons.cloud_upload_outlined
                      : Icons.plumbing_outlined,
                  color: submitted
                      ? NyumbaColors.terracottaDark
                      : NyumbaColors.midnightNavy,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        submitted ? 'New request saved' : 'Kitchen tap leak',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        submitted
                            ? 'Will send when your device reconnects'
                            : 'Plumber visit • 15 Jul, 10:00–12:00',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TenantTimelineStep(
            title: 'Reported',
            detail: submitted ? 'Saved just now' : '8 Jul at 09:14',
            complete: true,
          ),
          TenantTimelineStep(
            title: submitted ? 'Awaiting sync' : 'Manager reviewed',
            detail: submitted ? 'Connection required' : 'Contractor assigned',
            complete: !submitted,
          ),
          TenantTimelineStep(
            title: 'Resolved',
            detail: submitted
                ? 'Not started'
                : 'Scheduled after contractor visit',
            complete: false,
            last: true,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onView,
            child: const Text('View request details'),
          ),
        ],
      ),
    );
  }
}

class _NoticesPanel extends StatelessWidget {
  const _NoticesPanel();

  @override
  Widget build(BuildContext context) {
    return const TenantPanel(
      title: 'Notices from your property',
      subtitle: 'Important updates shared by your manager',
      child: Column(
        children: [
          _NoticeRow(
            icon: Icons.water_drop_outlined,
            color: NyumbaColors.midnightNavy,
            title: 'Planned water interruption',
            detail: 'Wednesday, 15 Jul • 09:00–14:00 for tank cleaning.',
            date: 'Today',
          ),
          Divider(height: 25),
          _NoticeRow(
            icon: Icons.security_outlined,
            color: NyumbaColors.sageDark,
            title: 'Visitor access update',
            detail: 'Please pre-register overnight guests with security.',
            date: '10 Jul',
          ),
        ],
      ),
    );
  }
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.date,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final String date;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 3),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(date, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _RecentPaymentsPanel extends StatelessWidget {
  const _RecentPaymentsPanel({required this.onReceipt});

  final VoidCallback onReceipt;

  @override
  Widget build(BuildContext context) {
    return TenantPanel(
      title: 'Recent payments',
      subtitle: 'Your latest confirmed rent receipts',
      trailing: TextButton(onPressed: onReceipt, child: const Text('Receipt')),
      child: const Column(
        children: [
          _PaymentRow(month: 'July 2026', date: '3 Jul', amount: 'KES 45,000'),
          Divider(height: 25),
          _PaymentRow(month: 'June 2026', date: '4 Jun', amount: 'KES 45,000'),
          Divider(height: 25),
          _PaymentRow(month: 'May 2026', date: '2 May', amount: 'KES 45,000'),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.month,
    required this.date,
    required this.amount,
  });

  final String month;
  final String date;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const CircleAvatar(
          radius: 18,
          backgroundColor: NyumbaColors.sageTint,
          child: Icon(
            Icons.check_rounded,
            size: 19,
            color: NyumbaColors.sageDark,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(month, style: Theme.of(context).textTheme.labelLarge),
              Text(date, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        Text(amount, style: Theme.of(context).textTheme.labelLarge),
      ],
    );
  }
}

class _StatementRow extends StatelessWidget {
  const _StatementRow({
    required this.month,
    required this.reference,
    required this.amount,
    required this.status,
  });

  final String month;
  final String reference;
  final String amount;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const CircleAvatar(
          backgroundColor: NyumbaColors.sageTint,
          child: Icon(Icons.check_rounded, color: NyumbaColors.sageDark),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(month, style: Theme.of(context).textTheme.labelLarge),
              Text(reference, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(amount, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 3),
            TenantStatusBadge(status: status),
          ],
        ),
      ],
    );
  }
}
