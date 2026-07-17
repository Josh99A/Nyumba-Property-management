import '../../../core/domain/sync_metadata.dart';
import '../../../core/offline/json_reader.dart';
import '../../../core/offline/sync_metadata_mapper.dart';
import '../domain/app_notification.dart';

abstract final class AppNotificationMapper {
  static Map<String, Object?> toJson(AppNotification notification) => {
    'id': notification.id,
    'kind': _kindToServer(notification.kind),
    'title': notification.title,
    'body': notification.body,
    'route': notification.route,
    'relatedEntityId': notification.relatedEntityId,
    'createdAt': notification.createdAt.toUtc().toIso8601String(),
    'updatedAt': notification.updatedAt.toUtc().toIso8601String(),
    'isRead': notification.isRead,
    'readAt': notification.readAt?.toUtc().toIso8601String(),
    'syncMetadata': SyncMetadataMapper.toJson(notification.syncMetadata),
  };

  static AppNotification fromJson(Map<String, Object?> json) {
    final reader = JsonReader(json);
    return AppNotification(
      id: reader.requiredString('id'),
      kind: _kindFromServer(reader.requiredString('kind')),
      title: reader.requiredString('title'),
      body: reader.requiredString('body'),
      route: reader.requiredString('route'),
      relatedEntityId: reader.optionalString('relatedEntityId'),
      createdAt: reader.requiredDate('createdAt'),
      updatedAt: reader.requiredDate('updatedAt'),
      isRead: reader.optionalBool('isRead'),
      readAt: reader.optionalDate('readAt'),
      syncMetadata: json['syncMetadata'] == null
          ? const SyncMetadata.synced()
          : SyncMetadataMapper.fromJson(json['syncMetadata']),
    );
  }

  static AppNotificationKind _kindFromServer(String value) => switch (value) {
    'application' => AppNotificationKind.application,
    'enquiry' => AppNotificationKind.enquiry,
    'tenant_notice' => AppNotificationKind.tenantNotice,
    _ => AppNotificationKind.system,
  };

  static String _kindToServer(AppNotificationKind value) => switch (value) {
    AppNotificationKind.application => 'application',
    AppNotificationKind.enquiry => 'enquiry',
    AppNotificationKind.tenantNotice => 'tenant_notice',
    AppNotificationKind.system => 'system',
  };
}
