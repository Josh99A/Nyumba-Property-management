import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/offline/firebase_remote_sync_gateway.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/core/offline/remote_sync_gateway.dart';

void main() {
  final createdAt = DateTime.utc(2026, 7, 15);

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
}
