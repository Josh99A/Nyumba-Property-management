import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/localization/generated/app_localizations_en.dart';
import 'package:nyumba_property_management/core/presentation/status_badge.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/marketplace/presentation/listing_publication.dart';

/// This file used to be the largest test in the marketplace, and almost all of
/// it was about a problem that no longer exists.
///
/// Its subject was the disagreement between what an advert's record said and
/// what its undelivered outbox entries said: a publication that had been
/// refused six times still rendered as "Publishing", a retiring advert looked
/// identical to a live one, and the screen had to guess which source to
/// believe. Those cases are gone because the disagreement is gone — a command
/// reaches the server and the record reflects it, or it fails in front of the
/// landlord and the record never changed.
///
/// What survives is the mapping itself, which still has to be right.
void main() {
  final now = DateTime.utc(2026, 7, 28);
  final copy = AppLocalizationsEn();

  Listing listingWith(ListingStatus status) => Listing(
    id: 'listing-1',
    unitId: 'unit-1',
    propertyId: 'property-1',
    landlordId: 'landlord-1',
    title: 'A1 at Acacia Court',
    description: 'A bright rental space in Kampala.',
    monthlyRentMinor: 150000000,
    currency: 'UGX',
    status: status,
    unitType: 'apartment',
    city: 'Kampala',
    // A published advert has to carry a public-safe location and a way to be
    // contacted; `validateForPublishing` enforces both.
    neighborhood: 'Ntinda',
    contactPhone: '+256700000000',
    createdAt: now,
    updatedAt: now,
    serverVersion: 3,
    publishedAt: status == ListingStatus.published ? now : null,
    imageUrls: const ['public/listings/l1/0-abcdef0123456789-full.webp'],
  );

  group('publication state comes from the server status', () {
    test('a published advert is live', () {
      final publication = resolveListingPublication(
        listing: listingWith(ListingStatus.published),
        copy: copy,
      );

      expect(publication.state, ListingPublicationState.live);
      expect(publication.label, copy.listingStatusPublishedLabel);
      expect(publication.tone, BadgeTone.success);
      expect(publication.isLive, isTrue);
    });

    test('a draft is not live and is not a failure', () {
      final publication = resolveListingPublication(
        listing: listingWith(ListingStatus.draft),
        copy: copy,
      );

      expect(publication.state, ListingPublicationState.draft);
      expect(publication.label, copy.listingStatusDraftLabel);
      expect(publication.tone, BadgeTone.neutral);
      expect(publication.isLive, isFalse);
    });

    test('a paused advert reads as paused, not as something in progress', () {
      final publication = resolveListingPublication(
        listing: listingWith(ListingStatus.paused),
        copy: copy,
      );

      expect(publication.state, ListingPublicationState.paused);
      expect(publication.label, copy.listingStatusPausedLabel);
      expect(publication.isLive, isFalse);
    });

    test('a closed advert reads as paused with its own label', () {
      final publication = resolveListingPublication(
        listing: listingWith(ListingStatus.closed),
        copy: copy,
      );

      // Closed and paused are the same thing to a viewer — off the marketplace
      // — but the landlord is told which one it is.
      expect(publication.state, ListingPublicationState.paused);
      expect(publication.label, copy.listingStatusClosedLabel);
    });
  });

  group('nothing carries a standing problem', () {
    // The whole "needsAttention" concept existed so a landlord could find an
    // advert whose delivery had failed days earlier. A refusal is now raised on
    // the action itself, so no advert is ever quietly waiting to be noticed.
    test('no publication state asks for attention', () {
      for (final status in ListingStatus.values) {
        final publication = resolveListingPublication(
          listing: listingWith(status),
          copy: copy,
        );
        expect(
          publication.needsAttention,
          isFalse,
          reason: '${status.name} must not report a standing failure',
        );
      }
    });

    test('every status maps to exactly one state with copy attached', () {
      for (final status in ListingStatus.values) {
        final publication = resolveListingPublication(
          listing: listingWith(status),
          copy: copy,
        );
        expect(publication.label, isNotEmpty);
        expect(publication.detail, isNotEmpty);
      }
    });
  });

  group('isPublic', () {
    // Previously this also required a local `synced` flag, so an advert the
    // server had accepted could still read as private until an acknowledgement
    // was merged. The server's status is now the only input.
    test('is true for exactly the published status', () {
      for (final status in ListingStatus.values) {
        expect(
          listingWith(status).isPublic,
          status == ListingStatus.published,
          reason: status.name,
        );
      }
    });
  });
}
