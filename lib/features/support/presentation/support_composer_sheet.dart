import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nyumba_property_management/core/localization/localized_material.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/async_action_button.dart';
import '../../../core/presentation/responsive.dart';
import '../../feedback/application/feedback_providers.dart';
import '../../feedback/presentation/feedback_sheet.dart' show currentPlatformName;
import '../application/support_providers.dart';
import '../domain/support_ticket.dart';
import 'support_visuals.dart';

/// Opens the composer, prefilled with whatever the caller already knows.
///
/// The prefill arguments are the whole reason this is a function rather than a
/// route: the useful moment to contact support is the moment something failed,
/// and the screen that failed knows the category and the fact. It fills in the
/// facts and never the complaint — "My subscription payment was rejected on
/// 12 Aug" is context; anything stronger is putting words in someone's mouth.
///
/// Returns the new ticket's ID when one was opened, so the caller can push
/// straight into the thread.
Future<String?> showSupportComposer(
  BuildContext context, {
  SupportCategory? category,
  String? subject,
  String? body,
}) {
  final sheet = _SupportComposer(
    initialCategory: category,
    initialSubject: subject,
    initialBody: body,
  );
  if (context.isCompact) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => sheet,
    );
  }
  return showDialog<String>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: sheet,
      ),
    ),
  );
}

class _SupportComposer extends ConsumerStatefulWidget {
  const _SupportComposer({
    this.initialCategory,
    this.initialSubject,
    this.initialBody,
  });

  final SupportCategory? initialCategory;
  final String? initialSubject;
  final String? initialBody;

  @override
  ConsumerState<_SupportComposer> createState() => _SupportComposerState();
}

class _SupportComposerState extends ConsumerState<_SupportComposer> {
  late SupportCategory _category =
      widget.initialCategory ?? SupportCategory.other;
  late final TextEditingController _subject = TextEditingController(
    text: widget.initialSubject ?? '',
  );
  late final TextEditingController _body = TextEditingController(
    text: widget.initialBody ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final navigator = Navigator.of(context);
    final appVersion = await ref.read(appVersionProvider.future);
    try {
      final ticket = await ref
          .read(supportActionsProvider)
          .open(
            subject: _subject.text,
            category: _category,
            body: _body.text,
            appVersion: appVersion,
            platform: currentPlatformName(),
          );
      if (mounted) navigator.pop(ticket.id);
    } on Object catch (error) {
      // Inline, never a snackbar: a snackbar dismisses the sheet's error with
      // the typed message still unsent and no way back to it.
      if (mounted) setState(() => _error = _readable(error));
    }
  }

  /// Turns the two rejections a landlord can actually hit into sentences they
  /// can act on. Everything else falls through to its own message.
  String _readable(Object error) {
    final text = error.toString();
    if (text.contains('tooManyOpenTickets')) {
      return 'You already have three conversations open with us. Reply on one '
          'of those and we will pick it up there.';
    }
    if (text.contains('RATE_LIMITED')) {
      return 'That was sent a moment ago. Give it a minute before starting '
          'another conversation.';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: context.isCompact ? 0 : 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.localized(
              'Message support',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            // The expectation is set once, here, where it is being made.
            Text.localized(
              'We usually reply within one working day.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Text.localized(
              'What is this about?',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            // Category first, so the opening interaction is a tap rather than a
            // blank field — the same reason the NPS sheet leads with the score.
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final category in SupportCategory.values)
                  ChoiceChip(
                    label: Text.localized(supportCategoryLabel(category)),
                    selected: _category == category,
                    onSelected: (_) => setState(() => _category = category),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _subject,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Subject',
                hintText: 'Payment not reconciling',
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _body,
              maxLines: 6,
              maxLength: 5000,
              autofocus: widget.initialBody == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'What happened, and what did you expect?',
              ),
            ),
            // Stated rather than silently attached: people should know what
            // leaves their device.
            Text.localized(
              'Your plan, app version and device are attached so we can look '
              'into it.',
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
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: AsyncActionButton(
                    style: AsyncActionStyle.text,
                    showBusyIndicator: false,
                    onPressed: () async => Navigator.of(context).pop(),
                    child: const Text.localized('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: AsyncActionButton.filled(
                    onPressed: _send,
                    child: const Text.localized('Send message'),
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
