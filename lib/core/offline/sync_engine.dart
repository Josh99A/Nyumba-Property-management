// ignore_for_file: prefer_initializing_formals

import '../domain/clock.dart';
import 'network_status.dart';
import 'offline_database.dart';
import 'remote_sync_gateway.dart';

final class RetryPolicy {
  const RetryPolicy({
    this.maxAttempts = 6,
    this.baseDelay = const Duration(seconds: 2),
    this.maximumDelay = const Duration(minutes: 5),
  }) : assert(maxAttempts > 0);

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maximumDelay;

  Duration delayFor({required int attempt, required String stableKey}) {
    final exponent = (attempt - 1).clamp(0, 20);
    final rawMilliseconds = baseDelay.inMilliseconds * (1 << exponent);
    final capped = rawMilliseconds.clamp(0, maximumDelay.inMilliseconds);
    // Stable jitter avoids synchronized clients while keeping tests repeatable.
    final jitterRange = (capped * 0.2).round();
    final jitter = jitterRange == 0
        ? 0
        : stableKey.hashCode.abs() % (jitterRange + 1);
    final withJitter = (capped + jitter).clamp(0, maximumDelay.inMilliseconds);
    return Duration(milliseconds: withJitter);
  }
}

final class SyncRunReport {
  const SyncRunReport({
    required this.startedAt,
    required this.finishedAt,
    required this.claimed,
    required this.succeeded,
    required this.retryScheduled,
    required this.permanentlyFailed,
    required this.remaining,
    this.skippedOffline = false,
  });

  final DateTime startedAt;
  final DateTime finishedAt;
  final int claimed;
  final int succeeded;
  final int retryScheduled;
  final int permanentlyFailed;
  final int remaining;
  final bool skippedOffline;
}

/// Serial durable-outbox processor.
///
/// Entries are claimed one at a time so explicit dependencies and aggregate
/// ordering are maintained. Concurrent callers share the same active run.
final class SyncEngine {
  SyncEngine({
    required OfflineDatabase database,
    required RemoteSyncGateway gateway,
    Clock clock = const SystemClock(),
    NetworkStatus networkStatus = const AlwaysOnlineNetworkStatus(),
    RetryPolicy retryPolicy = const RetryPolicy(),
  }) : _database = database,
       _gateway = gateway,
       _clock = clock,
       _networkStatus = networkStatus,
       _retryPolicy = retryPolicy;

  final OfflineDatabase _database;
  final RemoteSyncGateway _gateway;
  final Clock _clock;
  final NetworkStatus _networkStatus;
  final RetryPolicy _retryPolicy;
  Future<SyncRunReport>? _activeRun;

  Future<SyncRunReport> syncPending({int maxMutations = 100}) {
    if (maxMutations <= 0) {
      throw ArgumentError.value(
        maxMutations,
        'maxMutations',
        'must be positive',
      );
    }
    final active = _activeRun;
    if (active != null) return active;

    late final Future<SyncRunReport> run;
    run = _run(maxMutations: maxMutations).whenComplete(() {
      if (identical(_activeRun, run)) _activeRun = null;
    });
    _activeRun = run;
    return run;
  }

  Future<SyncRunReport> _run({required int maxMutations}) async {
    final startedAt = _clock.now().toUtc();
    if (!await _networkStatus.isOnline) {
      return SyncRunReport(
        startedAt: startedAt,
        finishedAt: _clock.now().toUtc(),
        claimed: 0,
        succeeded: 0,
        retryScheduled: 0,
        permanentlyFailed: 0,
        remaining: await _database.outboxCount(),
        skippedOffline: true,
      );
    }

    var claimed = 0;
    var succeeded = 0;
    var retryScheduled = 0;
    var permanentlyFailed = 0;
    while (claimed < maxMutations) {
      final entry = await _database.claimNextMutation(now: _clock.now());
      if (entry == null) break;
      claimed++;
      try {
        final result = await _gateway.push(RemoteMutation.fromOutbox(entry));
        await _database.acknowledgeMutation(
          mutationId: entry.id,
          syncedAt: result.committedAt,
          serverRevision: result.serverRevision,
        );
        succeeded++;
      } catch (error) {
        final retryable = error is! RemoteSyncException || error.retryable;
        final attempt = entry.attemptCount + 1;
        final permanent = !retryable || attempt >= _retryPolicy.maxAttempts;
        final now = _clock.now().toUtc();
        final retryAt = permanent
            ? null
            : now.add(
                _retryPolicy.delayFor(
                  attempt: attempt,
                  stableKey: entry.idempotencyKey,
                ),
              );
        await _database.failMutation(
          mutationId: entry.id,
          error: _errorMessage(error),
          permanent: permanent,
          failedAt: now,
          retryAt: retryAt,
        );
        if (permanent) {
          permanentlyFailed++;
        } else {
          retryScheduled++;
        }
      }
    }

    return SyncRunReport(
      startedAt: startedAt,
      finishedAt: _clock.now().toUtc(),
      claimed: claimed,
      succeeded: succeeded,
      retryScheduled: retryScheduled,
      permanentlyFailed: permanentlyFailed,
      remaining: await _database.outboxCount(),
    );
  }

  static String _errorMessage(Object error) => switch (error) {
    RemoteSyncException() => error.message,
    _ => error.toString(),
  };
}
