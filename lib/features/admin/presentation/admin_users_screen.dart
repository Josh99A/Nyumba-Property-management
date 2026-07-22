import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations_adapter.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/async_action_button.dart';
import '../../../core/presentation/operational_actions.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/status_message.dart';
import '../../../core/presentation/surface.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/authorization_policy.dart';
import '../../auth/domain/user_session.dart';
import '../application/admin_directory_providers.dart';
import '../domain/platform_account.dart';
import 'widgets/admin_components.dart';

class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

enum PendingLifecycleTarget { archived, active, deleted }

final class PendingLifecycleAction {
  const PendingLifecycleAction({
    required this.target,
    required this.expectedVersion,
  });

  final PendingLifecycleTarget target;
  final int expectedVersion;
}

/// Returns lifecycle actions confirmed by an authoritative directory snapshot.
///
/// Loading and error values may carry stale or absent data, so neither can
/// confirm a restoration or make a missing account count as deleted.
Set<String> resolvedPendingLifecycleActionIds({
  required AsyncValue<List<PlatformAccount>> accountsValue,
  required Map<String, PendingLifecycleAction> pendingActions,
}) {
  if (accountsValue.isLoading || accountsValue.hasError) {
    return const <String>{};
  }
  final accounts = accountsValue.value;
  if (accounts == null) return const <String>{};
  final byUid = {for (final account in accounts) account.uid: account};
  final resolved = <String>{};
  for (final entry in pendingActions.entries) {
    final account = byUid[entry.key];
    final pending = entry.value;
    final versionConfirmed =
        (account?.userVersion ?? -1) >= pending.expectedVersion;
    final confirmed = switch (pending.target) {
      PendingLifecycleTarget.archived =>
        versionConfirmed && account?.status == PlatformAccountStatus.archived,
      PendingLifecycleTarget.active =>
        versionConfirmed && account?.status == PlatformAccountStatus.active,
      PendingLifecycleTarget.deleted => account == null,
    };
    if (confirmed) resolved.add(entry.key);
  }
  return resolved;
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  String _query = '';
  String _role = 'All roles';
  String _status = 'All statuses';
  final _pendingLifecycleActions = <String, PendingLifecycleAction>{};

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(adminDirectorySourceProvider);
    final session = ref.watch(sessionControllerProvider);
    final accountsValue = ref.watch(platformAccountsProvider);
    final accounts = accountsValue.value ?? const <PlatformAccount>[];
    _reconcilePendingLifecycleActions(accountsValue);

    final query = _query.trim().toLowerCase();
    final filtered = accounts.where((account) {
      final matchesQuery =
          query.isEmpty ||
          account.displayName.toLowerCase().contains(query) ||
          account.email.toLowerCase().contains(query) ||
          (account.businessName?.toLowerCase().contains(query) ?? false) ||
          (account.location?.toLowerCase().contains(query) ?? false);
      final matchesRole = _role == 'All roles' || account.roleLabel == _role;
      final matchesStatus =
          _status == 'All statuses' || account.status.label == _status;
      return matchesQuery && matchesRole && matchesStatus;
    }).toList();

    final activeCount = accounts
        .where((account) => account.status == PlatformAccountStatus.active)
        .length;
    final pendingCount = accounts
        .where(
          (account) => account.status == PlatformAccountStatus.pendingApproval,
        )
        .length;
    final suspendedCount = accounts
        .where((account) => account.status == PlatformAccountStatus.suspended)
        .length;
    final archivedCount = accounts
        .where((account) => account.status == PlatformAccountStatus.archived)
        .length;
    final isSuperAdmin = session?.role == AppRole.superAdmin;

    bool canManage(PlatformAccount account) =>
        session != null &&
        account.uid != session.userId &&
        AuthorizationPolicy.canManageAccountRole(
          session.role,
          account.roleLabel,
        );

    return AdminPage(
      title: 'Users & access',
      description: source == AdminDirectorySource.live
          ? 'Live server directory of every account, with audited actions.'
          : 'Review accounts, roles, verification, and platform access.',
      secondaryAction: AsyncActionButton.outlined(
        onPressed: () => _exportUsers(filtered),
        icon: const Icon(Icons.download_outlined),
        child: const Text.localized('Export'),
      ),
      primaryAction: AsyncActionButton.outlined(
        onPressed: _explainProvisioning,
        showBusyIndicator: false,
        icon: const Icon(Icons.info_outline_rounded),
        child: const Text.localized('How accounts are created'),
      ),
      children: [
        AdminMetricGrid(
          children: [
            AdminMetricCard(
              label: 'All accounts',
              value: '${accounts.length}',
              caption: source == AdminDirectorySource.live
                  ? 'Live from the server directory'
                  : 'Directory unavailable',
              icon: Icons.groups_2_outlined,
              tone: context.nyumba.midnightNavy,
            ),
            AdminMetricCard(
              label: 'Active',
              value: '$activeCount',
              caption: accounts.isEmpty
                  ? 'No accounts yet'
                  : '${(activeCount / accounts.length * 100).round()}% of accounts',
              icon: Icons.verified_user_outlined,
              tone: context.nyumba.sageDark,
            ),
            AdminMetricCard(
              label: 'Pending approval',
              value: '$pendingCount',
              caption: 'Landlord applications awaiting review',
              icon: Icons.pending_actions_outlined,
              tone: context.nyumba.terracottaDark,
            ),
            AdminMetricCard(
              label: 'Suspended',
              value: '$suspendedCount',
              caption: 'Access is currently blocked',
              icon: Icons.person_off_outlined,
              tone: context.nyumba.danger,
            ),
            if (source == AdminDirectorySource.live)
              AdminMetricCard(
                label: 'Archived',
                value: '$archivedCount',
                caption: 'Awaiting restore or permanent deletion',
                icon: Icons.inventory_2_outlined,
                tone: context.nyumba.midnightNavy,
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
                    decoration: InputDecoration(
                      hintText: context.tr('Search name, email, or business'),
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
                    values: const ['All roles', 'Landlord', 'Tenant', 'Client'],
                    icon: Icons.badge_outlined,
                    onChanged: (value) => setState(() => _role = value),
                  ),
                ),
                SizedBox(
                  width: constraints.maxWidth < 640
                      ? constraints.maxWidth
                      : 200,
                  child: _FilterDropdown(
                    value: _status,
                    values: [
                      'All statuses',
                      PlatformAccountStatus.active.label,
                      PlatformAccountStatus.pendingApproval.label,
                      PlatformAccountStatus.suspended.label,
                      if (source == AdminDirectorySource.live)
                        PlatformAccountStatus.archived.label,
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
                    label: const Text.localized('Clear'),
                  ),
              ];
              return Wrap(spacing: 12, runSpacing: 12, children: filters);
            },
          ),
        ),
        const SizedBox(height: 16),
        if (source == AdminDirectorySource.unavailable)
          const NyumbaSurface(
            child: AdminEmptyState(
              title: 'Account directory is unavailable',
              message:
                  'The directory reads live from the server and needs a '
                  'configured Firebase project and an administrator session.',
              icon: Icons.cloud_off_outlined,
            ),
          )
        else if (accountsValue.isLoading && accounts.isEmpty)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (accountsValue.hasError && accounts.isEmpty)
          NyumbaStatusMessage(
            severity: NyumbaMessageSeverity.critical,
            title: appLocalizationsOf(
              context,
            ).adminAccountDirectoryLoadFailedTitle,
            message: appLocalizationsOf(
              context,
            ).adminAccountDirectoryLoadFailedMessage,
            details: '${accountsValue.error}',
            onRetry: () => ref.invalidate(platformAccountsProvider),
          )
        else
          NyumbaSurface(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 20, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text.localized(
                          '${filtered.length} user${filtered.length == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      const StatusBadge(
                        label: 'Live server data',
                        tone: BadgeTone.success,
                        icon: Icons.cloud_done_outlined,
                      ),
                    ],
                  ),
                ),
                const Divider(),
                if (filtered.isEmpty)
                  AdminEmptyState(
                    title: accounts.isEmpty
                        ? 'No accounts yet'
                        : 'No users match these filters',
                    message: accounts.isEmpty
                        ? 'Accounts appear here as soon as people sign in to '
                              'Nyumba.'
                        : 'Try another name, role, or account status.',
                    action: accounts.isEmpty
                        ? null
                        : OutlinedButton(
                            onPressed: _clearFilters,
                            child: const Text.localized('Clear filters'),
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
                                source: source,
                                canManage: canManage(filtered[index]),
                                isSuperAdmin: isSuperAdmin,
                                awaitingConfirmation: _pendingLifecycleActions
                                    .containsKey(filtered[index].uid),
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
                            columns: [
                              const DataColumn(label: Text.localized('User')),
                              const DataColumn(label: Text.localized('Role')),
                              const DataColumn(label: Text.localized('Status')),
                              const DataColumn(
                                label: Text.localized('Subscription'),
                              ),
                              const DataColumn(label: Text.localized('Joined')),
                              const DataColumn(label: Text.localized('')),
                            ],
                            rows: [
                              for (final account in filtered)
                                DataRow(
                                  cells: [
                                    DataCell(_UserIdentity(account: account)),
                                    DataCell(Text.localized(account.roleLabel)),
                                    DataCell(
                                      _pendingLifecycleActions.containsKey(
                                            account.uid,
                                          )
                                          ? StatusBadge(
                                              label: context.tr(
                                                'Awaiting confirmation',
                                              ),
                                              tone: BadgeTone.warning,
                                            )
                                          : _AccountStatusBadge(account.status),
                                    ),
                                    DataCell(
                                      _SubscriptionCell(account: account),
                                    ),
                                    DataCell(
                                      Text.localized(account.joinedLabel),
                                    ),
                                    DataCell(
                                      _AccountMenu(
                                        account: account,
                                        source: source,
                                        canManage: canManage(account),
                                        isSuperAdmin: isSuperAdmin,
                                        awaitingConfirmation:
                                            _pendingLifecycleActions
                                                .containsKey(account.uid),
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
                  child: Text.localized(
                    'Streaming from the server • admin actions are audited '
                    'server-side and need a connection',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 20),
        if (source == AdminDirectorySource.live)
          _ServerAuditPanel(events: ref.watch(adminAuditEventsProvider)),
      ],
    );
  }

  Future<void> _exportUsers(List<PlatformAccount> accounts) async {
    final rows = <String>[
      'id,name,email,role,status,subscription_tier,subscription_status,joined',
      for (final account in accounts)
        [
          account.uid,
          account.displayName,
          account.email,
          account.roleLabel,
          account.status.label,
          account.subscriptionTier ?? '',
          account.subscriptionStatus == PlatformSubscriptionStatus.none
              ? ''
              : account.subscriptionStatus.label,
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

  Future<void> _explainProvisioning() {
    return showNyumbaInfoDialog(
      context,
      title: 'How accounts are created',
      message:
          'People create their own accounts by signing in to Nyumba: '
          'landlords self-register and then apply for approval, tenants are '
          'invited by their landlord from the Tenants screen, and prospects '
          'sign in while browsing. Administrator privileges are granted '
          'outside the app with the audited ops script '
          '(firebase/functions/scripts/grant-admin.mjs), so no one can mint '
          'an admin from a stolen session.',
      icon: Icons.info_outline_rounded,
    );
  }

  void _handleAction(String action, PlatformAccount account) {
    switch (action) {
      case 'view':
        _showAccount(account);
      case 'approve':
        _runAccountAction(
          account,
          title: 'Approve this landlord?',
          body:
              '${account.displayName} will be able to open their workspace '
              'once their subscription is active.',
          confirmLabel: 'Approve landlord',
          reasonCodes: approveReasonCodes,
          run: (commands, reason) =>
              commands.approveLandlord(account: account, reasonCode: reason),
          successMessage:
              'Landlord approval for ${account.displayName} applied.',
        );
      case 'suspend':
        _runAccountAction(
          account,
          title: 'Suspend this landlord?',
          body:
              '${account.displayName} will lose access and their public '
              'listings will be taken down. Their records are retained.',
          confirmLabel: 'Suspend landlord',
          reasonCodes: suspendReasonCodes,
          run: (commands, reason) =>
              commands.suspendLandlord(account: account, reasonCode: reason),
          successMessage: 'Suspension of ${account.displayName} applied.',
        );
      case 'reinstate':
        _runAccountAction(
          account,
          title: 'Restore this landlord?',
          body: '${account.displayName} will be able to sign in again.',
          confirmLabel: 'Restore access',
          reasonCodes: reinstateReasonCodes,
          run: (commands, reason) =>
              commands.reinstateLandlord(account: account, reasonCode: reason),
          successMessage: 'Access restored for ${account.displayName}.',
        );
      case 'change-role':
        _changeUserRole(account);
      case 'archive':
        _runAccountAction(
          account,
          title: 'Archive this user?',
          body:
              '${account.displayName} will no longer be able to sign in, and '
              'any public listings they own will be taken down. Their records '
              'are kept in the archive until you restore or permanently '
              'delete the account.',
          confirmLabel: 'Archive user',
          reasonCodes: archiveUserReasonCodes,
          run: (commands, reason) =>
              commands.archiveUser(account: account, reasonCode: reason),
          successMessage:
              'Archive request accepted for ${account.displayName}. Sign-in '
              'disablement and listing cleanup are awaiting confirmation.',
          pendingTarget: PendingLifecycleTarget.archived,
        );
      case 'restore-archived':
        _runAccountAction(
          account,
          title: 'Restore this user from the archive?',
          body:
              '${account.displayName} will be able to sign in again with '
              'their previous role and records.',
          confirmLabel: 'Restore user',
          reasonCodes: restoreUserReasonCodes,
          run: (commands, reason) =>
              commands.restoreUser(account: account, reasonCode: reason),
          successMessage:
              'Restore request accepted for ${account.displayName}. Sign-in '
              'access is awaiting confirmation.',
          pendingTarget: PendingLifecycleTarget.active,
        );
      case 'delete-permanently':
        _runAccountAction(
          account,
          title: 'Permanently delete this user?',
          body:
              'This removes ${account.displayName} from the archive and '
              'deletes their sign-in account. This cannot be undone.',
          confirmLabel: 'Delete permanently',
          reasonCodes: deleteUserReasonCodes,
          destructive: true,
          run: (commands, reason) =>
              commands.deleteUser(account: account, reasonCode: reason),
          successMessage:
              'Deletion request accepted for ${account.displayName}. The '
              'sign-in account deletion is awaiting confirmation.',
          pendingTarget: PendingLifecycleTarget.deleted,
        );
    }
  }

  /// Picks a new ordinary role and the audit reason, then runs the
  /// super-admin-only `user.changeRole` command. Administrator privileges are
  /// never assignable here — they are Auth claims granted by the ops script.
  Future<void> _changeUserRole(PlatformAccount account) async {
    final currentRole = account.roleLabel.trim().toLowerCase();
    final options = assignableServerRoles
        .where((candidate) => candidate != currentRole)
        .toList(growable: false);
    var role = options.first;
    var reason = changeRoleReasonCodes.first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text.localized('Change this user\'s role?'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.localized(
                  '${account.displayName} is currently a '
                  '${account.roleLabel}. A landlord promotion still needs '
                  'approval and an active subscription before the workspace '
                  'opens.',
                ),
                const SizedBox(height: 16),
                Text.localized(
                  'New role',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                RadioGroup<String>(
                  groupValue: role,
                  onChanged: (value) =>
                      setDialogState(() => role = value ?? role),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final candidate in options)
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text.localized(_serverRoleLabel(candidate)),
                          value: candidate,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text.localized(
                  'Reason recorded in the audit log',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                RadioGroup<String>(
                  groupValue: reason,
                  onChanged: (value) =>
                      setDialogState(() => reason = value ?? reason),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final code in changeRoleReasonCodes)
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text.localized(_reasonLabel(code)),
                          value: code,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text.localized('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text.localized('Change role'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(adminAccountCommandsProvider)
          .changeUserRole(account: account, role: role, reasonCode: reason);
      if (mounted) {
        showAdminMessage(
          context,
          '${account.displayName} is now a ${_serverRoleLabel(role)}.',
        );
      }
    } on Object catch (error) {
      if (mounted) {
        showAdminMessage(context, 'The server rejected the action: $error');
      }
    }
  }

  static String _serverRoleLabel(String role) => switch (role) {
    'landlord' => 'Landlord',
    'tenant' => 'Tenant',
    _ => 'Client',
  };

  /// Runs one audited account action: confirm, pick the reason code the
  /// server will record, then send the command and report the real outcome.
  Future<void> _runAccountAction(
    PlatformAccount account, {
    required String title,
    required String body,
    required String confirmLabel,
    required List<String> reasonCodes,
    required Future<void> Function(AdminAccountCommands, String reason) run,
    required String successMessage,
    bool destructive = false,
    PendingLifecycleTarget? pendingTarget,
  }) async {
    var reason = reasonCodes.first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text.localized(title),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.localized(body),
                const SizedBox(height: 16),
                Text.localized(
                  'Reason recorded in the audit log',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                RadioGroup<String>(
                  groupValue: reason,
                  onChanged: (value) =>
                      setDialogState(() => reason = value ?? reason),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final code in reasonCodes)
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text.localized(_reasonLabel(code)),
                          value: code,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text.localized('Cancel'),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    )
                  : null,
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text.localized(confirmLabel),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    if (pendingTarget != null) {
      setState(() {
        _pendingLifecycleActions[account.uid] = PendingLifecycleAction(
          target: pendingTarget,
          expectedVersion: (account.userVersion ?? 0) + 1,
        );
      });
    }
    try {
      await run(ref.read(adminAccountCommandsProvider), reason);
      if (mounted) showAdminMessage(context, successMessage);
    } on Object catch (error) {
      if (mounted) {
        if (pendingTarget != null) {
          setState(() => _pendingLifecycleActions.remove(account.uid));
        }
        showAdminMessage(context, 'The server rejected the action: $error');
      }
    }
  }

  void _reconcilePendingLifecycleActions(
    AsyncValue<List<PlatformAccount>> accountsValue,
  ) {
    if (_pendingLifecycleActions.isEmpty) return;
    final resolved = resolvedPendingLifecycleActionIds(
      accountsValue: accountsValue,
      pendingActions: _pendingLifecycleActions,
    );
    if (resolved.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        for (final uid in resolved) {
          _pendingLifecycleActions.remove(uid);
        }
      });
    });
  }

  static String _reasonLabel(String code) => switch (code) {
    'IDENTITY_VERIFIED' => 'Identity verified',
    'COMPLIANCE_APPROVED' => 'Compliance approved',
    'POLICY_VIOLATION' => 'Policy violation',
    'FRAUD_RISK' => 'Fraud risk',
    'APPEAL_APPROVED' => 'Appeal approved',
    'ADMIN_CORRECTION' => 'Administrative correction',
    'USER_REQUESTED' => 'Requested by the user',
    _ => code,
  };

  Future<void> _showAccount(PlatformAccount account) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text.localized('Account details'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AdminAvatar(name: account.displayName, radius: 27),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.localized(
                          account.displayName,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text.localized(
                          account.email.isEmpty ? '—' : account.email,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  _AccountStatusBadge(account.status),
                ],
              ),
              const SizedBox(height: 22),
              _AccountFact(label: 'User ID', value: account.uid),
              _AccountFact(label: 'Role', value: account.roleLabel),
              if (account.businessName != null)
                _AccountFact(label: 'Business', value: account.businessName!),
              if (account.location != null)
                _AccountFact(label: 'Location', value: account.location!),
              if (account.subscriptionStatus != PlatformSubscriptionStatus.none)
                _AccountFact(
                  label: 'Subscription',
                  value:
                      '${account.subscriptionTier ?? 'No tier'} · '
                      '${account.subscriptionStatus.label}',
                ),
              _AccountFact(label: 'Joined', value: account.joinedLabel),
              if (account.lastActiveLabel != null)
                _AccountFact(
                  label: 'Last active',
                  value: account.lastActiveLabel!,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text.localized('Close'),
          ),
        ],
      ),
    );
  }
}

/// The server-owned audit trail — the authoritative history of admin actions,
/// written by the backend inside each command's transaction.
class _ServerAuditPanel extends StatelessWidget {
  const _ServerAuditPanel({required this.events});

  final AsyncValue<List<AdminAuditEvent>> events;

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      title: 'Recent platform activity',
      subtitle: 'Server-owned audit log — append-only, admin-read-only',
      child: switch (events) {
        AsyncValue(hasValue: true, :final value) when value!.isEmpty =>
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text.localized('No audited commands recorded yet.'),
          ),
        AsyncValue(hasValue: true, :final value) => Column(
          children: [
            for (var index = 0; index < value!.length && index < 8; index++)
              _AuditEventRow(
                event: value[index],
                showDivider: index < value.length - 1 && index < 7,
              ),
          ],
        ),
        AsyncValue(:final error?) => Padding(
          padding: const EdgeInsets.all(12),
          child: NyumbaStatusMessage.fromError(
            error,
            localizations: appLocalizationsOf(context),
            subject: appLocalizationsOf(context).statusSubjectAuditLog,
          ),
        ),
        _ => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      },
    );
  }
}

class _AuditEventRow extends StatelessWidget {
  const _AuditEventRow({required this.event, required this.showDivider});

  final AdminAuditEvent event;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final rejected = event.outcome == 'rejected';
    return Column(
      children: [
        Row(
          children: [
            Icon(
              rejected ? Icons.block_outlined : Icons.verified_outlined,
              size: 20,
              color: rejected ? context.nyumba.danger : context.nyumba.sageDark,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.localized(
                    event.reasonCode == null
                        ? event.action
                        : '${event.action} · ${event.reasonCode}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text.localized(
                    'by ${event.actorIsAdmin ? 'admin ' : ''}'
                    '${_shortUid(event.actorUid)}'
                    '${event.aggregateId == null ? '' : ' · on ${_shortUid(event.aggregateId!)}'}'
                    ' · ${DateFormat('d MMM, HH:mm').format(event.at.toLocal())}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            StatusBadge(
              label: event.outcome,
              tone: rejected ? BadgeTone.danger : BadgeTone.success,
            ),
          ],
        ),
        if (showDivider) const Divider(height: 24),
      ],
    );
  }

  static String _shortUid(String uid) =>
      uid.length <= 10 ? uid : '${uid.substring(0, 8)}…';
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
          value: values.contains(value) ? value : values.first,
          isDense: true,
          isExpanded: true,
          items: [
            for (final item in values)
              DropdownMenuItem(value: item, child: Text.localized(item)),
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

  final PlatformAccount account;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AdminAvatar(name: account.displayName),
        const SizedBox(width: 11),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.localized(
              account.displayName,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Text.localized(
              account.email.isEmpty ? '—' : account.email,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }
}

class _SubscriptionCell extends StatelessWidget {
  const _SubscriptionCell({required this.account});

  final PlatformAccount account;

  @override
  Widget build(BuildContext context) {
    if (account.subscriptionStatus == PlatformSubscriptionStatus.none) {
      return const Text.localized('—');
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.localized(
          account.subscriptionTier ?? 'No tier',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        Text.localized(
          account.subscriptionStatus.label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.account,
    required this.source,
    required this.canManage,
    required this.isSuperAdmin,
    required this.awaitingConfirmation,
    required this.onAction,
  });

  final PlatformAccount account;
  final AdminDirectorySource source;
  final bool canManage;
  final bool isSuperAdmin;
  final bool awaitingConfirmation;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminAvatar(name: account.displayName, radius: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.localized(
                  account.displayName,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text.localized(
                  account.email.isEmpty ? '—' : account.email,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 7,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusBadge(label: account.roleLabel, tone: BadgeTone.info),
                    if (awaitingConfirmation)
                      StatusBadge(
                        label: context.tr('Awaiting confirmation'),
                        tone: BadgeTone.warning,
                      )
                    else
                      _AccountStatusBadge(account.status),
                    if (account.subscriptionStatus !=
                        PlatformSubscriptionStatus.none)
                      StatusBadge(
                        label:
                            '${account.subscriptionTier ?? 'No tier'} · '
                            '${account.subscriptionStatus.label}',
                        tone:
                            account.subscriptionStatus ==
                                PlatformSubscriptionStatus.active
                            ? BadgeTone.success
                            : BadgeTone.warning,
                      ),
                    if (account.location != null)
                      Text.localized(
                        account.location!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ],
            ),
          ),
          _AccountMenu(
            account: account,
            source: source,
            canManage: canManage,
            isSuperAdmin: isSuperAdmin,
            awaitingConfirmation: awaitingConfirmation,
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
    required this.source,
    required this.canManage,
    required this.isSuperAdmin,
    required this.awaitingConfirmation,
    required this.onAction,
  });

  final PlatformAccount account;
  final AdminDirectorySource source;
  final bool canManage;
  final bool isSuperAdmin;
  final bool awaitingConfirmation;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final live = source == AdminDirectorySource.live;
    final archived = account.status == PlatformAccountStatus.archived;
    return PopupMenuButton<String>(
      enabled: !awaitingConfirmation,
      tooltip: context.tr(
        awaitingConfirmation ? 'Awaiting confirmation' : 'Account actions',
      ),
      onSelected: onAction,
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'view',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.visibility_outlined),
            title: Text.localized('View account'),
          ),
        ),
        // Live actions exist only where the server has a command: the
        // landlord approval-state transitions for staff, and the super-admin
        // `user.*` lifecycle (archive / restore / permanent delete) for any
        // role. Tenants and prospects still have no plain suspend, so no
        // control pretends otherwise.
        if (live && canManage && account.isLandlord && !archived)
          switch (account.status) {
            PlatformAccountStatus.pendingApproval => const PopupMenuItem(
              value: 'approve',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.verified_user_outlined),
                title: Text.localized('Approve landlord'),
              ),
            ),
            PlatformAccountStatus.suspended => const PopupMenuItem(
              value: 'reinstate',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.lock_open_outlined),
                title: Text.localized('Restore access'),
              ),
            ),
            _ => const PopupMenuItem(
              value: 'suspend',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.person_off_outlined),
                title: Text.localized('Suspend access'),
              ),
            ),
          },
        if (live && canManage && isSuperAdmin && !archived) ...[
          const PopupMenuItem(
            value: 'change-role',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.manage_accounts_outlined),
              title: Text.localized('Change role'),
            ),
          ),
          const PopupMenuItem(
            value: 'archive',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.inventory_2_outlined),
              title: Text.localized('Archive user'),
            ),
          ),
        ],
        if (live && canManage && isSuperAdmin && archived) ...[
          const PopupMenuItem(
            value: 'restore-archived',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.unarchive_outlined),
              title: Text.localized('Restore from archive'),
            ),
          ),
          PopupMenuItem(
            value: 'delete-permanently',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.delete_forever_outlined,
                color: context.nyumba.danger,
              ),
              title: Text.localized(
                'Delete permanently',
                style: TextStyle(color: context.nyumba.danger),
              ),
            ),
          ),
        ],
      ],
      icon: const Icon(Icons.more_horiz_rounded),
    );
  }
}

class _AccountStatusBadge extends StatelessWidget {
  const _AccountStatusBadge(this.status);

  final PlatformAccountStatus status;

  @override
  Widget build(BuildContext context) {
    return StatusBadge(
      label: status.label,
      tone: switch (status) {
        PlatformAccountStatus.active => BadgeTone.success,
        PlatformAccountStatus.pendingApproval ||
        PlatformAccountStatus.invited => BadgeTone.warning,
        PlatformAccountStatus.suspended => BadgeTone.danger,
        PlatformAccountStatus.archived => BadgeTone.neutral,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text.localized(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: Text.localized(
              value,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}
