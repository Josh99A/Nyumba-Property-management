import 'dart:convert';

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

  testWidgets('public Storage media is used by listing advertising', (
    tester,
  ) async {
    const reference = 'public/listings/listing_1234/0_cover.png';
    final requested = <String>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          propertyMediaLoaderProvider.overrideWith(
            (ref) => (value) async {
              requested.add(value);
              return base64Decode(_onePixelPng);
            },
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 240,
              child: listingImage(
                _listing(imageUrls: const <String>[reference]),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requested, <String>[reference]);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.widget<Image>(find.byType(Image)).image, isA<MemoryImage>());
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
