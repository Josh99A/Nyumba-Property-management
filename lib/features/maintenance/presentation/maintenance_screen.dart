import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/page_header.dart';
import '../../../core/presentation/responsive.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';

enum WorkOrderStatus { open, inProgress, resolved }

enum WorkOrderPriority { normal, high, urgent }

class _WorkOrder {
  const _WorkOrder({
    required this.id,
    required this.title,
    required this.location,
    required this.reporter,
    required this.createdAt,
    required this.priority,
    required this.status,
    this.assignee,
  });

  final String id;
  final String title;
  final String location;
  final String reporter;
  final DateTime createdAt;
  final WorkOrderPriority priority;
  final WorkOrderStatus status;
  final String? assignee;

  _WorkOrder copyWith({WorkOrderStatus? status, String? assignee}) =>
      _WorkOrder(
        id: id,
        title: title,
        location: location,
        reporter: reporter,
        createdAt: createdAt,
        priority: priority,
        status: status ?? this.status,
        assignee: assignee ?? this.assignee,
      );
}

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  String _filter = 'All';
  final List<_WorkOrder> _orders = [
    _WorkOrder(
      id: 'MNT-2048',
      title: 'Leaking tap in kitchen',
      location: 'Unit A2 · Greenview Court',
      reporter: 'Alice Njeri',
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      priority: WorkOrderPriority.urgent,
      status: WorkOrderStatus.open,
    ),
    _WorkOrder(
      id: 'MNT-2047',
      title: 'No power in the living room',
      location: 'Unit D3 · Riverside Heights',
      reporter: 'John M.',
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      priority: WorkOrderPriority.high,
      status: WorkOrderStatus.inProgress,
      assignee: 'Kamau Electricals',
    ),
    _WorkOrder(
      id: 'MNT-2046',
      title: 'Water not draining in bathroom',
      location: 'Unit B1 · Sunset Apartments',
      reporter: 'Sarah W.',
      createdAt: DateTime.now().subtract(const Duration(hours: 5)),
      priority: WorkOrderPriority.high,
      status: WorkOrderStatus.open,
    ),
    _WorkOrder(
      id: 'MNT-2045',
      title: 'Bedroom door lock is loose',
      location: 'Unit C1 · Nyumbani Gardens',
      reporter: 'David Kamau',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      priority: WorkOrderPriority.normal,
      status: WorkOrderStatus.resolved,
      assignee: 'Jenga Fixers',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final filtered = _orders.where((order) {
      return switch (_filter) {
        'Open' => order.status == WorkOrderStatus.open,
        'In progress' => order.status == WorkOrderStatus.inProgress,
        'Resolved' => order.status == WorkOrderStatus.resolved,
        'Urgent' => order.priority == WorkOrderPriority.urgent,
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
          constraints: const BoxConstraints(maxWidth: 1360),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Maintenance',
                description:
                    'Triage tenant requests and keep every repair moving.',
                primaryAction: FilledButton.icon(
                  onPressed: () => _showNewRequest(context),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New request'),
                ),
              ),
              const SizedBox(height: 24),
              _MaintenanceSummary(orders: _orders),
              const SizedBox(height: 22),
              NyumbaSurface(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Work orders',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final filter in const [
                                'All',
                                'Open',
                                'In progress',
                                'Resolved',
                                'Urgent',
                              ])
                                ChoiceChip(
                                  label: Text(filter),
                                  selected: _filter == filter,
                                  onSelected: (_) =>
                                      setState(() => _filter = filter),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    if (filtered.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(36),
                        child: Center(
                          child: Text('No work orders match this filter.'),
                        ),
                      )
                    else
                      for (final order in filtered)
                        _WorkOrderRow(
                          order: order,
                          onAdvance: () => _advance(order),
                          onAssign: () => _assign(context, order),
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

  void _advance(_WorkOrder order) {
    final next = switch (order.status) {
      WorkOrderStatus.open => WorkOrderStatus.inProgress,
      WorkOrderStatus.inProgress => WorkOrderStatus.resolved,
      WorkOrderStatus.resolved => WorkOrderStatus.resolved,
    };
    setState(() {
      final index = _orders.indexWhere((item) => item.id == order.id);
      _orders[index] = order.copyWith(status: next);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next == WorkOrderStatus.resolved
              ? '${order.id} marked resolved and queued to sync.'
              : '${order.id} moved to in progress.',
        ),
      ),
    );
  }

  Future<void> _assign(BuildContext context, _WorkOrder order) async {
    final assignee = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Assign ${order.id}'),
        children: [
          for (final contractor in const [
            'Kamau Electricals',
            'Jenga Fixers',
            'Maji Works',
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, contractor),
              child: Text(contractor),
            ),
        ],
      ),
    );
    if (assignee == null) return;
    setState(() {
      final index = _orders.indexWhere((item) => item.id == order.id);
      _orders[index] = order.copyWith(
        assignee: assignee,
        status: order.status == WorkOrderStatus.open
            ? WorkOrderStatus.inProgress
            : order.status,
      );
    });
  }

  Future<void> _showNewRequest(BuildContext context) async {
    final formKey = GlobalKey<FormState>();
    final title = TextEditingController();
    final reporter = TextEditingController();
    var priority = WorkOrderPriority.normal;
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create maintenance request'),
          content: SizedBox(
            width: 480,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: 'Unit A1 · Greenview Court',
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items: const [
                        DropdownMenuItem(
                          value: 'Unit A1 · Greenview Court',
                          child: Text('Unit A1 · Greenview Court'),
                        ),
                        DropdownMenuItem(
                          value: 'Unit B4 · Sunset Apartments',
                          child: Text('Unit B4 · Sunset Apartments'),
                        ),
                      ],
                      onChanged: (_) {},
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: title,
                      decoration: const InputDecoration(
                        labelText: 'What needs attention?',
                      ),
                      validator: (value) => (value?.trim().length ?? 0) < 5
                          ? 'Describe the issue'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: reporter,
                      decoration: const InputDecoration(
                        labelText: 'Reported by',
                      ),
                      validator: (value) => (value?.trim().isEmpty ?? true)
                          ? 'Enter a name'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<WorkOrderPriority>(
                      initialValue: priority,
                      decoration: const InputDecoration(labelText: 'Priority'),
                      items: const [
                        DropdownMenuItem(
                          value: WorkOrderPriority.normal,
                          child: Text('Normal'),
                        ),
                        DropdownMenuItem(
                          value: WorkOrderPriority.high,
                          child: Text('High'),
                        ),
                        DropdownMenuItem(
                          value: WorkOrderPriority.urgent,
                          child: Text('Urgent'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => priority = value);
                        }
                      },
                    ),
                  ],
                ),
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
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Save request'),
            ),
          ],
        ),
      ),
    );
    if (created == true) {
      setState(() {
        _orders.insert(
          0,
          _WorkOrder(
            id: 'MNT-${2049 + _orders.length}',
            title: title.text.trim(),
            location: 'Unit A1 · Greenview Court',
            reporter: reporter.text.trim(),
            createdAt: DateTime.now(),
            priority: priority,
            status: WorkOrderStatus.open,
          ),
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          const SnackBar(
            content: Text('Request saved locally and added to the sync queue.'),
          ),
        );
      }
    }
    title.dispose();
    reporter.dispose();
  }
}

