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
  ResumeSyncTrigger({required SyncEngine syncEngine})
    : _listener = AppLifecycleListener(
        onResume: () => unawaited(syncEngine.syncPending()),
      );

  final AppLifecycleListener _listener;

  void dispose() => _listener.dispose();
}
