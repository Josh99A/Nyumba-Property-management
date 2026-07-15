import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/offline/aggregate_sync_status.dart';
import '../../../core/offline/offline_entity.dart';
import '../../../core/offline/outbox_entry.dart';
import '../../../core/presentation/operational_actions.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import '../../../core/presentation/sync_state_badge.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/authorization_policy.dart';
import '../application/admin_providers.dart';
import '../domain/admin_action.dart';
import '../domain/managed_user.dart';
import 'widgets/admin_components.dart';

class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  String _query = '';
  String _role = 'All roles';
  String _status = 'All statuses';

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final usersValue = ref.watch(managedUsersProvider);
    final actions =
        ref.watch(adminActionsProvider).value ?? const <AdminActionRecord>[];
    final outbox =
        ref.watch(outboxEntriesProvider).value ?? const <OutboxEntry>[];
    final accounts = usersValue.value ?? const <ManagedUser>[];

    final query = _query.trim().toLowerCase();
    final filtered = accounts.where((account) {
      final matchesQuery =
          query.isEmpty ||
          account.name.toLowerCase().contains(query) ||
          account.email.toLowerCase().contains(query) ||
          account.location.toLowerCase().contains(query);
      final matchesRole = _role == 'All roles' || account.role == _role;
      final matchesStatus =
          _status == 'All statuses' || account.status.label == _status;
      return matchesQuery && matchesRole && matchesStatus;
    }).toList();
    final activeCount = accounts
        .where((account) => account.status == ManagedUserStatus.active)
        .length;
    final suspendedCount = accounts
        .where((account) => account.status == ManagedUserStatus.suspended)
        .length;

    AggregateSyncStatus statusOf(ManagedUser account) =>
        resolveAggregateSyncStatus(
          entityType: OfflineEntityType.userProfile,
          entityId: account.id,
          outbox: outbox,
          syncMetadata: account.syncMetadata,
        );
    bool canManage(ManagedUser account) =>
        session != null &&
        account.id != session.userId &&
        AuthorizationPolicy.canManageAccountRole(session.role, account.role);

    return AdminPage(
      title: 'Users & access',
      description: 'Review accounts, roles, verification, and platform access.',
      secondaryAction: OutlinedButton.icon(
        onPressed: () => _exportUsers(filtered),
        icon: const Icon(Icons.download_outlined),
        label: const Text('Export'),
      ),
      primaryAction: FilledButton.icon(
        onPressed: _inviteUser,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Invite user'),
      ),
      children: [
        AdminMetricGrid(
          children: [
            AdminMetricCard(
              label: 'All accounts',
              value: '${accounts.length}',
              caption: 'In this presentation workspace',
              icon: Icons.groups_2_outlined,
              tone: context.nyumba.midnightNavy,
            ),
            AdminMetricCard(
              label: 'Active',
              value: '$activeCount',
              caption: accounts.isEmpty
                  ? 'No accounts yet'
                  : '${(activeCount / accounts.length * 100).round()}% of users',
              icon: Icons.verified_user_outlined,
              tone: context.nyumba.sageDark,
            ),
            AdminMetricCard(
              label: 'Invitations pending',
              value:
                  '${accounts.where((item) => item.status == ManagedUserStatus.invited).length}',
              caption: 'Resend from the account menu',
              icon: Icons.mark_email_unread_outlined,
              tone: context.nyumba.terracottaDark,
            ),
            AdminMetricCard(
              label: 'Suspended',
              value: '$suspendedCount',
              caption: 'Access is currently blocked',
              icon: Icons.person_off_outlined,
              tone: context.nyumba.danger,
            ),
          ],
        ),
        const SizedBox(height: 20),
        NyumbaSurface(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final filters = <Widget>[
                SizedBox(
                  width: constraints.maxWidth < 640
                      ? constraints.maxWidth
                      : 320,
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search name, email, or district',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                SizedBox(
                  width: constraints.maxWidth < 640
                      ? constraints.maxWidth
                      : 180,
                  child: _FilterDropdown(
                    value: _role,
                    values: const [
                      'All roles',
                      'Super Admin',
                      'Admin',
                      'Landlord',
                      'Tenant',
                      'Client',
                    ],
                    icon: Icons.badge_outlined,
                    onChanged: (value) => setState(() => _role = value),
                  ),
                ),
                SizedBox(
                  width: constraints.maxWidth < 640
                      ? constraints.maxWidth
                      : 180,
                  child: _FilterDropdown(
                    value: _status,
                    values: const [
                      'All statuses',
                      'Active',
                      'Invited',
                      'Suspended',
                    ],
                    icon: Icons.tune_rounded,
                    onChanged: (value) => setState(() => _status = value),
                  ),
                ),
                if (_query.isNotEmpty ||
                    _role != 'All roles' ||
                    _status != 'All statuses')
                  TextButton.icon(
                    onPressed: _clearFilters,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Clear'),
                  ),
              ];
              return Wrap(spacing: 12, runSpacing: 12, children: filters);
            },
          ),
        ),
        const SizedBox(height: 16),
        if (usersValue.isLoading && accounts.isEmpty)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (usersValue.hasError && accounts.isEmpty)
          NyumbaSurface(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load accounts: ${usersValue.error}'),
            ),
          )
        else
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
                          '${filtered.length} user${filtered.length == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      const StatusBadge(
                        label: 'Role-based access',
                        tone: BadgeTone.info,
                        icon: Icons.lock_outline_rounded,
                      ),
                    ],
                  ),
                ),
                const Divider(),
                if (filtered.isEmpty)
                  AdminEmptyState(
                    title: 'No users match these filters',
                    message: 'Try another name, role, or account status.',
                    action: OutlinedButton(
                      onPressed: _clearFilters,
                      child: const Text('Clear filters'),
                    ),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 860) {
                        return Column(
                          children: [
                            for (
                              var index = 0;
                              index < filtered.length;
                              index++
                            ) ...[
                              _UserCard(
                                account: filtered[index],
                                syncStatus: statusOf(filtered[index]),
                                canManage: canManage(filtered[index]),
                                onAction: (action) =>
                                    _handleAction(action, filtered[index]),
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
                            columnSpacing: 30,
                            headingRowHeight: 48,
                            dataRowMinHeight: 66,
                            dataRowMaxHeight: 74,
                            columns: const [
                              DataColumn(label: Text('User')),
                              DataColumn(label: Text('Role')),
                              DataColumn(label: Text('Location')),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Sync')),
                              DataColumn(label: Text('Last active')),
                              DataColumn(label: Text('')),
                            ],
                            rows: [
                              for (final account in filtered)
                                DataRow(
                                  cells: [
                                    DataCell(_UserIdentity(account: account)),
                                    DataCell(Text(account.role)),
                                    DataCell(Text(account.location)),
                                    DataCell(
                                      _AccountStatusBadge(account.status),
                                    ),
                                    DataCell(
                                      SyncStateBadge(
                                        status: statusOf(account),
                                        compact: false,
                                      ),
                                    ),
                                    DataCell(Text(account.lastActiveLabel)),
                                    DataCell(
                                      _AccountMenu(
                                        account: account,
                                        canManage: canManage(account),
                                        onAction: (action) =>
                                            _handleAction(action, account),
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
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Text(
                    'Showing locally available account records • changes sync automatically',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 20),
        _AdminAuditPanel(actions: actions, outbox: outbox),
      ],
    );
  }

  Future<void> _exportUsers(List<ManagedUser> accounts) async {
    final rows = <String>[
      'id,name,email,role,location,status,last_active,joined',
      for (final account in accounts)
        [
          account.reference,
          account.name,
          account.email,
          account.role,
          account.location,
          account.status.label,
          account.lastActiveLabel,
          account.joinedLabel,
        ].map(csvCell).join(','),
    ];
    try {
      final saved = await exportTextFile(
        fileName: 'nyumba-users.csv',
        contents: rows.join('\n'),
      );
      if (mounted && saved) showAdminMessage(context, 'User export saved.');
    } on Object catch (error) {
      if (mounted) showAdminMessage(context, 'Could not export users: $error');
    }
  }

  void _clearFilters() {
    setState(() {
      _query = '';
      _role = 'All roles';
      _status = 'All statuses';
    });
  }

  Future<void> _inviteUser() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    var role = 'Landlord';
    final actorRole = ref.read(sessionControllerProvider)?.role;
    final assignableRoles = actorRole == null
        ? const <String>[]
        : AuthorizationPolicy.assignableAccountRoles(actorRole);
    if (assignableRoles.isEmpty) {
      showAdminMessage(context, 'You cannot assign account roles.');
      return;
    }
    role = assignableRoles.contains(role) ? role : assignableRoles.first;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Invite a user'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email address',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                _FilterDropdown(
                  value: role,
                  values: assignableRoles,
                  icon: Icons.badge_outlined,
                  onChanged: (value) => setDialogState(() => role = value),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: context.nyumba.midnightNavy,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'The invitation can be queued offline and will send '
                        'when connectivity returns.',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                final name = nameController.text.trim();
                final email = emailController.text.trim();
                if (name.isEmpty || !email.contains('@')) {
                  showAdminMessage(
                    dialogContext,
                    'Enter a name and valid email address.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.send_rounded),
              label: const Text('Send invite'),
            ),
          ],
        ),
      ),
    );
    if (submitted == true && mounted) {
      try {
        final user = await ref.read(inviteUserProvider)(
          InviteManagedUserInput(
            name: nameController.text.trim(),
            email: emailController.text.trim(),
            role: role,
          ),
        );
        if (mounted) {
          showAdminMessage(context, 'Invitation queued for ${user.email}.');
        }
      } on Object catch (error) {
        if (mounted) {
          showAdminMessage(context, 'Could not queue the invitation: $error');
        }
      }
    }
    nameController.dispose();
    emailController.dispose();
  }

  void _handleAction(String action, ManagedUser account) {
    switch (action) {
      case 'view':
        _showAccount(account);
      case 'status':
        _changeStatus(account);
      case 'resend':
        _resendInvitation(account);
    }
  }

  Future<void> _resendInvitation(ManagedUser account) async {
    try {
      await ref.read(changeUserStatusProvider)(
        userId: account.id,
        status: ManagedUserStatus.invited,
      );
      if (mounted) {
        showAdminMessage(
          context,
          'Invitation for ${account.email} queued to resend.',
        );
      }
    } on Object catch (error) {
      if (mounted) {
        showAdminMessage(context, 'Could not resend the invitation: $error');
      }
    }
  }

  Future<void> _changeStatus(ManagedUser account) async {
    final isSuspended = account.status == ManagedUserStatus.suspended;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isSuspended ? 'Restore access?' : 'Suspend this user?'),
        content: Text(
          isSuspended
              ? '${account.name} will be able to sign in again.'
              : '${account.name} will be signed out and blocked from Nyumba. '
                    'Their records will be retained.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(isSuspended ? 'Restore access' : 'Suspend user'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(changeUserStatusProvider)(
        userId: account.id,
        status: isSuspended
            ? ManagedUserStatus.active
            : ManagedUserStatus.suspended,
      );
      if (mounted) {
        showAdminMessage(
          context,
          isSuspended
              ? 'Access restore for ${account.name} queued to sync.'
              : 'Suspension of ${account.name} queued to sync.',
        );
      }
    } on Object catch (error) {
      if (mounted) {
        showAdminMessage(context, 'Could not update the account: $error');
      }
    }
  }

  Future<void> _showAccount(ManagedUser account) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Account details'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AdminAvatar(name: account.name, radius: 27),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          account.email,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  _AccountStatusBadge(account.status),
                ],
              ),
              const SizedBox(height: 22),
              _AccountFact(label: 'User ID', value: account.reference),
              _AccountFact(label: 'Role', value: account.role),
              _AccountFact(label: 'Location', value: account.location),
              _AccountFact(label: 'Joined', value: account.joinedLabel),
              _AccountFact(
                label: 'Last active',
                value: account.lastActiveLabel,
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

/// Local view of the append-only admin audit trail, including whether each
/// record has reached the server yet.
class _AdminAuditPanel extends StatelessWidget {
  const _AdminAuditPanel({required this.actions, required this.outbox});

  final List<AdminActionRecord> actions;
  final List<OutboxEntry> outbox;

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      title: 'Recent admin activity',
      subtitle: 'Append-only audit trail of account operations',
      child: actions.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No administrative actions recorded yet.'),
            )
          : Column(
              children: [
                for (
                  var index = 0;
                  index < actions.length && index < 6;
                  index++
                ) ...[
                  Row(
                    children: [
                      AdminAvatar(name: actions[index].targetName),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${actions[index].action} · ${actions[index].targetName}',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            Text(
                              '${actions[index].reference} · by '
                              '${actions[index].performedBy} · '
                              '${DateFormat('d MMM, HH:mm').format(actions[index].performedAt.toLocal())}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      SyncStateBadge(
                        status: resolveAggregateSyncStatus(
                          entityType: OfflineEntityType.adminAction,
                          entityId: actions[index].id,
                          outbox: outbox,
                          syncMetadata: actions[index].syncMetadata,
                        ),
                      ),
                    ],
                  ),
                  if (index < actions.length - 1 && index < 5)
                    const Divider(height: 24),
                ],
              ],
            ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.value,
    required this.values,
    required this.icon,
    required this.onChanged,
  });

  final String value;
  final List<String> values;
  final IconData icon;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(prefixIcon: Icon(icon), isDense: true),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          isExpanded: true,
          items: [
            for (final item in values)
              DropdownMenuItem(value: item, child: Text(item)),
          ],
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}

