// ignore_for_file: prefer_initializing_formals

import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/core/domain/id_generator.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/core/offline/remote_pull_gateway.dart';
import 'package:nyumba_property_management/core/domain/uuid_id_generator.dart';
import 'package:nyumba_property_management/features/reviews/data/mappers/landlord_review_mapper.dart';
import 'package:nyumba_property_management/features/reviews/domain/landlord_review.dart';
import 'package:nyumba_property_management/features/reviews/domain/review_repository.dart';

final class SembastReviewRepository implements ReviewRepository {
  SembastReviewRepository({
    required OfflineDatabase database,
    RemotePullGateway? pullGateway,
    IdGenerator? idGenerator,
    Clock clock = const SystemClock(),
  }) : _database = database,
       _pullGateway = pullGateway,
       _idGenerator = idGenerator ?? UuidIdGenerator(),
       _clock = clock;

  final OfflineDatabase _database;
  final RemotePullGateway? _pullGateway;
  final IdGenerator _idGenerator;
  final Clock _clock;

  @override
  Future<LandlordReview> submit(SubmitReviewInput input) async {
    final now = _clock.now().toUtc();
    final review = LandlordReview(
      // The lease ID *is* the review ID. `createOnly` below then makes a second
      // review of the same tenancy impossible locally, matching the server's
      // document-existence check instead of discovering the conflict on sync.
      id: input.leaseId,
      landlordId: input.landlordId,
      propertyName: input.propertyName,
      unitLabel: input.unitLabel,
      reviewerLabel: 'You',
      overall: input.overall,
      scores: Map<ReviewDimension, int>.unmodifiable(input.scores),
      body: _optional(input.body),
      status: ReviewStatus.published,
      flagState: ReviewFlagState.none,
      stayMonths: input.stayMonths,
      // The server sets the authoritative window from its own clock; this is the
      // optimistic value so the composer can show "editable until" immediately.
      editableUntil: now.add(const Duration(days: 14)),
      createdAt: now,
      updatedAt: now,
      pendingAction: ReviewAction.submit,
      syncMetadata: const SyncMetadata.pending(),
    );
    await _database.putEntityAndEnqueue(
      entityType: OfflineEntityType.landlordReview,
      entityId: review.id,
      entity: LandlordReviewMapper.toJson(review),
      mutationId: _idGenerator.generate(),
      operation: OutboxOperation.create,
      createdAt: now,
      createOnly: true,
      // The review cannot land before the tenancy it describes exists on the
      // server, which matters when a tenant records both while offline.
      dependsOn: <AggregateReference>[
        AggregateReference(type: OfflineEntityType.tenancy, id: input.leaseId),
      ],
    );
    return review;
  }

  @override
  Future<LandlordReview> edit(EditReviewInput input) async {
    final current = await _require(input.reviewId);
    final now = _clock.now().toUtc();
    if (!current.editableAt(now)) {
      throw DomainValidationException(<String, String>{
        'review': 'the edit window for this review has closed',
      });
    }
    return _enqueueUpdate(
      current.copyWith(
        overall: input.overall,
        scores: Map<ReviewDimension, int>.unmodifiable(input.scores),
        body: _optional(input.body),
        pendingAction: ReviewAction.edit,
      ),
      now,
    );
  }

  @override
  Future<LandlordReview> withdraw(String reviewId) async {
    final current = await _require(reviewId);
    if (current.status == ReviewStatus.withdrawn) {
      throw DomainValidationException(<String, String>{
        'review': 'this review was already withdrawn',
      });
    }
    return _enqueueUpdate(
      current.copyWith(
        status: ReviewStatus.withdrawn,
        pendingAction: ReviewAction.withdraw,
      ),
      _clock.now().toUtc(),
    );
  }

  @override
  Future<LandlordReview> respond({
    required String reviewId,
    required String response,
  }) async {
    final current = await _require(reviewId);
    final trimmed = response.trim();
    if (trimmed.isEmpty) {
      throw DomainValidationException(<String, String>{
        'response': 'a reply cannot be empty',
      });
    }
    final now = _clock.now().toUtc();
    return _enqueueUpdate(
      current.copyWith(
        landlordResponse: trimmed,
        respondedAt: now,
        pendingAction: ReviewAction.respond,
      ),
      now,
    );
  }

