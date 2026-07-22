import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/async_action_button.dart';

class PropertyArchiveButton extends StatelessWidget {
  const PropertyArchiveButton({
    required this.propertyName,
    required this.activeRentalSpaceCount,
    required this.onArchive,
    super.key,
  });

  final String propertyName;
  final int activeRentalSpaceCount;
  final Future<void> Function() onArchive;

  @override
  Widget build(BuildContext context) {
    return AsyncActionButton.outlined(
      key: const ValueKey('archive-property'),
      onPressed: () => _handlePressed(context),
      // The flow opens a dialog first, so a spinner here would only tick
      // away behind the scrim; the duplicate guard is what matters.
      showBusyIndicator: false,
      buttonStyle: OutlinedButton.styleFrom(
        foregroundColor: context.nyumba.danger,
        side: BorderSide(color: context.nyumba.danger),
      ),
      icon: const Icon(Icons.archive_outlined, size: 18),
      child: const Text.localized('Archive property'),
    );
  }

  Future<void> _handlePressed(BuildContext context) async {
    if (activeRentalSpaceCount > 0) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text.localized('Archive rental spaces first'),
          content: Text.localized(
            '$propertyName still has $activeRentalSpaceCount active '
            '${activeRentalSpaceCount == 1 ? 'rental space' : 'rental spaces'}. '
            'End any active tenancy, unpublish its listing, and archive each '
            'rental space before archiving this property.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text.localized('Got it'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text.localized('Archive $propertyName?'),
        content: const Text.localized(
          'The archive request will be queued. The property stays marked as '
          'archive pending until the server confirms it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text.localized('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: context.nyumba.danger,
            ),
            child: const Text.localized('Archive property'),
          ),
        ],
      ),
    );
    if (confirmed == true) await onArchive();
  }
}