class _MaintenanceSummary extends StatelessWidget {
  const _MaintenanceSummary({required this.orders});

  final List<_WorkOrder> orders;

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        'Open',
        orders.where((item) => item.status == WorkOrderStatus.open).length,
        Icons.inbox_outlined,
        NyumbaColors.midnightNavy,
      ),
      (
        'In progress',
        orders
            .where((item) => item.status == WorkOrderStatus.inProgress)
            .length,
        Icons.engineering_outlined,
        NyumbaColors.terracottaDark,
      ),
      (
        'Urgent',
        orders
            .where(
              (item) =>
                  item.priority == WorkOrderPriority.urgent &&
                  item.status != WorkOrderStatus.resolved,
            )
            .length,
        Icons.priority_high_rounded,
        NyumbaColors.danger,
      ),
      (
        'Resolved',
        orders.where((item) => item.status == WorkOrderStatus.resolved).length,
        Icons.check_circle_outline_rounded,
        NyumbaColors.sageDark,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 4 : 2;
        const gap = 14.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                height: 116,
                child: NyumbaSurface(
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: item.$4.withValues(alpha: .1),
                        child: Icon(item.$3, color: item.$4),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item.$2}',
                            style: Theme.of(
                              context,
                            ).textTheme.headlineSmall?.copyWith(color: item.$4),
                          ),
                          Text(
                            item.$1,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
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

class _WorkOrderRow extends StatelessWidget {
  const _WorkOrderRow({
    required this.order,
    required this.onAdvance,
    required this.onAssign,
  });

  final _WorkOrder order;
  final VoidCallback onAdvance;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEDE9E2))),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _WorkOrderDetails(order: order),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _PriorityBadge(priority: order.priority),
                    const SizedBox(width: 8),
                    _StatusBadge(status: order.status),
                    const Spacer(),
                    PopupMenuButton<String>(
                      tooltip: 'Work order actions',
                      onSelected: (value) =>
                          value == 'assign' ? onAssign() : onAdvance(),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'assign',
                          child: Text('Assign contractor'),
                        ),
                        if (order.status != WorkOrderStatus.resolved)
                          PopupMenuItem(
                            value: 'advance',
                            child: Text(
                              order.status == WorkOrderStatus.open
                                  ? 'Start work'
                                  : 'Mark resolved',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(flex: 5, child: _WorkOrderDetails(order: order)),
                Expanded(
                  flex: 2,
                  child: _PriorityBadge(priority: order.priority),
                ),
                Expanded(flex: 2, child: _StatusBadge(status: order.status)),
                Expanded(
                  flex: 3,
                  child: Text(
                    order.assignee ?? 'Unassigned',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Work order actions',
                  onSelected: (value) =>
                      value == 'assign' ? onAssign() : onAdvance(),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'assign',
                      child: Text('Assign contractor'),
                    ),
                    if (order.status != WorkOrderStatus.resolved)
                      PopupMenuItem(
                        value: 'advance',
                        child: Text(
                          order.status == WorkOrderStatus.open
                              ? 'Start work'
                              : 'Mark resolved',
                        ),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _WorkOrderDetails extends StatelessWidget {
  const _WorkOrderDetails({required this.order});

  final _WorkOrder order;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(order.title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 3),
        Text(order.location, style: Theme.of(context).textTheme.bodySmall),
        Text(
          '${order.id} · ${order.reporter} · ${DateFormat('d MMM, HH:mm').format(order.createdAt)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.priority});

  final WorkOrderPriority priority;

  @override
  Widget build(BuildContext context) => switch (priority) {
    WorkOrderPriority.urgent => const StatusBadge(
      label: 'Urgent',
      tone: BadgeTone.danger,
    ),
    WorkOrderPriority.high => const StatusBadge(
      label: 'High',
      tone: BadgeTone.warning,
    ),
    WorkOrderPriority.normal => const StatusBadge(label: 'Normal'),
  };
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final WorkOrderStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
    WorkOrderStatus.open => const StatusBadge(
      label: 'Open',
      tone: BadgeTone.info,
    ),
    WorkOrderStatus.inProgress => const StatusBadge(
      label: 'In progress',
      tone: BadgeTone.warning,
    ),
    WorkOrderStatus.resolved => const StatusBadge(
      label: 'Resolved',
      tone: BadgeTone.success,
    ),
  };
}
