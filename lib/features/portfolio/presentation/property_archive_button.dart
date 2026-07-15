import 'package:flutter/material.dart';

import '../../../app/theme/nyumba_colors.dart';

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
    return OutlinedButton.icon(
      key: const ValueKey('archive-property'),
      onPressed: () => _handlePressed(context),
      style: OutlinedButton.styleFrom(
        foregroundColor: context.nyumba.danger,
        side: BorderSide(color: context.nyumba.danger),
      ),
      icon: const Icon(Icons.archive_outlined, size: 18),
      label: const Text('Archive property'),
    );
  }

  Future<void> _handlePressed(BuildContext context) async {
    if (activeRentalSpaceCount > 0) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Archive rental spaces first'),
          content: Text(
            '$propertyName still has $activeRentalSpaceCount active '
            '${activeRentalSpaceCount == 1 ? 'rental space' : 'rental spaces'}. '
            'End any active tenancy, unpublish its listing, and archive each '
            'rental space before archiving this property.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Archive $propertyName?'),
        content: const Text(
          'The archive request will be queued. The property stays marked as '
          'archive pending until the server confirms it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: context.nyumba.danger,
            ),
            child: const Text('Archive property'),
          ),
        ],
      ),
    );
    if (confirmed == true) await onArchive();
  }
}
