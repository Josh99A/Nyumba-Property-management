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
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import '../../../core/presentation/sync_state_badge.dart';
import '../../auth/application/session_controller.dart';
import '../../maintenance/application/maintenance_providers.dart';
import '../../maintenance/domain/maintenance_request.dart';
import '../../tenants/application/tenancy_providers.dart';
import 'widgets/tenant_components.dart';

String tenantStatusLabel(MaintenanceStatus status) => switch (status) {
  MaintenanceStatus.submitted => 'Reported',
  MaintenanceStatus.scheduled => 'Scheduled',
  MaintenanceStatus.inProgress => 'In progress',
  MaintenanceStatus.resolved => 'Resolved',
  MaintenanceStatus.cancelled => 'Cancelled',
};

class TenantMaintenanceScreen extends ConsumerStatefulWidget {
  const TenantMaintenanceScreen({super.key});

  @override
  ConsumerState<TenantMaintenanceScreen> createState() =>
      _TenantMaintenanceScreenState();
}

class _TenantMaintenanceScreenState
    extends ConsumerState<TenantMaintenanceScreen> {
  String _filter = 'All';
  String _query = '';

  String get _tenantId => ref.read(sessionControllerProvider)?.userId ?? '';

  List<MaintenanceRequest> _applyFilters(List<MaintenanceRequest> requests) {
    final query = _query.trim().toLowerCase();
    return requests.where((request) {
      final matchesQuery =
          query.isEmpty ||
          request.title.toLowerCase().contains(query) ||
          request.category.toLowerCase().contains(query) ||
          request.reference.toLowerCase().contains(query);
      final matchesFilter = switch (_filter) {
        'Open' =>
          request.status == MaintenanceStatus.submitted ||
              request.status == MaintenanceStatus.inProgress,
        'Scheduled' => request.status == MaintenanceStatus.scheduled,
        'Resolved' => request.status == MaintenanceStatus.resolved,
        _ => true,
      };
      return matchesQuery && matchesFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final requestsValue = ref.watch(
      tenantMaintenanceRequestsProvider(_tenantId),
    );
    final outbox =
        ref.watch(outboxEntriesProvider).value ?? const <OutboxEntry>[];
    return TenantPage(
      title: 'Maintenance',
      description:
          'Report an issue and follow every update through resolution.',
      secondaryAction: OutlinedButton.icon(
        onPressed: _showEmergencyHelp,
        icon: const Icon(Icons.emergency_outlined),
        label: const Text('Emergency help'),
      ),
      primaryAction: FilledButton.icon(
        onPressed: _createRequest,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New request'),
      ),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          decoration: BoxDecoration(
            color: context.nyumba.sageTint,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.nyumba.sageBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.cloud_done_outlined,
                color: context.nyumba.sageDark,
                size: 20,
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'New requests, notes, and photos save on this device first. '
                  'They sync automatically when connectivity is available.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        requestsValue.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stack) => NyumbaSurface(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load your requests: $error'),
            ),
          ),
          data: (requests) => _buildLoaded(context, requests, outbox),
        ),
      ],
    );
  }

  Widget _buildLoaded(
    BuildContext context,
    List<MaintenanceRequest> requests,
    List<OutboxEntry> outbox,
  ) {
    final filtered = _applyFilters(requests);
    final openCount = requests
        .where(
          (item) =>
              item.status == MaintenanceStatus.submitted ||
              item.status == MaintenanceStatus.inProgress,
        )
        .length;
    final scheduled = requests
        .where((item) => item.status == MaintenanceStatus.scheduled)
        .toList();
    final resolvedCount = requests
        .where((item) => item.status == MaintenanceStatus.resolved)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TenantMetricGrid(
          children: [
            TenantMetricCard(
              label: 'Open requests',
              value: '$openCount',
              caption: 'Waiting for action or in progress',
              icon: Icons.home_repair_service_outlined,
              color: context.nyumba.terracottaDark,
            ),
            TenantMetricCard(
              label: 'Scheduled visits',
              value: '${scheduled.length}',
              caption: scheduled.isEmpty
                  ? 'No visits booked yet'
                  : scheduled.first.appointment ?? 'Visit booked',
              icon: Icons.event_available_outlined,
              color: context.nyumba.midnightNavy,
            ),
            TenantMetricCard(
              label: 'Resolved',
              value: '$resolvedCount',
              caption: 'Across this tenancy',
              icon: Icons.task_alt_rounded,
              color: context.nyumba.sageDark,
            ),
          ],
        ),
        const SizedBox(height: 20),
        NyumbaSurface(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: constraints.maxWidth < 620
                        ? constraints.maxWidth
                        : 320,
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: context.tr(
                          'Search issue, category, or request ID',
                        ),
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                  for (final item in const [
                    'All',
                    'Open',
                    'Scheduled',
                    'Resolved',
                  ])
                    ChoiceChip(
                      label: Text(item),
                      selected: _filter == item,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _filter = item),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          NyumbaSurface(
            child: TenantEmptyState(
              title: 'No maintenance requests found',
              message: 'Try another filter or report a new issue.',
              icon: Icons.handyman_outlined,
              action: OutlinedButton.icon(
                onPressed: () => setState(() {
                  _filter = 'All';
                  _query = '';
                }),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Show all requests'),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900 ? 2 : 1;
              const spacing = 14.0;
              final width =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final request in filtered)
                    SizedBox(
                      width: width,
                      child: _RequestCard(
                        request: request,
                        syncStatus: resolveAggregateSyncStatus(
                          entityType: OfflineEntityType.maintenanceRequest,
                          entityId: request.id,
                          outbox: outbox,
                          syncMetadata: request.syncMetadata,
                        ),
                        onTap: () => _showRequest(request),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  Future<void> _createRequest() async {
    final session = ref.read(sessionControllerProvider);
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    var category = 'Plumbing';
    var priority = MaintenancePriority.normal;
    var allowAccess = false;
    var photoCount = 0;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New maintenance request'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Category',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final item in const [
                        'Plumbing',
                        'Electrical',
                        'Appliance',
                        'Building',
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
                    controller: titleController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: context.tr('Short title'),
                      hintText: context.tr('e.g. Bathroom light not working'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    minLines: 3,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: context.tr('Describe the issue'),
                      alignLabelWithHint: true,
                      hintText: context.tr(
                        'Include the location and when it started.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Priority',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final item in const [
                        (MaintenancePriority.normal, 'Normal'),
                        (MaintenancePriority.urgent, 'Urgent'),
                      ])
                        ChoiceChip(
                          label: Text(item.$2),
                          selected: priority == item.$1,
                          showCheckmark: false,
                          onSelected: (_) =>
                              setDialogState(() => priority = item.$1),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => setDialogState(() => photoCount++),
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: Text(
                      photoCount == 0
                          ? 'Attach a photo'
                          : '$photoCount photo${photoCount == 1 ? '' : 's'} attached',
                    ),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: allowAccess,
                    title: const Text('Allow access while I am away'),
                    subtitle: const Text(
                      'The manager must confirm before entry',
                    ),
                    onChanged: (value) =>
                        setDialogState(() => allowAccess = value),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.offline_pin_outlined,
                        size: 18,
                        color: context.nyumba.sageDark,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'This request can be saved without a connection and '
                          'will show as awaiting sync.',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                final title = titleController.text.trim();
                final description = descriptionController.text.trim();
                if (title.length < 4 || description.length < 10) {
                  showTenantMessage(
                    dialogContext,
                    'Add a clear title and a little more detail.',
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
    if (submitted == true) {
      // The request must reach the landlord who actually owns this tenancy;
      // without it there is nobody to route the work to.
      final tenancy = ref.read(myTenancyProvider(_tenantId)).value;
      if (tenancy == null) {
        if (mounted) {
          showTenantMessage(
            context,
            'We could not find your tenancy yet, so this request has nowhere '
            'to go. It will work once your landlord activates your lease.',
          );
        }
        return;
      }
      try {
        final request = await ref.read(createMaintenanceRequestProvider)(
          CreateMaintenanceRequestInput(
            landlordId: tenancy.landlordId,
            tenantId: _tenantId,
            title: titleController.text.trim(),
            description: descriptionController.text.trim(),
            location: '${tenancy.unitLabel} · ${tenancy.propertyName}',
            reporterName: session?.displayName ?? 'Tenant',
            category: category,
            priority: priority,
            allowAccess: allowAccess,
            photoCount: photoCount,
          ),
        );
        if (mounted) {
          setState(() => _filter = 'All');
          showTenantMessage(
            context,
            '${request.reference} saved and queued to sync.',
          );
        }
      } on Object catch (error) {
        if (mounted) {
          showTenantMessage(context, 'Could not save the request: $error');
        }
      }
    }
    titleController.dispose();
    descriptionController.dispose();
  }

  Future<void> _showRequest(MaintenanceRequest request) async {
    final updates = _timelineFor(request);
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Expanded(child: Text(request.title)),
            TenantStatusBadge(status: tenantStatusLabel(request.status)),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    StatusBadge(label: request.category, tone: BadgeTone.info),
                    StatusBadge(
                      label: request.priority == MaintenancePriority.urgent
                          ? 'Urgent'
                          : 'Normal',
                      tone: request.priority == MaintenancePriority.urgent
                          ? BadgeTone.danger
                          : BadgeTone.neutral,
                    ),
                    if (request.photoCount > 0)
                      StatusBadge(
                        label:
                            '${request.photoCount} photo${request.photoCount == 1 ? '' : 's'}',
                        tone: BadgeTone.neutral,
                        icon: Icons.photo_outlined,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(request.description),
                if (request.appointment != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.nyumba.navyTint,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event_available_outlined,
                          color: context.nyumba.midnightNavy,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Contractor visit',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              Text(request.appointment!),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  'Request timeline',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 13),
                for (var index = 0; index < updates.length; index++)
                  TenantTimelineStep(
                    title: updates[index].$1,
                    detail: updates[index].$2,
                    complete: updates[index].$3,
                    last: index == updates.length - 1,
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (request.status == MaintenanceStatus.submitted)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: const Text('Cancel request'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, 'message'),
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: const Text('Message manager'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'message') {
      showTenantMessage(
        context,
        'A message draft for ${request.reference} was opened.',
      );
    } else if (action == 'cancel') {
      await _cancelRequest(request);
    }
  }

  List<(String, String, bool)> _timelineFor(MaintenanceRequest request) {
    final formatter = DateFormat('d MMM • HH:mm');
    final reviewed =
        request.assignee != null ||
        request.status != MaintenanceStatus.submitted;
    return [
      (
        'Request submitted',
        formatter.format(request.reportedAt.toLocal()),
        true,
      ),
      (
        'Manager reviewed',
        request.assignee != null
            ? 'Assigned to ${request.assignee}'
            : reviewed
            ? 'Reviewed by the manager'
            : 'Waiting for review',
        reviewed,
      ),
      (
        'Contractor visit scheduled',
        request.appointment ?? 'Not yet scheduled',
        request.appointment != null ||
            request.status == MaintenanceStatus.inProgress ||
            request.status == MaintenanceStatus.resolved,
      ),
      (
        'Issue resolved',
        request.resolvedAt != null
            ? formatter.format(request.resolvedAt!.toLocal())
            : request.status == MaintenanceStatus.cancelled
            ? 'Request cancelled'
            : 'Waiting for completion',
        request.status == MaintenanceStatus.resolved,
      ),
    ];
  }

  Future<void> _cancelRequest(MaintenanceRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this request?'),
        content: const Text(
          'The property manager will be notified. You can create a new request '
          'later if the issue returns.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep request'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(transitionMaintenanceRequestProvider)(
        TransitionMaintenanceInput(
          requestId: request.id,
          status: MaintenanceStatus.cancelled,
        ),
      );
      if (mounted) {
        showTenantMessage(
          context,
          '${request.reference} cancellation queued to sync.',
        );
      }
    } on Object catch (error) {
      if (mounted) {
        showTenantMessage(context, 'Could not cancel the request: $error');
      }
    }
  }

  Future<void> _showEmergencyHelp() {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Emergency help',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              const Text(
                'For fire, immediate danger, or a serious medical emergency, '
                'contact local emergency services first.',
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: context.nyumba.danger,
                ),
                onPressed: () => showTenantMessage(
                  context,
                  'Emergency call handoff is available on your phone.',
                ),
                icon: const Icon(Icons.call_outlined),
                label: const Text('Call property emergency line'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _createRequest();
                },
                icon: const Icon(Icons.report_problem_outlined),
                label: const Text('Report an urgent property issue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.syncStatus,
    required this.onTap,
  });

  final MaintenanceRequest request;
  final AggregateSyncStatus syncStatus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (request.status) {
      MaintenanceStatus.resolved => context.nyumba.sageDark,
      MaintenanceStatus.scheduled => context.nyumba.midnightNavy,
      MaintenanceStatus.cancelled => context.nyumba.danger,
      _ => context.nyumba.terracottaDark,
    };
    return NyumbaSurface(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 196),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_iconFor(request.category), color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${request.reference} • ${request.category}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TenantStatusBadge(status: tenantStatusLabel(request.status)),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              request.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 29),
            Row(
              children: [
                Expanded(
                  child: Text(
                    request.appointment ??
                        'Reported ${DateFormat('d MMM').format(request.reportedAt.toLocal())}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (request.priority == MaintenancePriority.urgent) ...[
                  const SizedBox(width: 8),
                  const StatusBadge(label: 'Urgent', tone: BadgeTone.danger),
                ],
                const SizedBox(width: 8),
                SyncStateBadge(status: syncStatus),
                const SizedBox(width: 5),
                const Icon(Icons.chevron_right_rounded, size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String category) => switch (category) {
    'Plumbing' => Icons.plumbing_outlined,
    'Electrical' => Icons.electrical_services_outlined,
    'Appliance' => Icons.kitchen_outlined,
    _ => Icons.home_repair_service_outlined,
  };
}
