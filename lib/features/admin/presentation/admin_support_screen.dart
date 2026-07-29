import 'package:flutter/material.dart' hide Text, Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nyumba_property_management/core/localization/localized_material.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/responsive.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import '../../support/application/support_providers.dart';
import '../../support/domain/support_ticket.dart';
import '../../support/presentation/support_thread_view.dart';
import '../../support/presentation/support_visuals.dart';
import 'widgets/admin_components.dart';

/// Which slice of the desk is on screen.
enum _Queue { needsReply, open, resolved, all }

/// Everything unanswered, oldest wait first.
///
/// Reads the canonical `supportTickets` collection through the administrative
/// pull, the same way the feedback screen reads `platformFeedback` — but unlike
/// that screen this one replies, because a support ticket is a conversation
/// somebody is waiting on rather than telemetry.
///
/// The filter and the selection are widget state, not providers: they describe
/// what this agent is looking at right now, and outliving the screen would mean
/// coming back later to someone else's scroll position.
class AdminSupportScreen extends ConsumerStatefulWidget {
  const AdminSupportScreen({super.key, this.initialTicketId});

  /// Set by the deep link in the support alert email, so an agent lands on the
  /// ticket they were told about rather than on the top of the queue.
  final String? initialTicketId;

  @override
  ConsumerState<AdminSupportScreen> createState() => _AdminSupportScreenState();
}

class _AdminSupportScreenState extends ConsumerState<AdminSupportScreen> {
  _Queue _filter = _Queue.needsReply;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialTicketId;
    // A ticket arrived at by deep link is rarely in the default slice — an
    // agent following an alert about a ticket they already answered would land
    // on an empty queue and think the link was broken.
    if (widget.initialTicketId != null) _filter = _Queue.all;
  }

  @override
  Widget build(BuildContext context) {
    final tickets = ref.watch(adminSupportTicketsProvider);
    final filter = _filter;
    final selectedId = _selectedId;

    return AdminPage(
      title: 'Support',
      description:
          'Conversations with landlords. Replying moves the ticket along, so '
          'the queue stays right without anyone setting a status.',
      children: [
        tickets.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => NyumbaSurface(
            child: Text.localized(
              'The support queue could not be loaded.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          data: (items) {
            final filtered = _apply(filter, items);
            final selected = _select(items, filtered, selectedId);
            final queue = _QueueList(
              tickets: filtered,
              selectedId: selected?.id,
              onSelect: (id) => setState(() => _selectedId = id),
            );
            final thread = selected == null
                ? const _NothingSelected()
                : SupportThreadView(
                    key: ValueKey<String>(selected.id),
                    ticket: selected,
                    asSupportAgent: true,
                  );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Filters(
                  counts: _counts(items),
                  selected: filter,
                  onSelect: (queue) => setState(() => _filter = queue),
                ),
                const SizedBox(height: 16),
                // Compact shows one pane at a time: the thread once something
                // is picked, the queue otherwise. A 360dp-wide two-pane layout
                // is two unusable panes.
                if (context.isCompact)
                  selected == null
                      ? queue
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: TextButton.icon(
                                onPressed: () =>
                                    setState(() => _selectedId = null),
                                icon: const Icon(Icons.arrow_back_rounded),
                                label: const Text.localized('Back to queue'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            thread,
                          ],
                        )
                else
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 360, child: queue),
                        const SizedBox(width: 16),
                        Expanded(child: thread),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// Keeps the selection valid across filter changes: a ticket that just left
  /// the visible slice is still the one being read, so it stays selected rather
  /// than snapping the agent to a different conversation mid-reply.
  SupportTicket? _select(
    List<SupportTicket> all,
    List<SupportTicket> filtered,
    String? selectedId,
  ) {
    if (selectedId != null) {
      for (final ticket in all) {
        if (ticket.id == selectedId) return ticket;
      }
    }
    return filtered.isEmpty ? null : filtered.first;
  }

  static Map<_Queue, int> _counts(List<SupportTicket> items) => <_Queue, int>{
    for (final queue in _Queue.values) queue: _apply(queue, items).length,
  };

  /// Sorted by how long each side has been waiting, not by when the ticket
  /// arrived. A queue ordered newest-first is how the oldest ticket never gets
  /// answered.
  static List<SupportTicket> _apply(_Queue queue, List<SupportTicket> items) {
    final matched = items
        .where(
          (ticket) => switch (queue) {
            _Queue.needsReply => ticket.awaitsSupport,
            _Queue.open => !ticket.status.isTerminal,
            _Queue.resolved => ticket.status.isTerminal,
            _Queue.all => true,
          },
        )
        .toList();
    matched.sort((left, right) {
      // Never-answered first, and among those the longest wait. A ticket with
      // no first response is a promise nobody has kept yet.
      final leftUnanswered = left.firstResponseAt == null && left.awaitsSupport;
      final rightUnanswered =
          right.firstResponseAt == null && right.awaitsSupport;
      if (leftUnanswered != rightUnanswered) return leftUnanswered ? -1 : 1;
      if (leftUnanswered) return left.createdAt.compareTo(right.createdAt);
      return right.lastMessageAt.compareTo(left.lastMessageAt);
    });
    return matched;
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.counts,
    required this.selected,
    required this.onSelect,
  });

  final Map<_Queue, int> counts;
  final _Queue selected;
  final ValueChanged<_Queue> onSelect;

  static String _label(_Queue queue) => switch (queue) {
    _Queue.needsReply => 'Needs reply',
    _Queue.open => 'Open',
    _Queue.resolved => 'Resolved',
    _Queue.all => 'All',
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final queue in _Queue.values)
          ChoiceChip(
            label: Text.localized('${_label(queue)} ${counts[queue] ?? 0}'),
            selected: selected == queue,
            onSelected: (_) => onSelect(queue),
          ),
      ],
    );
  }
}

