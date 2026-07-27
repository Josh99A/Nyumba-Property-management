import 'package:nyumba_property_management/features/reviews/domain/landlord_review.dart';

/// What just happened that might justify asking for a review.
///
/// Timing is most of what separates a review prompt people answer from one they
/// learn to dismiss on sight, so the moment is modelled explicitly rather than
/// left to whichever screen happens to call in.
enum ReviewPromptTrigger {
  /// A maintenance request the tenant filed was just marked resolved.
  ///
  /// The best moment there is. The tenant has just experienced the landlord's
  /// responsiveness first-hand, the outcome is fresh and concrete, and they are
  /// already looking at the thing being rated. Asking here reads as "how did
  /// that go?" rather than as a survey.
  maintenanceResolved,

  /// The tenancy just ended.
  ///
  /// The natural moment to review a whole experience, and it produces the most
  /// complete reviews — deposit handling is only knowable now. Also the last
  /// moment the tenant has any reason to open the app, so not asking here loses
  /// the review entirely.
  tenancyEnded,

  /// A dismissible card on the tenant's home screen.
  ///
  /// Not really a prompt: the always-available path for someone who wants to
  /// leave a review without waiting to be asked. Never modal, and exempt from
  /// the opt-out below — hiding the entry point because someone once dismissed a
  /// popup would take away the deliberate route along with the interruption.
  passiveCard,
}

// Moments deliberately NOT in ReviewPromptTrigger, and why:
//
//  - App launch / cold start. Interrupts an errand the user came to run and
//    attaches the request to nothing. The classic pattern people learn to
//    dismiss without reading.
//  - After recording a rent payment. The tenant has just parted with money; it
//    is the worst affective moment in the product to ask for a favour, and the
//    resulting scores measure the payment, not the landlord.
//  - After a maintenance request is *filed*. Nothing has happened yet.
//  - Immediately on tenancy start. No tenure, and the server would reject it.

/// Device-local prompt history for one lease.
final class ReviewPromptState {
  const ReviewPromptState({
    this.lastPromptedAt,
    this.dismissals = 0,
    this.optedOut = false,
  });

  final DateTime? lastPromptedAt;
  final int dismissals;

  /// Set by "don't ask me again", or reached after [maxDismissals] declines.
  final bool optedOut;

  ReviewPromptState recordPrompt(DateTime at) => ReviewPromptState(
    lastPromptedAt: at,
    dismissals: dismissals,
    optedOut: optedOut,
  );

  ReviewPromptState recordDismissal({bool permanent = false}) =>
      ReviewPromptState(
        lastPromptedAt: lastPromptedAt,
        dismissals: dismissals + 1,
        optedOut: permanent || dismissals + 1 >= maxDismissals,
      );

  /// Two declines is an answer. Continuing to ask past it does not produce
  /// reviews, it produces resentment and uninstalls.
  static const int maxDismissals = 2;

  /// A lease may raise a modal prompt at most this often.
  static const Duration promptInterval = Duration(days: 30);
}

/// A tenancy the tenant is eligible to review and has not yet reviewed.
final class ReviewPromptCandidate {
  const ReviewPromptCandidate({
    required this.leaseId,
    required this.landlordId,
    required this.propertyName,
    required this.unitLabel,
    required this.stayMonths,
    required this.hasEnded,
  });

  final String leaseId;
  final String landlordId;
  final String propertyName;
  final String unitLabel;
  final int stayMonths;
  final bool hasEnded;
}

/// Mirrors the server's eligibility gate in `commands/reviews.ts`.
///
/// Duplicated deliberately. The server is the authority and rejects anything
/// that fails these rules, but a client that cannot answer the same question
/// would have to offer the composer to everyone and surface the refusal as an
/// error after the fact — which reads as a bug, not as a rule.
final class ReviewEligibility {
  const ReviewEligibility._();

  /// REVIEW_MIN_TENANCY_DAYS on the server.
  static const Duration minimumTenancy = Duration(days: 30);

  /// REVIEW_POST_TENANCY_WINDOW_DAYS on the server.
  static const Duration postTenancyWindow = Duration(days: 90);

  static bool isEligible({
    required DateTime? activatedAt,
    required DateTime? endedAt,
    required bool hasEnded,
    required DateTime now,
  }) {
    if (activatedAt == null) return false;
    if (hasEnded) {
      final reference = endedAt ?? activatedAt;
      return !now.isAfter(reference.add(postTenancyWindow));
    }
    return !now.isBefore(activatedAt.add(minimumTenancy));
  }

  /// When an active tenancy becomes reviewable, for a "you can review from…"
  /// hint rather than a silently missing button.
  static DateTime eligibleFrom(DateTime activatedAt) =>
      activatedAt.add(minimumTenancy);
}

/// Decides whether a given moment should actually raise the prompt.
final class ReviewPromptPolicy {
  const ReviewPromptPolicy();

  /// The passive card is always available for an eligible, unreviewed tenancy.
  ///
  /// It is not gated on [ReviewPromptState] at all: dismissing an interruption
  /// says "not now", not "remove the way to do this".
  bool shouldShowCard({
    required ReviewPromptCandidate? candidate,
    required LandlordReview? existingReview,
  }) => candidate != null && existingReview == null;

  /// Whether an interruptive prompt is warranted right now.
  bool shouldInterrupt({
    required ReviewPromptTrigger trigger,
    required ReviewPromptCandidate? candidate,
    required LandlordReview? existingReview,
    required ReviewPromptState state,
    required DateTime now,
  }) {
    if (trigger == ReviewPromptTrigger.passiveCard) return false;
    if (candidate == null || existingReview != null) return false;
    if (state.optedOut) return false;
    final last = state.lastPromptedAt;
    if (last != null &&
        now.difference(last) < ReviewPromptState.promptInterval) {
      return false;
    }
    return true;
  }
}
