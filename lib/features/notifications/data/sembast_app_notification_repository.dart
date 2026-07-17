// ignore_for_file: prefer_initializing_formals

import '../../../core/domain/clock.dart';
import '../../../core/domain/id_generator.dart';
import '../../../core/offline/offline_database.dart';
import '../../../core/offline/offline_entity.dart';
import '../../../core/offline/outbox_entry.dart';
import '../../../core/offline/uuid_id_generator.dart';
import '../domain/app_notification.dart';
import '../domain/app_notification_repository.dart';
import 'app_notification_mapper.dart';

final class SembastAppNotificationRepository
    implements AppNotificationRepository {
  SembastAppNotificationRepository({
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
  Future<List<AppNotification>> getAll() async => _sort(
    (await _database.readEntities(
      OfflineEntityType.notification,
    )).map(AppNotificationMapper.fromJson),
  );

  @override
  Future<AppNotification?> getById(String id) async {
    final json = await _database.readEntity(OfflineEntityType.notification, id);
    return json == null ? null : AppNotificationMapper.fromJson(json);
  }

  @override
  Stream<List<AppNotification>> watchAll() => _database
      .watchEntities(OfflineEntityType.notification)
      .map((items) => _sort(items.map(AppNotificationMapper.fromJson)));

  @override
  Future<AppNotification> markRead(String id) async {
    final current = await getById(id);
    if (current == null) {
      throw StateError('Notification $id no longer exists.');
    }
    if (current.isRead) return current;
    final updated = current.markRead(at: _clock.now());
    await _database.putEntityAndEnqueue(
      entityType: OfflineEntityType.notification,
      entityId: id,
      entity: AppNotificationMapper.toJson(updated),
      mutationId: _idGenerator.generate(),
      operation: OutboxOperation.update,
      createdAt: _clock.now().toUtc(),
    );
    return updated;
  }

  static List<AppNotification> _sort(Iterable<AppNotification> values) {
    final result = values.toList(growable: false);
    result.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return result;
  }
}
