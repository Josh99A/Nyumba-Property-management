import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nyumba_property_management/core/localization/localized_material.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/async_action_button.dart';
import '../../../core/presentation/surface.dart';
import '../application/review_prompt_policy.dart';
import '../application/review_prompt_providers.dart';
import '../application/review_providers.dart';
import '../domain/landlord_review.dart';
import 'review_composer_sheet.dart';
import 'review_visuals.dart';

/// Raises the review prompt if — and only if — this moment warrants it.
///
/// Call this from the moment itself rather than from a screen's build: the
/// decision depends on what just happened, and a prompt that appears on every
/// rebuild of a screen is the pattern users learn to dismiss reflexively.
///
/// Silently does nothing in every "no" case. A caller must never have to know
/// why; the policy owns that, and adding a reason here would tempt call sites
/// into overriding it.
Future<void> maybePromptForReview(
  BuildContext context,
  WidgetRef ref, {
  required ReviewPromptTrigger trigger,
}) async {
  final candidate = ref.read(reviewCandidateProvider).value;
  if (candidate == null) return;
  final existing = ref
      .read(authoredReviewsProvider)
      .value
      ?.where((review) => review.id == candidate.leaseId)
      .firstOrNull;

  final store = ref.read(reviewPromptStoreProvider);
  final state = await store.read(candidate.leaseId);
  final now = DateTime.now().toUtc();
  if (!ref
      .read(reviewPromptPolicyProvider)
      .shouldInterrupt(
        trigger: trigger,
        candidate: candidate,
        existingReview: existing,
        state: state,
        now: now,
      )) {
    return;
  }
  // Recorded before the sheet opens, not after. If the app is killed mid-prompt
  // the ask still counts as made — otherwise a crash loop becomes a nag loop.
  await store.write(candidate.leaseId, state.recordPrompt(now));
  if (!context.mounted) return;

  final submitted = await showReviewComposer(
    context,
    candidate: candidate,
    trigger: trigger,
  );
  if (!submitted) {
    await store.write(
      candidate.leaseId,
      (await store.read(candidate.leaseId)).recordDismissal(),
    );
  }
}

/// The always-available entry point on the tenant's home screen.
///
/// Not gated on dismissal history: declining an interruption means "not now",
/// not "take away the way to do this". This is also the surface a tenant
/// returns to when they decide on their own that they want to leave a review,
/// which is the higher-quality path of the two.
class ReviewPromptCard extends ConsumerWidget {
  const ReviewPromptCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final candidate = ref.watch(reviewCandidateProvider).value;
    final theme = Theme.of(context);

    if (candidate == null) {
      final eligibleFrom = ref.watch(reviewEligibilityHintProvider);
      if (eligibleFrom == null) return const SizedBox.shrink();
      // Explain the wait rather than showing nothing.
      return NyumbaSurface(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.schedule_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text.localized(
                'You can review your landlord after 30 days in your home.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }

    final existing = ref
        .watch(authoredReviewsProvider)
        .value
        ?.where((review) => review.id == candidate.leaseId)
        .firstOrNull;
    if (!ref
        .watch(reviewPromptPolicyProvider)
        .shouldShowCard(candidate: candidate, existingReview: existing)) {
      return const SizedBox.shrink();
    }

    return NyumbaSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: context.nyumba.warningTint,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.star_rounded,
                  size: 22,
                  color: context.nyumba.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.localized(
                      candidate.hasEnded
                          ? 'Review your former landlord'
                          : 'Rate your landlord',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      candidate.propertyName,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text.localized(
            'You have lived here ${formatStay(candidate.stayMonths)}. Your '
            'review helps the next tenant and stays anonymous in public.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AsyncActionButton.filled(
              showBusyIndicator: false,
              icon: const Icon(Icons.rate_review_outlined, size: 18),
              onPressed: () async {
                await showReviewComposer(
                  context,
                  candidate: candidate,
                  // The card is never an interruption, so the composer opens in
                  // its neutral framing rather than a moment-specific one.
                  trigger: ReviewPromptTrigger.passiveCard,
                );
              },
              child: Text.localized('Write a review'),
            ),
          ),
        ],
      ),
    );
  }
}

/// One review as the author sees it, with the actions still open to them.
class AuthoredReviewTile extends ConsumerWidget {
  const AuthoredReviewTile({required this.review, super.key});

  final LandlordReview review;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = DateTime.now().toUtc();
    final editable = review.editableAt(now);
    return NyumbaSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StarRow(value: review.overall),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  review.propertyName,
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (review.status != ReviewStatus.published)
                _StatusChip(status: review.status),
            ],
          ),
          if (review.hasBody) ...[
            const SizedBox(height: 10),
            Text(review.body!, style: theme.textTheme.bodyMedium),
          ],
          if (review.status == ReviewStatus.hidden) ...[
            const SizedBox(height: 10),
            Text.localized(
              'Nyumba has hidden this review while it is checked. You can '
              'still see it here.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.nyumba.warning,
              ),
            ),
          ],
          if (review.hasResponse) ...[
            const SizedBox(height: 12),
            _ResponseBlock(response: review.landlordResponse!),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (editable) ...[
                AsyncActionButton(
                  style: AsyncActionStyle.text,
                  showBusyIndicator: false,
                  onPressed: () async {
                    await showReviewComposer(
                      context,
                      candidate: ReviewPromptCandidate(
                        leaseId: review.id,
                        landlordId: review.landlordId,
                        propertyName: review.propertyName,
                        unitLabel: review.unitLabel,
                        stayMonths: review.stayMonths,
                        hasEnded: false,
                      ),
                      existing: review,
                    );
                  },
                  child: Text.localized('Edit'),
                ),
                AsyncActionButton(
                  style: AsyncActionStyle.text,
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text.localized('Remove this review?'),
                        content: const Text.localized(
                          'This cannot be undone. The review will no longer be visible to '
                          'anyone, including your landlord.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, false),
                            child: const Text.localized('Keep review'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: const Text.localized('Remove'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await ref.read(withdrawReviewProvider)(review.id);
                    }
                  },
                  child: Text.localized('Remove'),
                ),
              ] else
                Text.localized(
                  'The 14-day edit window has closed.',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ReviewStatus status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      ReviewStatus.published => 'Published',
      ReviewStatus.withdrawn => 'Removed by you',
      ReviewStatus.hidden => 'Under review',
      ReviewStatus.removed => 'Taken down',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text.localized(
        label,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _ResponseBlock extends StatelessWidget {
  const _ResponseBlock({required this.response});

  final String response;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.localized(
            'Reply from the landlord',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(response, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
