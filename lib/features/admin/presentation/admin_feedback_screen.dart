import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nyumba_property_management/core/localization/localized_material.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/offline/offline_entity.dart';
import '../../../core/presentation/surface.dart';
import '../../feedback/data/sembast_feedback_repository.dart';
import '../../feedback/domain/platform_feedback.dart';
import '../../tenant_portal/presentation/widgets/tenant_components.dart';

/// Every landlord submission, newest first, with the rolling NPS above it.
///
/// Reads the canonical `platformFeedback` collection through the administrative
/// pull. There is no moderation and no reply path here on purpose: this is
/// telemetry, and the useful response to a detractor on a paid tier is an email
/// from a human, not a workflow inside the product they are unhappy with.
final adminFeedbackProvider = StreamProvider<List<PlatformFeedback>>((
  ref,
) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.database.watchEntities(OfflineEntityType.platformFeedback).map((
    items,
  ) {
    final parsed = items.map(PlatformFeedbackMapper.fromJson).toList()
      ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    return parsed;
  });
});

class AdminFeedbackScreen extends ConsumerWidget {
  const AdminFeedbackScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedback = ref.watch(adminFeedbackProvider);

    return TenantPage(
      title: 'Landlord feedback',
      description:
          'Private product feedback from landlords. Never shown publicly and '
          'never visible to tenants.',
      children: [
        feedback.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => NyumbaSurface(
            child: Text.localized(
              'Feedback could not be loaded.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          data: (items) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _NpsSummary(items: items),
              const SizedBox(height: 16),
              if (items.isEmpty)
                NyumbaSurface(
                  padding: const EdgeInsets.symmetric(
                    vertical: 32,
                    horizontal: 24,
                  ),
                  child: Text.localized(
                    'No feedback submitted yet.',
                    style: Theme.of(context).textTheme.titleSmall,
                    textAlign: TextAlign.center,
                  ),
                )
              else
                for (final entry in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _FeedbackTile(feedback: entry),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NpsSummary extends StatelessWidget {
  const _NpsSummary({required this.items});

  final List<PlatformFeedback> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scored = items
        .where((entry) => entry.kind == PlatformFeedbackKind.nps)
        .toList(growable: false);
    if (scored.isEmpty) {
      return NyumbaSurface(
        child: Text.localized(
          'No NPS responses yet.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    final promoters = scored.where((entry) => entry.isPromoter).length;
    final detractors = scored.where((entry) => entry.isDetractor).length;
    // Standard NPS: promoters minus detractors as a percentage, passives
    // counted in the denominator but contributing nothing.
    final nps = ((promoters - detractors) / scored.length * 100).round();
    return NyumbaSurface(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$nps',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: nps >= 0
                      ? context.nyumba.sageDark
                      : context.nyumba.danger,
                ),
              ),
              Text.localized(
                'Net promoter score',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(width: 26),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.localized(
                  '${scored.length} response${scored.length == 1 ? '' : 's'}',
                  style: theme.textTheme.bodyMedium,
                ),
                Text.localized(
                  '$promoters promoter${promoters == 1 ? '' : 's'} · '
                  '$detractors detractor${detractors == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackTile extends StatelessWidget {
  const _FeedbackTile({required this.feedback});

  final PlatformFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NyumbaSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (feedback.score != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: feedback.isDetractor
                        ? context.nyumba.dangerTint
                        : feedback.isPromoter
                        ? context.nyumba.sageTint
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${feedback.score}/10',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (feedback.category != null) ...[
                const SizedBox(width: 8),
                Text(
                  feedback.category!.name,
                  style: theme.textTheme.labelSmall,
                ),
              ],
              const Spacer(),
              Text(
                '${feedback.platform} · ${feedback.appVersion}',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          if (feedback.comment != null) ...[
            const SizedBox(height: 8),
            Text(feedback.comment!, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
