import '../../../core/config/market_config.dart';
import '../../../core/domain/sync_metadata.dart';
import '../../../core/localization/app_language.dart';

enum ThemePreference { system, light, dark }

final class UserSettings {
  const UserSettings({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.phone,
    required this.themePreference,
    required this.language,
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
  final AppLanguage? language;
  final bool emailNotifications;
  final bool pushNotifications;
  final bool rentReminders;
  final bool maintenanceUpdates;
  final DateTime updatedAt;
  final SyncMetadata syncMetadata;

  UserSettings copyWith({
    String? displayName,
    String? email,
    String? phone,
    ThemePreference? themePreference,
    AppLanguage? language,
    bool? emailNotifications,
    bool? pushNotifications,
    bool? rentReminders,
    bool? maintenanceUpdates,
    DateTime? updatedAt,
    SyncMetadata? syncMetadata,
  }) => UserSettings(
    userId: userId,
    displayName: displayName ?? this.displayName,
    email: email ?? this.email,
    phone: phone ?? this.phone,
    themePreference: themePreference ?? this.themePreference,
    language: language ?? this.language,
    emailNotifications: emailNotifications ?? this.emailNotifications,
    pushNotifications: pushNotifications ?? this.pushNotifications,
    rentReminders: rentReminders ?? this.rentReminders,
    maintenanceUpdates: maintenanceUpdates ?? this.maintenanceUpdates,
    updatedAt: updatedAt ?? this.updatedAt,
    syncMetadata: syncMetadata ?? this.syncMetadata,
  );

  void validate() {
    if (displayName.trim().length < 2) {
      throw const FormatException('Enter your full name.');
    }
    final normalizedEmail = email.trim();
    final emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!emailPattern.hasMatch(normalizedEmail)) {
      throw const FormatException('Enter a valid email address.');
    }
    // A missing phone is a legitimate state, not an invalid one: accounts
    // created through Google or email sign-in carry no number, and the server's
    // profile.update schema treats phone as optional. Requiring one here held
    // every other setting hostage — a phone-less account could not even change
    // its theme, because the appearance toggle saves through this same record.
    final normalizedPhone = phone.trim();
    if (normalizedPhone.isNotEmpty &&
        !NyumbaMarket.isValidPhone(normalizedPhone)) {
      throw const FormatException('Use a valid Uganda phone number.');
    }
  }
}
