import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/id_generator.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/localization/app_language.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/features/profile/data/sembast_user_settings_repository.dart';
import 'package:nyumba_property_management/features/profile/domain/user_settings.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  late OfflineDatabase database;
  late SembastUserSettingsRepository repository;
  final now = DateTime.utc(2026, 7, 14, 10);

  setUp(() async {
    database = OfflineDatabase(
      await databaseFactoryMemory.openDatabase(
        'settings-${DateTime.now().microsecondsSinceEpoch}.db',
      ),
    );
    await database.initialize();
    repository = SembastUserSettingsRepository(
      database: database,
      idGenerator: _FixedIdGenerator(),
      clock: FixedClock(now),
    );
  });

  tearDown(() => database.close());

  test(
    'profile and preferences persist with one durable update intent',
    () async {
      final saved = await repository.save(
        UserSettings(
          userId: 'demo-landlord-001',
          displayName: '  Joshua Mugisha  ',
          email: 'JOSHUA@EXAMPLE.COM',
          phone: '0772 123 456',
          themePreference: ThemePreference.dark,
          language: AppLanguage.luganda,
          emailNotifications: false,
          pushNotifications: true,
          rentReminders: true,
          maintenanceUpdates: false,
          updatedAt: now,
          syncMetadata: const SyncMetadata.pending(),
        ),
      );

      expect(saved.displayName, 'Joshua Mugisha');
      expect(saved.email, 'joshua@example.com');
      expect(saved.phone, '+256772123456');
      expect(saved.themePreference, ThemePreference.dark);
      expect(saved.language, AppLanguage.luganda);

      final restored = await repository.getByUserId('demo-landlord-001');
      expect(restored?.maintenanceUpdates, isFalse);
      expect(restored?.emailNotifications, isFalse);

      final entity = await database.readEntity(
        OfflineEntityType.userProfile,
        'demo-landlord-001',
      );
      expect(entity, isNotNull);
      final outbox = await database.readOutbox();
      expect(outbox, hasLength(1));
      expect(outbox.single.entityType, OfflineEntityType.userProfile);
      expect(outbox.single.payload['themePreference'], 'dark');
      expect(outbox.single.payload['locale'], 'lg');
    },
  );

  test('a phone-less account can still save its settings', () async {
    // Accounts created through Google or email sign-in carry no phone number,
    // and the server's profile.update schema treats phone as optional. This
    // save previously threw "Use a valid Uganda phone number", which surfaced
    // as "Appearance could not be saved" whenever such an account touched the
    // theme toggle — the appearance setting persists through this same record.
    final saved = await repository.save(
      UserSettings(
        userId: 'landlord-uid-1',
        displayName: 'Joshua Mugisha',
        email: 'joshua@example.com',
        phone: '',
        themePreference: ThemePreference.dark,
        language: AppLanguage.english,
        emailNotifications: true,
        pushNotifications: true,
        rentReminders: true,
        maintenanceUpdates: true,
        updatedAt: now,
        syncMetadata: const SyncMetadata.pending(),
      ),
    );
    expect(saved.themePreference, ThemePreference.dark);
    expect(saved.phone, isEmpty);
    expect(await database.outboxCount(), 1);
  });

  test('a present but invalid phone is still rejected', () async {
    await expectLater(
      repository.save(
        UserSettings(
          userId: 'landlord-uid-1',
          displayName: 'Joshua Mugisha',
          email: 'joshua@example.com',
          phone: '123',
          themePreference: ThemePreference.system,
          language: AppLanguage.english,
          emailNotifications: true,
          pushNotifications: true,
          rentReminders: true,
          maintenanceUpdates: true,
          updatedAt: now,
          syncMetadata: const SyncMetadata.pending(),
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(await database.outboxCount(), 0);
  });

  test('invalid contact details are rejected before persistence', () async {
    await expectLater(
      repository.save(
        UserSettings(
          userId: 'demo-landlord-001',
          displayName: 'Joshua Mugisha',
          email: 'not-an-email',
          phone: '123',
          themePreference: ThemePreference.system,
          language: AppLanguage.english,
          emailNotifications: true,
          pushNotifications: true,
          rentReminders: true,
          maintenanceUpdates: true,
          updatedAt: now,
          syncMetadata: const SyncMetadata.pending(),
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(await database.outboxCount(), 0);
  });
}

final class _FixedIdGenerator implements IdGenerator {
  @override
  String generate() => 'profile-command-1';
}
