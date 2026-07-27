import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nyumba_property_management/core/localization/localized_material.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/async_action_button.dart';
import '../application/review_prompt_policy.dart';
import '../application/review_providers.dart';
import '../domain/landlord_review.dart';
import '../domain/review_repository.dart';
import 'review_visuals.dart';

/// The one place a review is authored, whatever brought the tenant here.
///
/// Every entry point — the post-maintenance prompt, the end-of-tenancy prompt,
/// the home card, the reviews screen, and editing an existing review — opens
/// this same sheet. Only the heading changes with the trigger, so a tenant who
/// starts from one route and finishes from another sees the same form.
Future<bool> showReviewComposer(
  BuildContext context, {
  required ReviewPromptCandidate candidate,
  LandlordReview? existing,
  ReviewPromptTrigger trigger = ReviewPromptTrigger.passiveCard,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => _ReviewComposer(
      candidate: candidate,
      existing: existing,
      trigger: trigger,
    ),
  );
  return saved ?? false;
}

class _ReviewComposer extends ConsumerStatefulWidget {
  const _ReviewComposer({
    required this.candidate,
    required this.existing,
    required this.trigger,
  });

  final ReviewPromptCandidate candidate;
  final LandlordReview? existing;
  final ReviewPromptTrigger trigger;

  @override
  ConsumerState<_ReviewComposer> createState() => _ReviewComposerState();
}

class _ReviewComposerState extends ConsumerState<_ReviewComposer> {
  late int _overall = widget.existing?.overall ?? 0;
  late final Map<ReviewDimension, int> _scores = <ReviewDimension, int>{
    ...?widget.existing?.scores,
  };
  late final TextEditingController _body = TextEditingController(
    text: widget.existing?.body ?? '',
  );
  bool _showDetail = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // An existing review already has detail worth showing; a new one starts
    // collapsed so the ask is one tap, not a form.
    _showDetail = (widget.existing?.scores.isNotEmpty ?? false);
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  /// Framing, not just wording: the heading has to connect the ask to whatever
  /// the tenant just did, or it reads as an unprompted survey.
  String get _heading => switch (widget.trigger) {
    ReviewPromptTrigger.maintenanceResolved => 'How was that repair handled?',
    ReviewPromptTrigger.tenancyEnded =>
      'How was living at ${widget.candidate.propertyName}?',
    ReviewPromptTrigger.passiveCard =>
      widget.existing == null ? 'Rate your landlord' : 'Edit your review',
  };

  String get _subheading => switch (widget.trigger) {
    ReviewPromptTrigger.maintenanceResolved =>
      'Your rating covers the whole tenancy, not just this repair.',
    ReviewPromptTrigger.tenancyEnded =>
      'You can review for up to 90 days after moving out.',
    ReviewPromptTrigger.passiveCard =>
      'Help the next tenant know what to expect.',
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
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.localized(
              _heading,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text.localized(_subheading, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 18),

            // The whole required ask: one tap. Everything below is optional, and
            // a tenant who taps a star and submits has left a valid review.
            Center(
              child: StarSelector(
                value: _overall,
                onChanged: (value) => setState(() {
                  _overall = value;
                  _error = null;
                }),
              ),
            ),
            if (_overall > 0)
              Center(
                child: Text.localized(switch (_overall) {
                  1 => 'Poor',
                  2 => 'Below expectations',
                  3 => 'Acceptable',
                  4 => 'Good',
                  _ => 'Excellent',
                }, style: theme.textTheme.labelLarge),
              ),
            const SizedBox(height: 14),

            if (!_showDetail)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => setState(() => _showDetail = true),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text.localized('Add more detail (optional)'),
                ),
              )
            else ...[
              for (final dimension in ReviewDimension.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text.localized(
                          reviewDimensionLabel(dimension),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      StarSelector(
                        value: _scores[dimension] ?? 0,
                        onChanged: (value) =>
                            setState(() => _scores[dimension] = value),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: _body,
                maxLines: 5,
                maxLength: 1500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What should the next tenant know?',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],

            const SizedBox(height: 6),
            _VisibilityNotice(propertyName: widget.candidate.propertyName),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text.localized(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.nyumba.danger,
                ),
              ),
            ],
            const SizedBox(height: 16),
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
                    enabled: _overall > 0,
                    onPressed: _submit,
                    child: Text.localized(
                      widget.existing == null ? 'Post review' : 'Save changes',
                    ),
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

  Future<void> _submit() async {
    if (_overall == 0) {
      setState(() => _error = 'Choose a star rating first.');
      return;
    }
    final body = _body.text.trim();
    try {
      if (widget.existing == null) {
        await ref.read(submitReviewProvider)(
          SubmitReviewInput(
            leaseId: widget.candidate.leaseId,
            landlordId: widget.candidate.landlordId,
            propertyName: widget.candidate.propertyName,
            unitLabel: widget.candidate.unitLabel,
            overall: _overall,
            stayMonths: widget.candidate.stayMonths,
            scores: _scores,
            body: body.isEmpty ? null : body,
          ),
        );
      } else {
        await ref.read(editReviewProvider)(
          EditReviewInput(
            reviewId: widget.existing!.id,
            overall: _overall,
            scores: _scores,
            body: body.isEmpty ? null : body,
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }
}

/// Says plainly who will be able to tell who wrote this.
///
/// A review is keyed to one of the landlord's own leases, so on a small
/// property they will know regardless. Implying anonymity we cannot deliver
/// would be the worse failure: a tenant writes something candid believing they
/// are protected, and finds out otherwise from their landlord.
class _VisibilityNotice extends StatelessWidget {
  const _VisibilityNotice({required this.propertyName});

  final String propertyName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.nyumba.warningTint,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.visibility_outlined,
            size: 18,
            color: context.nyumba.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.localized(
              'Your name is never shown publicly — readers see "Verified '
              'tenant". Your landlord will be able to tell the review came '
              'from your tenancy, and can reply to it in public. You can edit '
              'or remove it for 14 days.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
