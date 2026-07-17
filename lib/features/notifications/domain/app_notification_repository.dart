import 'app_notification.dart';

abstract interface class AppNotificationRepository {
  Stream<List<AppNotification>> watchAll();
  Future<List<AppNotification>> getAll();
  Future<AppNotification?> getById(String id);
  Future<AppNotification> markRead(String id);
}
