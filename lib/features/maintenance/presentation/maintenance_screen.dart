import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/offline/aggregate_sync_status.dart';
import '../../../core/offline/offline_entity.dart';
import '../../../core/offline/outbox_entry.dart';
import '../../../core/presentation/metric_grid.dart';
import '../../../core/presentation/page_header.dart';
import '../../../core/presentation/responsive.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import '../../../core/presentation/sync_state_badge.dart';
import '../../portfolio/domain/property.dart';
import '../../portfolio/domain/unit.dart';
import '../../portfolio/application/rental_space_labels.dart';
import '../application/maintenance_providers.dart';
import '../domain/maintenance_request.dart';

class MaintenanceScreen extends ConsumerStatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  ConsumerState<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final requestsValue = ref.watch(maintenanceRequestsProvider);
    final units = ref.watch(portfolioUnitsProvider).value ?? const <Unit>[];
    final properties =
        ref.watch(portfolioPropertiesProvider).value ?? const <Property>[];
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
          constraints: const BoxConstraints(maxWidth: 1360),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Maintenance',
                description:
                    'Triage tenant requests and keep every repair moving.',
                primaryAction: FilledButton.icon(
                  onPressed: () => _showNewRequest(context, units, properties),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New request'),
                ),
              ),
              const SizedBox(height: 24),
              requestsValue.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stack) => NyumbaSurface(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Could not load maintenance requests: $error'),
                  ),
                ),
                data: (requests) => _buildLoaded(context, requests, outbox),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoaded(
    BuildContext context,
    List<MaintenanceRequest> requests,
    List<OutboxEntry> outbox,
  ) {
    final filtered = requests.where((request) {
      return switch (_filter) {
        'Open' => request.status.isOpen,
        'In progress' => request.status == MaintenanceStatus.inProgress,
        'Resolved' => request.status == MaintenanceStatus.resolved,
        'Urgent' =>
          request.priority == MaintenancePriority.urgent &&
              !request.status.isTerminal,
        _ => true,
      };
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MaintenanceSummary(requests: requests),
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
                            onSelected: (_) => setState(() => _filter = filter),
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
                for (final request in filtered)
                  _WorkOrderRow(
                    request: request,
                    syncStatus: resolveAggregateSyncStatus(
                      entityType: OfflineEntityType.maintenanceRequest,
                      entityId: request.id,
                      outbox: outbox,
                      syncMetadata: request.syncMetadata,
                    ),
                    onAdvance: () => _advance(request),
                    onAssign: () => _assign(context, request),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _advance(MaintenanceRequest request) async {
    final next = switch (request.status) {
      MaintenanceStatus.submitted ||
      MaintenanceStatus.scheduled => MaintenanceStatus.inProgress,
      MaintenanceStatus.inProgress => MaintenanceStatus.resolved,
      MaintenanceStatus.resolved ||
      MaintenanceStatus.cancelled => request.status,
    };
    if (next == request.status) return;
    try {
      await ref.read(transitionMaintenanceRequestProvider)(
        TransitionMaintenanceInput(requestId: request.id, status: next),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              next == MaintenanceStatus.resolved
                  ? '${request.reference} marked resolved locally — awaiting sync.'
                  : '${request.reference} moved to in progress — awaiting sync.',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not update: $error')));
      }
    }
  }

  Future<void> _assign(BuildContext context, MaintenanceRequest request) async {
    final assignee = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Assign ${request.reference}'),
        children: [
          for (final contractor in const [
            'Kato Electricals',
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
    try {
      await ref.read(transitionMaintenanceRequestProvider)(
        TransitionMaintenanceInput(
          requestId: request.id,
          status: request.status == MaintenanceStatus.submitted
              ? MaintenanceStatus.inProgress
              : request.status,
          assignee: assignee,
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          this.context,
        ).showSnackBar(SnackBar(content: Text('Could not assign: $error')));
      }
    }
  }

  Future<void> _showNewRequest(
    BuildContext context,
    List<Unit> units,
    List<Property> properties,
  ) async {
    final propertyNames = <String, String>{
      for (final property in properties) property.id: property.name,
    };
    final options = [
      for (final unit in units)
        (
          unit: unit,
          label:
              '${unit.displayName} · ${propertyNames[unit.propertyId] ?? 'Property'}',
        ),
    ];
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add a property and rental space before logging a request.',
          ),
        ),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final title = TextEditingController();
    final description = TextEditingController();
    final reporter = TextEditingController();
    var priority = MaintenancePriority.normal;
    var selected = options.first;
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
                      initialValue: selected.unit.id,
                      decoration: InputDecoration(
                        labelText: context.tr('Rental space'),
                      ),
                      items: [
                        for (final option in options)
                          DropdownMenuItem(
                            value: option.unit.id,
                            child: Text(option.label),
                          ),
                      ],
                      onChanged: (value) {
                        final match = options.where(
                          (option) => option.unit.id == value,
                        );
                        if (match.isNotEmpty) {
                          setDialogState(() => selected = match.first);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: title,
                      decoration: InputDecoration(
                        labelText: context.tr('What needs attention?'),
                      ),
                      validator: (value) => (value?.trim().length ?? 0) < 5
                          ? 'Describe the issue'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: description,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: context.tr('Details'),
                      ),
                      validator: (value) => (value?.trim().length ?? 0) < 5
                          ? 'Add a short description'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: reporter,
                      decoration: InputDecoration(
                        labelText: context.tr('Reported by'),
                      ),
                      validator: (value) => (value?.trim().isEmpty ?? true)
                          ? 'Enter a name'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<MaintenancePriority>(
                      initialValue: priority,
                      decoration: InputDecoration(
                        labelText: context.tr('Priority'),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: MaintenancePriority.normal,
                          child: Text('Normal'),
                        ),
                        DropdownMenuItem(
                          value: MaintenancePriority.high,
                          child: Text('High'),
                        ),
                        DropdownMenuItem(
                          value: MaintenancePriority.urgent,
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
      try {
        await ref.read(createMaintenanceRequestProvider)(
          CreateMaintenanceRequestInput(
            landlordId: selected.unit.landlordId,
            propertyId: selected.unit.propertyId,
            unitId: selected.unit.id,
            title: title.text.trim(),
            description: description.text.trim(),
            location: selected.label,
            reporterName: reporter.text.trim(),
            priority: priority,
          ),
        );
        if (mounted) {
          ScaffoldMessenger.of(this.context).showSnackBar(
            const SnackBar(
              content: Text(
                'Request saved locally and added to the sync queue.',
              ),
            ),
          );
        }
      } on Object catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(this.context).showSnackBar(
            SnackBar(content: Text('Could not save the request: $error')),
          );
        }
      }
    }
    title.dispose();
    description.dispose();
    reporter.dispose();
  }
}

class _MaintenanceSummary extends StatelessWidget {
  const _MaintenanceSummary({required this.requests});

  final List<MaintenanceRequest> requests;

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        'Open',
        requests.where((item) => item.status.isOpen).length,
        Icons.inbox_outlined,
        context.nyumba.midnightNavy,
      ),
      (
        'In progress',
        requests
            .where((item) => item.status == MaintenanceStatus.inProgress)
            .length,
        Icons.engineering_outlined,
        context.nyumba.terracottaDark,
      ),
      (
        'Urgent',
        requests
            .where(
              (item) =>
                  item.priority == MaintenancePriority.urgent &&
                  !item.status.isTerminal,
            )
            .length,
        Icons.priority_high_rounded,
        context.nyumba.danger,
      ),
      (
        'Resolved',
        requests
            .where((item) => item.status == MaintenanceStatus.resolved)
            .length,
        Icons.check_circle_outline_rounded,
        context.nyumba.sageDark,
      ),
    ];
    return MetricGrid(
      minRowHeight: 116,
      columnsForWidth: (width) => width >= 900 ? 4 : 2,
      children: [
        for (final item in items)
          NyumbaSurface(
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: item.$4.withValues(alpha: .1),
                  child: Icon(item.$3, color: item.$4),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
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
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _WorkOrderRow extends StatelessWidget {
  const _WorkOrderRow({
    required this.request,
    required this.syncStatus,
    required this.onAdvance,
    required this.onAssign,
  });

  final MaintenanceRequest request;
  final AggregateSyncStatus syncStatus;
  final VoidCallback onAdvance;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final actions = PopupMenuButton<String>(
      tooltip: context.tr('Work order actions'),
      onSelected: (value) => value == 'assign' ? onAssign() : onAdvance(),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'assign', child: Text('Assign contractor')),
        if (!request.status.isTerminal)
          PopupMenuItem(
            value: 'advance',
            child: Text(request.status.isOpen ? 'Start work' : 'Mark resolved'),
          ),
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.nyumba.divider)),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _WorkOrderDetails(request: request),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _PriorityBadge(priority: request.priority),
                    const SizedBox(width: 8),
                    _WorkStatusBadge(status: request.status),
                    const SizedBox(width: 8),
                    SyncStateBadge(status: syncStatus),
                    const Spacer(),
                    actions,
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(flex: 5, child: _WorkOrderDetails(request: request)),
                Expanded(
                  flex: 2,
                  child: _PriorityBadge(priority: request.priority),
                ),
                Expanded(
                  flex: 2,
                  child: _WorkStatusBadge(status: request.status),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    request.assignee ?? 'Unassigned',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                SizedBox(width: 110, child: SyncStateBadge(status: syncStatus)),
                actions,
              ],
            ),
    );
  }
}

class _WorkOrderDetails extends StatelessWidget {
  const _WorkOrderDetails({required this.request});

  final MaintenanceRequest request;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(request.title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 3),
        Text(request.location, style: Theme.of(context).textTheme.bodySmall),
        Text(
          '${request.reference} · ${request.reporterName} · '
          '${DateFormat('d MMM, HH:mm').format(request.reportedAt.toLocal())}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.priority});

  final MaintenancePriority priority;

  @override
  Widget build(BuildContext context) => switch (priority) {
    MaintenancePriority.urgent => const StatusBadge(
      label: 'Urgent',
      tone: BadgeTone.danger,
    ),
    MaintenancePriority.high => const StatusBadge(
      label: 'High',
      tone: BadgeTone.warning,
    ),
    MaintenancePriority.normal => const StatusBadge(label: 'Normal'),
  };
}

class _WorkStatusBadge extends StatelessWidget {
  const _WorkStatusBadge({required this.status});

  final MaintenanceStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
    MaintenanceStatus.submitted => const StatusBadge(
      label: 'Open',
      tone: BadgeTone.info,
    ),
    MaintenanceStatus.scheduled => const StatusBadge(
      label: 'Scheduled',
      tone: BadgeTone.info,
    ),
    MaintenanceStatus.inProgress => const StatusBadge(
      label: 'In progress',
      tone: BadgeTone.warning,
    ),
    MaintenanceStatus.resolved => const StatusBadge(
      label: 'Resolved',
      tone: BadgeTone.success,
    ),
    MaintenanceStatus.cancelled => const StatusBadge(label: 'Cancelled'),
  };
}
