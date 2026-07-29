import 'package:flutter/material.dart' hide Text, Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:nyumba_property_management/core/localization/localized_material.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/async_action_button.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import '../application/support_providers.dart';
import '../domain/support_ticket.dart';
import 'support_visuals.dart';

final DateFormat _messageStamp = DateFormat('d MMM HH:mm');

/// The conversation itself, shared by the landlord and the admin console.
///
/// One widget for both sides because it is genuinely one conversation: the same
/// messages, the same order, the same delivery truth. What differs is the
/// vocabulary and which status actions are offered, and both arrive as
/// parameters rather than as a second copy of this file.
class SupportThreadView extends ConsumerStatefulWidget {
  const SupportThreadView({
    required this.ticket,
    required this.asSupportAgent,
    super.key,
  });

  final SupportTicket ticket;

  /// Whether the reader answers on behalf of Nyumba. Controls the labels and
  /// the status actions — never who the message is attributed to, which the
  /// server derives from the ticket regardless of what this client believes.
  final bool asSupportAgent;

  @override
  ConsumerState<SupportThreadView> createState() => _SupportThreadViewState();
}

class _SupportThreadViewState extends ConsumerState<SupportThreadView> {
  final TextEditingController _reply = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _reply.text;
    if (body.trim().isEmpty) return;
    try {
      await ref
          .read(supportActionsProvider)
          .reply(ticketId: widget.ticket.id, body: body);
      // Cleared only after the write is durably enqueued. Clearing first would
      // lose the text on any rejection, which is the moment it matters most.
      if (mounted) {
        _reply.clear();
        setState(() => _error = null);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _move(SupportStatus status) async {
    try {
      await ref
          .read(supportActionsProvider)
          .updateStatus(ticketId: widget.ticket.id, status: status);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticket = widget.ticket;
    final delivery = ref.watch(supportDeliveryProvider(ticket.id));
    // Replies drain in order, so the trailing unconfirmed entries correspond to
    // the trailing messages. Anything before them the server has acknowledged.
    final firstUnconfirmed = ticket.messages.length - delivery.unconfirmed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(ticket: ticket, asSupportAgent: widget.asSupportAgent),
        const SizedBox(height: 14),
        for (final (index, message) in ticket.messages.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _MessageBubble(
              message: message,
              // "Mine" is the side that is not the other one. An agent reading
              // this sees support messages on the right; a landlord sees theirs.
              mine: widget.asSupportAgent
                  ? message.isFromSupport
                  : !message.isFromSupport,
              deliveryState: index < firstUnconfirmed
                  ? _Delivery.sent
                  : delivery.hasFailure
                  ? _Delivery.failed
                  : _Delivery.sending,
              failureReason: delivery.failureReason,
            ),
          ),
        const SizedBox(height: 6),
        if (_error != null) ...[
          Text.localized(
            _error!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.nyumba.danger,
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (ticket.status.acceptsReplies)
          _ReplyComposer(
            controller: _reply,
            hint: widget.asSupportAgent
                ? 'Reply to this landlord…'
                : 'Write a reply…',
            onSend: _send,
          )
        else
          _ClosedNotice(asSupportAgent: widget.asSupportAgent),
        const SizedBox(height: 10),
        _StatusActions(
          ticket: ticket,
          asSupportAgent: widget.asSupportAgent,
          onMove: _move,
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.ticket, required this.asSupportAgent});

  final SupportTicket ticket;
  final bool asSupportAgent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NyumbaSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Text(ticket.subject, style: theme.textTheme.titleMedium),
              ),
              const SizedBox(width: 10),
              // Flexible rather than intrinsic: at large text scales
              // "Nyumba is looking into this" is wider than a phone, and an
              // unbounded badge would take the row and push the subject off it.
              Flexible(
                flex: 2,
                child: StatusBadge(
                  label: asSupportAgent
                      ? adminStatusLabel(ticket.status)
                      : landlordStatusLabel(ticket.status),
                  tone: supportStatusTone(ticket.status),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text.localized(
            supportCategoryLabel(ticket.category),
            style: theme.textTheme.labelSmall,
          ),
          // The context an agent would otherwise have to ask for, captured when
          // the ticket was opened rather than joined from a tier they may since
          // have left. Withheld from the landlord's own view: it is our
          // shorthand about their account, not information they came here for.
          if (asSupportAgent) ...[
            const SizedBox(height: 8),
            Text(
              [
                ticket.landlordName ?? 'Unnamed landlord',
                if (ticket.planTier != null) 'plan ${ticket.planTier}',
                if (ticket.subscriptionStatus != null)
                  'subscription ${ticket.subscriptionStatus}',
                if (ticket.approvalStatus != null)
                  'account ${ticket.approvalStatus}',
                if (ticket.platform != null)
                  '${ticket.platform} ${ticket.appVersion ?? ''}'.trim(),
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            if (ticket.landlordEmail != null)
              SelectableText(
                ticket.landlordEmail!,
                style: theme.textTheme.bodySmall,
              ),
          ],
        ],
      ),
    );
  }
}

enum _Delivery { sent, sending, failed }

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.deliveryState,
    this.failureReason,
  });

  final SupportMessage message;
  final bool mine;
  final _Delivery deliveryState;
  final String? failureReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      mainAxisAlignment: mine
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!mine) ...[
          CircleAvatar(
            radius: 15,
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            child: Icon(
              message.isFromSupport
                  ? Icons.support_agent_rounded
                  : Icons.person_rounded,
              size: 17,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: mine ? context.nyumba.navyTint : context.nyumba.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: mine ? context.nyumba.navyBorder : context.nyumba.outline,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User-authored text: the plain Text constructor, never
                // Text.localized, so nobody's message is run through the
                // translation catalogue.
                Text(message.body, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 6),
                _DeliveryLine(
                  createdAt: message.createdAt,
                  mine: mine,
                  state: deliveryState,
                  failureReason: failureReason,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The timestamp, and — for your own messages — whether it actually left.
///
/// A checkmark that appears the instant a message is typed is a lie the moment
/// the network is down, which is precisely when someone is writing to support.
/// This reports the outbox, not the optimism.
class _DeliveryLine extends StatelessWidget {
  const _DeliveryLine({
    required this.createdAt,
    required this.mine,
    required this.state,
    this.failureReason,
  });

  final DateTime createdAt;
  final bool mine;
  final _Delivery state;
  final String? failureReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stamp = _messageStamp.format(createdAt.toLocal());
    if (!mine || state == _Delivery.sent) {
      return Text(
        stamp,
        style: theme.textTheme.labelSmall?.copyWith(
          color: context.nyumba.mutedInk,
        ),
      );
    }
    final failed = state == _Delivery.failed;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          failed ? Icons.error_outline_rounded : Icons.schedule_rounded,
          size: 13,
          color: failed ? context.nyumba.danger : context.nyumba.mutedInk,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text.localized(
            failed
                ? 'Not sent${failureReason == null ? '' : ' · $failureReason'}'
                : 'Sending…',
            style: theme.textTheme.labelSmall?.copyWith(
              color: failed ? context.nyumba.danger : context.nyumba.mutedInk,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReplyComposer extends StatelessWidget {
  const _ReplyComposer({
    required this.controller,
    required this.hint,
    required this.onSend,
  });

  final TextEditingController controller;
  final String hint;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 5,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: hint,
              isDense: true,
              counterText: '',
            ),
          ),
        ),
        const SizedBox(width: 10),
        AsyncActionButton.filled(
          onPressed: onSend,
          child: const Icon(Icons.send_rounded, size: 19),
        ),
      ],
    );
  }
}

class _ClosedNotice extends StatelessWidget {
  const _ClosedNotice({required this.asSupportAgent});

  final bool asSupportAgent;

  @override
  Widget build(BuildContext context) {
    return NyumbaSurface(
      padding: const EdgeInsets.all(14),
      backgroundColor: context.nyumba.neutralTint,
      child: Text.localized(
        asSupportAgent
            ? 'This conversation is closed. The landlord can start a new one.'
            : 'This conversation is closed. Start a new one and we will pick '
                  'it up from there.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

/// The status actions each side is entitled to.
///
/// A landlord gets exactly two, and both are theirs to make about their own
/// request: marking it sorted, and reopening a resolution that did not hold.
/// Everything else is the agent's. The server enforces the same split, so this
/// is about not offering a control that would be refused, not about security.
class _StatusActions extends StatelessWidget {
  const _StatusActions({
    required this.ticket,
    required this.asSupportAgent,
    required this.onMove,
  });

  final SupportTicket ticket;
  final bool asSupportAgent;
  final Future<void> Function(SupportStatus) onMove;

  @override
  Widget build(BuildContext context) {
    final actions = <(String, SupportStatus)>[
      if (asSupportAgent) ...[
        if (ticket.status == SupportStatus.open ||
            ticket.status == SupportStatus.awaitingLandlord ||
            ticket.status == SupportStatus.resolved)
          ('Mark in progress', SupportStatus.inProgress),
        if (ticket.status == SupportStatus.inProgress ||
            ticket.status == SupportStatus.awaitingLandlord)
          ('Mark resolved', SupportStatus.resolved),
        if (!ticket.status.isTerminal || ticket.status == SupportStatus.resolved)
          ('Close', SupportStatus.closed),
      ] else ...[
        if (!ticket.status.isTerminal)
          ('This is sorted', SupportStatus.closed),
        if (ticket.reopenableAt(DateTime.now().toUtc()))
          ('Reopen', SupportStatus.inProgress),
      ],
    ];
    if (actions.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final (label, status) in actions)
          AsyncActionButton(
            style: AsyncActionStyle.outlined,
            onPressed: () => onMove(status),
            child: Text.localized(label),
          ),
      ],
    );
  }
}
