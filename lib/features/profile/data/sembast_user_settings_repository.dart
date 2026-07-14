// ignore_for_file: prefer_initializing_formals

import '../../../core/domain/clock.dart';
import '../../../core/domain/id_generator.dart';
import '../../../core/domain/sync_metadata.dart';
import '../../../core/offline/offline_database.dart';
import '../../../core/offline/offline_entity.dart';
import '../../../core/offline/outbox_entry.dart';
import '../../../core/offline/uuid_id_generator.dart';
import '../domain/user_settings.dart';
import '../domain/user_settings_repository.dart';
import 'user_settings_mapper.dart';

final class SembastUserSettingsRepository implements UserSettingsRepository {
  SembastUserSettingsRepository({
    required OfflineDatabase database,
    IdGenerator? idGenerator,
    Clock clock = const SystemClock(),
  }) : _database = database,
       _idGenerator = idGenerator ?? UuidIdGenerator(),
       _clock = clock;

  final OfflineDatabase _database;
  final IdGenerator _idGenerator;
  final Clock _clock;

  @override
  Future<UserSettings?> getByUserId(String userId) async {
    final json = await _database.readEntity(
      OfflineEntityType.userProfile,
      userId,
    );
    return json == null ? null : UserSettingsMapper.fromJson(json);
  }

  @override
  Stream<UserSettings?> watchByUserId(String userId) => _database
      .watchEntity(OfflineEntityType.userProfile, userId)
      .map((json) => json == null ? null : UserSettingsMapper.fromJson(json));

  @override
  Future<UserSettings> save(UserSettings settings) async {
    settings.validate();
    final current = await getByUserId(settings.userId);
    final now = _clock.now().toUtc();
    final updated = UserSettings(
      userId: settings.userId,
      displayName: settings.displayName.trim(),
      email: settings.email.trim().toLowerCase(),
      phone: _normalizePhone(settings.phone),
      themePreference: settings.themePreference,
      emailNotifications: settings.emailNotifications,
      pushNotifications: settings.pushNotifications,
      rentReminders: settings.rentReminders,
      maintenanceUpdates: settings.maintenanceUpdates,
      updatedAt: now,
      syncMetadata:
          current?.syncMetadata.markPending() ?? const SyncMetadata.pending(),
    );
    await _database.putEntityAndEnqueue(
      entityType: OfflineEntityType.userProfile,
      entityId: updated.userId,
      entity: UserSettingsMapper.toJson(updated),
      mutationId: _idGenerator.generate(),
      operation: OutboxOperation.update,
      createdAt: now,
    );
    return updated;
  }

  static String _normalizePhone(String input) {
    var value = input.replaceAll(RegExp(r'[\s\-()]'), '');
    if (value.startsWith('0')) value = '+256${value.substring(1)}';
    return value;
  }
}
