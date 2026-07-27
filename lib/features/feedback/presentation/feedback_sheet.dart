import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nyumba_property_management/core/localization/localized_material.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/async_action_button.dart';
import '../application/feedback_providers.dart';
import '../domain/platform_feedback.dart';

String currentPlatformName() {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 'ios',
    TargetPlatform.android => 'android',
    // Desktop builds are development targets; reporting them as web keeps the
    // server's enum closed rather than adding values nothing analyses.
    _ => 'web',
  };
}

/// The recurring "how are we doing" question.
///
/// Deliberately answerable in one tap. The score is the deliverable; the comment
/// box is optional and appears only after a score is chosen, so nobody faces a
/// blank text field as the price of answering.
Future<void> showNpsSheet(
  BuildContext context, {
  required String appVersion,
  required FeedbackPromptMilestone milestone,
  required Future<void> Function({required bool permanent}) onDismissed,
}) async {
  final submitted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) =>
        _NpsSheet(appVersion: appVersion, milestone: milestone),
  );
  if (submitted != true) await onDismissed(permanent: false);
}

/// The always-available route, from landlord settings.
///
/// This is the entry point that produces actionable bugs. NPS produces a number
/// to trend; someone who came here on purpose has something specific to say.
Future<void> showFeedbackSheet(
  BuildContext context, {
  required String appVersion,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (sheetContext) => _FreeformSheet(appVersion: appVersion),
);

class _NpsSheet extends ConsumerStatefulWidget {
  const _NpsSheet({required this.appVersion, required this.milestone});

  final String appVersion;
  final FeedbackPromptMilestone milestone;

  @override
  ConsumerState<_NpsSheet> createState() => _NpsSheetState();
}

class _NpsSheetState extends ConsumerState<_NpsSheet> {
  int? _score;
  final TextEditingController _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  /// Names what just went right, so the question reads as a follow-up rather
  /// than an ambush.
  String get _context => switch (widget.milestone) {
    FeedbackPromptMilestone.paymentsRecorded =>
      'You have recorded ten rent payments in Nyumba.',
    FeedbackPromptMilestone.firstApplication =>
      'Your listing just received its first application.',
    FeedbackPromptMilestone.establishedSubscription =>
      'You have been managing your properties here for a month.',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.localized(_context, style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Text.localized(
              'How likely are you to recommend Nyumba to another landlord?',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var value = 0; value <= 10; value += 1)
                  ChoiceChip(
                    label: Text('$value'),
                    selected: _score == value,
                    onSelected: (_) => setState(() => _score = value),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text.localized('Not likely', style: theme.textTheme.bodySmall),
                Text.localized('Very likely', style: theme.textTheme.bodySmall),
              ],
            ),
            if (_score != null) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _comment,
                maxLines: 3,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: _score! <= 6
                      ? 'What is not working? (optional)'
                      : 'What works best for you? (optional)',
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: AsyncActionButton(
                    style: AsyncActionStyle.text,
                    showBusyIndicator: false,
                    onPressed: () async => Navigator.of(context).pop(false),
                    child: Text.localized('Not now'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: AsyncActionButton.filled(
                    enabled: _score != null,
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      await ref.read(submitFeedbackProvider)(
                        kind: PlatformFeedbackKind.nps,
                        score: _score,
                        comment: _comment.text,
                        appVersion: widget.appVersion,
                        platform: currentPlatformName(),
                      );
                      if (mounted) navigator.pop(true);
                    },
                    child: Text.localized('Send'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _FreeformSheet extends ConsumerStatefulWidget {
  const _FreeformSheet({required this.appVersion});

  final String appVersion;

  @override
  ConsumerState<_FreeformSheet> createState() => _FreeformSheetState();
}

class _FreeformSheetState extends ConsumerState<_FreeformSheet> {
  PlatformFeedbackCategory _category = PlatformFeedbackCategory.bug;
  final TextEditingController _comment = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  static String _label(PlatformFeedbackCategory category) => switch (category) {
    PlatformFeedbackCategory.bug => 'Something is broken',
    PlatformFeedbackCategory.featureRequest => 'I need a feature',
    PlatformFeedbackCategory.easeOfUse => 'Hard to use',
    PlatformFeedbackCategory.valueForMoney => 'Pricing and value',
    PlatformFeedbackCategory.support => 'Support',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.localized(
              'Send feedback',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text.localized(
              'This goes straight to the Nyumba team. It is not published '
              'anywhere and your tenants never see it.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final category in PlatformFeedbackCategory.values)
                  ChoiceChip(
                    label: Text.localized(_label(category)),
                    selected: _category == category,
                    onSelected: (_) => setState(() => _category = category),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _comment,
              maxLines: 6,
              maxLength: 1500,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'What happened, and what did you expect?',
              ),
            ),
            Text.localized(
              // Stated rather than silently attached: people should know what
              // leaves their device.
              'Your app version and device type are attached so we can '
              'reproduce it.',
              style: theme.textTheme.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text.localized(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.nyumba.danger,
                ),
              ),
            ],
            const SizedBox(height: 12),
            AsyncActionButton.filled(
              onPressed: () async {
                final navigator = Navigator.of(context);
                try {
                  await ref.read(submitFeedbackProvider)(
                    kind: PlatformFeedbackKind.freeform,
                    comment: _comment.text,
                    category: _category,
                    appVersion: widget.appVersion,
                    platform: currentPlatformName(),
                  );
                  if (mounted) navigator.pop();
                } on Object catch (error) {
                  if (mounted) setState(() => _error = error.toString());
                }
              },
              child: Text.localized('Send feedback'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
