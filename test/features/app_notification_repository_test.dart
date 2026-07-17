import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/id_generator.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/features/notifications/data/sembast_app_notification_repository.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  final createdAt = DateTime.utc(2026, 7, 17, 8);
  final readAt = DateTime.utc(2026, 7, 17, 9);

  test('pulled inbox item is readable and marking read is atomic', () async {
    final database = OfflineDatabase(
      await databaseFactoryMemory.openDatabase('notification-repository.db'),
    );
    addTearDown(database.close);
    await database.initialize();
    final repository = SembastAppNotificationRepository(
      database: database,
      idGenerator: _FixedIdGenerator(),
      clock: FixedClock(readAt),
    );

    await database.mergeRemoteEntity(
      entityType: OfflineEntityType.notification,
      entityId: 'application_app_1234',
      entity: <String, Object?>{
        'id': 'application_app_1234',
        'version': 3,
        'kind': 'application',
        'title': 'New application',
        'body': 'A prospect submitted an application.',
        'route': '/listings',
        'relatedEntityId': 'app_1234',
        'isRead': false,
        'readAt': null,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': createdAt.toIso8601String(),
      },
    );

    final before = await repository.getAll();
    expect(before, hasLength(1));
    expect(before.single.isRead, isFalse);
    expect(before.single.syncMetadata.serverRevision, '3');

    final updated = await repository.markRead('application_app_1234');
    expect(updated.isRead, isTrue);
    expect(updated.readAt, readAt);

    final outbox = await database.readOutbox();
    expect(outbox, hasLength(1));
    expect(outbox.single.entityType, OfflineEntityType.notification);
    expect(outbox.single.operation, OutboxOperation.update);
    final claimed = await database.claimNextMutation(now: readAt);
    expect(claimed?.payload['_expectedVersion'], 3);
  });
}

final class _FixedIdGenerator implements IdGenerator {
  @override
  String generate() => 'notification_read_command_1';
}
