import 'landlord_review.dart';

/// Everything needed to author a review of one tenancy.
final class SubmitReviewInput {
  const SubmitReviewInput({
    required this.leaseId,
    required this.landlordId,
    required this.propertyName,
    required this.unitLabel,
    required this.overall,
    required this.stayMonths,
    this.scores = const <ReviewDimension, int>{},
    this.body,
  });

  /// Doubles as the review's ID. The server keys reviews by lease, so this is
  /// simultaneously the identity and the eligibility proof.
  final String leaseId;
  final String landlordId;
  final String propertyName;
  final String unitLabel;
  final int overall;
  final int stayMonths;
  final Map<ReviewDimension, int> scores;
  final String? body;
}

final class EditReviewInput {
  const EditReviewInput({
    required this.reviewId,
    required this.overall,
    this.scores = const <ReviewDimension, int>{},
    this.body,
  });

  final String reviewId;
  final int overall;
  final Map<ReviewDimension, int> scores;
  final String? body;
}

abstract interface class ReviewRepository {
  Stream<List<LandlordReview>> watchAll({String? landlordId});
  Future<List<LandlordReview>> getAll({String? landlordId});
  Future<LandlordReview?> getById(String id);

  Future<LandlordReview> submit(SubmitReviewInput input);
  Future<LandlordReview> edit(EditReviewInput input);
  Future<LandlordReview> withdraw(String reviewId);

  /// The reviewed landlord's public reply.
  Future<LandlordReview> respond({
    required String reviewId,
    required String response,
  });

  /// Raises a review for adjudication. Never hides it — see [ReviewFlagState].
  Future<LandlordReview> flag({
    required String reviewId,
    required ReviewFlagReason reason,
    String? note,
    bool asReader = false,
  });

  Future<LandlordReview> moderate({
    required String reviewId,
    required ReviewModerationDecision decision,
    String? note,
  });

  /// Public reviews about one landlord, read from the local mirror.
  Stream<List<LandlordReview>> watchPublic(String landlordToken);

  /// Refreshes [watchPublic] from the server for one landlord.
  Future<void> refreshPublic(String landlordToken);
}
