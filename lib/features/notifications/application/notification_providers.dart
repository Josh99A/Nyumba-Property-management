import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../domain/app_notification.dart';

final appNotificationsProvider = StreamProvider<List<AppNotification>>((
  ref,
) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.notifications.watchAll();
});

final unreadNotificationCountProvider = Provider<int>((ref) {
  final notifications = ref.watch(appNotificationsProvider).value;
  if (notifications == null) return 0;
  return notifications.where((notification) => !notification.isRead).length;
});

final markNotificationReadProvider = Provider<MarkNotificationRead>(
  MarkNotificationRead.new,
);

class MarkNotificationRead {
  const MarkNotificationRead(this._ref);

  final Ref _ref;

  Future<void> call(String id) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    await deps.notifications.markRead(id);
    // Wake the existing serialized outbox runner. This is not a widget-owned
    // retry loop; the engine retains its normal backoff and idempotency policy.
    unawaited(deps.syncEngine.syncPending());
  }
}
