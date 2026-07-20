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
  }) : _subscription = networkStatus.changes
           .where((online) => online)
           .listen((_) => unawaited(syncEngine.syncPending()));

  final StreamSubscription<bool> _subscription;

  Future<void> close() => _subscription.cancel();
}
