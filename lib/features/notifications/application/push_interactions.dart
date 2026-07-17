import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final pushInteractionProvider = StreamProvider.family<PushInteraction, String>((
  ref,
  fallbackTitle,
) {
  if (Firebase.apps.isEmpty) return const Stream<PushInteraction>.empty();

  final controller = StreamController<PushInteraction>();
  final foreground = FirebaseMessaging.onMessage.listen(
    (message) => controller.add(
      PushInteraction.foreground(message, fallbackTitle: fallbackTitle),
    ),
  );
  final opened = FirebaseMessaging.onMessageOpenedApp.listen(
    (message) => controller.add(
      PushInteraction.opened(message, fallbackTitle: fallbackTitle),
    ),
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
        controller.add(
          PushInteraction.opened(initial, fallbackTitle: fallbackTitle),
        );
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

  factory PushInteraction.foreground(
    RemoteMessage message, {
    required String fallbackTitle,
  }) => PushInteraction._fromMessage(
    message,
    opensRoute: false,
    fallbackTitle: fallbackTitle,
  );

  factory PushInteraction.opened(
    RemoteMessage message, {
    required String fallbackTitle,
  }) => PushInteraction._fromMessage(
    message,
    opensRoute: true,
    fallbackTitle: fallbackTitle,
  );

  factory PushInteraction._fromMessage(
    RemoteMessage message, {
    required bool opensRoute,
    required String fallbackTitle,
  }) => PushInteraction(
    title:
        message.notification?.title ?? message.data['title'] ?? fallbackTitle,
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