  @override
  Future<LandlordReview> flag({
    required String reviewId,
    required ReviewFlagReason reason,
    String? note,
    bool asReader = false,
  }) async {
    final current = await _require(reviewId);
    if (current.flagState == ReviewFlagState.pending) {
      throw DomainValidationException(<String, String>{
        'review': 'this review is already awaiting review by Nyumba',
      });
    }
    return _enqueueUpdate(
      current.copyWith(
        // Optimistically pending, and deliberately still `published`: raising a
        // flag must not remove the review from anyone's view, including the
        // flagger's. See ReviewFlagState.
        flagState: ReviewFlagState.pending,
        flagReasonCode: reason,
        flagNote: _optional(note),
        pendingAction: asReader ? ReviewAction.report : ReviewAction.flag,
      ),
      _clock.now().toUtc(),
    );
  }

  @override
  Future<LandlordReview> moderate({
    required String reviewId,
    required ReviewModerationDecision decision,
    String? note,
  }) async {
    final current = await _require(reviewId);
    return _enqueueUpdate(
      current.copyWith(
        status: switch (decision) {
          ReviewModerationDecision.publish => ReviewStatus.published,
          ReviewModerationDecision.hide => ReviewStatus.hidden,
          ReviewModerationDecision.remove => ReviewStatus.removed,
        },
        flagState: decision == ReviewModerationDecision.publish
            ? ReviewFlagState.dismissed
            : ReviewFlagState.upheld,
        moderationDecision: decision,
        moderationNote: _optional(note),
        pendingAction: ReviewAction.moderate,
      ),
      _clock.now().toUtc(),
    );
  }

  Future<LandlordReview> _enqueueUpdate(
    LandlordReview next,
    DateTime now,
  ) async {
    final updated = next.copyWith(
      updatedAt: now,
      syncMetadata: next.syncMetadata.markPending(),
    );
    await _database.putEntityAndEnqueue(
      entityType: OfflineEntityType.landlordReview,
      entityId: updated.id,
      entity: LandlordReviewMapper.toJson(updated),
      mutationId: _idGenerator.generate(),
      operation: OutboxOperation.update,
      createdAt: now,
    );
    return updated;
  }

  @override
  Future<List<LandlordReview>> getAll({String? landlordId}) async => _sorted(
    (await _database.readEntities(
      OfflineEntityType.landlordReview,
    )).map(LandlordReviewMapper.fromJson),
    landlordId,
  );

  @override
  Future<LandlordReview?> getById(String id) async {
    final json = await _database.readEntity(
      OfflineEntityType.landlordReview,
      id,
    );
    return json == null ? null : LandlordReviewMapper.fromJson(json);
  }

  @override
  Stream<List<LandlordReview>> watchAll({String? landlordId}) => _database
      .watchEntities(OfflineEntityType.landlordReview)
      .map(
        (items) =>
            _sorted(items.map(LandlordReviewMapper.fromJson), landlordId),
      );

  @override
  Stream<List<LandlordReview>> watchPublic(String landlordToken) => _database
      .watchEntities(OfflineEntityType.publicReview)
      .map(
        (items) => _sorted(
          items.map(LandlordReviewMapper.fromJson),
          // The public mirror substitutes the opaque token for the landlord ID,
          // so the same filter works without the client ever seeing a UID.
          landlordToken,
        ),
      );

  @override
  Future<void> refreshPublic(String landlordToken) async {
    final gateway = _pullGateway;
    // No gateway in demo/offline builds. Whatever the mirror already holds still
    // renders; a failed refresh must not empty the screen.
    if (gateway == null) return;
    final records = await gateway.fetchPublicReviews(landlordToken);
    if (records.isEmpty) return;
    await _database.mergeRemoteEntities(<RemoteEntityMerge>[
      for (final record in records)
        RemoteEntityMerge(
          entityType: record.entityType,
          entityId: record.id,
          entity: record.data,
        ),
    ]);
  }

  Future<LandlordReview> _require(String id) async {
    final review = await getById(id);
    if (review == null) throw EntityNotFoundException('review', id);
    return review;
  }

  static List<LandlordReview> _sorted(
    Iterable<LandlordReview> items,
    String? landlordId,
  ) {
    final result = items
        .where(
          (review) => landlordId == null || review.landlordId == landlordId,
        )
        .toList(growable: false);
    result.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return result;
  }

  static String? _optional(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
