import 'package:flutter/material.dart' hide Text, Tooltip;
import 'package:intl/intl.dart';
import 'package:nyumba_property_management/core/localization/localized_material.dart';

import '../../app/theme/nyumba_colors.dart';
import '../cloud/cloud_data.dart';
import '../localization/app_localizations_adapter.dart';
import '../localization/generated/app_localizations.dart';
import 'status_message.dart';

/// Renders one cloud read across every state it can be in.
///
/// Screens use this instead of hand-rolling `loading / data / error`, because
/// the three-way split is precisely what loses the distinctions that matter:
/// an empty list and a denied read look identical through it, and cached data
/// arrives indistinguishable from validated data. Everything a user needs in
/// order to trust — or distrust — what is on screen is decided here, once.
///
/// The rules it enforces:
///
/// - visible data is never discarded because a refresh started;
/// - unvalidated data always carries a warning and a way to retry;
/// - "no results" is only ever shown for a confirmed empty server answer;
/// - a permission denial never reads as a network problem.
class CloudDataView<T> extends StatelessWidget {
  const CloudDataView({
    required this.data,
    required this.builder,
    super.key,
    this.onRetry,
    this.emptyBuilder,
    this.loadingBuilder,
    this.subject,
    this.showFreshness = true,
  });

  final CloudData<T> data;

  /// Renders the data itself. [isValidated] is false while what is on screen
  /// has not been confirmed against the server, so a caller that wants to gate
  /// an action on freshness can — though authorization must never be gated on
  /// it, only presentation.
  final Widget Function(BuildContext context, T value, bool isValidated)
  builder;

  /// Re-runs the read. Offered for connection failures and stale data; withheld
  /// for permission denials, where retrying unchanged cannot help.
  final Future<void> Function()? onRetry;

  /// What a confirmed-empty server result looks like on this screen.
  final WidgetBuilder? emptyBuilder;

  final WidgetBuilder? loadingBuilder;

  /// Names what failed to load, for error copy ("your properties").
  final String? subject;

  /// Whether to show the "last updated" stamp above the content.
  final bool showFreshness;

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);

    return switch (data.status) {
      CloudDataStatus.initialLoading =>
        loadingBuilder?.call(context) ??
            _Loading(label: copy.cloudLoadingLabel),

      // Confirmed empty. Distinct from every failure above and below it.
      CloudDataStatus.empty =>
        emptyBuilder?.call(context) ??
            _Empty(retrievedAt: data.retrievedAt, showFreshness: showFreshness),

      // Data on screen, freshness proven.
      CloudDataStatus.live => _withFreshness(
        context,
        copy,
        child: builder(context, data.value as T, true),
      ),

      // Data on screen, freshness in question but no failure yet. Honest
      // banner, no warning tone — nothing has gone wrong.
      CloudDataStatus.refreshing ||
      CloudDataStatus.cachedAwaitingValidation ||
      CloudDataStatus.reconnecting => _pendingValidation(context, copy),

      // Data on screen and the refresh failed. This is the state that must
      // never be silent.
      CloudDataStatus.cachedPotentiallyOutdated => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OutdatedBanner(retrievedAt: data.retrievedAt, onRetry: onRetry),
          const SizedBox(height: 12),
          builder(context, data.value as T, false),
        ],
      ),

      CloudDataStatus.connectionFailure ||
      CloudDataStatus.permissionDenied ||
      CloudDataStatus.serverRejection => _failure(context, copy),
    };
  }

  Widget _pendingValidation(BuildContext context, AppLocalizations copy) {
    final label = switch (data.status) {
      CloudDataStatus.reconnecting => copy.cloudReconnecting,
      CloudDataStatus.refreshing => copy.cloudRefreshing,
      _ => copy.cloudCheckingForUpdates,
    };
    // With nothing yet to show, a reconnect is still a first load.
    if (!data.hasValue) {
      return loadingBuilder?.call(context) ?? _Loading(label: label);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RefreshingBanner(label: label, retrievedAt: data.retrievedAt),
        const SizedBox(height: 12),
        builder(context, data.value as T, false),
      ],
    );
  }

  Widget _withFreshness(
    BuildContext context,
    AppLocalizations copy, {
    required Widget child,
  }) {
    if ((!showFreshness || data.retrievedAt == null) &&
        !data.hasDiscardedRecords) {
      return child;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.hasDiscardedRecords)
          _DiscardedRecordsWarning(count: data.discardedRecordCount),
        if (data.hasDiscardedRecords &&
            showFreshness &&
            data.retrievedAt != null)
          const SizedBox(height: 8),
        if (showFreshness && data.retrievedAt != null)
          _FreshnessStamp(retrievedAt: data.retrievedAt!),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _failure(BuildContext context, AppLocalizations copy) {
    final error = data.error;
    final named = subject ?? '';
    return switch (error?.kind) {
      // Deliberately not retryable and deliberately not a network message: the
      // server answered, and it said no.
      CloudErrorKind.permissionDenied => NyumbaStatusMessage(
        severity: NyumbaMessageSeverity.warning,
        title: copy.cloudAccessDeniedTitle,
        message: copy.cloudAccessDeniedMessage,
        details: error?.detail,
      ),
      CloudErrorKind.serverRejection => NyumbaStatusMessage(
        severity: NyumbaMessageSeverity.critical,
        title: copy.cloudServerRefusedTitle,
        message: copy.cloudServerRefusedMessage,
        details: error?.detail ?? named,
        onRetry: onRetry == null ? null : () => onRetry!(),
      ),
      _ => NyumbaStatusMessage(
        severity: NyumbaMessageSeverity.warning,
        title: copy.cloudNoConnectionTitle,
        message: copy.cloudNoConnectionMessage,
        details: error?.detail,
        onRetry: onRetry == null ? null : () => onRetry!(),
      ),
    };
  }
}

