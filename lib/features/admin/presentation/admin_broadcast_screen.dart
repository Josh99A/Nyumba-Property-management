import 'package:flutter/material.dart' hide Text, Tooltip;
import 'package:intl/intl.dart';

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/user_session.dart';
import '../../subscriptions/application/subscription_providers.dart';
import '../application/admin_directory_providers.dart';
import '../domain/platform_account.dart';
import 'widgets/admin_components.dart';

final _broadcastTime = DateFormat('d MMM yyyy, HH:mm');

String _audienceLabel(String audience, {String? audienceId}) =>
    switch (audience) {
      'all_users' => 'Everyone',
      'landlords' => 'All landlords',
      'tenants' => 'All tenants',
      'clients' => 'All prospective clients',
      'tier' => 'Plan: ${audienceId ?? 'unknown'}',
      'user' => 'One account',
      _ => audience,
    };

/// Labels for the audience dropdown, where no target is chosen yet — the
/// scoped audiences describe the selector instead of a concrete target.
String _audiencePickerLabel(String audience) => switch (audience) {
  'tier' => 'One subscription plan',
  _ => _audienceLabel(audience),
};

/// Platform announcements: super admins broadcast an incident, maintenance
/// window, or commercial notice to everyone, a target group (role or
/// subscription tier), or a single account. Delivery is server-owned — the
/// audited `platform.broadcast` command records the announcement and a
/// durable job fans it out to notification inboxes, push, and email.
class AdminBroadcastScreen extends ConsumerStatefulWidget {
  const AdminBroadcastScreen({super.key});

  @override
  ConsumerState<AdminBroadcastScreen> createState() =>
      _AdminBroadcastScreenState();
}

