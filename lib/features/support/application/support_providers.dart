import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../core/offline/offline_entity.dart';
import '../../../core/offline/outbox_entry.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/user_session.dart';
import '../domain/support_ticket.dart';

/// The signed-in landlord's own conversations, newest activity first.
///
/// Scoped to `effectiveWorkspaceId` rather than to the signed-in uid so the
/// filter matches the pull, which is keyed the same way.
final landlordSupportTicketsProvider = StreamProvider<List<SupportTicket>>((
  ref,
) async* {
  final session = ref.watch(sessionControllerProvider);
  if (session == null) {
    yield const <SupportTicket>[];
    return;
  }
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.support.watchAll(landlordId: session.effectiveWorkspaceId);
});

/// Every ticket the administrative pull mirrored, for the support queue.
final adminSupportTicketsProvider = StreamProvider<List<SupportTicket>>((
  ref,
) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.support.watchAll();
});

/// One conversation, live. Used by both sides' thread views — the store is the
/// same, and which tickets are in it is already decided by the pull.
final supportTicketProvider = StreamProvider.family<SupportTicket?, String>((
  ref,
  ticketId,
) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.support.watchById(ticketId);
});

/// How many conversations are waiting on Nyumba. Drives the admin nav badge.
final supportQueueDepthProvider = Provider<int>((ref) {
  final tickets = ref.watch(adminSupportTicketsProvider);
  return tickets.maybeWhen(
    data: (items) => items.where((ticket) => ticket.awaitsSupport).length,
    orElse: () => 0,
  );
});

/// Conversations waiting on the landlord. Drives the "Needs you" count on their
/// support entry point, so an unanswered question is visible without opening it.
final landlordSupportUnreadProvider = Provider<int>((ref) {
  final tickets = ref.watch(landlordSupportTicketsProvider);
  return tickets.maybeWhen(
    data: (items) => items.where((ticket) => ticket.awaitsLandlord).length,
    orElse: () => 0,
  );
});

/// What the outbox actually knows about one conversation's unsent writes.
///
/// The thread renders this rather than a checkmark on every message. A support
/// message that silently failed is the single worst bug this feature can have —
/// the landlord believes they have asked for help and nobody has been asked.
final class SupportDelivery {
  const SupportDelivery({
    this.unconfirmed = 0,
    this.failed = 0,
    this.failureReason,
  });

  /// Messages at the end of the thread that the server has not acknowledged.
  /// Replies are enqueued one per message and drained in order, so the count of
  /// outstanding entries is the count of trailing unconfirmed messages.
  final int unconfirmed;

  /// How many of those the sync engine has given up on.
  final int failed;

  /// The server's own explanation, when it sent one. "Validation failed" alone
  /// is not something anyone can act on.
  final String? failureReason;

  bool get isSettled => unconfirmed == 0;
  bool get hasFailure => failed > 0;
}

final supportDeliveryProvider = Provider.family<SupportDelivery, String>((
  ref,
  ticketId,
) {
  final entries = ref.watch(outboxEntriesProvider);
  return entries.maybeWhen(
    data: (outbox) {
      final mine = outbox
          .where(
            (entry) =>
                entry.entityType == OfflineEntityType.supportTicket &&
                entry.entityId == ticketId,
          )
          .toList(growable: false);
      if (mine.isEmpty) return const SupportDelivery();
      final failed = mine
          .where((entry) => entry.state == OutboxState.permanentlyFailed)
          .toList(growable: false);
      return SupportDelivery(
        unconfirmed: mine.length,
        failed: failed.length,
        failureReason: failed.isEmpty
            ? null
            : failed.last.errorReason ?? failed.last.lastError,
      );
    },
    // An outbox we cannot read is not proof that anything sent. Reporting zero
    // unconfirmed here would be the same false reassurance as a fake checkmark.
    orElse: () => const SupportDelivery(unconfirmed: 0),
  );
});

final supportActionsProvider = Provider<SupportActions>(SupportActions.new);

/// The three writes, with the session details each command needs filled in from
/// the session rather than from the caller — a screen should not be able to
/// open a ticket against a workspace it is not in.
class SupportActions {
  const SupportActions(this._ref);

  final Ref _ref;

  Future<SupportTicket> open({
    required String subject,
    required SupportCategory category,
    required String body,
    required String appVersion,
    required String platform,
  }) async {
    final session = _requireSession();
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.support.open(
      landlordId: session.effectiveWorkspaceId,
      subject: subject,
      category: category,
      body: body,
      appVersion: appVersion,
      platform: platform,
      landlordName: session.displayName,
    );
  }

  Future<SupportTicket> reply({
    required String ticketId,
    required String body,
  }) async {
    final session = _requireSession();
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.support.reply(
      ticketId: ticketId,
      authorUid: session.userId,
      body: body,
    );
  }

  Future<SupportTicket> updateStatus({
    required String ticketId,
    required SupportStatus status,
    String? note,
  }) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.support.updateStatus(
      ticketId: ticketId,
      status: status,
      note: note,
    );
  }

  UserSession _requireSession() {
    final session = _ref.read(sessionControllerProvider);
    if (session == null) {
      throw StateError('Support is unavailable while signed out.');
    }
    return session;
  }
}