/// The freshness banner on its own, for layouts that cannot accept
/// [CloudDataView] — sliver lists and custom scroll views, mainly.
///
/// It renders exactly what [CloudDataView] would render *above* the content, so
/// a sliver screen keeps the same honesty guarantees without restructuring:
/// stale data still carries its warning and its retry, and a permission denial
/// still reads as a refusal rather than a network problem.
class CloudFreshnessBanner<T> extends StatelessWidget {
  const CloudFreshnessBanner({
    required this.data,
    super.key,
    this.onRetry,
    this.showFreshness = true,
  });

  final CloudData<T> data;
  final Future<void> Function()? onRetry;
  final bool showFreshness;

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    return switch (data.status) {
      CloudDataStatus.initialLoading => const SizedBox.shrink(),
      CloudDataStatus.live when data.hasDiscardedRecords => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DiscardedRecordsWarning(count: data.discardedRecordCount),
          if (showFreshness && data.retrievedAt != null) ...[
            const SizedBox(height: 8),
            _FreshnessStamp(retrievedAt: data.retrievedAt!),
          ],
        ],
      ),
      CloudDataStatus.live || CloudDataStatus.empty =>
        showFreshness && data.retrievedAt != null
            ? _FreshnessStamp(retrievedAt: data.retrievedAt!)
            : const SizedBox.shrink(),
      CloudDataStatus.refreshing => _RefreshingBanner(
        label: copy.cloudRefreshing,
        retrievedAt: data.retrievedAt,
      ),
      CloudDataStatus.reconnecting => _RefreshingBanner(
        label: copy.cloudReconnecting,
        retrievedAt: data.retrievedAt,
      ),
      CloudDataStatus.cachedAwaitingValidation => _RefreshingBanner(
        label: copy.cloudCheckingForUpdates,
        retrievedAt: data.retrievedAt,
      ),
      CloudDataStatus.cachedPotentiallyOutdated => _OutdatedBanner(
        retrievedAt: data.retrievedAt,
        onRetry: onRetry,
      ),
      CloudDataStatus.permissionDenied => NyumbaStatusMessage(
        severity: NyumbaMessageSeverity.warning,
        title: copy.cloudAccessDeniedTitle,
        message: copy.cloudAccessDeniedMessage,
        details: data.error?.detail,
      ),
      CloudDataStatus.serverRejection => NyumbaStatusMessage(
        severity: NyumbaMessageSeverity.critical,
        title: copy.cloudServerRefusedTitle,
        message: copy.cloudServerRefusedMessage,
        details: data.error?.detail,
        onRetry: onRetry == null ? null : () => onRetry!(),
      ),
      CloudDataStatus.connectionFailure => NyumbaStatusMessage(
        severity: NyumbaMessageSeverity.warning,
        title: copy.cloudNoConnectionTitle,
        message: copy.cloudNoConnectionMessage,
        details: data.error?.detail,
        onRetry: onRetry == null ? null : () => onRetry!(),
      ),
    };
  }
}

