import 'dart:async';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/bootstrap/app_dependencies.dart';
import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/core/domain/id_generator.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/core/offline/remote_pull_gateway.dart';
import 'package:nyumba_property_management/features/portfolio/data/mappers/property_mapper.dart';
import 'package:nyumba_property_management/features/portfolio/data/sembast_property_repository.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property.dart';
import 'package:nyumba_property_management/features/portfolio/presentation/portfolio_visuals.dart';
import 'package:nyumba_property_management/features/portfolio/presentation/property_photo_picker.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  final now = DateTime.utc(2026, 7, 15, 10);

  test('property uploads allow two images of at most 5 MB each', () {
    expect(propertyPhotoLimit, 2);
    expect(propertyPhotoMaxBytes, 5 * 1024 * 1024);
  });

  test('property photos round-trip with the primary image first', () async {
    final database = OfflineDatabase(
      await databaseFactoryMemory.openDatabase('property-media.db'),
    );
    addTearDown(database.close);
    await database.initialize();
    final repository = SembastPropertyRepository(
      database: database,
      idGenerator: _SequenceIdGenerator(),
      clock: FixedClock(now),
    );
    const images = <String>[
      'data:image/png;base64,AA==',
      'data:image/jpeg;base64,AQ==',
    ];

    final property = await repository.create(
      const CreatePropertyInput(
        landlordId: 'landlord-1',
        name: 'Acacia Court',
        addressLine: '12 Acacia Avenue',
        city: 'Kampala',
        imageUrls: images,
      ),
    );

    expect(property.imageUrls, images);
    expect((await repository.getById(property.id))?.imageUrls, images);
    final outbox = await database.readOutbox();
    expect(outbox, hasLength(1));
    expect(outbox.single.payload['imageUrls'], images);
  });

  test('property rejects more than two images', () {
    expect(
      () => CreatePropertyInput(
        landlordId: 'landlord-1',
        name: 'Acacia Court',
        addressLine: '12 Acacia Avenue',
        city: 'Kampala',
        imageUrls: List.generate(3, (index) => 'image-$index'),
      ).validate(),
      throwsA(isA<DomainValidationException>()),
    );
  });

  test('legacy records without images remain readable', () {
    final property = PropertyMapper.fromJson(<String, Object?>{
      'id': 'property-1',
      'landlordId': 'landlord-1',
      'name': 'Legacy Court',
      'addressLine': 'Old Road',
      'city': 'Kampala',
      'country': 'Uganda',
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'syncMetadata': <String, Object?>{
        'state': 'pending',
        'serverVersion': 0,
        'pendingCommandIds': <String>[],
      },
    });

    expect(property.imageUrls, isEmpty);
    expect(property.isArchived, isFalse);
  });

  test('legacy records keep only their primary-first image pair', () {
    final property = PropertyMapper.fromJson(<String, Object?>{
      'id': 'property-legacy-media',
      'landlordId': 'landlord-1',
      'name': 'Legacy Court',
      'addressLine': 'Old Road',
      'city': 'Kampala',
      'country': 'Uganda',
      'imageUrls': const <String>['primary', 'secondary', 'legacy-extra'],
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'syncMetadata': <String, Object?>{
        'state': 'synced',
        'serverVersion': 1,
        'pendingCommandIds': <String>[],
      },
    });

    expect(property.imageUrls, const <String>['primary', 'secondary']);
  });

  test(
    'archive keeps a durable tombstone and hides the active property',
    () async {
      final database = OfflineDatabase(
        await databaseFactoryMemory.openDatabase('property-archive.db'),
      );
      addTearDown(database.close);
      await database.initialize();
      final repository = SembastPropertyRepository(
        database: database,
        idGenerator: _SequenceIdGenerator(),
        clock: FixedClock(now),
      );
      final property = await repository.create(
        const CreatePropertyInput(
          landlordId: 'landlord-1',
          name: 'Archive Court',
          addressLine: '1 Archive Road',
          city: 'Kampala',
        ),
      );
      final createMutation = (await database.readOutbox()).single;
      await database.acknowledgeMutation(
        mutationId: createMutation.id,
        syncedAt: now,
        serverRevision: '1',
      );

      final archived = await repository.archive(property.id);

      expect(archived.isArchived, isTrue);
      expect(archived.archivedAt, now);
      expect(
        await repository.getAll(),
        contains(predicate<Property>((item) => item.id == property.id)),
      );
      expect(
        await repository.getAll(includeArchived: true),
        contains(predicate<Property>((item) => item.id == property.id)),
      );
      final archiveMutation = (await database.readOutbox()).single;
      expect(archiveMutation.operation, OutboxOperation.delete);
      expect(archiveMutation.payload['isDeleted'], isTrue);
      expect(archiveMutation.payload['deletedAt'], now.toIso8601String());

      await database.acknowledgeMutation(
        mutationId: archiveMutation.id,
        syncedAt: now,
        serverRevision: '2',
      );
      final retained = await repository.getById(property.id);
      expect(retained?.isArchived, isTrue);
      expect(retained?.syncMetadata.serverRevision, '2');
      expect(await repository.getAll(), isEmpty);
    },
  );

  test('selected photo data references decode for local display', () {
    final bytes = Uint8List.fromList(<int>[0, 1, 2, 254, 255]);
    final photo = PickedPropertyPhoto(
      name: 'home.webp',
      mimeType: 'image/webp',
      bytes: bytes,
    );

    expect(propertyPhotoBytes(photo.dataUri), orderedEquals(bytes));
  });

  test('pulled property media keeps the server primary image first', () {
    expect(
      propertyImageReferencesFromRemote(<String, Object?>{
        'stagedImagePaths': <String>[
          'uploads/landlord/command/primary.webp',
          'uploads/landlord/command/secondary.webp',
        ],
      }),
      <String>[
        'uploads/landlord/command/primary.webp',
        'uploads/landlord/command/secondary.webp',
      ],
    );
    expect(
      propertyImageReferencesFromRemote(<String, Object?>{
        'imagePaths': <String>['private/landlords/owner/primary.webp'],
        'stagedImagePaths': <String>[
          'uploads/landlord/command/old-primary.webp',
        ],
      }),
      <String>['private/landlords/owner/primary.webp'],
    );
  });

  testWidgets('property card image loads the primary Storage object', (
    tester,
  ) async {
    const primary = 'uploads/landlord/command/primary.png';
    const secondary = 'uploads/landlord/command/secondary.png';
    final requested = <String>[];
    final property = Property(
      id: 'property-1',
      landlordId: 'landlord-1',
      name: 'Acacia Court',
      addressLine: '12 Acacia Avenue',
      city: 'Kampala',
      country: 'Uganda',
      imageUrls: const <String>[primary, secondary],
      createdAt: now,
      updatedAt: now,
      syncMetadata: const SyncMetadata.synced(serverRevision: '1'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          propertyMediaUrlResolverProvider.overrideWith(
            (ref) => (reference) async {
              requested.add(reference);
              return 'https://example.test/${Uri.encodeComponent(reference)}';
            },
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              key: const Key('property-image'),
              width: 300,
              height: 160,
              child: propertyImage(property),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requested, <String>[primary]);
    final image = tester.widget<CachedNetworkImage>(
      find.descendant(
        of: find.byKey(const Key('property-image')),
        matching: find.byType(CachedNetworkImage),
      ),
    );
    expect(
      image.imageUrl,
      'https://example.test/${Uri.encodeComponent(primary)}',
    );
    // The decode budget, not the source resolution, is what bounds Flutter's
    // image cache.
    expect(image.memCacheWidth, 1600);
  });

  testWidgets('a grid tile asks for the thumbnail delivery copy', (
    tester,
  ) async {
    const full =
        'private/landlords/l1/properties/p1/0-abcdef0123456789-full.webp';
    final requested = <String>[];
    final property = Property(
      id: 'property-thumb',
      landlordId: 'landlord-1',
      name: 'Acacia Court',
      addressLine: '12 Acacia Avenue',
      city: 'Kampala',
      country: 'Uganda',
      imageUrls: const <String>[full],
      createdAt: now,
      updatedAt: now,
      syncMetadata: const SyncMetadata.synced(serverRevision: '1'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          propertyMediaUrlResolverProvider.overrideWith(
            (ref) => (reference) async {
              requested.add(reference);
              return 'https://example.test/${Uri.encodeComponent(reference)}';
            },
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 160,
              child: propertyImage(
                property,
                cacheWidth: 640,
                preferThumbnail: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requested, <String>[
      'private/landlords/l1/properties/p1/0-abcdef0123456789-thumb.webp',
    ]);
  });

  testWidgets('every storage reference is resolved through Storage itself', (
    tester,
  ) async {
    // Public listing media is not an exception. A hand-built `?alt=media` URL
    // for the `public/` prefix carries no download token, and Storage answers
    // those with 403 — so the public marketplace rendered no photos at all.
    // Every reference, public or private, must go through the resolver.
    const publicRef = 'public/listings/listing_1/0-abcdef0123456789-full.webp';
    final requested = <String>[];
    final property = Property(
      id: 'property-public',
      landlordId: 'landlord-1',
      name: 'Acacia Court',
      addressLine: '12 Acacia Avenue',
      city: 'Kampala',
      country: 'Uganda',
      imageUrls: const <String>[publicRef],
      createdAt: now,
      updatedAt: now,
      syncMetadata: const SyncMetadata.synced(serverRevision: '1'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          propertyMediaUrlResolverProvider.overrideWith(
            (ref) => (reference) async {
              requested.add(reference);
              return 'https://example.test/tokened';
            },
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 160,
              child: propertyImage(property),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requested, <String>[publicRef]);
    expect(
      tester
          .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .imageUrl,
      'https://example.test/tokened',
    );
  });

  testWidgets('a staged upload with no thumbnail falls back to itself', (
    tester,
  ) async {
    const staged = 'uploads/landlord/command/primary.png';
    final requested = <String>[];
    final property = Property(
      id: 'property-staged',
      landlordId: 'landlord-1',
      name: 'Acacia Court',
      addressLine: '12 Acacia Avenue',
      city: 'Kampala',
      country: 'Uganda',
      imageUrls: const <String>[staged],
      createdAt: now,
      updatedAt: now,
      syncMetadata: const SyncMetadata.synced(serverRevision: '1'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          propertyMediaUrlResolverProvider.overrideWith(
            (ref) => (reference) async {
              requested.add(reference);
              return 'https://example.test/x';
            },
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 160,
              child: propertyImage(property, preferThumbnail: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requested, <String>[staged]);
  });

  testWidgets('Storage media uses neutral loading and unavailable states', (
    tester,
  ) async {
    const primary = 'uploads/landlord/command/primary.png';
    final pending = Completer<String?>();
    final property = Property(
      id: 'property-loading',
      landlordId: 'landlord-1',
      name: 'Acacia Court',
      addressLine: '12 Acacia Avenue',
      city: 'Kampala',
      country: 'Uganda',
      imageUrls: const <String>[primary],
      createdAt: now,
      updatedAt: now,
      syncMetadata: const SyncMetadata.synced(serverRevision: '1'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          propertyMediaUrlResolverProvider.overrideWith(
            (ref) =>
                (_) => pending.future,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 160,
              child: propertyImage(property),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    pending.complete(null);
    await tester.pumpAndSettle();

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    expect(find.bySemanticsLabel('Image unavailable'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a resolved media URL survives a brief card removal', (
    tester,
  ) async {
    const primary = 'uploads/landlord/command/primary.png';
    final requested = <String>[];
    final property = Property(
      id: 'property-cache',
      landlordId: 'landlord-1',
      name: 'Acacia Court',
      addressLine: '12 Acacia Avenue',
      city: 'Kampala',
      country: 'Uganda',
      imageUrls: const <String>[primary],
      createdAt: now,
      updatedAt: now,
      syncMetadata: const SyncMetadata.synced(serverRevision: '1'),
    );
    final visibility = GlobalKey<_MediaVisibilityState>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          propertyMediaUrlResolverProvider.overrideWith(
            (ref) => (reference) async {
              requested.add(reference);
              return 'https://example.test/${Uri.encodeComponent(reference)}';
            },
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: _MediaVisibility(key: visibility, property: property),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    visibility.currentState!.show = false;
    await tester.pump();
    visibility.currentState!.show = true;
    await tester.pumpAndSettle();

    expect(requested, const <String>[primary]);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _MediaVisibility extends StatefulWidget {
  const _MediaVisibility({required this.property, super.key});

  final Property property;

  @override
  State<_MediaVisibility> createState() => _MediaVisibilityState();
}

class _MediaVisibilityState extends State<_MediaVisibility> {
  bool _show = true;

  set show(bool value) => setState(() => _show = value);

  @override
  Widget build(BuildContext context) => _show
      ? SizedBox(width: 300, height: 160, child: propertyImage(widget.property))
      : const SizedBox.shrink();
}

final class _SequenceIdGenerator implements IdGenerator {
  int _value = 0;

  @override
  String generate() => 'property-media-${_value++}';
}
