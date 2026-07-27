// ignore_for_file: prefer_initializing_formals

import 'dart:collection';

import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/core/domain/id_generator.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/json_reader.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/core/offline/sync_metadata_mapper.dart';
import 'package:nyumba_property_management/core/offline/uuid_id_generator.dart';
import 'package:nyumba_property_management/features/feedback/domain/platform_feedback.dart';

final class PlatformFeedbackMapper {
  const PlatformFeedbackMapper._();

  static Map<String, Object?> toJson(PlatformFeedback feedback) =>
      <String, Object?>{
        'id': feedback.id,
        'kind': feedback.kind.name,
        'score': feedback.score,
        'comment': feedback.comment,
        'category': feedback.category?.name,
        'appVersion': feedback.appVersion,
        'platform': feedback.platform,
        'submittedAt': feedback.submittedAt.toUtc().toIso8601String(),
        'syncMetadata': SyncMetadataMapper.toJson(feedback.syncMetadata),
      };

  static PlatformFeedback fromJson(Map<String, Object?> json) {
    final reader = JsonReader(json);
    final category = json['category'];
    return PlatformFeedback(
      id: reader.requiredString('id'),
      kind: reader.enumValue('kind', PlatformFeedbackKind.values),
      score: reader.optionalInt('score'),
      comment: reader.optionalString('comment'),
      category: category is String
          ? PlatformFeedbackCategory.values
                .where((value) => value.name == category)
                .firstOrNull
          : null,
      appVersion: reader.requiredString('appVersion'),
      platform: reader.requiredString('platform'),
      submittedAt: reader.requiredDate('submittedAt'),
      syncMetadata: SyncMetadataMapper.fromJson(json['syncMetadata']),
    );
  }
}

abstract interface class FeedbackRepository {
  Future<PlatformFeedback> submit({
    required PlatformFeedbackKind kind,
    required String appVersion,
    required String platform,
    int? score,
    String? comment,
    PlatformFeedbackCategory? category,
  });
}

final class SembastFeedbackRepository implements FeedbackRepository {
  SembastFeedbackRepository({
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
  Future<PlatformFeedback> submit({
    required PlatformFeedbackKind kind,
    required String appVersion,
    required String platform,
    int? score,
    String? comment,
    PlatformFeedbackCategory? category,
  }) async {
    final trimmed = comment?.trim();
    if (kind == PlatformFeedbackKind.nps && score == null) {
      throw DomainValidationException(<String, String>{
        'score': 'choose a score from 0 to 10',
      });
    }
    if (kind == PlatformFeedbackKind.freeform &&
        (trimmed == null || trimmed.isEmpty)) {
      throw DomainValidationException(<String, String>{
        'comment': 'tell us what happened',
      });
    }
    final now = _clock.now().toUtc();
    final feedback = PlatformFeedback(
      id: _idGenerator.generate(),
      kind: kind,
      // An NPS submission may carry no comment; the score alone is the answer.
      score: kind == PlatformFeedbackKind.nps ? score : null,
      comment: trimmed == null || trimmed.isEmpty ? null : trimmed,
      category: category,
      appVersion: appVersion,
      platform: platform,
      submittedAt: now,
      syncMetadata: const SyncMetadata.pending(),
    );
    // Enqueued like any other write, so feedback composed on a bad connection
    // is not lost — which is exactly when people have the most to say.
    await _database.putEntityAndEnqueue(
      entityType: OfflineEntityType.platformFeedback,
      entityId: feedback.id,
      entity: PlatformFeedbackMapper.toJson(feedback),
      mutationId: _idGenerator.generate(),
      operation: OutboxOperation.create,
      createdAt: now,
      createOnly: true,
    );
    return feedback;
  }
}
