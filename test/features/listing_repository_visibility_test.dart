import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/cloud/cloud_cache.dart';
import 'package:nyumba_property_management/core/cloud/cloud_command.dart';
import 'package:nyumba_property_management/core/cloud/cloud_read_gateway.dart';
import 'package:nyumba_property_management/core/cloud/cloud_reader.dart';
import 'package:nyumba_property_management/core/cloud/command_dispatcher.dart';
import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/features/marketplace/data/cloud_listing_repository.dart';
import 'package:nyumba_property_management/features/marketplace/data/mappers/listing_mapper.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';

import '../support/fake_cloud.dart';
import '../support/fake_portfolio_repositories.dart';

void main() {
  final now = DateTime.utc(2026, 7, 24);
  const partition = CachePartition(
    environment: 'test-project',
    userId: 'landlord-1',
    role: 'landlord',
  );

  Listing listingWith({
    required String id,
    required ListingStatus status,
    String title = 'C1 at Acacia Court',
    String landlordId = 'landlord-1',
    String unitId = 'unit-1',
    String propertyId = 'property-1',
    String? publicContactToken,
  }) => Listing(
    id: id,
    unitId: unitId,
    propertyId: propertyId,
    landlordId: landlordId,
    title: title,
    description: 'A bright rental space in Kampala.',
    monthlyRentMinor: 150000000,
    currency: 'UGX',
    status: status,
    unitType: 'apartment',
    city: 'Kampala',
    neighborhood: 'Ntinda',
    // A published advert must be contactable. The public projection carries an
    // opaque token instead of the landlord's real number; both satisfy the rule.
    contactPhone: publicContactToken == null ? '+256700000000' : null,
    publicContactToken: publicContactToken,
    createdAt: now,
    updatedAt: now,
    serverVersion: 2,
    publishedAt: status == ListingStatus.published ? now : null,
    expiresAt: status == ListingStatus.published
        ? now.add(const Duration(days: 30))
        : null,
    imageUrls: const ['public/listings/l1/0-abcdef0123456789-full.webp'],
  );

  CloudReader readerFor(FakeCloudReadGateway gateway) => CloudReader(
    cache: CloudCache(clock: FixedClock(now)),
    gateway: gateway,
    partition: partition,
    clock: FixedClock(now),
  );

  CloudListingRepository privateRepositoryOn(CloudReader reader) =>
      CloudListingRepository(
        reader: reader,
        commands: CommandDispatcher(
          gateway: RecordingCommandGateway(),
          connection: StubConnection(),
          clock: FixedClock(now),
        ),
        scope: const LandlordScope('landlord-1'),
        units: FakeUnitRepository(),
        properties: FakePropertyRepository(),
        clock: FixedClock(now),
      );

  group('public visibility', () {
    // The old version of this test asserted that a *published* advert stayed
    // out of the public catalogue until its publication had been acknowledged.
    // That state no longer exists — a publish reaches the server or it does not
    // happen — so `status` alone decides. What still has to hold is that
    // anything not published stays out.
    test('publicOnly returns exactly the published adverts', () async {
      final reads = FakeCloudReadGateway();
      final repository = privateRepositoryOn(readerFor(reads));
      reads.seed(CommandAggregate.listing, [
        ListingMapper.toJson(
          listingWith(id: 'draft-1', status: ListingStatus.draft),
        ),
        ListingMapper.toJson(
          listingWith(id: 'paused-1', status: ListingStatus.paused),
        ),
        ListingMapper.toJson(
          listingWith(id: 'live-1', status: ListingStatus.published),
        ),
      ]);

      final publicOnly = await repository.getAll(publicOnly: true);

      expect(publicOnly.value!.map((listing) => listing.id), <String>[
        'live-1',
      ]);
      // The landlord's own view still shows everything they own.
      final all = await repository.getAll(forceRefresh: true);
      expect(all.value, hasLength(3));
    });
  });

  group('private and public catalogues do not collide', () {
    // The two projections share document ids and deliberately carry different
    // fields — the public copy has opaque unit/property/landlord tokens and no
    // contact details. They are read through separate aggregates so they land
    // in separate cache namespaces; without that, whichever arrived last would
    // erase the other's fields.
    test('a public copy never overwrites the private one', () async {
      final reads = FakeCloudReadGateway();
      final reader = readerFor(reads);
      final private = privateRepositoryOn(reader);
      final publicCatalogue = CloudListingRepository.publicCatalog(
        reader: reader,
        clock: FixedClock(now),
      );

      reads.seed(CommandAggregate.listing, [
        ListingMapper.toJson(
          listingWith(
            id: 'shared-listing',
            status: ListingStatus.published,
            title: 'Private workspace title',
          ),
        ),
      ]);
      reads.seed(CommandAggregate.publicListing, [
        ListingMapper.toJson(
          listingWith(
            id: 'shared-listing',
            status: ListingStatus.published,
            title: 'Public catalogue title',
            landlordId: 'opaque-landlord-token',
            unitId: 'public_unit_shared-listing',
            propertyId: 'public_property_shared-listing',
            publicContactToken: 'opaque-contact-token',
          ),
        ),
      ]);

      final fromPublic = await publicCatalogue.getById('shared-listing');
      final fromPrivate = await private.getById('shared-listing');

      expect(fromPublic.value?.title, 'Public catalogue title');
      expect(fromPublic.value?.landlordId, 'opaque-landlord-token');
      // The private read is untouched by the public one having been fetched
      // first, which is the whole point of the separate namespaces.
      expect(fromPrivate.value?.title, 'Private workspace title');
      expect(fromPrivate.value?.landlordId, 'landlord-1');
    });
  });

  group('the public catalogue is read-only', () {
    // An anonymous visitor has no command the server would accept. Refusing
    // here rather than letting the request travel means nothing is attempted,
    // and the refusal names the actual reason.
    test('every mutation is refused before it reaches a gateway', () async {
      final catalogue = CloudListingRepository.publicCatalog(
        reader: readerFor(FakeCloudReadGateway()),
        clock: FixedClock(now),
      );
      final listing = listingWith(
        id: 'live-1',
        status: ListingStatus.published,
      );

      for (final attempt in <Future<MutationResult> Function()>[
        () => catalogue.publish(listing),
        () => catalogue.unpublish(listing),
        () => catalogue.remove(listing),
        () => catalogue.update(listing),
      ]) {
        await expectLater(
          attempt(),
          throwsA(
            isA<CommandException>()
                .having(
                  (e) => e.kind,
                  'kind',
                  CommandFailureKind.permissionDenied,
                )
                .having((e) => e.reason, 'reason', 'signInRequired'),
          ),
        );
      }
    });
  });
}
