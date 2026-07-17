import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';

import '../../app/theme/nyumba_colors.dart';

/// Lets a toast outlive the widget that asked for it.
///
/// A successful sign-in redirects immediately, disposing the form and its
/// ScaffoldMessenger before a message posted against the form's context could
/// paint. Messages sent through the app-level messenger survive that route
/// change, so confirmation still reaches the destination screen.
final nyumbaMessengerKey = GlobalKey<ScaffoldMessengerState>();

enum NyumbaToastVariant { success, error, info }

/// Shows [message] over whatever screen is current. Safe to call after an
/// `await` that navigated away, and safe before the app has mounted (no-op).
void showNyumbaToast(
  String message, {
  NyumbaToastVariant variant = NyumbaToastVariant.info,
  SnackBarAction? action,
}) {
  final messenger = nyumbaMessengerKey.currentState;
  final context = nyumbaMessengerKey.currentContext;
  if (messenger == null || context == null) return;

  final palette = context.nyumba;
  final (background, icon) = switch (variant) {
    NyumbaToastVariant.success => (
      palette.sageDark,
      Icons.check_circle_outline_rounded,
    ),
    NyumbaToastVariant.error => (palette.danger, Icons.error_outline_rounded),
    NyumbaToastVariant.info => (
      palette.midnightNavy,
      Icons.info_outline_rounded,
    ),
  };

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        // An error asks the reader to do something about it, so it stays long
        // enough to be read twice.
        duration: variant == NyumbaToastVariant.error
            ? const Duration(seconds: 6)
            : const Duration(seconds: 4),
        action: action,
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
}
