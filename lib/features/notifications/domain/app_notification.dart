import '../../../core/domain/domain_validation.dart';
import '../../../core/domain/sync_metadata.dart';

enum AppNotificationKind { application, enquiry, tenantNotice, system }

/// A server-owned, recipient-scoped inbox item mirrored into Sembast.
final class AppNotification {
  AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.route,
    required this.createdAt,
    required this.updatedAt,
    required this.isRead,
    required this.syncMetadata,
    this.relatedEntityId,
    this.readAt,
  }) {
    validate();
  }

  final String id;
  final AppNotificationKind kind;
  final String title;
  final String body;
  final String route;
  final String? relatedEntityId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isRead;
  final DateTime? readAt;
  final SyncMetadata syncMetadata;

  void validate() {
    DomainValidation.check(<String, String?>{
      'id': DomainValidation.requiredText(id, maxLength: 180),
      'title': DomainValidation.requiredText(title, maxLength: 200),
      'body': DomainValidation.requiredText(body, maxLength: 500),
      'route': route.startsWith('/') && route.length <= 200
          ? null
          : 'must be an app-relative route',
      'readAt': isRead && readAt == null ? 'is required when read' : null,
    });
  }

  AppNotification markRead({required DateTime at}) => AppNotification(
    id: id,
    kind: kind,
    title: title,
    body: body,
    route: route,
    relatedEntityId: relatedEntityId,
    createdAt: createdAt,
    updatedAt: at.toUtc(),
    isRead: true,
    readAt: at.toUtc(),
    syncMetadata: syncMetadata.markPending(),
  );
}
