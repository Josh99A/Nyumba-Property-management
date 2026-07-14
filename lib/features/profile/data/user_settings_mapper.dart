import '../../../core/domain/sync_metadata.dart';
import '../../../core/offline/json_reader.dart';
import '../../../core/offline/sync_metadata_mapper.dart';
import '../domain/user_settings.dart';

abstract final class UserSettingsMapper {
  static UserSettings fromJson(Map<String, Object?> json) {
    final reader = JsonReader(json);
    return UserSettings(
      userId: reader.requiredString('id'),
      displayName: reader.requiredString('displayName'),
      email: reader.requiredString('email'),
      phone: reader.requiredString('phone'),
      themePreference: ThemePreference.values.firstWhere(
        (value) => value.name == reader.requiredString('themePreference'),
        orElse: () => ThemePreference.system,
      ),
      emailNotifications: reader.optionalBool(
        'emailNotifications',
        fallback: true,
      ),
      pushNotifications: reader.optionalBool(
        'pushNotifications',
        fallback: true,
      ),
      rentReminders: reader.optionalBool('rentReminders', fallback: true),
      maintenanceUpdates: reader.optionalBool(
        'maintenanceUpdates',
        fallback: true,
      ),
      updatedAt: reader.requiredDate('updatedAt'),
      syncMetadata: json['syncMetadata'] == null
          ? const SyncMetadata.pending()
          : SyncMetadataMapper.fromJson(json['syncMetadata']),
    );
  }

  static Map<String, Object?> toJson(UserSettings settings) => {
    'id': settings.userId,
    'displayName': settings.displayName,
    'email': settings.email,
    'phone': settings.phone,
    'themePreference': settings.themePreference.name,
    'emailNotifications': settings.emailNotifications,
    'pushNotifications': settings.pushNotifications,
    'rentReminders': settings.rentReminders,
    'maintenanceUpdates': settings.maintenanceUpdates,
    'updatedAt': settings.updatedAt.toUtc().toIso8601String(),
    'syncMetadata': SyncMetadataMapper.toJson(settings.syncMetadata),
  };
}
