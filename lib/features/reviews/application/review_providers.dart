import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../domain/landlord_review.dart';
import '../domain/review_repository.dart';

/// Every review written about the signed-in landlord.
final receivedReviewsProvider = StreamProvider<List<LandlordReview>>((
  ref,
) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.reviews.watchAll();
});

/// The landlord's own rating, derived from the reviews already on this device.
///
/// Not a separate pull: the landlord holds every review written about them, so
/// a server round trip would buy arithmetic over data already in memory.
final receivedRatingProvider = Provider<AsyncValue<RatingSummary>>((ref) {
  return ref.watch(receivedReviewsProvider).whenData(RatingSummary.from);
});

/// Reviews authored by the signed-in tenant.
///
/// Same store as [receivedReviewsProvider] and no filter is needed: the
/// workspace mirror is scoped per account and role, so a tenant's store holds
/// only reviews they wrote and a landlord's only reviews about them.
final authoredReviewsProvider = StreamProvider<List<LandlordReview>>((
  ref,
) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.reviews.watchAll();
});

/// Public reviews about one landlord, keyed by the opaque token a public
/// listing carries in place of the landlord's UID.
final publicReviewsProvider = StreamProvider.family<List<LandlordReview>, String>(
  (ref, landlordToken) async* {
    final deps = await ref.watch(appDependenciesProvider.future);
    // Fire the refresh but do not await it: the mirror renders immediately and
    // the stream re-emits when the merge lands, so a slow network delays fresh
    // reviews rather than the whole screen.
    unawaited(deps.reviews.refreshPublic(landlordToken));
    yield* deps.reviews.watchPublic(landlordToken);
  },
);

final publicRatingProvider = Provider.family<AsyncValue<RatingSummary>, String>(
  (ref, landlordToken) => ref
      .watch(publicReviewsProvider(landlordToken))
      .whenData(RatingSummary.from),
);

final submitReviewProvider = Provider<SubmitReview>(SubmitReview.new);
final editReviewProvider = Provider<EditReview>(EditReview.new);
final withdrawReviewProvider = Provider<WithdrawReview>(WithdrawReview.new);
final respondToReviewProvider = Provider<RespondToReview>(RespondToReview.new);
final flagReviewProvider = Provider<FlagReview>(FlagReview.new);
final moderateReviewProvider = Provider<ModerateReview>(ModerateReview.new);

class SubmitReview {
  const SubmitReview(this._ref);

  final Ref _ref;

  Future<LandlordReview> call(SubmitReviewInput input) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.reviews.submit(input);
  }
}

class EditReview {
  const EditReview(this._ref);

  final Ref _ref;

  Future<LandlordReview> call(EditReviewInput input) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.reviews.edit(input);
  }
}

class WithdrawReview {
  const WithdrawReview(this._ref);

  final Ref _ref;

  Future<LandlordReview> call(String reviewId) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.reviews.withdraw(reviewId);
  }
}

class RespondToReview {
  const RespondToReview(this._ref);

  final Ref _ref;

  Future<LandlordReview> call({
    required String reviewId,
    required String response,
  }) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.reviews.respond(reviewId: reviewId, response: response);
  }
}

class FlagReview {
  const FlagReview(this._ref);

  final Ref _ref;

  Future<LandlordReview> call({
    required String reviewId,
    required ReviewFlagReason reason,
    String? note,
    bool asReader = false,
  }) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.reviews.flag(
      reviewId: reviewId,
      reason: reason,
      note: note,
      asReader: asReader,
    );
  }
}

class ModerateReview {
  const ModerateReview(this._ref);

  final Ref _ref;

  Future<LandlordReview> call({
    required String reviewId,
    required ReviewModerationDecision decision,
    String? note,
  }) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.reviews.moderate(
      reviewId: reviewId,
      decision: decision,
      note: note,
    );
  }
}
