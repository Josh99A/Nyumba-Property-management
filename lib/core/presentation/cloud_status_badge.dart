import 'package:flutter/material.dart' hide Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/localized_material.dart';
import '../../app/bootstrap/app_dependencies.dart';
import '../../app/theme/nyumba_colors.dart';
import '../localization/nyumba_localizations.dart';
import 'responsive.dart';
import 'status_badge.dart';

/// Workspace-level connection indicator for the top bar.
///
/// This reports the whole workspace's link to the server, unlike
/// `SyncStateBadge`, which reports a single aggregate's sync state. It never
/// claims a working cloud link on configuration alone: `Synced` appears only
/// after a snapshot has actually been delivered.
///
/// The label collapses to its icon on compact widths; a phone top bar has no
/// room for it beside the logo and account actions.
class CloudStatusBadge extends ConsumerWidget {
  const CloudStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // While the workspace is still opening, `connecting` is the honest answer.
    final status =
        ref.watch(cloudStatusProvider).value ?? CloudStatus.connecting;
    final (label, tone, icon) = switch (status) {
      CloudStatus.live => (
        'Synced',
        BadgeTone.success,
        Icons.cloud_done_outlined,
      ),
      CloudStatus.connecting => (
        'Connecting…',
        BadgeTone.info,
        Icons.cloud_sync_outlined,
      ),
      CloudStatus.failed => (
        'Offline',
        BadgeTone.warning,
        Icons.cloud_off_outlined,
      ),
      CloudStatus.demo => (
        'Demo data',
        BadgeTone.warning,
        Icons.science_outlined,
      ),
    };
    final message = switch (status) {
      CloudStatus.live => 'Connected to Nyumba cloud. Showing live data.',
      CloudStatus.connecting => 'Contacting Nyumba cloud…',
      CloudStatus.failed =>
        'Cannot reach Nyumba cloud. Showing data saved on this device.',
      CloudStatus.demo =>
        'Not connected to a Nyumba project. These are local demo records.',
    };
    return Tooltip(
      message: message,
      child: context.isCompact
          ? Semantics(
              label: context.tr(label),
              child: Icon(icon, size: 20, color: _iconColor(context, tone)),
            )
          : StatusBadge(label: label, tone: tone, icon: icon),
    );
  }

  Color _iconColor(BuildContext context, BadgeTone tone) => switch (tone) {
    BadgeTone.success => context.nyumba.sageDark,
    BadgeTone.info => context.nyumba.midnightNavy,
    BadgeTone.warning => context.nyumba.terracottaDark,
    BadgeTone.danger => context.nyumba.danger,
    BadgeTone.neutral => context.nyumba.mutedInk,
  };
}
