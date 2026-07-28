import 'package:flutter/material.dart';

import '../../../core/domain/sync_metadata.dart';
import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/offline/command_failure.dart';
import '../../../core/offline/offline_entity.dart';
import '../../../core/offline/outbox_entry.dart';
import '../../../core/presentation/status_badge.dart';
import '../domain/listing.dart';

/// What has actually become of an advert, in the terms its landlord cares
/// about: is it live, is it on its way, or did it fail.
///
/// The listings screen used to derive this from `syncMetadata.state != synced`
/// alone, which renders an in-flight publication and one the server has
/// permanently refused as the same amber "Publishing". A refused advert then
/// waits forever for an acknowledgement that already came back as "no", with
/// no reason shown and no way to retry. Keeping publication honest is a
/// correctness rule — see [Listing.isPublic] — but the landlord still has to
/// be told which of the two they are looking at.
enum ListingPublicationState {
  /// Not advertised yet, and not waiting to be.
  draft,

  /// The server holds this advert and tenants can find it.
  live,

  /// Taken out of search, settled on the server.
  paused,

  /// Queued or in flight on its first attempt; expected to clear in a moment.
  goingLive,

  /// Delivery already failed at least once and a retry is scheduled. The
  /// advert still gets there, but not right now.
  retrying,

  /// An unpublish is on its way to the server.
  removing,

  /// A local edit is on its way, without changing whether the advert is public.
  saving,

  /// The server refused the change. Nothing further happens without the
  /// landlord doing something.
  failed,

  /// A mutation this advert queues behind failed, so it cannot even be tried.
  blocked,

  /// A remote change could not be applied over an unsynced local edit.
  conflicted,
}

/// The advert's state plus everything the card needs to explain it.
final class ListingPublication {
  const ListingPublication({
    required this.state,
    required this.label,
    required this.tone,
    required this.icon,
    required this.detail,
    this.failure,
    this.mutationId,
  });

  final ListingPublicationState state;

  /// Badge text, in the landlord's terms rather than the outbox's.
  final String label;
  final BadgeTone tone;
  final IconData icon;

  /// One sentence: what is happening, and what happens next.
  final String detail;

  /// What the server refused, resolved to a stable identity the presentation
  /// layer turns into localized copy naming the fix.
  ///
  /// A raw error string is never shown: the server sends stable tokens
  /// (`VALIDATION_FAILED` with `listingMissingPhotos`), and putting those on
  /// screen is what left a landlord reading "validation failed" with nothing
  /// to act on.
  final CommandFailureDescriptor? failure;

  /// The outbox entry a retry would re-queue, when one can be.
  final String? mutationId;

  bool get isLive => state == ListingPublicationState.live;

  /// Stalled in a way only the landlord can clear.
  bool get needsAttention => switch (state) {
    ListingPublicationState.failed ||
    ListingPublicationState.blocked ||
    ListingPublicationState.conflicted => true,
    _ => false,
  };

  /// On its way to the server. Nothing to do but let it land.
  bool get inFlight => switch (state) {
    ListingPublicationState.goingLive ||
    ListingPublicationState.retrying ||
    ListingPublicationState.removing ||
    ListingPublicationState.saving => true,
    _ => false,
  };

  bool get canRetry => mutationId != null;
}

/// Resolves what to tell the landlord about [listing], from the durable
/// outbox first and the entity's own metadata second.
///
/// The outbox is preferred because it is where a rejection actually lives: it
/// carries the server's reason and the entry a retry re-queues. The entity's
/// [SyncMetadata] is the fallback for a failure whose entry has since been
/// cleared, so a rejected advert never quietly reads as settled.
ListingPublication resolveListingPublication({
  required Listing listing,
  required List<OutboxEntry> outbox,
  required AppLocalizations copy,
}) {
  OutboxEntry? failed;
  OutboxEntry? blocked;
  OutboxEntry? pending;
  for (final entry in outbox) {
    if (entry.entityType != OfflineEntityType.listing) continue;
    if (entry.entityId != listing.id) continue;
    switch (entry.state) {
      case OutboxState.permanentlyFailed:
        failed ??= entry;
      case OutboxState.blocked:
        blocked ??= entry;
      case OutboxState.processing:
      case OutboxState.pending:
      case OutboxState.retryScheduled:
        // The most-attempted entry sets the tone: one mutation already
        // bouncing makes the advert "retrying", not "going live".
        if (pending == null || entry.attemptCount > pending.attemptCount) {
          pending = entry;
        }
    }
  }

  if (failed != null) {
    return _failed(
      listing,
      copy: copy,
      operation: failed.operation,
      failure: _describe(failed),
      mutationId: failed.id,
    );
  }
  if (blocked != null) {
    return ListingPublication(
      state: ListingPublicationState.blocked,
      label: copy.listingStatusBlockedLabel,
      tone: BadgeTone.warning,
      icon: Icons.block_rounded,
      detail: copy.listingStatusBlockedDetail,
      failure: _describe(blocked),
    );
  }
  if (pending != null) return _inFlight(listing, pending, copy);

  // No durable intent is left, so the entity's own metadata is the record of
  // what happened — including a failure whose outbox entry has been cleared.
  // Only the bare code survives there, so the advice is necessarily coarser
  // than what the outbox entry could have said.
  if (listing.syncMetadata.state == EntitySyncState.failed) {
    final code = listing.syncMetadata.lastError;
    return _failed(
      listing,
      copy: copy,
      failure: code == null
          ? null
          : describeStoredCommandFailure(code: code),
    );
  }
  if (listing.syncMetadata.state == EntitySyncState.conflicted) {
    return ListingPublication(
      state: ListingPublicationState.conflicted,
      label: copy.listingStatusConflictedLabel,
      tone: BadgeTone.danger,
      icon: Icons.fork_right_rounded,
      detail: copy.listingStatusConflictedDetail,
    );
  }

  return switch (listing.status) {
    ListingStatus.published => ListingPublication(
      state: ListingPublicationState.live,
      label: copy.listingStatusPublishedLabel,
      tone: BadgeTone.success,
      icon: Icons.check_circle_outline_rounded,
      detail: copy.listingStatusPublishedDetail,
    ),
    ListingStatus.paused => ListingPublication(
      state: ListingPublicationState.paused,
      label: copy.listingStatusPausedLabel,
      tone: BadgeTone.neutral,
      icon: Icons.pause_circle_outline_rounded,
      detail: copy.listingStatusPausedDetail,
    ),
    ListingStatus.closed => ListingPublication(
      state: ListingPublicationState.paused,
      label: copy.listingStatusClosedLabel,
      tone: BadgeTone.neutral,
      icon: Icons.inventory_2_outlined,
      detail: copy.listingStatusClosedDetail,
    ),
    ListingStatus.draft => ListingPublication(
      state: ListingPublicationState.draft,
      label: copy.listingStatusDraftLabel,
      tone: BadgeTone.neutral,
      icon: Icons.edit_note_rounded,
      detail: copy.listingStatusDraftDetail,
    ),
  };
}

