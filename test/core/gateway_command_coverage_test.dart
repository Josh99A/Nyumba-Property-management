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
  (OfflineEntityType.payment, OutboxOperation.create):
      'payment.recordAgainstTenancy',
  (OfflineEntityType.maintenanceRequest, OutboxOperation.create):
      'maintenance.create',
  (OfflineEntityType.maintenanceRequest, OutboxOperation.update):
      'maintenance.updateStatus',
  (OfflineEntityType.notice, OutboxOperation.create): 'notice.publish',
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
};

RemoteMutation _mutationFor(
  OfflineEntityType entityType,
  OutboxOperation operation,
) => RemoteMutation(
  mutationId: 'mutation-1',
  entityType: entityType,
  entityId: 'aggregate-1',
  operation: operation,
  // Enough of a payload for any mapping to read; absent keys map to null,
  // which is what a real sparse aggregate would produce anyway.
  payload: const <String, Object?>{'_expectedVersion': 3},
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