class _DiscardedRecordsWarning extends StatelessWidget {
  const _DiscardedRecordsWarning({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    return Semantics(
      liveRegion: true,
      child: NyumbaStatusMessage(
        severity: NyumbaMessageSeverity.warning,
        title: copy.cloudPartialDataTitle,
        message: copy.cloudPartialDataMessage(count),
      ),
    );
  }
}

/// A spinner that announces itself, so a screen reader is not left on a silent
/// blank page.
class _Loading extends StatelessWidget {
  const _Loading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 12),
          Text.localized(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.nyumba.mutedInk),
          ),
        ],
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.retrievedAt, required this.showFreshness});

  final DateTime? retrievedAt;
  final bool showFreshness;

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showFreshness && retrievedAt != null)
          _FreshnessStamp(retrievedAt: retrievedAt!),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text.localized(
            copy.noDataYet,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: context.nyumba.mutedInk),
          ),
        ),
      ],
    );
  }
}

/// "Last updated 09:41" — the number a user needs to judge for themselves
/// whether what they are looking at is worth acting on.
class _FreshnessStamp extends StatelessWidget {
  const _FreshnessStamp({required this.retrievedAt});

  final DateTime retrievedAt;

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Text.localized(
        copy.cloudLastUpdated(formatFreshness(context, retrievedAt)),
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: context.nyumba.mutedInk),
      ),
    );
  }
}

class _RefreshingBanner extends StatelessWidget {
  const _RefreshingBanner({required this.label, required this.retrievedAt});

  final String label;
  final DateTime? retrievedAt;

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: context.nyumba.navyTint,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.nyumba.navyBorder),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.nyumba.midnightNavy,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.localized(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.nyumba.midnightNavy,
                ),
              ),
            ),
            if (retrievedAt != null)
              Text.localized(
                copy.cloudLastUpdated(formatFreshness(context, retrievedAt!)),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: context.nyumba.mutedInk,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The warning that must accompany any unvalidated data. It states plainly that
/// the server could not be reached, says how old the data is, and offers the
/// retry — three things, because omitting any one of them turns stale data into
/// a quiet lie.
class _OutdatedBanner extends StatelessWidget {
  const _OutdatedBanner({required this.retrievedAt, required this.onRetry});

  final DateTime? retrievedAt;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    final message = retrievedAt == null
        ? copy.cloudMayBeOutdatedMessage
        : '${copy.cloudMayBeOutdatedMessage} '
              '${copy.cloudLastUpdated(formatFreshness(context, retrievedAt!))}';
    return NyumbaStatusMessage(
      severity: NyumbaMessageSeverity.warning,
      title: copy.cloudMayBeOutdatedTitle,
      message: message,
      onRetry: onRetry == null ? null : () => onRetry!(),
    );
  }
}

/// A short, locale-aware stamp: clock time for something read today, date and
/// time once it is older, because "09:41" on a three-day-old record reads as
/// far fresher than it is.
String formatFreshness(BuildContext context, DateTime retrievedAt) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  final local = retrievedAt.toLocal();
  final now = DateTime.now();
  final isToday =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  return isToday
      ? DateFormat.jm(locale).format(local)
      : DateFormat.yMMMd(locale).add_jm().format(local);
}