/// In-flight work is deliberately calm on the first attempt and only escalates
/// once delivery has actually failed. A publication that clears in a second
/// does not deserve the same warning colour as one that cannot get out.
ListingPublication _inFlight(
  Listing listing,
  OutboxEntry entry,
  AppLocalizations copy,
) {
  final struggling = entry.attemptCount > 0;
  final (state, label, detail) = switch (entry.operation) {
    OutboxOperation.publish => (
      ListingPublicationState.goingLive,
      copy.listingStatusGoingLiveLabel,
      copy.listingStatusGoingLiveDetail,
    ),
    OutboxOperation.delete => (
      ListingPublicationState.removing,
      copy.listingStatusRemovingLabel,
      copy.listingStatusRemovingDetail,
    ),
    _ => (
      ListingPublicationState.saving,
      copy.listingStatusSavingLabel,
      copy.listingStatusSavingDetail,
    ),
  };
  if (!struggling) {
    return ListingPublication(
      state: state,
      label: label,
      tone: BadgeTone.info,
      icon: Icons.cloud_upload_outlined,
      detail: detail,
    );
  }
  return ListingPublication(
    state: state == ListingPublicationState.goingLive
        ? ListingPublicationState.retrying
        : state,
    label: copy.listingStatusRetryingLabel,
    tone: BadgeTone.warning,
    icon: Icons.sync_problem_rounded,
    detail:
        '${copy.listingRetryingLead} '
        '${listing.status == ListingStatus.published ? copy.listingRetryingPublishedTail : copy.listingRetryingPendingTail}',
    failure: _describe(entry),
  );
}

/// Replays a persisted failure through the shared command-failure translator,
/// so a background rejection reads exactly like the same rejection caught in
/// the foreground.
CommandFailureDescriptor? _describe(OutboxEntry entry) {
  final code = entry.lastError;
  if (code == null) return null;
  return describeStoredCommandFailure(
    code: code,
    reason: entry.errorReason,
    fields: entry.errorFields,
  );
}

/// Failure wording follows the operation that failed, not the local status: a
/// listing whose publish was refused still reads `published` on this device,
/// and telling its landlord it is "published" is the whole problem.
ListingPublication _failed(
  Listing listing, {
  required AppLocalizations copy,
  OutboxOperation? operation,
  CommandFailureDescriptor? failure,
  String? mutationId,
}) {
  final intent =
      operation ??
      switch (listing.status) {
        ListingStatus.published => OutboxOperation.publish,
        ListingStatus.paused || ListingStatus.closed => OutboxOperation.delete,
        ListingStatus.draft => OutboxOperation.update,
      };
  final (label, detail) = switch (intent) {
    OutboxOperation.publish => (
      copy.listingStatusNotPublishedLabel,
      copy.listingStatusNotPublishedDetail,
    ),
    OutboxOperation.delete => (
      copy.listingStatusStillPublicLabel,
      copy.listingStatusStillPublicDetail,
    ),
    _ => (copy.listingStatusNotSavedLabel, copy.listingStatusNotSavedDetail),
  };
  return ListingPublication(
    state: ListingPublicationState.failed,
    label: label,
    tone: BadgeTone.danger,
    icon: Icons.error_outline_rounded,
    detail: detail,
    failure: failure,
    mutationId: mutationId,
  );
}
