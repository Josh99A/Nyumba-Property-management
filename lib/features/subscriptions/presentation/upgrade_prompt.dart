import 'package:flutter/material.dart' hide Text;
import 'package:go_router/go_router.dart';

import 'package:nyumba_property_management/core/localization/localized_material.dart';

/// Prompt shown when a landlord hits a plan limit or reaches for a capability
/// their current plan does not include.
///
/// Never blocks silently: it names the wall and offers the path through it —
/// the subscription screen, where a higher tier can be requested. The upgrade
/// itself stays payment-gated server-side; this dialog only navigates.
Future<void> showUpgradePrompt(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text.localized(title),
      content: SizedBox(width: 420, child: Text.localized(message)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text.localized('Not now'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(dialogContext);
            context.go('/subscription');
          },
          icon: const Icon(Icons.workspace_premium_outlined, size: 18),
          label: const Text.localized('View plans'),
        ),
      ],
    ),
  );
}
