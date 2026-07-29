import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/localization/generated/app_localizations_en.dart';
import 'package:nyumba_property_management/core/offline/command_failure.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/core/presentation/status_badge.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/marketplace/presentation/listing_publication.dart';

void main() {
  final now = DateTime.utc(2026, 7, 28);
  final copy = AppLocalizationsEn();

  test('a refused publication is never reported as still publishing', () {
    final listing = _listing(
      status: ListingStatus.published,
      syncMetadata: const SyncMetadata.pending(),
    );

    final publication = resolveListingPublication(
      listing: listing,
      outbox: [
        _entry(
          listingId: listing.id,
          operation: OutboxOperation.publish,
          state: OutboxState.permanentlyFailed,
          attemptCount: 6,
          lastError: 'VALIDATION_FAILED',
          errorReason: 'listingMissingPhotos',
          createdAt: now,
        ),
      ],
      copy: copy,
    );

    expect(publication.state, ListingPublicationState.failed);
    expect(publication.label, copy.listingStatusNotPublishedLabel);
    expect(publication.tone, BadgeTone.danger);
    expect(publication.needsAttention, isTrue);
    expect(publication.inFlight, isFalse);
    // The server's reason survives the trip and resolves to the specific
    // failure, not the generic "validation failed" the bare code gives.
    expect(publication.failure?.code, CommandFailureCode.listingMissingPhotos);
    expect(publication.mutationId, 'mutation-1');
    expect(publication.canRetry, isTrue);
  });

  test('a refused unpublish says the advert may still be public', () {
    final listing = _listing(
      status: ListingStatus.paused,
      syncMetadata: const SyncMetadata.pending(),
    );

    final publication = resolveListingPublication(
      listing: listing,
      outbox: [
        _entry(
          listingId: listing.id,
          operation: OutboxOperation.delete,
          state: OutboxState.permanentlyFailed,
          createdAt: now,
        ),
      ],
      copy: copy,
    );

    expect(publication.label, copy.listingStatusStillPublicLabel);
    expect(publication.needsAttention, isTrue);
  });

  test('a first delivery attempt stays calm, a bouncing one escalates', () {
    final listing = _listing(
      status: ListingStatus.published,
      syncMetadata: const SyncMetadata.pending(),
    );
    OutboxEntry pending({
      required int attemptCount,
      required OutboxState state,
    }) => _entry(
      listingId: listing.id,
      operation: OutboxOperation.publish,
      state: state,
      attemptCount: attemptCount,
      createdAt: now,
    );

    final firstTry = resolveListingPublication(
      listing: listing,
      outbox: [pending(attemptCount: 0, state: OutboxState.pending)],
      copy: copy,
    );
    expect(firstTry.state, ListingPublicationState.goingLive);
    expect(firstTry.label, copy.listingStatusGoingLiveLabel);
    // The happy path resolves in a round-trip, so it must not wear the same
    // colour as work that is actually in trouble.
    expect(firstTry.tone, BadgeTone.info);
    expect(firstTry.inFlight, isTrue);
    expect(firstTry.needsAttention, isFalse);

    final bouncing = resolveListingPublication(
      listing: listing,
      outbox: [pending(attemptCount: 3, state: OutboxState.retryScheduled)],
      copy: copy,
    );
    expect(bouncing.state, ListingPublicationState.retrying);
    expect(bouncing.tone, BadgeTone.warning);
    expect(bouncing.inFlight, isTrue);
    expect(bouncing.needsAttention, isFalse);
  });

  test('a failure the outbox has forgotten still reads as a failure', () {
    final listing = _listing(
      status: ListingStatus.published,
      syncMetadata: const SyncMetadata(
        state: EntitySyncState.failed,
        lastError: 'UNIT_LIMIT_REACHED',
      ),
    );

    final publication = resolveListingPublication(
      listing: listing,
      outbox: const [],
      copy: copy,
    );

    expect(publication.state, ListingPublicationState.failed);
    expect(publication.failure?.code, CommandFailureCode.unitLimitReached);
    // Nothing left to re-queue, so no retry is offered rather than a button
    // that would do nothing.
    expect(publication.canRetry, isFalse);
  });

  test('an acknowledged publication is the only one reported as live', () {
    final live = resolveListingPublication(
      listing: _listing(
        status: ListingStatus.published,
        syncMetadata: SyncMetadata.synced(lastSyncedAt: now),
      ),
      outbox: const [],
      copy: copy,
    );

    expect(live.state, ListingPublicationState.live);
    expect(live.isLive, isTrue);
    expect(live.tone, BadgeTone.success);
  });

  test('other aggregates in the outbox do not colour this advert', () {
    final listing = _listing(
      status: ListingStatus.published,
      syncMetadata: SyncMetadata.synced(lastSyncedAt: now),
    );

    final publication = resolveListingPublication(
      listing: listing,
      outbox: [
        _entry(
          listingId: 'another-listing',
          operation: OutboxOperation.publish,
          state: OutboxState.permanentlyFailed,
          createdAt: now,
        ),
        _entry(
          listingId: listing.id,
          entityType: OfflineEntityType.payment,
          operation: OutboxOperation.update,
          state: OutboxState.permanentlyFailed,
          createdAt: now,
        ),
      ],
      copy: copy,
    );

    expect(publication.isLive, isTrue);
  });
}

OutboxEntry _entry({
  required String listingId,
  required OutboxOperation operation,
  required OutboxState state,
  required DateTime createdAt,
  OfflineEntityType entityType = OfflineEntityType.listing,
  int attemptCount = 0,
  String? lastError,
  String? errorReason,
}) => OutboxEntry(
  id: 'mutation-1',
  entityType: entityType,
  entityId: listingId,
  operation: operation,
  payload: const <String, Object?>{},
  createdAt: createdAt,
  state: state,
  attemptCount: attemptCount,
  lastError: lastError,
  errorReason: errorReason,
);

Listing _listing({
  required ListingStatus status,
  required SyncMetadata syncMetadata,
}) => Listing(
  id: 'listing-1',
  unitId: 'unit-1',
  propertyId: 'property-1',
  landlordId: 'landlord-1',
  title: 'Apartment A1',
  description: 'A bright two-bedroom apartment.',
  monthlyRentMinor: 4500000,
  currency: 'UGX',
  status: status,
  unitType: 'apartment',
  city: 'Kampala',
  neighborhood: 'Ntinda',
  contactPhone: '+256700000000',
  createdAt: DateTime.utc(2026, 7, 1),
  updatedAt: DateTime.utc(2026, 7, 1),
  publishedAt: status == ListingStatus.draft ? null : DateTime.utc(2026, 7, 1),
  syncMetadata: syncMetadata,
);
