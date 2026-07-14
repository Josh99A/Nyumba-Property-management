import 'package:flutter/material.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import 'widgets/tenant_components.dart';

class TenantMaintenanceScreen extends StatefulWidget {
  const TenantMaintenanceScreen({super.key});

  @override
  State<TenantMaintenanceScreen> createState() =>
      _TenantMaintenanceScreenState();
}

class _TenantMaintenanceScreenState extends State<TenantMaintenanceScreen> {
  final List<_MaintenanceRequest> _requests = [..._seedRequests];
  String _filter = 'All';
  String _query = '';

  List<_MaintenanceRequest> get _filteredRequests {
    final query = _query.trim().toLowerCase();
    return _requests.where((request) {
      final matchesQuery =
          query.isEmpty ||
          request.title.toLowerCase().contains(query) ||
          request.category.toLowerCase().contains(query) ||
          request.id.toLowerCase().contains(query);
      final matchesFilter = switch (_filter) {
        'Open' =>
          request.status == 'Reported' || request.status == 'In progress',
        'Scheduled' => request.status == 'Scheduled',
        'Resolved' => request.status == 'Resolved',
        _ => true,
      };
      return matchesQuery && matchesFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRequests;
    final openCount = _requests
        .where(
          (item) => item.status == 'Reported' || item.status == 'In progress',
        )
        .length;
    final resolvedCount = _requests
        .where((item) => item.status == 'Resolved')
        .length;
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
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'New requests, notes, and photos save on this device first. '
                  'They sync automatically when connectivity is available.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
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
              value:
                  '${_requests.where((item) => item.status == 'Scheduled').length}',
              caption: 'Next visit on 15 Jul',
              icon: Icons.event_available_outlined,
              color: context.nyumba.midnightNavy,
            ),
            TenantMetricCard(
              label: 'Resolved this year',
              value: '$resolvedCount',
              caption: 'Average resolution: 3.2 days',
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
                      decoration: const InputDecoration(
                        hintText: 'Search issue, category, or request ID',
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
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    var category = 'Plumbing';
    var priority = 'Normal';
    var allowAccess = false;
    var photoCount = 0;
    final request = await showDialog<_MaintenanceRequest>(
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
                    decoration: const InputDecoration(
                      labelText: 'Short title',
                      hintText: 'e.g. Bathroom light not working',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    minLines: 3,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Describe the issue',
                      alignLabelWithHint: true,
                      hintText: 'Include the location and when it started.',
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
                      for (final item in const ['Normal', 'Urgent'])
                        ChoiceChip(
                          label: Text(item),
                          selected: priority == item,
                          showCheckmark: false,
                          onSelected: (_) =>
                              setDialogState(() => priority = item),
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
                      SizedBox(width: 8),
                      Expanded(
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
                Navigator.pop(
                  dialogContext,
                  _MaintenanceRequest(
                    id: 'MNT-${1060 + _requests.length}',
                    title: title,
                    category: category,
                    description: description,
                    status: 'Reported',
                    priority: priority,
                    reported: 'Just now • awaiting sync',
                    appointment: null,
                    photoCount: photoCount,
                    allowAccess: allowAccess,
                    updates: const [
                      _RequestUpdate(
                        title: 'Saved on this device',
                        detail:
                            'Waiting for a connection to notify the manager',
                        complete: true,
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.send_rounded),
              label: const Text('Submit request'),
            ),
          ],
        ),
      ),
    );
    titleController.dispose();
    descriptionController.dispose();
    if (request == null || !mounted) return;
    setState(() {
      _requests.insert(0, request);
      _filter = 'All';
    });
    showTenantMessage(context, '${request.id} saved and queued to sync.');
  }

  Future<void> _showRequest(_MaintenanceRequest request) async {
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Expanded(child: Text(request.title)),
            TenantStatusBadge(status: request.status),
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
                      label: request.priority,
                      tone: request.priority == 'Urgent'
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
                for (var index = 0; index < request.updates.length; index++)
                  TenantTimelineStep(
                    title: request.updates[index].title,
                    detail: request.updates[index].detail,
                    complete: request.updates[index].complete,
                    last: index == request.updates.length - 1,
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (request.status == 'Reported')
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
        'A message draft for ${request.id} was opened.',
      );
    } else if (action == 'cancel') {
      await _cancelRequest(request);
    }
  }

  Future<void> _cancelRequest(_MaintenanceRequest request) async {
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
    final index = _requests.indexOf(request);
    if (index < 0) return;
    setState(() {
      _requests[index] = request.copyWith(status: 'Cancelled');
    });
    showTenantMessage(context, '${request.id} cancellation queued to sync.');
  }

  Future<void> _showEmergencyHelp() {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
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
  const _RequestCard({required this.request, required this.onTap});

  final _MaintenanceRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (request.status) {
      'Resolved' => context.nyumba.sageDark,
      'Scheduled' => context.nyumba.midnightNavy,
      'Cancelled' => context.nyumba.danger,
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
                        '${request.id} • ${request.category}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TenantStatusBadge(status: request.status),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              request.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Spacer(),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: Text(
                    request.appointment ?? request.reported,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (request.priority == 'Urgent') ...[
                  const SizedBox(width: 8),
                  const StatusBadge(label: 'Urgent', tone: BadgeTone.danger),
                ],
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

class _MaintenanceRequest {
  const _MaintenanceRequest({
    required this.id,
    required this.title,
    required this.category,
    required this.description,
    required this.status,
    required this.priority,
    required this.reported,
    required this.appointment,
    required this.photoCount,
    required this.allowAccess,
    required this.updates,
  });

  final String id;
  final String title;
  final String category;
  final String description;
  final String status;
  final String priority;
  final String reported;
  final String? appointment;
  final int photoCount;
  final bool allowAccess;
  final List<_RequestUpdate> updates;

  _MaintenanceRequest copyWith({String? status}) {
    return _MaintenanceRequest(
      id: id,
      title: title,
      category: category,
      description: description,
      status: status ?? this.status,
      priority: priority,
      reported: reported,
      appointment: appointment,
      photoCount: photoCount,
      allowAccess: allowAccess,
      updates: updates,
    );
  }
}

class _RequestUpdate {
  const _RequestUpdate({
    required this.title,
    required this.detail,
    required this.complete,
  });

  final String title;
  final String detail;
  final bool complete;
}

const _seedRequests = [
  _MaintenanceRequest(
    id: 'MNT-1058',
    title: 'Kitchen tap leak',
    category: 'Plumbing',
    description:
        'The kitchen mixer tap drips continuously, even when fully closed.',
    status: 'Scheduled',
    priority: 'Normal',
    reported: 'Reported 8 Jul 2026',
    appointment: '15 Jul 2026 • 10:00–12:00',
    photoCount: 2,
    allowAccess: false,
    updates: [
      _RequestUpdate(
        title: 'Request submitted',
        detail: '8 Jul at 09:14',
        complete: true,
      ),
      _RequestUpdate(
        title: 'Manager reviewed',
        detail: 'Sandra assigned Kato Services',
        complete: true,
      ),
      _RequestUpdate(
        title: 'Contractor visit scheduled',
        detail: '15 Jul • 10:00–12:00',
        complete: true,
      ),
      _RequestUpdate(
        title: 'Issue resolved',
        detail: 'Waiting for contractor visit',
        complete: false,
      ),
    ],
  ),
  _MaintenanceRequest(
    id: 'MNT-1037',
    title: 'Bedroom power socket',
    category: 'Electrical',
    description:
        'The socket near the wardrobe has stopped powering any devices.',
    status: 'In progress',
    priority: 'Normal',
    reported: 'Reported 29 Jun 2026',
    appointment: null,
    photoCount: 1,
    allowAccess: true,
    updates: [
      _RequestUpdate(
        title: 'Request submitted',
        detail: '29 Jun at 18:22',
        complete: true,
      ),
      _RequestUpdate(
        title: 'Electrician assigned',
        detail: 'Kampala Electrical Co. is sourcing a replacement',
        complete: true,
      ),
      _RequestUpdate(
        title: 'Repair completed',
        detail: 'Update expected by 16 Jul',
        complete: false,
      ),
    ],
  ),
  _MaintenanceRequest(
    id: 'MNT-0994',
    title: 'Loose wardrobe hinge',
    category: 'Building',
    description: 'The upper wardrobe door hinge had loosened from the frame.',
    status: 'Resolved',
    priority: 'Normal',
    reported: 'Resolved 12 Jun 2026',
    appointment: null,
    photoCount: 1,
    allowAccess: true,
    updates: [
      _RequestUpdate(
        title: 'Request submitted',
        detail: '9 Jun at 08:40',
        complete: true,
      ),
      _RequestUpdate(
        title: 'Carpenter assigned',
        detail: 'Visit completed 12 Jun',
        complete: true,
      ),
      _RequestUpdate(
        title: 'Resolved',
        detail: 'Hinge and mounting plate replaced',
        complete: true,
      ),
    ],
  ),
  _MaintenanceRequest(
    id: 'MNT-0962',
    title: 'Fridge door seal',
    category: 'Appliance',
    description:
        'The supplied refrigerator was not sealing along the top edge.',
    status: 'Resolved',
    priority: 'Normal',
    reported: 'Resolved 20 May 2026',
    appointment: null,
    photoCount: 2,
    allowAccess: false,
    updates: [
      _RequestUpdate(
        title: 'Request submitted',
        detail: '16 May at 14:10',
        complete: true,
      ),
      _RequestUpdate(
        title: 'Technician visited',
        detail: '20 May at 10:30',
        complete: true,
      ),
      _RequestUpdate(
        title: 'Resolved',
        detail: 'Door seal replaced and tested',
        complete: true,
      ),
    ],
  ),
];
