import 'package:flutter/material.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/presentation/status_badge.dart';
import '../domain/listing.dart';

/// Where an advert stands with the server.
///
/// This used to carry seven more values — `goingLive`, `retrying`, `removing`,
/// `saving`, `failed`, `blocked`, `conflicted` — every one of them derived from
/// durable outbox entries describing work that had not reached the server yet.
/// None of them can occur now: a publish, an edit, or a retirement either
/// reaches the server, in which case one of the three states below is already
/// the truth, or it fails while the landlord is watching and is reported to
/// them right then.
///
/// What replaced those states is not a different badge but a different moment.
/// A refusal is surfaced at the point of action rather than lingering as a
/// property of the advert that nothing will ever clear.
enum ListingPublicationState {
  /// Not advertised, and not waiting to be.
  draft,

  /// The server holds this advert and tenants can find it.
  live,

  /// Taken out of search, settled on the server.
  paused,
}

/// The advert's state plus everything the card needs to explain it.
final class ListingPublication {
  const ListingPublication({
    required this.state,
    required this.label,
    required this.tone,
    required this.icon,
    required this.detail,
  });

  final ListingPublicationState state;
  final String label;
  final BadgeTone tone;
  final IconData icon;
  final String detail;

  /// Whether visitors can find this advert right now.
  bool get isLive => state == ListingPublicationState.live;

  /// Kept so callers that filtered on it keep compiling and keep meaning
  /// something honest. No advert carries a standing problem any more — a
  /// refused command is reported when it is refused, not stored on the record.
  bool get needsAttention => false;
}

/// The advert's publication state, read straight from the server's own status.
///
/// There is no second source to reconcile against. This previously had to weigh
/// the entity's status against pending outbox entries and a stored failure
/// code, because those could disagree for as long as delivery was outstanding —
/// and while they disagreed, the screen had to guess which one to believe.
ListingPublication resolveListingPublication({
  required Listing listing,
  required AppLocalizations copy,
}) => switch (listing.status) {
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
