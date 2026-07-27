import 'package:nyumba_property_management/core/domain/sync_metadata.dart';

/// Whether a review is currently part of the public record.
enum ReviewStatus {
  published,
  withdrawn,

  /// Taken down by a moderator pending or after adjudication. The author still
  /// sees it — a review that silently vanishes is worse than one refused.
  hidden,
  removed;

  bool get isPublic => this == ReviewStatus.published;
}

/// Where a review sits in the moderation queue.
///
/// A flag never hides anything. If it did, every negative review would be
/// flagged within a day and the ratings would show only what landlords were
/// happy with — worse than no ratings, because it would still look trustworthy.
enum ReviewFlagState { none, pending, upheld, dismissed }

enum ReviewFlagReason { inaccurate, abusive, notMyTenant, personalData, spam }

enum ReviewModerationDecision { publish, hide, remove }

/// The edit a pending review record is carrying to the server.
///
/// A review can change in five distinct ways but the outbox has only five
/// generic operations shared across every aggregate, so the operation alone
/// cannot say which. This names it, and `firebase_remote_sync_gateway` reads it
/// back to pick the command.
enum ReviewAction { submit, edit, withdraw, respond, flag, report, moderate }

/// The four optional aspect scores.
///
/// Optional on purpose: a tenant who only wants to leave a star rating should
/// not face five required questions. But they are what makes a review useful
/// before a landlord has enough volume for a trustworthy average, and what gives
/// the landlord something specific to act on rather than a number to resent.
enum ReviewDimension {
  responsiveness,
  maintenance,
  listingAccuracy,
  depositFairness,
}

final class LandlordReview {
  const LandlordReview({
    required this.id,
    required this.landlordId,
    required this.propertyName,
    required this.unitLabel,
    required this.reviewerLabel,
    required this.overall,
    required this.status,
    required this.flagState,
    required this.stayMonths,
    required this.createdAt,
    required this.updatedAt,
    required this.syncMetadata,
    this.scores = const <ReviewDimension, int>{},
    this.body,
    this.landlordResponse,
    this.respondedAt,
    this.editableUntil,
    this.version = 1,
    this.pendingAction,
    this.flagReasonCode,
    this.flagNote,
    this.moderationDecision,
    this.moderationNote,
  });

  /// Always the ID of the lease being reviewed. One review per tenancy falls out
  /// of that for free, and so does an idempotent retry.
  final String id;
  final String landlordId;
  final String propertyName;
  final String unitLabel;

  /// Display attribution, resolved by the server per audience: "You" for the
  /// author, "Tenant of B4" for the landlord, "Verified tenant" in public.
  final String reviewerLabel;

  final int overall;
  final Map<ReviewDimension, int> scores;
  final String? body;
  final ReviewStatus status;
  final ReviewFlagState flagState;
  final String? landlordResponse;
  final DateTime? respondedAt;

  /// When the author's edit window closes. Null on any copy but the author's.
  final DateTime? editableUntil;

  /// Whole months the reviewer lived in the unit. The only provenance a public
  /// reader gets, and the one that matters: it says they actually lived there.
  final int stayMonths;

  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;
  final SyncMetadata syncMetadata;

  final ReviewAction? pendingAction;
  final ReviewFlagReason? flagReasonCode;
  final String? flagNote;
  final ReviewModerationDecision? moderationDecision;
  final String? moderationNote;

  bool get hasResponse =>
      landlordResponse != null && landlordResponse!.trim().isNotEmpty;

  bool get hasBody => body != null && body!.trim().isNotEmpty;

  /// Whether the author may still change this review.
  bool editableAt(DateTime now) =>
      status == ReviewStatus.published &&
      editableUntil != null &&
      now.isBefore(editableUntil!);

  LandlordReview copyWith({
    int? overall,
    Map<ReviewDimension, int>? scores,
    String? body,
    ReviewStatus? status,
    ReviewFlagState? flagState,
    String? landlordResponse,
    DateTime? respondedAt,
    DateTime? updatedAt,
    int? version,
    SyncMetadata? syncMetadata,
    ReviewAction? pendingAction,
    ReviewFlagReason? flagReasonCode,
    String? flagNote,
    ReviewModerationDecision? moderationDecision,
    String? moderationNote,
  }) => LandlordReview(
    id: id,
    landlordId: landlordId,
    propertyName: propertyName,
    unitLabel: unitLabel,
    reviewerLabel: reviewerLabel,
    overall: overall ?? this.overall,
    scores: scores ?? this.scores,
    body: body ?? this.body,
    status: status ?? this.status,
    flagState: flagState ?? this.flagState,
    landlordResponse: landlordResponse ?? this.landlordResponse,
    respondedAt: respondedAt ?? this.respondedAt,
    editableUntil: editableUntil,
    stayMonths: stayMonths,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    version: version ?? this.version,
    syncMetadata: syncMetadata ?? this.syncMetadata,
    pendingAction: pendingAction ?? this.pendingAction,
    flagReasonCode: flagReasonCode ?? this.flagReasonCode,
    flagNote: flagNote ?? this.flagNote,
    moderationDecision: moderationDecision ?? this.moderationDecision,
    moderationNote: moderationNote ?? this.moderationNote,
  );
}

/// A landlord's aggregate rating, computed from the reviews on this device.
///
/// Deliberately derived on the client rather than pulled. The landlord already
/// holds every review written about them, and the public mirror already carries
/// the authoritative average on each listing card, so a third copy scoped to a
/// landlord's own UID would be a Firestore read and a rules path bought for
/// arithmetic over data already in memory.
final class RatingSummary {
  const RatingSummary({
    required this.count,
    required this.average,
    required this.distribution,
    required this.dimensionAverages,
  });

  factory RatingSummary.from(Iterable<LandlordReview> reviews) {
    final counted = reviews.where((review) => review.status.isPublic).toList();
    if (counted.isEmpty) return RatingSummary.empty;
    final distribution = List<int>.filled(5, 0);
    var total = 0;
    final dimensionSums = <ReviewDimension, int>{};
    final dimensionCounts = <ReviewDimension, int>{};
    for (final review in counted) {
      total += review.overall;
      final bucket = review.overall.clamp(1, 5).toInt() - 1;
      distribution[bucket] += 1;
      for (final entry in review.scores.entries) {
        dimensionSums[entry.key] =
            (dimensionSums[entry.key] ?? 0) + entry.value;
        dimensionCounts[entry.key] = (dimensionCounts[entry.key] ?? 0) + 1;
      }
    }
    return RatingSummary(
      count: counted.length,
      average: total / counted.length,
      distribution: distribution,
      dimensionAverages: <ReviewDimension, double>{
        for (final entry in dimensionSums.entries)
          entry.key: entry.value / dimensionCounts[entry.key]!,
      },
    );
  }

  static const RatingSummary empty = RatingSummary(
    count: 0,
    average: null,
    distribution: <int>[0, 0, 0, 0, 0],
    dimensionAverages: <ReviewDimension, double>{},
  );

  final int count;
  final double? average;

  /// Index 0 holds one-star reviews through index 4 holding five-star.
  final List<int> distribution;
  final Map<ReviewDimension, double> dimensionAverages;

  /// Mirrors `REVIEW_PUBLIC_DISPLAY_MIN_COUNT` on the server. One review is
  /// noise and one bad review is a weapon; neither should read as a verdict.
  static const int publicDisplayMinimum = 3;

  bool get isPublicallyDisplayable => count >= publicDisplayMinimum;

  int shareOf(int stars) =>
      count == 0 ? 0 : ((distribution[stars - 1] / count) * 100).round();
}
