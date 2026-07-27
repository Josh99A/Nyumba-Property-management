import 'package:flutter/material.dart' hide Text;

import 'package:nyumba_property_management/core/localization/localized_material.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../domain/landlord_review.dart';

/// Shared rating rendering. Kept in one place so a star means the same size,
/// colour, and rounding on a marketplace card, a profile page, and a composer.
const List<int> kStarValues = <int>[1, 2, 3, 4, 5];

String reviewDimensionLabel(ReviewDimension dimension) => switch (dimension) {
  ReviewDimension.responsiveness => 'Responsiveness',
  ReviewDimension.maintenance => 'Repairs and maintenance',
  ReviewDimension.listingAccuracy => 'Listing was accurate',
  ReviewDimension.depositFairness => 'Deposit handled fairly',
};

String reviewFlagReasonLabel(ReviewFlagReason reason) => switch (reason) {
  ReviewFlagReason.inaccurate => 'Factually inaccurate',
  ReviewFlagReason.abusive => 'Abusive or harassing',
  ReviewFlagReason.notMyTenant => 'Not written by my tenant',
  ReviewFlagReason.personalData => 'Contains personal information',
  ReviewFlagReason.spam => 'Spam or advertising',
};

/// Rounds to one decimal, matching how the server stores the average.
String formatRating(double value) => value.toStringAsFixed(1);

/// A stay of under a year reads better in months.
String formatStay(int months) {
  if (months < 12) return '$months month${months == 1 ? '' : 's'}';
  final years = months ~/ 12;
  final remainder = months % 12;
  final yearPart = '$years year${years == 1 ? '' : 's'}';
  return remainder == 0 ? yearPart : '$yearPart $remainder mo';
}

class StarRow extends StatelessWidget {
  const StarRow({required this.value, super.key, this.size = 18, this.color});

  final int value;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.nyumba.warning;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final star in kStarValues)
          Icon(
            star <= value ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: star <= value
                ? tint
                : Theme.of(context).colorScheme.outlineVariant,
          ),
      ],
    );
  }
}

/// The interactive star input.
///
/// Deliberately large touch targets and no half-stars: a five-point scale that
/// people can hit accurately on a phone beats a ten-point one they cannot.
class StarSelector extends StatelessWidget {
  const StarSelector({
    required this.value,
    required this.onChanged,
    super.key,
    this.enabled = true,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final star in kStarValues)
          Semantics(
            button: true,
            selected: star <= value,
            label: '$star star${star == 1 ? '' : 's'}',
            child: IconButton(
              onPressed: enabled ? () => onChanged(star) : null,
              iconSize: 34,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                star <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                color: star <= value
                    ? context.nyumba.warning
                    : Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
      ],
    );
  }
}

/// The compact badge on a marketplace card.
///
/// Three states, and the middle one is the point: a landlord below the display
/// threshold is shown as new rather than as unrated, because "no rating" and
/// "one bad rating" must not look the same.
class RatingBadge extends StatelessWidget {
  const RatingBadge({
    required this.average,
    required this.count,
    super.key,
    this.compact = false,
  });

  final double? average;
  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (average == null) {
      return Text.localized(
        count == 0 ? 'New on Nyumba' : 'Too few reviews yet',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: 16, color: context.nyumba.warning),
        const SizedBox(width: 3),
        Text(
          formatRating(average!),
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: 4),
          Text(
            '($count)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Five bars, one per star value, with the headline average beside them.
class RatingDistribution extends StatelessWidget {
  const RatingDistribution({required this.summary, super.key});

  final RatingSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (summary.count == 0) {
      return Text.localized(
        'No reviews yet.',
        style: theme.textTheme.bodyMedium,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatRating(summary.average!),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StarRow(value: summary.average!.round()),
                  Text.localized(
                    '${summary.count} review${summary.count == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        for (final star in kStarValues.reversed)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  child: Text(
                    '$star',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.end,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: summary.shareOf(star) / 100,
                      minHeight: 8,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        context.nyumba.warning,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 34,
                  child: Text(
                    '${summary.shareOf(star)}%',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
        if (summary.dimensionAverages.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final entry in summary.dimensionAverages.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text.localized(
                      reviewDimensionLabel(entry.key),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    formatRating(entry.value),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