class _AdminBroadcastScreenState extends ConsumerState<AdminBroadcastScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _audience = 'all_users';
  String? _tier;
  String? _targetUid;
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  int? _estimatedRecipients(List<PlatformAccount> accounts) {
    final live = accounts
        .where((a) => a.status != PlatformAccountStatus.archived)
        .toList(growable: false);
    return switch (_audience) {
      'all_users' => live.length,
      'landlords' =>
        live.where((a) => a.roleLabel.toLowerCase() == 'landlord').length,
      'tenants' =>
        live.where((a) => a.roleLabel.toLowerCase() == 'tenant').length,
      'clients' =>
        live.where((a) => a.roleLabel.toLowerCase() == 'client').length,
      'tier' => live.where((a) => a.subscriptionTier == _tier).length,
      'user' => _targetUid == null ? null : 1,
      _ => null,
    };
  }

  Future<void> _send() async {
    final audienceId = switch (_audience) {
      'tier' => _tier,
      'user' => _targetUid,
      _ => null,
    };
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      showAdminMessage(context, 'A broadcast needs a title and a message.');
      return;
    }
    if ((_audience == 'tier' || _audience == 'user') && audienceId == null) {
      showAdminMessage(context, 'Choose who this broadcast targets.');
      return;
    }
    final accounts =
        ref.read(platformAccountsProvider).value ?? const <PlatformAccount>[];
    final estimate = _estimatedRecipients(accounts);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text.localized('Send this broadcast?'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.localized(
                'Audience: ${_audienceLabel(_audience, audienceId: audienceId)}'
                '${estimate == null ? '' : ' (about $estimate accounts)'}.',
              ),
              const SizedBox(height: 8),
              Text.localized(
                'Every recipient gets an in-app notification, a push where a '
                'device is registered, and an email copy. This cannot be '
                'recalled once sent.',
                style: Theme.of(dialogContext).textTheme.bodySmall,
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
            child: const Text.localized('Send broadcast'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _sending = true);
    try {
      await ref.read(sendPlatformBroadcastProvider)(
        title: _title.text,
        body: _body.text,
        audience: _audience,
        audienceId: audienceId,
      );
      if (mounted) {
        _title.clear();
        _body.clear();
        showAdminMessage(
          context,
          'Broadcast accepted — delivery is running in the background.',
        );
      }
    } on Object catch (error) {
      if (mounted) {
        showAdminMessage(context, 'The server rejected the broadcast: $error');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(adminDirectorySourceProvider);
    if (source == AdminDirectorySource.unavailable) {
      return const AdminPage(
        title: 'Announcements',
        description: 'Broadcast platform notices to users.',
        children: [
          NyumbaSurface(
            child: AdminEmptyState(
              title: 'Broadcasts are unavailable',
              message:
                  'Sending announcements needs a configured Firebase project '
                  'and an administrator session.',
              icon: Icons.cloud_off_outlined,
            ),
          ),
        ],
      );
    }
    final isSuperAdmin =
        ref.watch(sessionControllerProvider)?.role == AppRole.superAdmin;
    return AdminPage(
      title: 'Announcements',
      description:
          'Platform-wide notices for incidents, maintenance, and commercial '
          'updates. Delivery is audited and runs server-side.',
      children: [
        if (isSuperAdmin)
          _buildCompose(context)
        else
          const NyumbaSurface(
            child: AdminEmptyState(
              title: 'Super administrators only',
              message:
                  'Sending a platform broadcast is restricted to super '
                  'administrators. The history below stays visible to all '
                  'platform staff.',
              icon: Icons.lock_outline_rounded,
            ),
          ),
        const SizedBox(height: 20),
        _BroadcastHistoryPanel(
          broadcasts: ref.watch(platformBroadcastsProvider),
        ),
      ],
    );
  }

  Widget _buildCompose(BuildContext context) {
    final catalog = ref
        .watch(publicPlanCatalogProvider)
        .maybeWhen(
          data: (plans) => plans,
          orElse: () => const <String, PublicPlanFacts>{},
        );
    final accounts =
        ref.watch(platformAccountsProvider).value ?? const <PlatformAccount>[];
    final selectableAccounts = accounts
        .where((a) => a.status != PlatformAccountStatus.archived)
        .toList(growable: false);
    return AdminPanel(
      title: 'New broadcast',
      subtitle:
          'Sent through the audited platform.broadcast command; recipients '
          'get an inbox notification, push, and email copy',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _title,
            maxLength: 200,
            decoration: InputDecoration(
              labelText: context.tr('Title'),
              hintText: context.tr('e.g. Scheduled maintenance on Saturday'),
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            minLines: 4,
            maxLines: 10,
            maxLength: 5000,
            decoration: InputDecoration(
              labelText: context.tr('Message'),
              hintText: context.tr(
                'What happened, who is affected, and what to expect next.',
              ),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final audiencePicker = DropdownButtonFormField<String>(
                initialValue: _audience,
                decoration: InputDecoration(
                  labelText: context.tr('Audience'),
                ),
                items: [
                  for (final audience in broadcastAudiences)
                    DropdownMenuItem(
                      value: audience,
                      child: Text.localized(_audiencePickerLabel(audience)),
                    ),
                ],
                onChanged: _sending
                    ? null
                    : (value) => setState(() {
                        _audience = value ?? 'all_users';
                      }),
              );
              final Widget? scopePicker = switch (_audience) {
                'tier' => DropdownButtonFormField<String>(
                  initialValue: _tier,
                  decoration: InputDecoration(
                    labelText: context.tr('Subscription plan'),
                  ),
                  items: [
                    for (final plan in catalog.values)
                      DropdownMenuItem(
                        value: plan.tier,
                        child: Text.localized(plan.displayName),
                      ),
                  ],
                  onChanged: _sending
                      ? null
                      : (value) => setState(() => _tier = value),
                ),
                'user' => DropdownButtonFormField<String>(
                  initialValue: _targetUid,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: context.tr('Account'),
                  ),
                  items: [
                    for (final account in selectableAccounts)
                      DropdownMenuItem(
                        value: account.uid,
                        child: Text(
                          account.email.isEmpty
                              ? account.displayName
                              : '${account.displayName} · ${account.email}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _sending
                      ? null
                      : (value) => setState(() => _targetUid = value),
                ),
                _ => null,
              };
              if (scopePicker == null) return audiencePicker;
              if (constraints.maxWidth < 560) {
                return Column(
                  children: [
                    audiencePicker,
                    const SizedBox(height: 12),
                    scopePicker,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: audiencePicker),
                  const SizedBox(width: 12),
                  Expanded(child: scopePicker),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.campaign_outlined, size: 19),
              label: const Text.localized('Send broadcast'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Recent announcements from the server-owned `platformBroadcasts`
/// collection, with their fanout state and recipient counts.
class _BroadcastHistoryPanel extends StatelessWidget {
  const _BroadcastHistoryPanel({required this.broadcasts});

  final AsyncValue<List<PlatformBroadcast>> broadcasts;

  @override
  Widget build(BuildContext context) {
    final items = broadcasts.value ?? const <PlatformBroadcast>[];
    return AdminPanel(
      title: 'Broadcast history',
      subtitle: 'Server-owned records; delivery counts fill in as fanout '
          'completes',
      child: broadcasts.isLoading && items.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          : items.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: Text.localized('No broadcasts have been sent yet.'),
            )
          : Column(
              children: [
                for (final (index, broadcast) in items.indexed) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.campaign_outlined,
                        size: 20,
                        color: context.nyumba.midnightNavy,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              broadcast.title,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            Text.localized(
                              '${_audienceLabel(broadcast.audience, audienceId: broadcast.audienceId)}'
                              '${broadcast.recipientCount == null ? '' : ' · ${broadcast.recipientCount} recipients'}'
                              '${broadcast.createdAt == null ? '' : ' · ${_broadcastTime.format(broadcast.createdAt!.toLocal())}'}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              broadcast.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: context.nyumba.mutedInk),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      StatusBadge(
                        label: broadcast.deliveryState == 'sent'
                            ? 'Sent'
                            : 'Sending',
                        tone: broadcast.deliveryState == 'sent'
                            ? BadgeTone.success
                            : BadgeTone.info,
                      ),
                    ],
                  ),
                  if (index < items.length - 1) const Divider(height: 26),
                ],
              ],
            ),
    );
  }
}
