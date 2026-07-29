import 'package:flutter/material.dart' hide Text, Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nyumba_property_management/core/localization/localized_material.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/async_action_button.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import '../../tenant_portal/presentation/widgets/tenant_components.dart';
import '../application/support_providers.dart';
import '../domain/support_ticket.dart';
import 'support_composer_sheet.dart';
import 'support_faq.dart';
import 'support_visuals.dart';

/// Help & support: answers first, then the landlord's own conversations.
///
/// The order is the point. A list of past tickets above a compose button asks
/// someone to file before they have looked; a short answers list above it means
/// the common questions never become tickets at all.
class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key, this.openComposerOnLoad = false});

  /// Set by the deep link that contextual entry points use, so a landlord who
  /// tapped "Contact support" on a failure lands in the composer rather than on
  /// a page they have to act on again.
  final bool openComposerOnLoad;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(landlordSupportTicketsProvider);

    return _ComposerLauncher(
      enabled: openComposerOnLoad,
      child: TenantPage(
        title: 'Help & support',
        description:
            'Ask the Nyumba team about your account, billing, or anything in '
            'the app. We usually reply within one working day.',
        primaryAction: AsyncActionButton.filled(
          icon: const Icon(Icons.forum_outlined, size: 18),
          showBusyIndicator: false,
          onPressed: () async => showSupportComposer(context),
          child: const Text.localized('Message support'),
        ),
        children: [
          const _CommonQuestions(),
          const SizedBox(height: 20),
          NyumbaSectionHeader(
            title: 'Your conversations',
            subtitle: 'Everything you have asked us, and where it got to.',
          ),
          const SizedBox(height: 12),
          tickets.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            ),
            // The local mirror is the source of truth, so a read failure is a
            // real fault rather than "you have no conversations" — which would
            // read as their message having vanished.
            error: (error, _) => NyumbaSurface(
              child: Text.localized(
                'Your conversations could not be loaded. They are safe — try '
                'again in a moment.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            data: (items) => items.isEmpty
                ? const _NoConversations()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final ticket in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _TicketCard(ticket: ticket),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Opens the composer once, after the first frame, when the route asked for it.
class _ComposerLauncher extends StatefulWidget {
  const _ComposerLauncher({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<_ComposerLauncher> createState() => _ComposerLauncherState();
}

class _ComposerLauncherState extends State<_ComposerLauncher> {
  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final ticketId = await showSupportComposer(context);
      if (ticketId != null && mounted) context.go('/support/$ticketId');
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _CommonQuestions extends StatelessWidget {
  const _CommonQuestions();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NyumbaSurface(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 4),
            child: Text.localized(
              'Common questions',
              style: theme.textTheme.titleMedium,
            ),
          ),
          for (final answer in supportAnswers)
            ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              childrenPadding: const EdgeInsetsDirectional.fromSTEB(
                14,
                0,
                14,
                14,
              ),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              shape: const Border(),
              collapsedShape: const Border(),
              leading: Icon(
                supportCategoryIcon(answer.category),
                size: 20,
                color: context.nyumba.mutedInk,
              ),
              title: Text.localized(
                answer.question,
                style: theme.textTheme.bodyMedium,
              ),
              children: [
                Text.localized(answer.answer, style: theme.textTheme.bodySmall),
                const SizedBox(height: 10),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AsyncActionButton(
                    style: AsyncActionStyle.text,
                    showBusyIndicator: false,
                    // Carries the category across, so someone who read the
                    // nearest answer and still needs help does not have to
                    // classify their own problem a second time.
                    onPressed: () async =>
                        showSupportComposer(context, category: answer.category),
                    child: const Text.localized('This did not help'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _NoConversations extends StatelessWidget {
  const _NoConversations();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NyumbaSurface(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        children: [
          Icon(
            Icons.mark_email_read_outlined,
            size: 34,
            color: context.nyumba.mutedInk,
          ),
          const SizedBox(height: 12),
          Text.localized(
            'No conversations yet',
            style: theme.textTheme.titleSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text.localized(
            'When you message us it appears here, with our reply.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _TicketCard extends ConsumerWidget {
  const _TicketCard({required this.ticket});

  final SupportTicket ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final delivery = ref.watch(supportDeliveryProvider(ticket.id));
    final preview = ticket.latestMessage?.body ?? '';
    return NyumbaSurface(
      padding: const EdgeInsets.all(16),
      onTap: () => context.go('/support/${ticket.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The unread dot, and the only thing on this card that is about
              // urgency: a reply is waiting and nobody has opened it.
              if (ticket.awaitsLandlord)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8, top: 6),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: context.nyumba.terracottaDark,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              Expanded(
                flex: 3,
                child: Text(
                  ticket.subject,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: ticket.awaitsLandlord
                        ? FontWeight.w700
                        : FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // See the note in support_thread_view.dart: an unbounded badge
              // takes the whole row once the label wraps at large text scales.
              Flexible(
                flex: 2,
                child: StatusBadge(
                  label: landlordStatusLabel(ticket.status),
                  tone: supportStatusTone(ticket.status),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text.localized(
            '${supportCategoryShortLabel(ticket.category)} · '
            '${ticket.messages.length} message'
            '${ticket.messages.length == 1 ? '' : 's'} · '
            '${supportRelativeTime(ticket.lastMessageAt, DateTime.now().toUtc())}',
            style: theme.textTheme.labelSmall,
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
          // Surfaced on the card, not only inside the thread: a message that
          // never left the device is exactly the thing someone would otherwise
          // sit and wait on.
          if (delivery.hasFailure) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 15,
                  color: context.nyumba.danger,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text.localized(
                    'A message here has not been sent.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: context.nyumba.danger,
                    ),
                  ),
                ),
              ],
            ),
          ] else if (!delivery.isSettled) ...[
            const SizedBox(height: 8),
            Text.localized(
              'Sending…',
              style: theme.textTheme.labelSmall?.copyWith(
                color: context.nyumba.mutedInk,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
