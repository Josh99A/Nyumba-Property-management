import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/offline/firebase_remote_sync_gateway.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/core/offline/remote_sync_gateway.dart';

/// A configurable [FlutterSecureStorage] stand-in for the installation-id
/// degradation paths. Optionally throws to mimic secure storage being
/// unavailable (private browsing, restricted device, unregistered plugin).
class _FakeSecureStorage extends FlutterSecureStorage {
  _FakeSecureStorage({
    this.stored,
    this.throwOnRead = false,
    this.throwOnWrite = false,
  }) : super();

  String? stored;
  final bool throwOnRead;
  final bool throwOnWrite;
  final List<String?> writes = <String?>[];

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (throwOnRead) {
      throw MissingPluginException('secure storage read unavailable');
    }
    return stored;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writes.add(value);
    if (throwOnWrite) {
      throw MissingPluginException('secure storage write unavailable');
    }
    stored = value;
  }
}

void main() {
  final createdAt = DateTime.utc(2026, 7, 15);

  group('resolveInstallationId', () {
    test('returns the persisted id without rewriting it', () async {
      final storage = _FakeSecureStorage(stored: 'install_persisted');

      final id = await FirebaseRemoteSyncGateway.resolveInstallationId(
        storage: storage,
      );

      expect(id, 'install_persisted');
      expect(storage.writes, isEmpty);
    });

    test('generates and persists an id when none is stored', () async {
      final storage = _FakeSecureStorage();

      final id = await FirebaseRemoteSyncGateway.resolveInstallationId(
        storage: storage,
      );

      expect(id, isNotEmpty);
      expect(storage.writes, <String?>[id]);
    });

    test('falls back to an ephemeral id when the read throws', () async {
      final storage = _FakeSecureStorage(throwOnRead: true);

      final id = await FirebaseRemoteSyncGateway.resolveInstallationId(
        storage: storage,
      );

      expect(id, isNotEmpty);
    });

    test('returns a usable id even when persistence throws', () async {
      final storage = _FakeSecureStorage(throwOnWrite: true);

      final id = await FirebaseRemoteSyncGateway.resolveInstallationId(
        storage: storage,
      );

      expect(id, isNotEmpty);
      expect(storage.writes, <String?>[id]);
      expect(storage.stored, isNull);
    });
  });

  test('maps stable outbox identity and allowlisted unit fields', () async {
    Map<String, Object?>? captured;
    final gateway = FirebaseRemoteSyncGateway(
      installationId: 'install_1234',
      appVersion: '1.2.3',
      platform: 'web',
      invoke: (envelope) async {
        captured = envelope;
        return <String, Object?>{
          'commandId': 'command_1234',
          'status': 'applied',
          'aggregateId': 'unit_123456',
          'serverVersion': 1,
          'serverUpdatedAt': '2026-07-15T00:00:00.000Z',
          'result': <String, Object?>{},
          'error': null,
        };
      },
    );
    final mutation = RemoteMutation(
      mutationId: 'outbox_12345',
      entityType: OfflineEntityType.unit,
      entityId: 'unit_123456',
      operation: OutboxOperation.create,
      payload: <String, Object?>{
        'id': 'unit_123456',
        'propertyId': 'property_1234',
        'landlordId': 'untrusted_uid',
        'label': 'A1',
        'type': 'apartment',
        'monthlyRentMinor': 100000,
        'bedrooms': 1,
        'bathrooms': 1,
        'amenities': <String>[],
        'status': 'occupied',
      },
      idempotencyKey: 'command_1234',
      clientCreatedAt: createdAt,
    );

    final result = await gateway.push(mutation);

    expect(captured?['commandId'], 'command_1234');
    expect(captured?['type'], 'unit.create');
    expect(captured?['expectedVersion'], 0);
    final payload = captured?['payload']! as Map<String, Object?>;
    expect(payload, isNot(contains('landlordId')));
    expect(payload, isNot(contains('status')));
    expect(result.serverRevision, '1');
  });

  test('maps rejected domain response to a permanent sync failure', () async {
    final gateway = FirebaseRemoteSyncGateway(
      installationId: 'install_1234',
      appVersion: '1.2.3',
      platform: 'web',
      invoke: (_) async => <String, Object?>{
        'status': 'rejected',
        'serverUpdatedAt': '2026-07-15T00:00:00.000Z',
        'error': <String, Object?>{'code': 'UNIT_LIMIT_REACHED'},
      },
    );
    final mutation = RemoteMutation(
      mutationId: 'outbox_12345',
      entityType: OfflineEntityType.unit,
      entityId: 'unit_123456',
      operation: OutboxOperation.create,
      payload: <String, Object?>{
        'propertyId': 'property_1234',
        'label': 'A1',
        'type': 'apartment',
        'monthlyRentMinor': 100000,
        'bedrooms': 1,
        'bathrooms': 1,
        'amenities': <String>[],
      },
      idempotencyKey: 'command_1234',
      clientCreatedAt: createdAt,
    );

    await expectLater(
      gateway.push(mutation),
      throwsA(
        isA<RemoteSyncException>()
            .having((error) => error.message, 'message', 'UNIT_LIMIT_REACHED')
            .having((error) => error.retryable, 'retryable', isFalse),
      ),
    );
  });

  test(
    'uses the machine code rather than the server localization key',
    () async {
      final gateway = FirebaseRemoteSyncGateway(
        installationId: 'install_1234',
        appVersion: '1.2.3',
        platform: 'web',
        invoke: (_) async => <String, Object?>{
          'status': 'rejected',
          'serverUpdatedAt': '2026-07-15T00:00:00.000Z',
          'error': <String, Object?>{
            'code': 'SEAT_LIMIT_REACHED',
            'messageKey': 'subscription.seatLimitReached',
          },
        },
      );
      final mutation = RemoteMutation(
        mutationId: 'outbox_staff',
        entityType: OfflineEntityType.unit,
        entityId: 'unit_1234',
        operation: OutboxOperation.create,
        payload: const <String, Object?>{},
        idempotencyKey: 'command_staff',
        clientCreatedAt: createdAt,
      );

      await expectLater(
        gateway.push(mutation),
        throwsA(
          isA<RemoteSyncException>().having(
            (error) => error.message,
            'message',
            'SEAT_LIMIT_REACHED',
          ),
        ),
      );
    },
  );

  test('property commands send only five staged image paths in order', () {
    final gateway = FirebaseRemoteSyncGateway(
      installationId: 'install_1234',
      appVersion: '1.2.3',
      platform: 'web',
      invoke: (_) async => <String, Object?>{},
    );
    final mutation = RemoteMutation(
      mutationId: 'outbox_property',
      entityType: OfflineEntityType.property,
      entityId: 'property_1234',
      operation: OutboxOperation.create,
      payload: <String, Object?>{
        'name': 'Acacia Court',
        'addressLine': '12 Acacia Avenue',
        'city': 'Kampala',
        'imageUrls': <String>[
          'data:image/png;base64,AA==',
          for (var index = 0; index < 6; index++)
            'uploads/landlord/command/photo-$index.webp',
        ],
      },
      idempotencyKey: 'command_property',
      clientCreatedAt: createdAt,
    );

    final envelope = gateway.buildEnvelope(mutation);
    final payload = envelope['payload']! as Map<String, Object?>;
    expect(payload['stagedImagePaths'], <String>[
      for (var index = 0; index < 5; index++)
        'uploads/landlord/command/photo-$index.webp',
    ]);
  });

  test(
    'text edits do not clear already-uploaded property or listing media',
    () {
      final gateway = FirebaseRemoteSyncGateway(
        installationId: 'install_1234',
        appVersion: '1.2.3',
        platform: 'web',
        invoke: (_) async => <String, Object?>{},
      );
      RemoteMutation edit({required OfflineEntityType type}) => RemoteMutation(
        mutationId: 'outbox_${type.name}',
        entityType: type,
        entityId: '${type.name}_123456',
        operation: OutboxOperation.update,
        payload: <String, Object?>{
          '_expectedVersion': 1,
          'unitId': 'unit_123456',
          'name': 'Updated name',
          'title': 'Updated title',
          'description': 'Updated description',
          'monthlyRentMinor': 100000,
          'unitType': 'apartment',
          'city': 'Kampala',
          'neighborhood': 'Ntinda',
          'bedrooms': 1,
          'bathrooms': 1,
          'amenities': <String>[],
          'imageUrls': <String>[
            'https://cdn.example.com/already-published.webp',
          ],
        },
        idempotencyKey: 'command_${type.name}',
        clientCreatedAt: createdAt,
      );

      final propertyPayload =
          gateway.buildEnvelope(
                edit(type: OfflineEntityType.property),
              )['payload']!
              as Map<String, Object?>;
      final listingPayload =
          gateway.buildEnvelope(
                edit(type: OfflineEntityType.listing),
              )['payload']!
              as Map<String, Object?>;

      expect(propertyPayload, isNot(contains('stagedImagePaths')));
      expect(listingPayload, isNot(contains('stagedImagePaths')));
    },
  );
}
