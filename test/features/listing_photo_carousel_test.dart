import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/bootstrap/app_dependencies.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/marketplace/presentation/listing_visuals.dart';

const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
    'AAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
const _dataUri = 'data:image/png;base64,$_onePixelPng';
final _now = DateTime.utc(2026, 7, 24);

void main() {
  testWidgets('carousel navigates all five listing photos', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            child: ListingPhotoCarousel(
              listing: _listing(imageUrls: List<String>.filled(5, _dataUri)),
              aspectRatio: 2,
            ),
          ),
        ),
      ),
    );

    expect(find.text('1/5'), findsOneWidget);
    expect(find.byTooltip('Previous photo'), findsOneWidget);
    expect(find.byTooltip('Next photo'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('listing-photo-indicator-4')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Next photo'));
    await tester.pumpAndSettle();
    expect(find.text('2/5'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('listing-photo-indicator-4')));
    await tester.pumpAndSettle();
    expect(find.text('5/5'), findsOneWidget);
  });

  testWidgets('listing advertising loads the first public photo as primary', (
    tester,
  ) async {
    const primary = 'public/listings/listing_1234/0_cover.png';
    const secondary = 'public/listings/listing_1234/1_kitchen.png';
    final requested = <String>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          propertyMediaUrlResolverProvider.overrideWith(
            (ref) => (value) async {
              requested.add(value);
              return 'https://example.test/${Uri.encodeComponent(value)}';
            },
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 240,
              child: listingImage(
                _listing(imageUrls: const <String>[primary, secondary]),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requested, <String>[primary]);
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(
      image.imageUrl,
      'https://example.test/${Uri.encodeComponent(primary)}',
    );
    expect(image.memCacheWidth, 1600);
  });

  testWidgets('a missing listing photo never substitutes another home', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 240,
            child: listingImage(_listing(imageUrls: const <String>[])),
          ),
        ),
      ),
    );

    // An advert with no photos is empty, not broken: it earns the neutral
    // "no photos yet" state rather than the failure glyph, which on a public
    // card reads to a renter as a defect in the app.
    expect(find.byIcon(Icons.home_work_outlined), findsOneWidget);
    expect(find.bySemanticsLabel('No photos yet'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a photo that will not resolve still reports as unavailable', (
    tester,
  ) async {
    // The other half of the distinction above. This listing claims a photo, so
    // a blank tile here really is a fault and must keep saying so.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 240,
            child: listingImage(
              _listing(imageUrls: const <String>['not-a-usable-reference']),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    expect(find.bySemanticsLabel('Image unavailable'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('carousel stays directional and overflow-free in Arabic RTL', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final width in <double>[320, 1200]) {
      tester.view.physicalSize = Size(width, 700);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Directionality(
              textDirection: TextDirection.rtl,
              child: ListingPhotoCarousel(
                listing: _listing(imageUrls: List<String>.filled(5, _dataUri)),
                aspectRatio: width < 600 ? 4 / 3 : 2.45,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'width=$width');
      expect(
        tester.getCenter(find.byTooltip('Previous photo')).dx,
        greaterThan(tester.getCenter(find.byTooltip('Next photo')).dx),
        reason: 'previous stays on the directional start edge at width=$width',
      );
    }
  });
}

Listing _listing({required List<String> imageUrls}) => Listing(
  id: 'listing_1234',
  unitId: 'unit_1234',
  propertyId: 'property_1234',
  landlordId: 'landlord_1234',
  title: 'Bright apartment',
  description: 'A bright apartment near local amenities.',
  monthlyRentMinor: 150000000,
  currency: 'UGX',
  status: ListingStatus.draft,
  city: 'Kampala',
  imageUrls: imageUrls,
  createdAt: _now,
  updatedAt: _now,
  syncMetadata: const SyncMetadata.pending(),
);