class _UserIdentity extends StatelessWidget {
  const _UserIdentity({required this.account});

  final ManagedUser account;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AdminAvatar(name: account.name),
        const SizedBox(width: 11),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(account.name, style: Theme.of(context).textTheme.labelLarge),
            Text(account.email, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.account,
    required this.syncStatus,
    required this.canManage,
    required this.onAction,
  });

  final ManagedUser account;
  final AggregateSyncStatus syncStatus;
  final bool canManage;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminAvatar(name: account.name, radius: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  account.email,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 7,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusBadge(label: account.role, tone: BadgeTone.info),
                    _AccountStatusBadge(account.status),
                    SyncStateBadge(status: syncStatus),
                    Text(
                      account.location,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          _AccountMenu(
            account: account,
            canManage: canManage,
            onAction: onAction,
          ),
        ],
      ),
    );
  }
}

class _AccountMenu extends StatelessWidget {
  const _AccountMenu({
    required this.account,
    required this.canManage,
    required this.onAction,
  });

  final ManagedUser account;
  final bool canManage;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Account actions',
      onSelected: onAction,
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'view',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.visibility_outlined),
            title: Text('View account'),
          ),
        ),
        if (canManage && account.status == ManagedUserStatus.invited)
          const PopupMenuItem(
            value: 'resend',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.forward_to_inbox_outlined),
              title: Text('Resend invitation'),
            ),
          )
        else if (canManage)
          PopupMenuItem(
            value: 'status',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                account.status == ManagedUserStatus.suspended
                    ? Icons.lock_open_outlined
                    : Icons.person_off_outlined,
              ),
              title: Text(
                account.status == ManagedUserStatus.suspended
                    ? 'Restore access'
                    : 'Suspend access',
              ),
            ),
          ),
      ],
      icon: const Icon(Icons.more_horiz_rounded),
    );
  }
}

class _AccountStatusBadge extends StatelessWidget {
  const _AccountStatusBadge(this.status);

  final ManagedUserStatus status;

  @override
  Widget build(BuildContext context) {
    return StatusBadge(
      label: status.label,
      tone: switch (status) {
        ManagedUserStatus.active => BadgeTone.success,
        ManagedUserStatus.invited => BadgeTone.warning,
        ManagedUserStatus.suspended => BadgeTone.danger,
      },
    );
  }
}

class _AccountFact extends StatelessWidget {
  const _AccountFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.labelLarge),
          ),
        ],
      ),
    );
  }
}
