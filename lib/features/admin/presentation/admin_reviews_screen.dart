import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nyumba_property_management/core/localization/localized_material.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/async_action_button.dart';
import '../../../core/presentation/surface.dart';
import '../../reviews/application/review_providers.dart';
import '../../reviews/domain/landlord_review.dart';
import '../../reviews/presentation/review_visuals.dart';
import '../../tenant_portal/presentation/widgets/tenant_components.dart';

/// Adjudication queue for reported reviews.
///
/// Reviews arrive here from two directions — a landlord reporting one about
/// themselves, and a reader reporting one they saw — and neither is hidden by
/// the act of reporting. That is the point: the queue exists so a person
/// decides, and until a person has, the review stands.
class AdminReviewsScreen extends ConsumerWidget {
  const AdminReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(receivedReviewsProvider);

    return TenantPage(
      title: 'Review moderation',
      description:
          'Reported reviews stay public until a decision is made. Hiding one '
          'removes it from the landlord\'s rating; publishing dismisses the '
          'report.',
      children: [
        reviews.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => NyumbaSurface(
            child: Text.localized(
              'The moderation queue could not be loaded.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          data: (items) {
            final queue = items
                .where((review) => review.flagState == ReviewFlagState.pending)
                .toList(growable: false);
            final decided = items
                .where(
                  (review) =>
                      review.flagState == ReviewFlagState.upheld ||
                      review.flagState == ReviewFlagState.dismissed,
                )
                .toList(growable: false);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (queue.isEmpty)
                  NyumbaSurface(
                    padding: const EdgeInsets.symmetric(
                      vertical: 32,
                      horizontal: 24,
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.verified_outlined,
                          size: 34,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 10),
                        Text.localized(
                          'Nothing awaiting a decision.',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                  )
                else
                  for (final review in queue)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _ModerationCard(review: review),
                    ),
                if (decided.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  NyumbaSectionHeader(
                    title: 'Recently decided',
                    subtitle: '${decided.length} handled',
                  ),
                  const SizedBox(height: 10),
                  for (final review in decided.take(20))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _DecidedRow(review: review),
                    ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ModerationCard extends ConsumerWidget {
  const _ModerationCard({required this.review});

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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: context.nyumba.warningTint,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text.localized(
                  review.flagReasonCode == null
                      ? 'Reported'
                      : reviewFlagReasonLabel(review.flagReasonCode!),
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text.localized(
            'Tenancy of ${formatStay(review.stayMonths)} · still visible to '
            'the public',
            style: theme.textTheme.bodySmall,
          ),
          if (review.hasBody) ...[
            const SizedBox(height: 10),
            Text(review.body!, style: theme.textTheme.bodyMedium),
          ],
          if (review.flagNote != null) ...[
            const SizedBox(height: 8),
            Text(
              'Reporter note: ${review.flagNote}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AsyncActionButton(
                style: AsyncActionStyle.tonal,
                onPressed: () => ref.read(moderateReviewProvider)(
                  reviewId: review.id,
                  decision: ReviewModerationDecision.publish,
                ),
                child: Text.localized('Keep published'),
              ),
              AsyncActionButton(
                style: AsyncActionStyle.outlined,
                onPressed: () => ref.read(moderateReviewProvider)(
                  reviewId: review.id,
                  decision: ReviewModerationDecision.hide,
                ),
                child: Text.localized('Hide pending appeal'),
              ),
              AsyncActionButton(
                style: AsyncActionStyle.text,
                onPressed: () => ref.read(moderateReviewProvider)(
                  reviewId: review.id,
                  decision: ReviewModerationDecision.remove,
                ),
                child: Text.localized('Remove'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DecidedRow extends StatelessWidget {
  const _DecidedRow({required this.review});

  final LandlordReview review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        StarRow(value: review.overall, size: 14),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            review.propertyName,
            style: theme.textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text.localized(switch (review.status) {
          ReviewStatus.published => 'Kept',
          ReviewStatus.hidden => 'Hidden',
          ReviewStatus.removed => 'Removed',
          ReviewStatus.withdrawn => 'Withdrawn',
        }, style: theme.textTheme.labelSmall),
      ],
    );
  }
}
