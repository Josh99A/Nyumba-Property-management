import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../auth/application/session_controller.dart';
import '../../tenants/domain/tenancy.dart';
import '../data/review_prompt_store.dart';
import '../domain/landlord_review.dart';
import 'review_prompt_policy.dart';
import 'review_providers.dart';

final reviewPromptStoreProvider = Provider<ReviewPromptStore>(
  (ref) => const ReviewPromptStore(),
);

final reviewPromptPolicyProvider = Provider<ReviewPromptPolicy>(
  (ref) => const ReviewPromptPolicy(),
);

/// The tenancy this tenant could review right now, if any.
///
/// Null covers three different situations that all mean "do not ask": no
/// tenancy on this device, a tenancy outside the eligibility window, and a
/// tenancy already reviewed. Only the middle one is worth explaining in the UI,
/// which [reviewEligibilityHintProvider] does.
final reviewCandidateProvider = Provider<AsyncValue<ReviewPromptCandidate?>>((
  ref,
) {
  final tenantId = ref.watch(sessionControllerProvider)?.userId;
  if (tenantId == null) {
    return const AsyncValue<ReviewPromptCandidate?>.data(null);
  }

  final tenancies = ref.watch(myTenanciesForReviewProvider(tenantId));
  final reviews = ref.watch(authoredReviewsProvider);
  if (tenancies.isLoading || reviews.isLoading) {
    return const AsyncValue<ReviewPromptCandidate?>.loading();
  }
  final reviewed = <String>{
    for (final review in reviews.value ?? const <LandlordReview>[]) review.id,
  };
  final now = DateTime.now().toUtc();
  for (final tenancy in tenancies.value ?? const <Tenancy>[]) {
    if (reviewed.contains(tenancy.id)) continue;
    final hasEnded = tenancy.status == TenancyStatus.ended;
    if (!ReviewEligibility.isEligible(
      activatedAt: tenancy.leaseStart,
      endedAt: hasEnded ? tenancy.leaseEnd : null,
      hasEnded: hasEnded,
      now: now,
    )) {
      continue;
    }
    return AsyncValue<ReviewPromptCandidate?>.data(
      ReviewPromptCandidate(
        leaseId: tenancy.id,
        landlordId: tenancy.landlordId,
        propertyName: tenancy.propertyName,
        unitLabel: tenancy.unitLabel,
        stayMonths: _monthsBetween(
          tenancy.leaseStart,
          hasEnded ? tenancy.leaseEnd : now,
        ),
        hasEnded: hasEnded,
      ),
    );
  }
  return const AsyncValue<ReviewPromptCandidate?>.data(null);
});

/// When an otherwise-reviewable tenancy becomes eligible.
///
/// Shown instead of nothing, because a missing button reads as a bug while
/// "you can review from 12 March" reads as a rule.
final reviewEligibilityHintProvider = Provider<DateTime?>((ref) {
  final tenantId = ref.watch(sessionControllerProvider)?.userId;
  if (tenantId == null) return null;
  final tenancies =
      ref.watch(myTenanciesForReviewProvider(tenantId)).value ??
      const <Tenancy>[];
  final reviewed = <String>{
    for (final review
        in ref.watch(authoredReviewsProvider).value ?? const <LandlordReview>[])
      review.id,
  };
  final now = DateTime.now().toUtc();
  for (final tenancy in tenancies) {
    if (reviewed.contains(tenancy.id)) continue;
    if (tenancy.status == TenancyStatus.ended) continue;
    final eligibleFrom = ReviewEligibility.eligibleFrom(tenancy.leaseStart);
    if (now.isBefore(eligibleFrom)) return eligibleFrom;
  }
  return null;
});

/// Every tenancy belonging to this tenant, ended ones included.
///
/// `myTenancyProvider` yields only the first, which is enough for the portal's
/// "your current home" framing but wrong here: the most reviewable tenancy is
/// usually the one that just ended.
final myTenanciesForReviewProvider =
    StreamProvider.family<List<Tenancy>, String>((ref, tenantUserId) async* {
      final deps = await ref.watch(appDependenciesProvider.future);
      yield* deps.tenancies.watchAll(tenantUserId: tenantUserId);
    });

int _monthsBetween(DateTime from, DateTime to) {
  final days = to.difference(from).inDays;
  return days <= 0 ? 1 : (days / 30.44).round().clamp(1, 600);
}
