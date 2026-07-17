import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final pushInteractionProvider = StreamProvider<PushInteraction>((ref) {
  if (Firebase.apps.isEmpty) return const Stream<PushInteraction>.empty();

  final controller = StreamController<PushInteraction>();
  final foreground = FirebaseMessaging.onMessage.listen(
    (message) => controller.add(PushInteraction.foreground(message)),
  );
  final opened = FirebaseMessaging.onMessageOpenedApp.listen(
    (message) => controller.add(PushInteraction.opened(message)),
  );
  unawaited(() async {
    try {
      final isApple =
          !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS);
      if (isApple) {
        // Foreground messages are rendered by Nyumba's in-app banner, avoiding
        // a duplicate OS banner while the notification inbox is already open.
        await FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(
              alert: false,
              badge: true,
              sound: false,
            );
      }
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null && !controller.isClosed) {
        controller.add(PushInteraction.opened(initial));
      }
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'Nyumba push interactions',
        ),
      );
    }
  }());

  ref.onDispose(() {
    unawaited(() async {
      await foreground.cancel();
      await opened.cancel();
      await controller.close();
    }());
  });
  return controller.stream;
});

final class PushInteraction {
  const PushInteraction({
    required this.title,
    required this.body,
    required this.route,
    required this.opensRoute,
  });

  factory PushInteraction.foreground(RemoteMessage message) =>
      PushInteraction._fromMessage(message, opensRoute: false);

  factory PushInteraction.opened(RemoteMessage message) =>
      PushInteraction._fromMessage(message, opensRoute: true);

  factory PushInteraction._fromMessage(
    RemoteMessage message, {
    required bool opensRoute,
  }) => PushInteraction(
    title:
        message.notification?.title ??
        message.data['title'] ??
        'New notification',
    body: message.notification?.body ?? message.data['body'] ?? '',
    route: safeNotificationRoute(message.data['route']),
    opensRoute: opensRoute,
  );

  final String title;
  final String body;
  final String? route;
  final bool opensRoute;
}

/// Push data is untrusted input. Only known application destinations may be
/// opened; IDs remain data for the destination to resolve under authorization.
String? safeNotificationRoute(Object? value) {
  if (value is! String) return null;
  return const <String>{
        '/listings',
        '/tenant',
        '/tenant/payments',
        '/tenant/maintenance',
        '/tenant/documents',
        '/maintenance',
        '/finances',
        '/admin',
      }.contains(value)
      ? value
      : null;
}
