import 'package:flutter/material.dart';

import '../offline/aggregate_sync_status.dart';
import 'status_badge.dart';

/// Renders the honest sync state of a single aggregate. Screens place this
/// next to each mutable record so unacknowledged work is always visible.
class SyncStateBadge extends StatelessWidget {
  const SyncStateBadge({required this.status, super.key, this.compact = true});

  final AggregateSyncStatus status;

  /// When true the synced state renders nothing, keeping settled lists calm.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      AggregateSyncStatus.synced =>
        compact
            ? const SizedBox.shrink()
            : const StatusBadge(
                label: 'Synced',
                tone: BadgeTone.success,
                icon: Icons.check_circle_outline_rounded,
              ),
      AggregateSyncStatus.pending => const StatusBadge(
        label: 'Pending sync',
        tone: BadgeTone.warning,
        icon: Icons.cloud_upload_outlined,
      ),
      AggregateSyncStatus.syncing => const StatusBadge(
        label: 'Syncing…',
        tone: BadgeTone.info,
        icon: Icons.sync_rounded,
      ),
      AggregateSyncStatus.rejected => const StatusBadge(
        label: 'Rejected',
        tone: BadgeTone.danger,
        icon: Icons.error_outline_rounded,
      ),
      AggregateSyncStatus.blocked => const StatusBadge(
        label: 'Blocked',
        tone: BadgeTone.danger,
        icon: Icons.block_rounded,
      ),
      AggregateSyncStatus.conflicted => const StatusBadge(
        label: 'Conflicted',
        tone: BadgeTone.danger,
        icon: Icons.fork_right_rounded,
      ),
    };
  }
}
