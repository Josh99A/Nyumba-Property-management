/// Guards the rules that decide when a tenant is interrupted.
///
/// These are product decisions with a real cost when they regress: a prompt
/// that reappears after someone declined twice, or one that fires the week a
/// tenant moves in, does more damage to the review corpus than a missing
/// feature would. The eligibility half also mirrors the server's gate in
/// `commands/reviews.ts` — if the two drift, the client offers a composer whose
/// submission the server then refuses, which reads as a bug rather than a rule.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/features/reviews/application/review_prompt_policy.dart';
import 'package:nyumba_property_management/features/reviews/domain/landlord_review.dart';

const _policy = ReviewPromptPolicy();
final _now = DateTime.utc(2026, 7, 1);

ReviewPromptCandidate _candidate({bool hasEnded = false}) =>
    ReviewPromptCandidate(
      leaseId: 'lease-1',
      landlordId: 'landlord-1',
      propertyName: 'Kireka Heights',
      unitLabel: 'B4',
      stayMonths: 14,
      hasEnded: hasEnded,
    );

void main() {
  group('eligibility mirrors the server gate', () {
    test('blocks an active tenancy under 30 days old', () {
      expect(
        ReviewEligibility.isEligible(
          activatedAt: _now.subtract(const Duration(days: 20)),
          endedAt: null,
          hasEnded: false,
          now: _now,
        ),
        isFalse,
      );
    });

    test('allows an active tenancy past 30 days', () {
      expect(
        ReviewEligibility.isEligible(
          activatedAt: _now.subtract(const Duration(days: 31)),
          endedAt: null,
          hasEnded: false,
          now: _now,
        ),
        isTrue,
      );
    });

    test('allows a short tenancy once it has ended', () {
      // A stay cut short after three weeks is often the most informative review
      // there is; `stayMonths` tells readers how long it lasted.
      expect(
        ReviewEligibility.isEligible(
          activatedAt: _now.subtract(const Duration(days: 21)),
          endedAt: _now.subtract(const Duration(days: 1)),
          hasEnded: true,
          now: _now,
        ),
        isTrue,
      );
    });

    test('closes 90 days after the tenancy ended', () {
      expect(
        ReviewEligibility.isEligible(
          activatedAt: _now.subtract(const Duration(days: 400)),
          endedAt: _now.subtract(const Duration(days: 91)),
          hasEnded: true,
          now: _now,
        ),
        isFalse,
      );
    });

    test('rejects a tenancy that never started', () {
      expect(
        ReviewEligibility.isEligible(
          activatedAt: null,
          endedAt: null,
          hasEnded: false,
          now: _now,
        ),
        isFalse,
      );
    });
  });

  group('interruptive prompts', () {
    test('fire on a resolved repair and on a tenancy ending', () {
      for (final trigger in const [
        ReviewPromptTrigger.maintenanceResolved,
        ReviewPromptTrigger.tenancyEnded,
      ]) {
        expect(
          _policy.shouldInterrupt(
            trigger: trigger,
            candidate: _candidate(),
            existingReview: null,
            state: const ReviewPromptState(),
            now: _now,
          ),
          isTrue,
          reason: '$trigger should be able to raise a prompt',
        );
      }
    });

    test('never fire for the passive card', () {
      // The card is an entry point, not an interruption; treating it as one
      // would put it behind the dismissal budget and eventually hide it.
      expect(
        _policy.shouldInterrupt(
          trigger: ReviewPromptTrigger.passiveCard,
          candidate: _candidate(),
          existingReview: null,
          state: const ReviewPromptState(),
          now: _now,
        ),
        isFalse,
      );
    });

    test('respect the 30-day interval', () {
      final recent = ReviewPromptState(
        lastPromptedAt: _now.subtract(const Duration(days: 5)),
      );
      expect(
        _policy.shouldInterrupt(
          trigger: ReviewPromptTrigger.maintenanceResolved,
          candidate: _candidate(),
          existingReview: null,
          state: recent,
          now: _now,
        ),
        isFalse,
      );
      expect(
        _policy.shouldInterrupt(
          trigger: ReviewPromptTrigger.maintenanceResolved,
          candidate: _candidate(),
          existingReview: null,
          state: recent,
          now: _now.add(const Duration(days: 26)),
        ),
        isTrue,
      );
    });

    test('stop permanently after two dismissals', () {
      var state = const ReviewPromptState().recordDismissal();
      expect(state.optedOut, isFalse);
      state = state.recordDismissal();
      // Two declines is an answer.
      expect(state.optedOut, isTrue);
      expect(
        _policy.shouldInterrupt(
          trigger: ReviewPromptTrigger.tenancyEnded,
          candidate: _candidate(hasEnded: true),
          existingReview: null,
          state: state,
          now: _now.add(const Duration(days: 400)),
        ),
        isFalse,
      );
    });

    test('honour an explicit "do not ask again" on the first decline', () {
      expect(
        const ReviewPromptState().recordDismissal(permanent: true).optedOut,
        isTrue,
      );
    });

    test('never fire when there is nothing to review', () {
      expect(
        _policy.shouldInterrupt(
          trigger: ReviewPromptTrigger.tenancyEnded,
          candidate: null,
          existingReview: null,
          state: const ReviewPromptState(),
          now: _now,
        ),
        isFalse,
      );
    });
  });

  group('the passive card', () {
    test('survives a permanent opt-out from the popup', () {
      // Declining an interruption means "not now", not "remove the feature".
      // This is the deliberate route for someone who later decides to write one.
      expect(
        _policy.shouldShowCard(candidate: _candidate(), existingReview: null),
        isTrue,
      );
    });

    test('disappears once the tenancy has been reviewed', () {
      expect(
        _policy.shouldShowCard(
          candidate: _candidate(),
          existingReview: LandlordReview(
            id: 'lease-1',
            landlordId: 'landlord-1',
            propertyName: 'Kireka Heights',
            unitLabel: 'B4',
            reviewerLabel: 'You',
            overall: 4,
            status: ReviewStatus.published,
            flagState: ReviewFlagState.none,
            stayMonths: 14,
            createdAt: _now,
            updatedAt: _now,
            syncMetadata: const SyncMetadata.synced(),
          ),
        ),
        isFalse,
      );
    });
  });
}
