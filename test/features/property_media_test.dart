import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/cloud/cloud_cache.dart';
import 'package:nyumba_property_management/core/cloud/cloud_command.dart';
import 'package:nyumba_property_management/core/cloud/cloud_read_gateway.dart';
import 'package:nyumba_property_management/core/cloud/cloud_reader.dart';
import 'package:nyumba_property_management/core/cloud/command_dispatcher.dart';
import 'package:nyumba_property_management/features/portfolio/data/cloud_property_repository.dart';
import '../support/fake_cloud.dart';
import 'package:nyumba_property_management/app/bootstrap/app_dependencies.dart';
import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/core/offline/remote_pull_gateway.dart';
import 'package:nyumba_property_management/features/portfolio/data/mappers/property_mapper.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property.dart';
import 'package:nyumba_property_management/features/portfolio/presentation/portfolio_visuals.dart';
import 'package:nyumba_property_management/features/portfolio/presentation/property_photo_picker.dart';

void main() {
  final now = DateTime.utc(2026, 7, 15, 10);

  test('property uploads allow two images of at most 5 MB each', () {
    expect(propertyPhotoLimit, 2);
    expect(propertyPhotoMaxBytes, 5 * 1024 * 1024);
  });

  test('property photos reach the command in primary-first order', () async {
    final reads = FakeCloudReadGateway();
    final commands = RecordingCommandGateway();
    final repository = CloudPropertyRepository(
      reader: CloudReader(
        cache: CloudCache(clock: FixedClock(now)),
        gateway: reads,
        partition: const CachePartition(
          environment: 'test-project',
          userId: 'landlord-1',
          role: 'landlord',
        ),
        clock: FixedClock(now),
      ),
      commands: CommandDispatcher(
        gateway: commands,
        connection: StubConnection(),
        clock: FixedClock(now),
      ),
      scope: const LandlordScope('landlord-1'),
      clock: FixedClock(now),
    );
    const images = <String>[
      'data:image/png;base64,AA==',
      'data:image/jpeg;base64,AQ==',
    ];

    await repository.create(
      const CreatePropertyInput(
        landlordId: 'landlord-1',
        name: 'Acacia Court',
        addressLine: '12 Acacia Avenue',
        city: 'Kampala',
        imageUrls: images,
      ),
    );

    // Order is the contract: the first image is the cover the marketplace uses,
    // so it must survive to the command exactly as the landlord arranged it.
    final command = commands.lastCommand;
    expect(command.type, 'property.create');
    expect(command.payload['imageUrls'], images);
    // A create is recognised by the router through `expectedVersion: 0`.
    expect(command.expectedVersion, 0);
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
    'archiving a property is the server\'s decision, not a local one',
    () async {
      final reads = FakeCloudReadGateway();
      final commands = RecordingCommandGateway();
      final repository = CloudPropertyRepository(
        reader: CloudReader(
          cache: CloudCache(clock: FixedClock(now)),
          gateway: reads,
          partition: const CachePartition(
            environment: 'test-project',
            userId: 'landlord-1',
            role: 'landlord',
          ),
          clock: FixedClock(now),
        ),
        commands: CommandDispatcher(
          gateway: commands,
          connection: StubConnection(),
          clock: FixedClock(now),
        ),
        scope: const LandlordScope('landlord-1'),
        clock: FixedClock(now),
      );
      Map<String, Object?> record({bool archived = false, int version = 1}) =>
          PropertyMapper.toJson(
            Property(
              id: 'property-1',
              landlordId: 'landlord-1',
              name: 'Archive Court',
              addressLine: '1 Archive Road',
              city: 'Kampala',
              country: 'Uganda',
              createdAt: now,
              updatedAt: now,
              serverVersion: version,
              isArchived: archived,
              archivedAt: archived ? now : null,
            ),
          );
      reads.seed(CommandAggregate.property, [record()]);

      final property = (await repository.getAll()).value!.single;
      await repository.archive(property);

      expect(commands.lastCommand.type, 'property.archive');
      expect(commands.lastCommand.expectedVersion, 1);
      // Still active: the command was accepted, but what a landlord sees is
      // whatever the server last sent, and no local edit forged that.
      expect((await repository.getAll(forceRefresh: true)).value, hasLength(1));

      reads.emitUpdate(CommandAggregate.property, [
        record(archived: true, version: 2),
      ]);

      expect((await repository.getAll(forceRefresh: true)).value, isEmpty);
      final retained = await repository.getById(
        'property-1',
        forceRefresh: true,
      );
      expect(retained.value?.isArchived, isTrue);
      expect(retained.value?.serverVersion, 2);
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

  test('media URL resolution retries a publication-worker race', () async {
    var attempts = 0;
    final waits = <Duration>[];

    final url = await resolveMediaUrlWithRetry(
      (reference) async {
        attempts++;
        if (attempts == 1) throw StateError('object-not-found');
        if (attempts == 2) return null;
        return 'https://example.test/delivered.webp';
      },
      'public/listings/listing-1/image.webp',
      retryDelays: const [Duration(milliseconds: 1), Duration(milliseconds: 2)],
      wait: (delay) async => waits.add(delay),
    );

    expect(url, 'https://example.test/delivered.webp');
    expect(attempts, 3);
    expect(waits, const [Duration(milliseconds: 1), Duration(milliseconds: 2)]);
  });

  test(
    'an object still missing after the grace window settles as absent',
    () async {
      // Not a thrown error: the caller has to tell "there is no such object"
      // from "ask again later", because only the first is safe to cache.
      var attempts = 0;

      final url = await resolveMediaUrlWithRetry(
        (reference) async {
          attempts++;
          throw FirebaseException(
            plugin: 'firebase_storage',
            code: 'object-not-found',
          );
        },
        'public/listings/listing-1/image.webp',
        retryDelays: const [Duration(milliseconds: 1)],
        wait: (delay) async {},
      );

      expect(url, isNull);
      expect(attempts, 2, reason: 'the grace window is still honoured');
    },
  );

  test('a rejected reference is not retried at all', () async {
    // Four attempts at a read the rules will never allow is four times the
    // round trips for the same grey tile.
    var attempts = 0;
    final waits = <Duration>[];

    await expectLater(
      resolveMediaUrlWithRetry(
        (reference) async {
          attempts++;
          throw FirebaseException(
            plugin: 'firebase_storage',
            code: 'unauthorized',
          );
        },
        'private/landlords/l1/properties/p1/0-full.webp',
        retryDelays: const [
          Duration(milliseconds: 1),
          Duration(milliseconds: 2),
        ],
        wait: (delay) async => waits.add(delay),
      ),
      throwsA(
        isA<FirebaseException>().having((e) => e.code, 'code', 'unauthorized'),
      ),
    );
    expect(attempts, 1);
    expect(waits, isEmpty);
  });

  test('an unrecognised failure keeps the benefit of the doubt', () async {
    // A socket error is not a verdict about the object, so it still gets the
    // whole ladder — and still throws, so nothing memoises it.
    var attempts = 0;

    await expectLater(
      resolveMediaUrlWithRetry(
        (reference) async {
          attempts++;
          throw const SocketException('no route to host');
        },
        'public/listings/listing-1/image.webp',
        retryDelays: const [
          Duration(milliseconds: 1),
          Duration(milliseconds: 2),
        ],
        wait: (delay) async {},
      ),
      throwsA(isA<SocketException>()),
    );
    expect(attempts, 3);
  });

  test(
    'a missing object is asked for again only once its TTL lapses',
    () async {
      const reference = 'public/listings/listing-1/image.webp';
      var attempts = 0;
      var moment = DateTime.utc(2026, 8, 3, 9);
      final cache = PropertyMediaUrlCache(
        (_) async {
          attempts++;
          throw FirebaseException(
            plugin: 'firebase_storage',
            code: 'object-not-found',
          );
        },
        clock: () => moment,
        graceWindow: const [Duration.zero],
      );

      expect(await cache.resolve(reference), isNull);
      final afterFirstLadder = attempts;
      expect(afterFirstLadder, greaterThan(1), reason: 'the grace window ran');

      moment = moment.add(
        PropertyMediaUrlCache.missTtl - const Duration(minutes: 1),
      );
      expect(await cache.resolve(reference), isNull);
      expect(attempts, afterFirstLadder);

      // The TTL is what keeps a backfilled object from staying invisible until
      // the app restarts.
      moment = moment.add(const Duration(minutes: 2));
      expect(await cache.resolve(reference), isNull);
      expect(attempts, greaterThan(afterFirstLadder));
    },
  );

  test(
    'a rejected reference replays its refusal instead of re-asking',
    () async {
      const reference = 'private/landlords/l1/properties/p1/0-full.webp';
      var attempts = 0;
      final cache = PropertyMediaUrlCache((_) async {
        attempts++;
        throw FirebaseException(
          plugin: 'firebase_storage',
          code: 'unauthorized',
        );
      });

      final unauthorized = throwsA(
        isA<FirebaseException>().having((e) => e.code, 'code', 'unauthorized'),
      );
      await expectLater(cache.resolve(reference), unauthorized);
      await expectLater(cache.resolve(reference), unauthorized);
      expect(attempts, 1);
    },
  );

  testWidgets('a missing object is looked up once, not once per rebuild', (
    tester,
  ) async {
    // One listing whose media never delivered used to reissue the full retry
    // ladder every time its tile scrolled back into view.
    const primary = 'uploads/landlord/command/primary.png';
    var attempts = 0;
    final property = Property(
      id: 'property-missing',
      landlordId: 'landlord-1',
      name: 'Acacia Court',
      addressLine: '12 Acacia Avenue',
      city: 'Kampala',
      country: 'Uganda',
      imageUrls: const <String>[primary],
      createdAt: now,
      updatedAt: now,
    );
    final visibility = GlobalKey<_MediaVisibilityState>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          propertyMediaUrlResolverProvider.overrideWith(
            (ref) => (reference) async {
              attempts++;
              throw FirebaseException(
                plugin: 'firebase_storage',
                code: 'object-not-found',
              );
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
    final afterFirstMount = attempts;

    visibility.currentState!.show = false;
    await tester.pump();
    visibility.currentState!.show = true;
    await tester.pumpAndSettle();

    expect(afterFirstMount, greaterThan(1), reason: 'the grace window ran');
    expect(attempts, afterFirstMount);
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
