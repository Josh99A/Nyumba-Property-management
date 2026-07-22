import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/offline/firebase_remote_sync_gateway.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/core/offline/remote_sync_gateway.dart';

/// Every (entityType, operation) pair a repository can enqueue, and the command
/// it must reach.
///
/// This list is the contract between the repositories and the gateway. An
/// enqueued pair with no mapping is not a visible failure: the gateway throws a
/// non-retryable error, the sync engine marks the mutation permanentlyFailed,
/// and the user's tenancy or payment simply never reaches the server while the
/// app looks like it worked. Keep this in step with the repositories, and with
/// `commandHandlers` in firebase/functions/src/commands/index.ts.
const _expectedCommands = <(OfflineEntityType, OutboxOperation), String>{
  (OfflineEntityType.userProfile, OutboxOperation.update): 'profile.update',
  (OfflineEntityType.property, OutboxOperation.create): 'property.create',
  (OfflineEntityType.property, OutboxOperation.update): 'property.update',
  (OfflineEntityType.property, OutboxOperation.delete): 'property.archive',
  (OfflineEntityType.unit, OutboxOperation.create): 'unit.create',
  (OfflineEntityType.unit, OutboxOperation.update): 'unit.update',
  (OfflineEntityType.unit, OutboxOperation.delete): 'unit.archive',
  (OfflineEntityType.tenancy, OutboxOperation.create): 'tenancy.establish',
  (OfflineEntityType.listing, OutboxOperation.create): 'listing.saveDraft',
  (OfflineEntityType.listing, OutboxOperation.update): 'listing.saveDraft',
  (OfflineEntityType.listing, OutboxOperation.publish): 'listing.publish',
  (OfflineEntityType.listing, OutboxOperation.delete): 'listing.unpublish',
  (OfflineEntityType.application, OutboxOperation.create): 'application.submit',
  (OfflineEntityType.application, OutboxOperation.apply): 'application.submit',
  (OfflineEntityType.application, OutboxOperation.update):
      'application.withdraw',
  // A landlord recording money they hold. The tenant's counterpart carries
  // `declaredByTenant` and maps to `payment.declare` (covered below).
  (OfflineEntityType.payment, OutboxOperation.create):
      'payment.recordAgainstTenancy',
  (OfflineEntityType.maintenanceRequest, OutboxOperation.create):
      'maintenance.create',
  (OfflineEntityType.maintenanceRequest, OutboxOperation.update):
      'maintenance.updateStatus',
  (OfflineEntityType.notice, OutboxOperation.create): 'notice.publish',
  (OfflineEntityType.notification, OutboxOperation.update):
      'notification.markRead',
};

/// Aggregates that never enqueue, so the gateway is never asked about them.
///
/// Each entry states why no command could accept it. This is not a to-do list:
/// a type here must be written through `putLocalEntity`, whose `reason`
/// argument records the same fact at the write site.
const _neverEnqueued = <OfflineEntityType, String>{
  OfflineEntityType.invoice:
      'Server-owned. Created inside payment/tenancy commands; the client only '
      'ever pulls invoices, never authors one.',
  OfflineEntityType.leaseDocument:
      'A local index over aggregates the server already owns, rendered to PDF '
      'on the device. No canonical collection holds these rows.',
  OfflineEntityType.document:
      'Uploaded files. Written by document.finalizeUpload once an upload flow '
      'exists; no screen currently uploads one.',
  OfflineEntityType.managedUser:
      'Keyed by a client UUID, while the server identifies accounts by Firebase '
      'UID. Cannot address a real account.',
  OfflineEntityType.adminAction:
      'The server writes its own authoritative auditLogs inside each admin '
      'command. An audit log cannot be client-authored.',
  OfflineEntityType.subscriptionPlan:
      'Admin plan drafts. planCatalog is server-owned and denies client writes; '
      'prices are still TBD.',
  OfflineEntityType.staffInvite:
      'Server-owned staff access projection. Only staff commands can write it.',
  OfflineEntityType.planCatalog:
      'Published server-owned entitlements. Clients only pull this catalogue.',
};

