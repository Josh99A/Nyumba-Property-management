import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/core/domain/id_generator.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/features/portfolio/data/mappers/property_mapper.dart';
import 'package:nyumba_property_management/features/portfolio/data/sembast_property_repository.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property.dart';
import 'package:nyumba_property_management/features/portfolio/presentation/property_photo_picker.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  final now = DateTime.utc(2026, 7, 15, 10);

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

  test('property rejects more than five images', () {
    expect(
      () => CreatePropertyInput(
        landlordId: 'landlord-1',
        name: 'Acacia Court',
        addressLine: '12 Acacia Avenue',
        city: 'Kampala',
        imageUrls: List.generate(6, (index) => 'image-$index'),
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
}

final class _SequenceIdGenerator implements IdGenerator {
  int _value = 0;

  @override
  String generate() => 'property-media-${_value++}';
}
