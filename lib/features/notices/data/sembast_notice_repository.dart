// ignore_for_file: prefer_initializing_formals

import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/id_generator.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/core/offline/uuid_id_generator.dart';
import 'package:nyumba_property_management/features/notices/data/mappers/notice_mapper.dart';
import 'package:nyumba_property_management/features/notices/domain/notice.dart';
import 'package:nyumba_property_management/features/notices/domain/notice_repository.dart';

final class SembastNoticeRepository implements NoticeRepository {
  SembastNoticeRepository({
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
  Future<Notice> create(CreateNoticeInput input) async {
    final now = _clock.now().toUtc();
    final notice = Notice(
      id: _idGenerator.generate(),
      reference:
          'NTC-${now.year}-'
          '${(now.millisecondsSinceEpoch % 1000).toString().padLeft(3, '0')}',
      landlordId: input.landlordId.trim(),
      title: input.title.trim(),
      body: input.body.trim(),
      audience: input.audience.trim(),
      audienceType: input.audienceType,
      audienceId: input.audienceId?.trim(),
      status: input.queueForSending ? NoticeStatus.queued : NoticeStatus.draft,
      createdAt: now,
      updatedAt: now,
      syncMetadata: const SyncMetadata.pending(),
    );
    await _database.putEntityAndEnqueue(
      entityType: OfflineEntityType.notice,
      entityId: notice.id,
      entity: NoticeMapper.toJson(notice),
      mutationId: _idGenerator.generate(),
      operation: OutboxOperation.create,
      createdAt: now,
      createOnly: true,
    );
    return notice;
  }

  @override
  Future<List<Notice>> getAll({String? landlordId}) async => _filterAndSort(
    (await _database.readEntities(
      OfflineEntityType.notice,
    )).map(NoticeMapper.fromJson),
    landlordId,
  );

  @override
  Future<Notice?> getById(String id) async {
    final json = await _database.readEntity(OfflineEntityType.notice, id);
    return json == null ? null : NoticeMapper.fromJson(json);
  }

  @override
  Stream<List<Notice>> watchAll({String? landlordId}) => _database
      .watchEntities(OfflineEntityType.notice)
      .map(
        (items) => _filterAndSort(items.map(NoticeMapper.fromJson), landlordId),
      );

  static List<Notice> _filterAndSort(
    Iterable<Notice> items,
    String? landlordId,
  ) {
    final result = items
        .where(
          (notice) => landlordId == null || notice.landlordId == landlordId,
        )
        .toList(growable: false);
    result.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return result;
  }
}