RemoteMutation _mutationFor(
  OfflineEntityType entityType,
  OutboxOperation operation, {
  // Enough of a payload for any mapping to read; absent keys map to null,
  // which is what a real sparse aggregate would produce anyway. Focused
  // payload-contract tests below pass the aggregate fields they exercise.
  Map<String, Object?> payload = const <String, Object?>{'_expectedVersion': 3},
}) => RemoteMutation(
  mutationId: 'mutation-1',
  entityType: entityType,
  entityId: 'aggregate-1',
  operation: operation,
  payload: payload,
  idempotencyKey: 'mutation-1',
  clientCreatedAt: DateTime.utc(2026, 7, 16),
);

void main() {
  final gateway = FirebaseRemoteSyncGateway(
    invoke: (_) async => <String, Object?>{},
    installationId: 'installation-1',
    appVersion: '1.0.0',
    platform: 'test',
  );

  group('gateway command coverage', () {
    test('maps every mutation a repository can enqueue', () {
      final unmapped = <String>[];
      for (final entry in _expectedCommands.entries) {
        final (entityType, operation) = entry.key;
        try {
          final envelope = gateway.buildEnvelope(
            _mutationFor(entityType, operation),
          );
          expect(
            envelope['type'],
            entry.value,
            reason:
                '${entityType.name}.${operation.name} mapped to the '
                'wrong command',
          );
        } on RemoteSyncException catch (error) {
          unmapped.add(
            '${entityType.name}.${operation.name}: ${error.message}',
          );
        }
      }
      expect(unmapped, isEmpty);
    });

    test('tenancy.establish payload maps required and optional fields', () {
      final mutation = RemoteMutation(
        mutationId: 'mutation-1',
        entityType: OfflineEntityType.tenancy,
        entityId: 'tenancy-1',
        operation: OutboxOperation.create,
        payload: <String, Object?>{
          '_expectedVersion': 0,
          'unitId': 'unit-1',
          'tenantName': 'Test Tenant',
          'email': 'tenant@example.com',
          'phone': '+256700000000',
          'leaseStart': '2026-01-01',
          'leaseEnd': '2026-12-31',
          'monthlyRentMinor': 100000,
          'balanceMinor': 50000,
        },
        idempotencyKey: 'mutation-1',
        clientCreatedAt: DateTime.utc(2026, 7, 16),
      );
      final envelope = gateway.buildEnvelope(mutation);
      expect(envelope['type'], 'tenancy.establish');
      final payload = envelope['payload'] as Map<String, Object?>;
      expect(payload['unitId'], 'unit-1');
      expect(payload['displayName'], 'Test Tenant');
      expect(payload['email'], 'tenant@example.com');
      expect(payload['phone'], '+256700000000');
      expect(payload['startDate'], '2026-01-01');
      expect(payload['endDate'], '2026-12-31');
      expect(payload['monthlyRentMinor'], 100000);
      expect(payload['openingBalanceMinor'], 50000);
    });

    test('profile preferences are low-risk versionless updates', () {
      final envelope = gateway.buildEnvelope(
        _mutationFor(
          OfflineEntityType.userProfile,
          OutboxOperation.update,
          payload: const <String, Object?>{
            'displayName': 'Joshua',
            'locale': 'lg',
            'emailNotifications': false,
            'pushNotifications': true,
            'rentReminders': false,
            'maintenanceUpdates': true,
          },
        ),
      );
      expect(envelope.containsKey('expectedVersion'), isFalse);
      expect(envelope['payload'], <String, Object?>{
        'displayName': 'Joshua',
        'locale': 'lg',
        'notifications': <String, Object?>{
          'email': false,
          'push': true,
          'rentReminders': false,
          'maintenanceUpdates': true,
        },
      });

      final localeOnly = gateway.buildEnvelope(
        _mutationFor(
          OfflineEntityType.userProfile,
          OutboxOperation.update,
          payload: const <String, Object?>{'locale': 'sw'},
        ),
      );
      expect(localeOnly.containsKey('expectedVersion'), isFalse);
      expect(localeOnly['payload'], <String, Object?>{'locale': 'sw'});
      expect(
        (localeOnly['payload'] as Map<String, Object?>).containsKey(
          'notifications',
        ),
        isFalse,
      );
    });

    test('notice publication preserves a property audience', () {
      final envelope = gateway.buildEnvelope(
        _mutationFor(
          OfflineEntityType.notice,
          OutboxOperation.create,
          payload: const <String, Object?>{
            'title': 'Water interruption',
            'body': 'Water will be unavailable on Saturday morning.',
            'audienceType': 'property',
            'audienceId': 'property_1234',
          },
        ),
      );
      expect(envelope['payload'], <String, Object?>{
        'title': 'Water interruption',
        'body': 'Water will be unavailable on Saturday morning.',
        'audience': 'property',
        'audienceId': 'property_1234',
      });

      expect(
        () => gateway.buildEnvelope(
          _mutationFor(
            OfflineEntityType.notice,
            OutboxOperation.create,
            payload: const <String, Object?>{
              'title': 'Unsupported audience',
              'body': 'This payload must not silently broaden its audience.',
              'audienceType': 'building',
              'audienceId': 'building_1234',
            },
          ),
        ),
        throwsA(
          isA<RemoteSyncException>().having(
            (error) => error.retryable,
            'retryable',
            isFalse,
          ),
        ),
      );
      expect(
        () => gateway.buildEnvelope(
          _mutationFor(
            OfflineEntityType.notice,
            OutboxOperation.create,
            payload: const <String, Object?>{
              'title': 'All tenants',
              'body': 'This payload has an inconsistent audience selector.',
              'audienceType': 'allActiveTenants',
              'audienceId': 'property_1234',
            },
          ),
        ),
        throwsA(isA<RemoteSyncException>()),
      );
    });

    test('tenancy.establish omits openingBalanceMinor when null', () {
      final mutation = RemoteMutation(
        mutationId: 'mutation-2',
        entityType: OfflineEntityType.tenancy,
        entityId: 'tenancy-2',
        operation: OutboxOperation.create,
        payload: <String, Object?>{
          '_expectedVersion': 0,
          'unitId': 'unit-2',
          'tenantName': 'Test Tenant',
          'email': 'tenant@example.com',
          'phone': '+256700000000',
          'leaseStart': '2026-01-01',
          'leaseEnd': '2026-12-31',
          'monthlyRentMinor': 100000,
        },
        idempotencyKey: 'mutation-2',
        clientCreatedAt: DateTime.utc(2026, 7, 16),
      );
      final envelope = gateway.buildEnvelope(mutation);
      final payload = envelope['payload'] as Map<String, Object?>;
      expect(payload.containsKey('openingBalanceMinor'), isFalse);
    });

    test('payment.recordAgainstTenancy maps fields with snake_case method', () {
      final mutation = RemoteMutation(
        mutationId: 'mutation-3',
        entityType: OfflineEntityType.payment,
        entityId: 'payment-1',
        operation: OutboxOperation.create,
        payload: <String, Object?>{
          '_expectedVersion': 0,
          'tenancyId': 'lease-1',
          'amountMinor': 100000,
          'method': 'mtnMomo',
          'period': 'January 2026',
        },
        idempotencyKey: 'mutation-3',
        clientCreatedAt: DateTime.utc(2026, 7, 16),
      );
      final envelope = gateway.buildEnvelope(mutation);
      expect(envelope['type'], 'payment.recordAgainstTenancy');
      final payload = envelope['payload'] as Map<String, Object?>;
      expect(payload['tenancyId'], 'lease-1');
      expect(payload['amountMinor'], 100000);
      expect(payload['method'], 'mtn_momo');
      expect(payload['period'], 'January 2026');
    });

    test('accounts for every entity type', () {
      final covered = {
        ..._expectedCommands.keys.map((key) => key.$1),
        ..._neverEnqueued.keys,
      };
      // A new OfflineEntityType must be classified as either mapped to a
      // command or explicitly local-only, so it cannot be added and silently
      // start failing sync.
      expect(covered, containsAll(OfflineEntityType.values));
    });

    // Command names alone cannot catch a broken field mapping: an envelope
    // that reaches the right handler with the wrong keys fails zod validation
    // server-side and the mutation dies as permanentlyFailed. These pin the
    // payload contracts for the two money-bearing commands.
    test('tenancy.establish maps the client tenancy fields', () {
      final envelope = gateway.buildEnvelope(
        _mutationFor(
          OfflineEntityType.tenancy,
          OutboxOperation.create,
          payload: const <String, Object?>{
            'unitId': 'unit-1',
            'tenantName': 'Sandra Nakato',
            'email': 'sandra@example.ug',
            'phone': '+256700000001',
            'leaseStart': '2026-01-01T00:00:00.000Z',
            'leaseEnd': '2026-12-31T00:00:00.000Z',
            'monthlyRentMinor': 90000000,
            'balanceMinor': 250000,
          },
        ),
      );
      expect(envelope['expectedVersion'], 0);
      expect(envelope['payload'], const <String, Object?>{
        'unitId': 'unit-1',
        'displayName': 'Sandra Nakato',
        'email': 'sandra@example.ug',
        'phone': '+256700000001',
        'startDate': '2026-01-01T00:00:00.000Z',
        'endDate': '2026-12-31T00:00:00.000Z',
        'monthlyRentMinor': 90000000,
        'openingBalanceMinor': 250000,
      });
    });

    test('tenancy.establish omits an absent opening balance', () {
      final envelope = gateway.buildEnvelope(
        _mutationFor(
          OfflineEntityType.tenancy,
          OutboxOperation.create,
          payload: const <String, Object?>{
            'unitId': 'unit-1',
            'tenantName': 'Sandra Nakato',
            'email': 'sandra@example.ug',
            'phone': '+256700000001',
            'leaseStart': '2026-01-01T00:00:00.000Z',
            'leaseEnd': '2026-12-31T00:00:00.000Z',
            'monthlyRentMinor': 90000000,
          },
        ),
      );
      final payload = envelope['payload'] as Map<String, Object?>;
      // The command schema rejects unknown keys and a null here would fail
      // zod's int check, so the key must be absent, not null.
      expect(payload.containsKey('openingBalanceMinor'), isFalse);
    });

    test('payment.recordAgainstTenancy maps and snake_cases the payment', () {
      final envelope = gateway.buildEnvelope(
        _mutationFor(
          OfflineEntityType.payment,
          OutboxOperation.create,
          payload: const <String, Object?>{
            'tenancyId': 'lease-1',
            'amountMinor': 500000,
            'method': 'mtnMomo',
            'period': 'July 2026',
          },
        ),
      );
      expect(envelope['payload'], const <String, Object?>{
        'tenancyId': 'lease-1',
        'amountMinor': 500000,
        // The client's camelCase method enum must arrive as the command
        // schema's snake_case value or the whole payment is rejected.
        'method': 'mtn_momo',
        'period': 'July 2026',
      });
    });

    test(
      'a tenant-declared payment maps to payment.declare with its proof',
      () {
        // The landlord-only command rejects a tenant actor outright, so routing
        // a declaration there made every tenant-reported payment fail
        // permanently while the app said it was queued.
        final envelope = gateway.buildEnvelope(
          _mutationFor(
            OfflineEntityType.payment,
            OutboxOperation.create,
            payload: const <String, Object?>{
              'tenancyId': 'lease-1',
              'amountMinor': 450000,
              'method': 'mtnMomo',
              'period': 'July 2026',
              'reference': 'MP2607.1234.A56789',
              'declaredByTenant': true,
            },
          ),
        );
        expect(envelope['type'], 'payment.declare');
        expect(envelope['payload'], const <String, Object?>{
          'tenancyId': 'lease-1',
          'amountMinor': 450000,
          'method': 'mtn_momo',
          'period': 'July 2026',
          // Proof must survive the mapping: it is the only thing the landlord
          // has to judge the claim on.
          'reference': 'MP2607.1234.A56789',
        });
      },
    );

    test('a landlord-recorded payment still settles directly', () {
      final envelope = gateway.buildEnvelope(
        _mutationFor(
          OfflineEntityType.payment,
          OutboxOperation.create,
          payload: const <String, Object?>{
            'tenancyId': 'lease-1',
            'amountMinor': 450000,
            'method': 'cash',
            'period': 'July 2026',
            'declaredByTenant': false,
          },
        ),
      );
      expect(envelope['type'], 'payment.recordAgainstTenancy');
    });

    test('rejects an unmapped mutation without retrying forever', () {
      // subscriptionPlan is local-only, so reaching the gateway at all means a
      // repository regressed to putEntityAndEnqueue. Assert the failure is
      // non-retryable: a retryable one would spin the outbox for eight attempts.
      try {
        gateway.buildEnvelope(
          _mutationFor(
            OfflineEntityType.subscriptionPlan,
            OutboxOperation.create,
          ),
        );
        fail('Expected an unmapped mutation to throw.');
      } on RemoteSyncException catch (error) {
        expect(error.retryable, isFalse);
      }
    });
  });
}
