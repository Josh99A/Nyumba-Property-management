import '../../../core/config/market_config.dart';
import '../../../core/domain/sync_metadata.dart';

enum ThemePreference { system, light, dark }

final class UserSettings {
  const UserSettings({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.phone,
    required this.themePreference,
    required this.emailNotifications,
    required this.pushNotifications,
    required this.rentReminders,
    required this.maintenanceUpdates,
    required this.updatedAt,
    required this.syncMetadata,
  });

  final String userId;
  final String displayName;
  final String email;
  final String phone;
  final ThemePreference themePreference;
  final bool emailNotifications;
  final bool pushNotifications;
  final bool rentReminders;
  final bool maintenanceUpdates;
  final DateTime updatedAt;
  final SyncMetadata syncMetadata;

  void validate() {
    if (displayName.trim().length < 2) {
      throw const FormatException('Enter your full name.');
    }
    final normalizedEmail = email.trim();
    final emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!emailPattern.hasMatch(normalizedEmail)) {
      throw const FormatException('Enter a valid email address.');
    }
    if (!NyumbaMarket.isValidPhone(phone)) {
      throw const FormatException('Use a valid Uganda phone number.');
    }
  }
}
