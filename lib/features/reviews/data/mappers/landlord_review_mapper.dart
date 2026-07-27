import 'package:nyumba_property_management/core/offline/json_reader.dart';
import 'package:nyumba_property_management/core/offline/sync_metadata_mapper.dart';
import 'package:nyumba_property_management/features/reviews/domain/landlord_review.dart';

/// Translates between [LandlordReview] and the persisted/remote JSON shape.
///
/// The field names here are also the server's: `tenantReviewProjection`,
/// `landlordReviewProjection`, and `publicReviewProjection` in
/// `functions/src/shared/projections.ts` publish exactly these keys, and
/// `reviews-projection.test.ts` asserts the list. That pairing is the whole
/// reason a tenant projection is readable at all in this app — every earlier one
/// was written against a mapper that already existed and did not fit, which
/// surfaced as a FormatException on a screen far from the mismatch.
///
/// Consequence: a rename on either side must land on both, in one change.
final class LandlordReviewMapper {
  const LandlordReviewMapper._();

  /// Dimension scores are flattened to top-level keys rather than nested.
  ///
  /// Firestore rules cannot inspect nested maps cheaply and the projection
  /// whitelists are flat by convention; keeping the wire shape flat also means a
  /// new dimension is an added key rather than a reshaped object.
  static const Map<ReviewDimension, String> _dimensionKeys =
      <ReviewDimension, String>{
        ReviewDimension.responsiveness: 'responsiveness',
        ReviewDimension.maintenance: 'maintenance',
        ReviewDimension.listingAccuracy: 'listingAccuracy',
        ReviewDimension.depositFairness: 'depositFairness',
      };

  static Map<String, Object?> toJson(
    LandlordReview review,
  ) => <String, Object?>{
    'id': review.id,
    'version': review.version,
    'landlordId': review.landlordId,
    'propertyName': review.propertyName,
    'unitLabel': review.unitLabel,
    'reviewerLabel': review.reviewerLabel,
    'overall': review.overall,
    for (final entry in _dimensionKeys.entries)
      entry.value: review.scores[entry.key],
    'body': review.body,
    'status': review.status.name,
    'flagState': review.flagState.name,
    'landlordResponse': review.landlordResponse,
    'respondedAt': review.respondedAt?.toUtc().toIso8601String(),
    'editableUntil': review.editableUntil?.toUtc().toIso8601String(),
    'stayMonths': review.stayMonths,
    'createdAt': review.createdAt.toUtc().toIso8601String(),
    'updatedAt': review.updatedAt.toUtc().toIso8601String(),
    // Locally authored intent, never published by the server. It is what tells
    // the sync gateway which of the five review commands this record carries.
    'pendingAction': review.pendingAction?.name,
    'flagReasonCode': review.flagReasonCode?.name,
    'flagNote': review.flagNote,
    'moderationDecision': review.moderationDecision?.name,
    'moderationNote': review.moderationNote,
    'syncMetadata': SyncMetadataMapper.toJson(review.syncMetadata),
  };

  static LandlordReview fromJson(Map<String, Object?> json) {
    final reader = JsonReader(json);
    final scores = <ReviewDimension, int>{};
    for (final entry in _dimensionKeys.entries) {
      final score = reader.optionalInt(entry.value);
      if (score != null) scores[entry.key] = score;
    }
    return LandlordReview(
      id: reader.requiredString('id'),
      version: reader.optionalInt('version') ?? 1,
      landlordId: reader.requiredString('landlordId'),
      // Tolerated as optional so a public review — which carries no unit label
      // and, for an older record, may carry no property name — reads through the
      // same mapper instead of needing a parallel one.
      propertyName: reader.optionalString('propertyName') ?? '',
      unitLabel: reader.optionalString('unitLabel') ?? '',
      reviewerLabel: reader.optionalString('reviewerLabel') ?? '',
      overall: reader.requiredInt('overall'),
      scores: scores,
      body: reader.optionalString('body'),
      status: reader.enumValue('status', ReviewStatus.values),
      flagState: _flagState(json['flagState']),
      landlordResponse: reader.optionalString('landlordResponse'),
      respondedAt: reader.optionalDate('respondedAt'),
      editableUntil: reader.optionalDate('editableUntil'),
      stayMonths: reader.optionalInt('stayMonths') ?? 1,
      createdAt: reader.requiredDate('createdAt'),
      updatedAt: reader.requiredDate('updatedAt'),
      pendingAction: _enumOrNull(json['pendingAction'], ReviewAction.values),
      flagReasonCode: _enumOrNull(
        json['flagReasonCode'],
        ReviewFlagReason.values,
      ),
      flagNote: reader.optionalString('flagNote'),
      moderationDecision: _enumOrNull(
        json['moderationDecision'],
        ReviewModerationDecision.values,
      ),
      moderationNote: reader.optionalString('moderationNote'),
      syncMetadata: SyncMetadataMapper.fromJson(json['syncMetadata']),
    );
  }

  /// A public review is projected with `flagState: 'none'` and a locally
  /// authored one may not carry it at all, so absence means "not flagged"
  /// rather than a malformed record.
  static ReviewFlagState _flagState(Object? raw) {
    if (raw is! String) return ReviewFlagState.none;
    return ReviewFlagState.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => ReviewFlagState.none,
    );
  }

  static T? _enumOrNull<T extends Enum>(Object? raw, List<T> values) {
    if (raw is! String) return null;
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }
}
