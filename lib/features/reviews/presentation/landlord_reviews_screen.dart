import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nyumba_property_management/core/localization/localized_material.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/async_action_button.dart';
import '../../../core/presentation/surface.dart';
import '../../tenant_portal/presentation/widgets/tenant_components.dart';
import '../application/review_providers.dart';
import '../domain/landlord_review.dart';
import 'review_visuals.dart';

/// What tenants have said about this landlord, and the two things they can do
/// about it: reply in public, or ask Nyumba to look at it.
///
/// There is deliberately no "delete" here. A landlord who could remove reviews
/// would make every rating on the platform meaningless, including the good ones
/// they want credit for.
class LandlordReviewsScreen extends ConsumerWidget {
  const LandlordReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(receivedReviewsProvider);
    final summary =
        ref.watch(receivedRatingProvider).value ?? RatingSummary.empty;

    return TenantPage(
      title: 'Reviews',
      description:
          'Tenants can review you after 30 days in one of your units. Replying '
          'in public is usually more persuasive than disputing.',
      children: [
        NyumbaSurface(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RatingDistribution(summary: summary),
              if (summary.count > 0 && !summary.isPublicallyDisplayable) ...[
                const SizedBox(height: 12),
                Text.localized(
                  'Your star rating is not shown on listings yet — it appears '
                  'once you have ${RatingSummary.publicDisplayMinimum} reviews. '
                  'Until then your listings show "New on Nyumba".',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        reviews.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => NyumbaSurface(
            child: Text.localized(
              'Reviews could not be loaded right now.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          data: (items) {
            final visible = items
                .where((review) => review.status != ReviewStatus.removed)
                .toList(growable: false);
            if (visible.isEmpty) {
              return NyumbaSurface(
                padding: const EdgeInsets.symmetric(
                  vertical: 36,
                  horizontal: 24,
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.reviews_outlined,
                      size: 36,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text.localized(
                      'No reviews yet.',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text.localized(
                      'Handling repairs quickly is the single biggest driver '
                      'of the ratings tenants leave.',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }
            return Column(
              children: [
                for (final review in visible)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: ReceivedReviewTile(review: review),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class ReceivedReviewTile extends ConsumerWidget {
  const ReceivedReviewTile({required this.review, super.key});

  final LandlordReview review;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
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
                  '${review.propertyName} · ${review.unitLabel}',
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text.localized(
                formatStay(review.stayMonths),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          if (review.scores.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final entry in review.scores.entries)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text.localized(
                      '${reviewDimensionLabel(entry.key)} ${entry.value}/5',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
          ],
          if (review.hasBody) ...[
            const SizedBox(height: 10),
            Text(review.body!, style: theme.textTheme.bodyMedium),
          ],
          if (review.status == ReviewStatus.hidden) ...[
            const SizedBox(height: 10),
            Text.localized(
              'Hidden from the public while Nyumba checks it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.nyumba.warning,
              ),
            ),
          ],
          if (review.flagState == ReviewFlagState.pending) ...[
            const SizedBox(height: 10),
            Text.localized(
              'You reported this review. It stays visible while we look at it.',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (review.hasResponse) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.localized(
                    'Your public reply',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    review.landlordResponse!,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              AsyncActionButton(
                style: AsyncActionStyle.tonal,
                showBusyIndicator: false,
                icon: const Icon(Icons.reply_rounded, size: 18),
                onPressed: () => _openReply(context, ref),
                child: Text.localized(
                  review.hasResponse ? 'Edit reply' : 'Reply publicly',
                ),
              ),
              const SizedBox(width: 8),
              if (review.flagState == ReviewFlagState.none)
                AsyncActionButton(
                  style: AsyncActionStyle.text,
                  showBusyIndicator: false,
                  onPressed: () => _openFlag(context, ref),
                  child: Text.localized('Report'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openReply(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(
      text: review.landlordResponse ?? '',
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.localized(
              'Reply in public',
              style: Theme.of(
                sheetContext,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text.localized(
              'Anyone reading this review will see your reply next to it. A '
              'calm, factual answer persuades far more readers than the review '
              'itself does.',
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              maxLines: 6,
              maxLength: 1500,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Your reply',
              ),
            ),
            const SizedBox(height: 8),
            AsyncActionButton.filled(
              onPressed: () async {
                await ref.read(respondToReviewProvider)(
                  reviewId: review.id,
                  response: controller.text,
                );
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              },
              child: Text.localized('Post reply'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _openFlag(BuildContext context, WidgetRef ref) async {
    var reason = ReviewFlagReason.inaccurate;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (builderContext, setState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.localized(
                'Report this review',
                style: Theme.of(builderContext).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              // Set the expectation up front. A landlord who believes reporting
              // is a takedown button will report everything and then feel
              // cheated; saying so here is what keeps the queue meaningful.
              Text.localized(
                'Nyumba will look at it. The review stays visible in the '
                'meantime — reporting is not a way to remove criticism.',
                style: Theme.of(builderContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final option in ReviewFlagReason.values)
                    ChoiceChip(
                      label: Text.localized(reviewFlagReasonLabel(option)),
                      selected: reason == option,
                      onSelected: (_) => setState(() => reason = option),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              AsyncActionButton.filled(
                onPressed: () async {
                  await ref.read(flagReviewProvider)(
                    reviewId: review.id,
                    reason: reason,
                  );
                  if (builderContext.mounted) {
                    Navigator.of(builderContext).pop();
                  }
                },
                child: Text.localized('Send report'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
