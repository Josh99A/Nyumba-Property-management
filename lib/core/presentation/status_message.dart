import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';

import '../../app/theme/nyumba_colors.dart';
import '../localization/app_localizations_adapter.dart';
import '../localization/generated/app_localizations.dart';

/// How urgent a status is for the reader, ordered from most benign to most
/// urgent. [debug] is reserved for raw technical detail that only matters when
/// diagnosing a problem, not for anything a landlord is expected to act on.
enum NyumbaMessageSeverity { debug, info, warning, critical }

/// A colour-coded panel that explains a status or failure in plain language,
/// keeps the raw technical error tucked away for diagnosis, and is honest about
/// whether anything is actually broken.
///
/// Prefer [NyumbaStatusMessage.fromError] at load-failure sites: it classifies
/// the error into a severity and writes a truthful, human-readable explanation,
/// while still exposing the original exception under "Technical details".
class NyumbaStatusMessage extends StatefulWidget {
  const NyumbaStatusMessage({
    required this.severity,
    required this.title,
    required this.message,
    super.key,
    this.details,
    this.onRetry,
  });

  /// Builds a message from a caught [error], choosing a severity and honest
  /// explanation based on what went wrong. [subject] names what failed to load
  /// (e.g. `'tenants'`, `'your properties'`) so the copy reads naturally.
  factory NyumbaStatusMessage.fromError(
    Object error, {
    required AppLocalizations localizations,
    required String subject,
    Key? key,
    VoidCallback? onRetry,
  }) {
    final raw = error.toString();
    final lower = raw.toLowerCase();

    // A missing platform plugin means a required device capability isn't wired
    // into this build. Here it's flutter_secure_storage, whose key unlocks the
    // encrypted local database — without it the data genuinely cannot be read,
    // so this is critical and not something the reader can just dismiss.
    if (lower.contains('flutter_secure_storage')) {
      return NyumbaStatusMessage(
        key: key,
        severity: NyumbaMessageSeverity.critical,
        title: localizations.statusMessageSecureStorageTitle,
        message: localizations.statusMessageSecureStorageMessage(subject),
        details: raw,
        onRetry: onRetry,
      );
    }

    // The app is offline-first, so a connectivity blip is expected and
    // recoverable rather than alarming.
    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('network is unreachable')) {
      return NyumbaStatusMessage(
        key: key,
        severity: NyumbaMessageSeverity.warning,
        title: localizations.statusMessageOfflineTitle,
        message: localizations.statusMessageOfflineMessage(subject),
        details: raw,
        onRetry: onRetry,
      );
    }

    // Anything else is a genuine failure to load local data. Stay honest: the
    // data is not showing, and we don't pretend to know why.
    return NyumbaStatusMessage(
      key: key,
      severity: NyumbaMessageSeverity.critical,
      title: localizations.statusMessageLoadFailedTitle(subject),
      message: localizations.statusMessageLoadFailedMessage,
      details: raw,
      onRetry: onRetry,
    );
  }

  final NyumbaMessageSeverity severity;

  /// Plain-language headline for the reader.
  final String title;

  /// Plain-language explanation that is honest about the current status.
  final String message;

  /// The raw technical error, shown collapsed under "Technical details".
  final String? details;

  /// Optional retry handler; renders a "Try again" button when provided.
  final VoidCallback? onRetry;

  @override
  State<NyumbaStatusMessage> createState() => _NyumbaStatusMessageState();
}

class _NyumbaStatusMessageState extends State<NyumbaStatusMessage> {
  bool _showDetails = false;

  ({Color foreground, Color background, Color border, IconData icon, String label})
  _tokens(BuildContext context, AppLocalizations copy) => switch (widget.severity) {
    NyumbaMessageSeverity.debug => (
      foreground: context.nyumba.mutedInk,
      background: context.nyumba.neutralTint,
      border: context.nyumba.outline,
      icon: Icons.bug_report_outlined,
      label: copy.statusMessageSeverityDebug,
    ),
    NyumbaMessageSeverity.info => (
      foreground: context.nyumba.midnightNavy,
      background: context.nyumba.navyTint,
      border: context.nyumba.navyBorder,
      icon: Icons.info_outline_rounded,
      label: copy.statusMessageSeverityInfo,
    ),
    NyumbaMessageSeverity.warning => (
      foreground: context.nyumba.terracottaDark,
      background: context.nyumba.goldTint,
      border: context.nyumba.goldBorder,
      icon: Icons.warning_amber_rounded,
      label: copy.statusMessageSeverityWarning,
    ),
    NyumbaMessageSeverity.critical => (
      foreground: context.nyumba.danger,
      background: context.nyumba.dangerTint,
      border: context.nyumba.dangerBorder,
      icon: Icons.error_outline_rounded,
      label: copy.statusMessageSeverityCritical,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final copy = appLocalizationsOf(context);
    final t = _tokens(context, copy);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(t.icon, color: t.foreground, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SeverityTag(label: t.label, color: t.foreground),
                    const SizedBox(height: 8),
                    Text.localized(
                      widget.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: context.nyumba.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text.localized(
                      widget.message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: context.nyumba.ink,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.onRetry != null || widget.details != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (widget.onRetry != null)
                  FilledButton.tonalIcon(
                    onPressed: widget.onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(copy.statusMessageTryAgain),
                  ),
                if (widget.onRetry != null && widget.details != null)
                  const SizedBox(width: 8),
                if (widget.details != null)
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _showDetails = !_showDetails),
                    icon: Icon(
                      _showDetails
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                    ),
                    label: Text.localized(
                      _showDetails
                          ? copy.statusMessageHideTechnicalDetails
                          : copy.statusMessageTechnicalDetails,
                    ),
                  ),
              ],
            ),
          ],
          if (_showDetails && widget.details != null) ...[
            const SizedBox(height: 10),
            _DebugDetails(details: widget.details!),
          ],
        ],
      ),
    );
  }
}

/// A small uppercase severity chip (INFO / WARNING / CRITICAL / DEBUG).
class _SeverityTag extends StatelessWidget {
  const _SeverityTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text.localized(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// The raw error, rendered in a neutral "debug" box so it reads as diagnostic
/// detail rather than part of the plain-language message.
class _DebugDetails extends StatelessWidget {
  const _DebugDetails({required this.details});

  final String details;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.nyumba.neutralTint,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.nyumba.outline),
      ),
      child: SelectableText(
        details,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.4,
          color: context.nyumba.mutedInk,
        ),
      ),
    );
  }
}
