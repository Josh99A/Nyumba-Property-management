// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'network_status.dart';
import 'sync_engine.dart';

/// Flushes the durable outbox as soon as connectivity returns.
///
/// The connectivity stream is a scheduling hint, not proof of reachability: a
/// spurious "online" event costs one sync pass whose failures land back in the
/// retry policy. Repeated events are also harmless because concurrent callers
/// share the engine's single active run.
final class ReconnectSyncTrigger {
  ReconnectSyncTrigger({
    required SyncEngine syncEngine,
    required NetworkStatus networkStatus,
  }) : _syncEngine = syncEngine {
    _subscription = networkStatus.changes
        .where((online) => online)
        .listen(_onOnline);
  }

  final SyncEngine _syncEngine;
  late final StreamSubscription<bool> _subscription;
  Future<void>? _inflight;

  void _onOnline(bool _) {
    // Retain the handle so close() can quiesce. A failed run is already
    // recorded in the outbox retry state, so the error is swallowed here
    // rather than surfacing as an unhandled async error.
    _inflight = _syncEngine.syncPending().then((_) {}, onError: (_) {});
  }

  /// Stops reacting to connectivity and waits for any trigger-started sync
  /// pass to finish, so the workspace database can close without an in-flight
  /// run behind it.
  Future<void> close() async {
    await _subscription.cancel();
    await _inflight;
  }
}
