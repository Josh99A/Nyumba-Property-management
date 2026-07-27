/// Pins the Dart half of the review read-model contract.
///
/// Its counterpart is `firebase/functions/test/unit/reviews-projection.test.ts`.
/// Together they are the reason a tenant projection is readable in this app at
/// all: every earlier one was written against a mapper that already existed and
/// did not fit, and the mismatch surfaced as a FormatException on a screen far
/// from the cause — which is why the tenant pull was disabled outright (see
/// app_dependencies.dart).
///
/// If the two files disagree, the pull is broken in production and only this
/// pair will say so.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/features/reviews/data/mappers/landlord_review_mapper.dart';
import 'package:nyumba_property_management/features/reviews/domain/landlord_review.dart';

/// What the mapper actually receives for a pulled review.
///
/// Two transformations sit between Firestore and here, and both matter:
/// `FirestoreRemotePullGateway._normalize` turns Timestamps into ISO-8601
/// strings, and `OfflineDatabase.mergeRemoteEntity` stamps `syncMetadata` on
/// every merged record. The server projection deliberately omits the latter —
/// see the note on `projections.ts` — so a test that fed the raw projection
/// straight to the mapper would fail for a reason production never hits.
Map<String, Object?> mergedTenantRecord() => <String, Object?>{
  ...serverTenantProjection(),
  'syncMetadata': <String, Object?>{
    'state': 'synced',
    'serverRevision': '3',
    'lastSyncedAt': '2026-01-04T09:00:00.000Z',
    'lastError': null,
  },
};

/// Byte-for-byte what `tenantReviewProjection` publishes, after Timestamp
/// normalization. Keep this list in step with `reviews-projection.test.ts`.
Map<String, Object?> serverTenantProjection() => <String, Object?>{
  'id': 'lease-1',
  'version': 3,
  'overall': 4,
  'responsiveness': 5,
  'maintenance': 3,
  'listingAccuracy': null,
  'depositFairness': null,
  'body': 'Repairs were handled quickly.',
  'status': 'published',
  'landlordResponse': null,
  'respondedAt': null,
  'stayMonths': 14,
  'createdAt': '2026-01-04T09:00:00.000Z',
  'updatedAt': '2026-01-04T09:00:00.000Z',
  'landlordId': 'landlord-1',
  'propertyName': 'Kireka Heights',
  'unitLabel': 'B4',
  'reviewerLabel': 'You',
  'editableUntil': '2026-01-18T09:00:00.000Z',
  'flagState': 'none',
  'isDeleted': false,
};

/// What `publicReviewProjection` publishes: no reviewer, no unit, token in
/// place of the landlord's UID.
Map<String, Object?> mergedPublicRecord() => <String, Object?>{
  ...mergedTenantRecord(),
  'landlordId': 'token-abc',
  'landlordToken': 'token-abc',
  'unitLabel': '',
  'reviewerLabel': 'Verified tenant',
  'editableUntil': null,
};

void main() {
  group('server projection contract', () {
    test('reads the tenant projection without loss', () {
      final review = LandlordReviewMapper.fromJson(mergedTenantRecord());

      expect(review.id, 'lease-1');
      expect(review.version, 3);
      expect(review.landlordId, 'landlord-1');
      expect(review.overall, 4);
      expect(review.status, ReviewStatus.published);
      expect(review.flagState, ReviewFlagState.none);
      expect(review.stayMonths, 14);
      expect(review.propertyName, 'Kireka Heights');
      expect(review.reviewerLabel, 'You');
      // Only the dimensions actually scored are present; the two the reviewer
      // skipped must be absent rather than zero.
      expect(review.scores, <ReviewDimension, int>{
        ReviewDimension.responsiveness: 5,
        ReviewDimension.maintenance: 3,
      });
    });

    test('reads the public projection through the same mapper', () {
      final review = LandlordReviewMapper.fromJson(mergedPublicRecord());
      expect(review.landlordId, 'token-abc');
      expect(review.unitLabel, '');
      expect(review.reviewerLabel, 'Verified tenant');
      expect(review.editableUntil, isNull);
      // Provenance survives: this is what tells a reader the author lived there.
      expect(review.stayMonths, 14);
    });

    test('never throws on a projection field it does not know', () {
      // A server-side addition must not break existing clients mid-rollout.
      final review = LandlordReviewMapper.fromJson(<String, Object?>{
        ...mergedTenantRecord(),
        'someFutureField': 'value',
      });
      expect(review.id, 'lease-1');
    });

    test('treats an absent flagState as not flagged', () {
      final json = mergedTenantRecord()..remove('flagState');
      expect(
        LandlordReviewMapper.fromJson(json).flagState,
        ReviewFlagState.none,
      );
    });

    test('round-trips its own output', () {
      final original = LandlordReviewMapper.fromJson(mergedTenantRecord());
      final round = LandlordReviewMapper.fromJson(
        LandlordReviewMapper.toJson(original),
      );
      expect(round.overall, original.overall);
      expect(round.scores, original.scores);
      expect(round.body, original.body);
      expect(round.editableUntil, original.editableUntil);
      expect(round.stayMonths, original.stayMonths);
    });

    test(
      'carries the locally authored action the sync gateway dispatches on',
      () {
        // `pendingAction` is client-only and never published by the server, but
        // it must survive a local persist/read cycle or the outbox entry would
        // reach `_commandFor` with no way to tell which review command it is.
        final review = LandlordReviewMapper.fromJson(mergedTenantRecord());
        final flagged = review.copyWith(
          pendingAction: ReviewAction.flag,
          flagReasonCode: ReviewFlagReason.notMyTenant,
        );
        final round = LandlordReviewMapper.fromJson(
          LandlordReviewMapper.toJson(flagged),
        );
        expect(round.pendingAction, ReviewAction.flag);
        expect(round.flagReasonCode, ReviewFlagReason.notMyTenant);
      },
    );
  });

  group('edit window', () {
    final review = LandlordReviewMapper.fromJson(mergedTenantRecord());

    test('is open inside 14 days and closed after', () {
      expect(review.editableAt(DateTime.utc(2026, 1, 10)), isTrue);
      expect(review.editableAt(DateTime.utc(2026, 2, 1)), isFalse);
    });

    test('is closed for a review that is no longer published', () {
      // A hidden review is still visible to its author, but editing it while a
      // moderator is looking at it would change what is being adjudicated.
      expect(
        review
            .copyWith(status: ReviewStatus.hidden)
            .editableAt(DateTime.utc(2026, 1, 10)),
        isFalse,
      );
    });
  });
}
