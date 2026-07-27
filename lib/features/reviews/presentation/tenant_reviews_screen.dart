import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nyumba_property_management/core/localization/localized_material.dart';

import '../../../core/presentation/surface.dart';
import '../../tenant_portal/presentation/widgets/tenant_components.dart';
import '../application/review_prompt_providers.dart';
import '../application/review_providers.dart';
import '../domain/landlord_review.dart';
import 'review_prompt.dart';

/// The tenant's own reviews, and the deliberate way in to writing one.
///
/// The prompts elsewhere are opportunistic — they catch someone at a good
/// moment. This screen is the opposite and matters just as much: somebody who
/// has decided on their own that they want to say something needs a route that
/// does not depend on the app having asked them first. It is also the only place
/// a review that was hidden, withdrawn, or replied to can be seen after the fact.
class TenantReviewsScreen extends ConsumerWidget {
  const TenantReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(authoredReviewsProvider);
    final candidate = ref.watch(reviewCandidateProvider).value;

    return TenantPage(
      title: 'Your reviews',
      description:
          'Reviews you have written about your landlord. Published reviews '
          'appear on their listings without your name.',
      children: [
        if (candidate != null) ...[
          const ReviewPromptCard(),
          const SizedBox(height: 16),
        ],
        reviews.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => NyumbaSurface(
            child: Text.localized(
              'Your reviews could not be loaded. They are safe — try again '
              'when you are back online.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          data: (items) => items.isEmpty
              ? _EmptyState(hasCandidate: candidate != null)
              : Column(
                  children: [
                    for (final review in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: AuthoredReviewTile(review: review),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasCandidate});

  final bool hasCandidate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NyumbaSurface(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(
        children: [
          Icon(
            Icons.rate_review_outlined,
            size: 36,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text.localized(
            'You have not written a review yet.',
            style: theme.textTheme.titleSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text.localized(
            hasCandidate
                ? 'Use the card above whenever you are ready.'
                : 'You can review a landlord after 30 days in your home, and '
                      'for up to 90 days after you move out.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// A single row for the tenant home screen's quick-links list.
///
/// Small on purpose: this is a signpost to [TenantReviewsScreen], not a second
/// place where reviews are managed. Two surfaces that both half-manage reviews
/// would leave neither trustworthy as the complete picture.
class TenantReviewsLink extends ConsumerWidget {
  const TenantReviewsLink({required this.onOpen, super.key});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews =
        ref.watch(authoredReviewsProvider).value ?? const <LandlordReview>[];
    final awaitingReply = reviews.where((review) => review.hasResponse).length;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.star_outline_rounded),
      title: Text.localized('Your reviews'),
      subtitle: Text.localized(
        reviews.isEmpty
            ? 'Rate your landlord'
            : awaitingReply > 0
            ? '${reviews.length} written · $awaitingReply replied to'
            : '${reviews.length} written',
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onOpen,
    );
  }
}
