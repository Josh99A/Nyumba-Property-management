// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/offline/sync_engine.dart';

/// Flushes the durable outbox when the app returns to the foreground.
///
/// Android can suspend the process while connectivity changes, so the
/// reconnect event may never reach `ReconnectSyncTrigger`; resuming is the
/// moment the platform delivers network calls again. A redundant pass is
/// cheap: concurrent callers share the engine's single active run, and an
/// offline device skips without claiming anything.
final class ResumeSyncTrigger {
  ResumeSyncTrigger({required SyncEngine syncEngine}) : _syncEngine = syncEngine {
    _listener = AppLifecycleListener(onResume: _onResume);
  }

  final SyncEngine _syncEngine;
  late final AppLifecycleListener _listener;
  Future<void>? _inflight;

  void _onResume() {
    // Retain the handle so close() can quiesce. A failed run is already
    // recorded in the outbox retry state, so the error is swallowed here
    // rather than surfacing as an unhandled async error.
    _inflight = _syncEngine.syncPending().then((_) {}, onError: (_) {});
  }

  /// Stops reacting to lifecycle changes and waits for any trigger-started
  /// sync pass to finish, so the workspace database can close without an
  /// in-flight run behind it.
  Future<void> close() async {
    _listener.dispose();
    await _inflight;
  }
}
