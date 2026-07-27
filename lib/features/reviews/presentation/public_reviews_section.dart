import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nyumba_property_management/core/localization/localized_material.dart';

import '../../../core/presentation/async_action_button.dart';
import '../../../core/presentation/surface.dart';
import '../application/review_providers.dart';
import '../domain/landlord_review.dart';
import 'review_visuals.dart';

/// The reputation block on a public listing.
///
/// Reads from the anonymous mirror, which carries no reviewer identity at all —
/// see `publicReviewProjection`. The headline figures come from the listing's
/// own denormalized badge because they are authoritative platform-wide, while
/// the distribution and individual entries come from the reviews fetched for
/// this landlord.
class PublicReviewsSection extends ConsumerWidget {
  const PublicReviewsSection({
    required this.landlordToken,
    required this.ratingAverage,
    required this.ratingCount,
    super.key,
  });

  final String landlordToken;
  final double? ratingAverage;
  final int ratingCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (landlordToken.trim().isEmpty) return const SizedBox.shrink();

    final reviews =
        ref.watch(publicReviewsProvider(landlordToken)).value ??
        const <LandlordReview>[];
    final withText = reviews.where((review) => review.hasBody).toList();

    return NyumbaSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NyumbaSectionHeader(
            title: 'Landlord reviews',
            subtitle: ratingCount == 0
                ? 'No tenant has reviewed this landlord yet.'
                : ratingAverage == null
                // The distinction that keeps the system honest: too few reviews
                // to average is not the same as no reviews, and neither is a bad
                // rating.
                ? '$ratingCount review${ratingCount == 1 ? '' : 's'} so far — '
                      'a star rating appears at '
                      '${RatingSummary.publicDisplayMinimum}.'
                : 'From tenants who actually lived in this landlord\'s units.',
            trailing: RatingBadge(average: ratingAverage, count: ratingCount),
          ),
          if (reviews.isNotEmpty) ...[
            const SizedBox(height: 16),
            RatingDistribution(summary: RatingSummary.from(reviews)),
          ],
          if (withText.isEmpty && ratingCount > 0) ...[
            const SizedBox(height: 12),
            Text.localized(
              'No written reviews yet — only star ratings.',
              style: theme.textTheme.bodySmall,
            ),
          ],
          for (final review in withText.take(5))
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _PublicReviewTile(review: review),
            ),
        ],
      ),
    );
  }
}

class _PublicReviewTile extends ConsumerWidget {
  const _PublicReviewTile({required this.review});

  final LandlordReview review;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            StarRow(value: review.overall, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text.localized(
                // The only provenance a public reader gets, and the one that
                // matters: this person actually lived there, for this long.
                'Verified tenant · ${formatStay(review.stayMonths)}',
                style: theme.textTheme.bodySmall,
              ),
            ),
            IconButton(
              tooltip: 'Report this review',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              onPressed: () => _report(context, ref),
              icon: const Icon(Icons.flag_outlined),
            ),
          ],
        ),
        if (review.hasBody)
          Text(review.body!, style: theme.textTheme.bodyMedium),
        if (review.hasResponse) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.localized(
                  'Landlord replied',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  review.landlordResponse!,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    var reason = ReviewFlagReason.abusive;
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
                style: Theme.of(
                  builderContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text.localized(
                'Nyumba will look at it. Reports do not hide a review.',
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
              const SizedBox(height: 12),
              AsyncActionButton.filled(
                onPressed: () async {
                  await ref.read(flagReviewProvider)(
                    reviewId: review.id,
                    reason: reason,
                    asReader: true,
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