class _QueueList extends StatelessWidget {
  const _QueueList({
    required this.tickets,
    required this.selectedId,
    required this.onSelect,
  });

  final List<SupportTicket> tickets;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (tickets.isEmpty) {
      return const AdminEmptyState(
        icon: Icons.mark_email_read_outlined,
        title: 'Nothing waiting',
        message: 'No conversations match this filter.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final ticket in tickets)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _QueueRow(
              ticket: ticket,
              selected: ticket.id == selectedId,
              onTap: () => onSelect(ticket.id),
            ),
          ),
      ],
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.ticket,
    required this.selected,
    required this.onTap,
  });

  final SupportTicket ticket;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now().toUtc();
    return NyumbaSurface(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      borderColor: selected ? context.nyumba.navyBorder : null,
      backgroundColor: selected ? context.nyumba.navyTint : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  ticket.landlordName ?? 'Unnamed landlord',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: 8),
              // See the note in support_thread_view.dart: "Awaiting landlord"
              // is wider than this 360dp column once text is scaled up.
              Flexible(
                flex: 2,
                child: StatusBadge(
                  label: adminStatusLabel(ticket.status),
                  tone: supportStatusTone(ticket.status),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            ticket.subject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text.localized(
                  // Plan and priority are read off the ticket rather than
                  // joined: that is the whole reason they are denormalized at
                  // open time, and a week later the join would read a tier the
                  // landlord has since left.
                  [
                    supportCategoryShortLabel(ticket.category),
                    supportRelativeTime(ticket.lastMessageAt, now),
                    if (ticket.planTier != null) ticket.planTier!,
                    if (ticket.priority == 'high') 'high',
                  ].join(' · '),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: ticket.priority == 'high'
                        ? context.nyumba.terracottaDark
                        : context.nyumba.mutedInk,
                  ),
                ),
              ),
              if (ticket.firstResponseAt == null && ticket.awaitsSupport)
                Text.localized(
                  'Never answered',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: context.nyumba.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NothingSelected extends StatelessWidget {
  const _NothingSelected();

  @override
  Widget build(BuildContext context) => const AdminEmptyState(
    icon: Icons.support_agent_outlined,
    title: 'Pick a conversation',
    message: 'Choose a ticket from the queue to read and reply to it.',
  );
}
