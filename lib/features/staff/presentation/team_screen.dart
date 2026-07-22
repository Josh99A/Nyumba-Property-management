import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/localization/app_localizations_adapter.dart';
import '../../../core/localization/command_failure_localizations.dart';
import '../../../core/offline/command_failure.dart';
import '../../../core/offline/remote_sync_gateway.dart';
import '../../../core/presentation/toast.dart';
import '../application/staff_providers.dart';
import '../domain/staff_permission.dart';
import '../domain/staff_repository.dart';
import 'staff_permission_localizations.dart';

/// The owner-only Team screen: invite staff, see who holds which seat, tailor
/// their permissions (Premium+), and revoke access. Every mutation goes through
/// the server-authoritative `staff.*` commands; this screen only reflects the
/// server-owned invite/membership documents and enforces nothing itself.
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(staffPlanProvider).asData?.value;
    final invitesAsync = ref.watch(staffInvitesProvider);
    final invites = invitesAsync.asData?.value ?? const <StaffInvite>[];
    final hasSeats = plan != null && plan.seatLimit > 0;
    final atCapacity = plan != null && invites.length >= plan.seatLimit;

    return Scaffold(
      backgroundColor: context.nyumba.softIvory,
      floatingActionButton: hasSeats && !atCapacity
          ? FloatingActionButton.extended(
              onPressed: () => _openInviteDialog(context, ref, plan),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text.localized('Invite teammate'),
            )
          : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 96),
          children: [
            Text.localized(
              'Team',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text.localized(
              'Invite people to help run your workspace and choose what each '
              'of them can do.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            _SeatSummary(plan: plan, used: invites.length),
            const SizedBox(height: 16),
            if (plan != null && plan.seatLimit == 0)
              const _UpsellCard()
            else if (invitesAsync.isLoading && invites.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (invites.isEmpty)
              const _EmptyTeam()
            else
              for (final invite in invites)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _StaffCard(
                    invite: invite,
                    canCustomize: plan?.customRoles ?? false,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openInviteDialog(
  BuildContext context,
  WidgetRef ref,
  StaffPlan plan,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _StaffPermissionsDialog(
      title: 'Invite a teammate',
      submitLabel: 'Send invite',
      canCustomize: plan.customRoles,
      collectContact: true,
      initialPermissions: standardStaffPermissions,
      onSubmit: (email, name, permissions) => ref.read(inviteStaffProvider)(
        email: email!,
        displayName: name,
        permissions: permissions,
      ),
    ),
  );
}

class _SeatSummary extends StatelessWidget {
  const _SeatSummary({required this.plan, required this.used});

  final StaffPlan? plan;
  final int used;

  @override
  Widget build(BuildContext context) {
    final label = plan == null
        ? 'Seat allowance unavailable'
        : plan!.seatLimit == 0
        ? 'No staff seats on your plan'
        : '$used of ${plan!.seatLimit} seat${plan!.seatLimit == 1 ? '' : 's'} used';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.nyumba.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.nyumba.outline),
      ),
      child: Row(
        children: [
          Icon(Icons.groups_rounded, color: context.nyumba.mutedInk),
          const SizedBox(width: 12),
          Expanded(
            child: Text.localized(
              label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpsellCard extends StatelessWidget {
  const _UpsellCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.nyumba.goldTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.nyumba.goldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.localized(
            'Add your team on a higher plan',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text.localized(
            'Your current plan is for a single account. Upgrade to Pro to add '
            'staff with standard access, or Premium to tailor exactly what each '
            'person can do.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => context.go('/subscription'),
            child: const Text.localized('See plans'),
          ),
        ],
      ),
    );
  }
}

class _EmptyTeam extends StatelessWidget {
  const _EmptyTeam();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Icon(
            Icons.group_add_outlined,
            size: 48,
            color: context.nyumba.mutedInk,
          ),
          const SizedBox(height: 12),
          Text.localized(
            'No one on your team yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text.localized(
            'Invite a teammate to get started.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _StaffCard extends ConsumerWidget {
  const _StaffCard({required this.invite, required this.canCustomize});

  final StaffInvite invite;
  final bool canCustomize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = invite.state == StaffInviteState.pending;
    final copy = appLocalizationsOf(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.nyumba.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.nyumba.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.localized(
                      invite.displayName ?? invite.email,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (invite.displayName != null)
                      Text.localized(
                        invite.email,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              _StatusChip(pending: pending),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final permission in StaffPermission.values)
                if (invite.permissions.contains(permission))
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      localizedStaffPermissionLabel(copy, permission),
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (canCustomize)
                TextButton.icon(
                  onPressed: () => _editPermissions(context, ref),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text.localized('Change access'),
                ),
              TextButton.icon(
                onPressed: () => _confirmRevoke(context, ref),
                icon: const Icon(Icons.person_remove_alt_1_outlined, size: 18),
                label: const Text.localized('Remove'),
                style: TextButton.styleFrom(
                  foregroundColor: context.nyumba.danger,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editPermissions(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _StaffPermissionsDialog(
        title: 'Change access',
        submitLabel: 'Save',
        canCustomize: true,
        collectContact: false,
        initialPermissions: invite.permissions,
        onSubmit: (_, _, permissions) =>
            ref.read(updateStaffPermissionsProvider)(invite, permissions),
      ),
    );
  }

  Future<void> _confirmRevoke(BuildContext context, WidgetRef ref) async {
    final copy = appLocalizationsOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text.localized('Remove from team?'),
        content: Text.localized(
          '${invite.displayName ?? invite.email} will lose access to your '
          'workspace. You can invite them again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text.localized('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text.localized('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(revokeStaffProvider)(invite);
      showNyumbaToast(
        'Removed from your team.',
        variant: NyumbaToastVariant.success,
      );
    } on RemoteSyncException catch (error) {
      showNyumbaToast(
        localizeCommandFailure(copy, describeCommandFailure(error)),
        variant: NyumbaToastVariant.error,
      );
    } on Object {
      showNyumbaToast(
        'Could not remove them just now. Try again.',
        variant: NyumbaToastVariant.error,
      );
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.pending});

  final bool pending;

  @override
  Widget build(BuildContext context) {
    final tint = pending ? context.nyumba.goldTint : context.nyumba.sageTint;
    final border = pending
        ? context.nyumba.goldBorder
        : context.nyumba.sageBorder;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Text.localized(
        pending ? 'Invited' : 'Active',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

/// Shared invite/edit dialog. Collects contact details only when inviting; the
/// permission checkboxes are locked to the standard preset unless the owner's
/// plan allows custom roles.
class _StaffPermissionsDialog extends ConsumerStatefulWidget {
  const _StaffPermissionsDialog({
    required this.title,
    required this.submitLabel,
    required this.canCustomize,
    required this.collectContact,
    required this.initialPermissions,
    required this.onSubmit,
  });

  final String title;
  final String submitLabel;
  final bool canCustomize;
  final bool collectContact;
  final Set<StaffPermission> initialPermissions;
  final Future<void> Function(
    String? email,
    String? name,
    Set<StaffPermission> permissions,
  )
  onSubmit;

  @override
  ConsumerState<_StaffPermissionsDialog> createState() =>
      _StaffPermissionsDialogState();
}

class _StaffPermissionsDialogState
    extends ConsumerState<_StaffPermissionsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  late Set<StaffPermission> _selected;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.canCustomize
        ? {...widget.initialPermissions}
        : {...standardStaffPermissions};
  }

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    return AlertDialog(
      title: Text.localized(widget.title),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.collectContact) ...[
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: context.tr('Email address'),
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty || !text.contains('@')) {
                        return context.tr('Enter a valid email address.');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: context.tr('Name (optional)'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Text.localized(
                  'What can they do?',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (!widget.canCustomize)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text.localized(
                      'Your plan grants every teammate standard access. Upgrade '
                      'to Premium to customize this per person.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 8),
                for (final permission in StaffPermission.values)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: _selected.contains(permission),
                    onChanged: widget.canCustomize
                        ? (checked) => setState(() {
                            if (checked == true) {
                              _selected.add(permission);
                            } else {
                              _selected.remove(permission);
                            }
                          })
                        : null,
                    title: Text(
                      localizedStaffPermissionLabel(copy, permission),
                    ),
                    subtitle: Text(
                      localizedStaffPermissionDescription(copy, permission),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text.localized('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text.localized(widget.submitLabel),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (widget.collectContact &&
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_selected.isEmpty) {
      showNyumbaToast(
        'Choose at least one thing this person can do.',
        variant: NyumbaToastVariant.error,
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(
        widget.collectContact ? _emailController.text.trim() : null,
        widget.collectContact ? _nameController.text.trim() : null,
        _selected,
      );
      if (!mounted) return;
      Navigator.pop(context);
      showNyumbaToast(
        widget.collectContact ? 'Invite sent.' : 'Access updated.',
        variant: NyumbaToastVariant.success,
      );
    } on RemoteSyncException catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showNyumbaToast(
        localizeCommandFailure(
          appLocalizationsOf(context),
          describeCommandFailure(error),
        ),
        variant: NyumbaToastVariant.error,
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showNyumbaToast(
        error is StateError
            ? error.message
            : 'Something went wrong. Try again.',
        variant: NyumbaToastVariant.error,
      );
    }
  }
}
