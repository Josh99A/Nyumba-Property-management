import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';

import '../../app/theme/nyumba_colors.dart';
import '../domain/domain_exception.dart';
import '../localization/nyumba_localizations.dart';

/// A failed action, explained the way a landlord would explain it.
///
/// [message] never contains an exception name, a field key, or a stack frame;
/// everything technical goes into [details], which the UI keeps folded away.
final class ActionFailure {
  const ActionFailure({required this.message, this.details});

  /// One or two plain sentences saying what went wrong and, where there is
  /// one, what to do about it.
  final String message;

  /// The raw error, for diagnosis. Null when the message already says
  /// everything there is to know.
  final String? details;
}

/// Turns a caught error into something worth showing a landlord.
///
/// [action] completes the sentence "Nyumba could not …" — for example
/// `'save this property'`. Screens used to render `caught.toString()`, which
/// produced lines like `DomainValidationException: imageUrls: must contain at
/// most 5 images`: accurate, and useless to the person who has to fix it.
ActionFailure describeActionFailure(Object error, {required String action}) {
  final raw = error.toString();

  if (error is DomainValidationException) {
    return ActionFailure(
      message: error.errors.entries
          .map((entry) => _fieldSentence(entry.key, entry.value))
          .join(' '),
      details: raw,
    );
  }

  if (error is EntityNotFoundException) {
    return ActionFailure(
      message:
          'Nyumba could not $action because the ${_entityNoun(error.entityType)} '
          'it refers to no longer exists. It may have been archived on another '
          'device. Refresh and try again.',
      details: raw,
    );
  }

  if (error is EntityAlreadyExistsException) {
    return ActionFailure(
      message:
          'That ${_entityNoun(error.entityType)} already exists, so Nyumba did '
          'not $action again.',
      details: raw,
    );
  }

  final lower = raw.toLowerCase();

  if (lower.contains('permission is required') ||
      lower.contains('permission-denied') ||
      lower.contains('permission_denied')) {
    return ActionFailure(
      message:
          'Your account is not allowed to $action. Ask the account owner to '
          'give you access, then sign out and back in.',
      details: raw,
    );
  }

  // Browsers and phones both refuse writes once their storage allowance is
  // spent. Photos are by far the biggest thing Nyumba stores locally, so say
  // so rather than leaving the landlord guessing.
  if (lower.contains('quotaexceeded') ||
      lower.contains('quota_exceeded') ||
      lower.contains('quota exceeded') ||
      lower.contains('no space left') ||
      lower.contains('storage full')) {
    return ActionFailure(
      message:
          'This device has run out of space for offline data, so Nyumba could '
          'not $action. Photos take up the most room — try adding fewer or '
          'smaller ones, or free up space and try again.',
      details: raw,
    );
  }

  if (lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('connection refused') ||
      lower.contains('network is unreachable') ||
      lower.contains('unavailable')) {
    return ActionFailure(
      message:
          'Nyumba could not reach the server. Your work is kept on this device '
          'and will sync once you are back online.',
      details: raw,
    );
  }

  return ActionFailure(
    message:
        'Nyumba could not $action. Nothing was changed. Try again, and if it '
        'keeps happening send the technical details below to support.',
    details: raw,
  );
}

/// "imageUrls" + "must contain at most 5 images" → "Photos must contain at
/// most 5 images."
String _fieldSentence(String field, String problem) {
  final label = _fieldLabels[field] ?? _humanizeField(field);
  final normalized = problem.trim();
  final sentence = '$label $normalized';
  return sentence.endsWith('.') ? sentence : '$sentence.';
}

const Map<String, String> _fieldLabels = {
  'imageUrls': 'Photos',
  'landlordId': 'The landlord account',
  'addressLine': 'The street address',
  'name': 'The name',
  'city': 'The city or town',
  'country': 'The country',
  'description': 'The description',
  'label': 'The label',
  'unit.status': 'The rental space status',
  'property': 'This property',
  'listing': 'This listing',
  'unit': 'This rental space',
  'monthlyRentMinor': 'The monthly rent',
  'currency': 'The currency',
  'updatedAt': 'The last-updated time',
  'archivedAt': 'The archived date',
};

/// Fallback for a field with no hand-written label: "monthlyRentMinor" →
/// "The monthly rent minor".
String _humanizeField(String field) {
  final words = field
      .split('.')
      .last
      .replaceAllMapped(
        RegExp('[A-Z]'),
        (match) => ' ${match[0]!.toLowerCase()}',
      )
      .trim();
  return 'The ${words.isEmpty ? field : words}';
}

String _entityNoun(String entityType) => switch (entityType) {
  'unit' => 'rental space',
  _ => entityType,
};

/// A red, always-visible explanation of why the action in a form or dialog did
/// not go through.
///
/// Dialogs used to put this at the bottom of a scrolling column, below the
/// fold, so a landlord who pressed Save saw nothing move. This is meant to be
/// pinned outside the scroll view, directly above the buttons.
class ActionFailureNotice extends StatefulWidget {
  const ActionFailureNotice({required this.failure, super.key});

  final ActionFailure failure;

  @override
  State<ActionFailureNotice> createState() => _ActionFailureNoticeState();
}

class _ActionFailureNoticeState extends State<ActionFailureNotice> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = widget.failure.details;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.nyumba.dangerTint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.nyumba.dangerBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 20,
                color: context.nyumba.danger,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.localized(
                  widget.failure.message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: context.nyumba.ink,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          if (details != null) ...[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => setState(() => _showDetails = !_showDetails),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
                child: Text(
                  context.tr(
                    _showDetails
                        ? 'Hide technical details'
                        : 'Technical details',
                  ),
                ),
              ),
            ),
            if (_showDetails)
              SelectableText(
                details,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// The same explanation, for the amber "some of what you chose was not added"
/// case, which is a warning rather than a failure.
class PickProblemsNotice extends StatelessWidget {
  const PickProblemsNotice({required this.problems, super.key});

  final List<String> problems;

  @override
  Widget build(BuildContext context) {
    if (problems.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.nyumba.goldTint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.nyumba.goldBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: context.nyumba.terracottaDark,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final problem in problems)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text.localized(
                      problem,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.nyumba.ink,
                        height: 1.35,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
