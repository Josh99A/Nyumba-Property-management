import 'package:flutter/material.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/coming_soon.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import 'widgets/admin_components.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final List<_UserAccount> _accounts = [..._seedAccounts];
  String _query = '';
  String _role = 'All roles';
  String _status = 'All statuses';

  List<_UserAccount> get _filteredAccounts {
    final query = _query.trim().toLowerCase();
    return _accounts.where((account) {
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
  }

  int get _activeCount => _accounts
      .where((account) => account.status == _AccountStatus.active)
      .length;

  int get _suspendedCount => _accounts
      .where((account) => account.status == _AccountStatus.suspended)
      .length;

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredAccounts;
    return AdminPage(
      title: 'Users & access',
      description: 'Review accounts, roles, verification, and platform access.',
      secondaryAction: ComingSoon(
        message: 'User export coming soon',
        child: OutlinedButton.icon(
          onPressed: null,
          icon: Icon(Icons.download_outlined),
          label: Text('Export'),
        ),
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
              value: '${_accounts.length}',
              caption: 'In this presentation workspace',
              icon: Icons.groups_2_outlined,
              tone: context.nyumba.midnightNavy,
            ),
            AdminMetricCard(
              label: 'Active',
              value: '$_activeCount',
              caption:
                  '${(_activeCount / _accounts.length * 100).round()}% of users',
              icon: Icons.verified_user_outlined,
              tone: context.nyumba.sageDark,
            ),
            AdminMetricCard(
              label: 'Invitations pending',
              value:
                  '${_accounts.where((item) => item.status == _AccountStatus.invited).length}',
              caption: 'Resend from the account menu',
              icon: Icons.mark_email_unread_outlined,
              tone: context.nyumba.terracottaDark,
            ),
            AdminMetricCard(
              label: 'Suspended',
              value: '$_suspendedCount',
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
                    values: const ['All roles', 'Admin', 'Landlord', 'Tenant'],
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
                                  DataCell(_AccountStatusBadge(account.status)),
                                  DataCell(Text(account.lastActive)),
                                  DataCell(
                                    _AccountMenu(
                                      account: account,
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
      ],
    );
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
    final account = await showDialog<_UserAccount>(
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
                  values: const ['Admin', 'Landlord', 'Tenant'],
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
                    SizedBox(width: 8),
                    Expanded(
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
                Navigator.pop(
                  dialogContext,
                  _UserAccount(
                    id: 'USR-${_accounts.length + 4100}',
                    name: name,
                    email: email,
                    role: role,
                    location: 'Not set',
                    status: _AccountStatus.invited,
                    lastActive: 'Invitation pending',
                    joined: '13 Jul 2026',
                  ),
                );
              },
              icon: const Icon(Icons.send_rounded),
              label: const Text('Send invite'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    emailController.dispose();
    if (account == null || !mounted) return;
    setState(() => _accounts.insert(0, account));
    showAdminMessage(context, 'Invitation queued for ${account.email}.');
  }

  void _handleAction(String action, _UserAccount account) {
    switch (action) {
      case 'view':
        _showAccount(account);
      case 'status':
        _changeStatus(account);
      case 'resend':
        showAdminMessage(context, 'Invitation resent to ${account.email}.');
    }
  }

  Future<void> _changeStatus(_UserAccount account) async {
    final isSuspended = account.status == _AccountStatus.suspended;
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
    final index = _accounts.indexOf(account);
    if (index < 0) return;
    setState(() {
      _accounts[index] = account.copyWith(
        status: isSuspended ? _AccountStatus.active : _AccountStatus.suspended,
      );
    });
    showAdminMessage(
      context,
      isSuspended
          ? 'Access restored for ${account.name}.'
          : '${account.name} has been suspended.',
    );
  }

  Future<void> _showAccount(_UserAccount account) {
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
              _AccountFact(label: 'User ID', value: account.id),
              _AccountFact(label: 'Role', value: account.role),
              _AccountFact(label: 'Location', value: account.location),
              _AccountFact(label: 'Joined', value: account.joined),
              _AccountFact(label: 'Last active', value: account.lastActive),
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

  final _UserAccount account;

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
  const _UserCard({required this.account, required this.onAction});

  final _UserAccount account;
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
                    Text(
                      account.location,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          _AccountMenu(account: account, onAction: onAction),
        ],
      ),
    );
  }
}

class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.account, required this.onAction});

  final _UserAccount account;
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
        if (account.status == _AccountStatus.invited)
          const PopupMenuItem(
            value: 'resend',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.forward_to_inbox_outlined),
              title: Text('Resend invitation'),
            ),
          )
        else
          PopupMenuItem(
            value: 'status',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                account.status == _AccountStatus.suspended
                    ? Icons.lock_open_outlined
                    : Icons.person_off_outlined,
              ),
              title: Text(
                account.status == _AccountStatus.suspended
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

  final _AccountStatus status;

  @override
  Widget build(BuildContext context) {
    return StatusBadge(
      label: status.label,
      tone: switch (status) {
        _AccountStatus.active => BadgeTone.success,
        _AccountStatus.invited => BadgeTone.warning,
        _AccountStatus.suspended => BadgeTone.danger,
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

enum _AccountStatus {
  active('Active'),
  invited('Invited'),
  suspended('Suspended');

  const _AccountStatus(this.label);

  final String label;
}

class _UserAccount {
  const _UserAccount({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.location,
    required this.status,
    required this.lastActive,
    required this.joined,
  });

  final String id;
  final String name;
  final String email;
  final String role;
  final String location;
  final _AccountStatus status;
  final String lastActive;
  final String joined;

  _UserAccount copyWith({_AccountStatus? status}) {
    return _UserAccount(
      id: id,
      name: name,
      email: email,
      role: role,
      location: location,
      status: status ?? this.status,
      lastActive: lastActive,
      joined: joined,
    );
  }
}

const _seedAccounts = [
  _UserAccount(
    id: 'USR-4082',
    name: 'Sandra Nakato',
    email: 'sandra@acaciahomes.ug',
    role: 'Landlord',
    location: 'Kampala',
    status: _AccountStatus.active,
    lastActive: '8 min ago',
    joined: '14 Feb 2025',
  ),
  _UserAccount(
    id: 'USR-4079',
    name: 'Brian Okello',
    email: 'brian.otieno@example.com',
    role: 'Tenant',
    location: 'Kampala',
    status: _AccountStatus.active,
    lastActive: '42 min ago',
    joined: '3 Jun 2025',
  ),
  _UserAccount(
    id: 'USR-4058',
    name: 'Amina Noor',
    email: 'amina@tuliahomes.ug',
    role: 'Landlord',
    location: 'Mbarara',
    status: _AccountStatus.invited,
    lastActive: 'Invitation pending',
    joined: '11 Jul 2026',
  ),
  _UserAccount(
    id: 'USR-4024',
    name: 'Kevin Odongo',
    email: 'kevin.kiptoo@example.com',
    role: 'Tenant',
    location: 'Jinja',
    status: _AccountStatus.suspended,
    lastActive: '9 Jul 2026',
    joined: '22 Nov 2025',
  ),
  _UserAccount(
    id: 'USR-3998',
    name: 'Faith Nabirye',
    email: 'faith.wambui@example.com',
    role: 'Tenant',
    location: 'Wakiso',
    status: _AccountStatus.active,
    lastActive: 'Yesterday',
    joined: '6 Oct 2025',
  ),
  _UserAccount(
    id: 'USR-3951',
    name: 'Sam Walusimbi',
    email: 'sam@kilimaproperties.ug',
    role: 'Landlord',
    location: 'Mukono',
    status: _AccountStatus.active,
    lastActive: 'Yesterday',
    joined: '18 Aug 2025',
  ),
  _UserAccount(
    id: 'USR-3905',
    name: 'Mercy Atim',
    email: 'mercy.chebet@example.com',
    role: 'Tenant',
    location: 'Uasin Gishu',
    status: _AccountStatus.active,
    lastActive: '2 days ago',
    joined: '2 Jul 2025',
  ),
  _UserAccount(
    id: 'USR-3818',
    name: 'Daniel Musoke',
    email: 'daniel.musoke@nyumba.ug',
    role: 'Admin',
    location: 'Kampala',
    status: _AccountStatus.active,
    lastActive: 'Just now',
    joined: '10 Jan 2025',
  ),
];
