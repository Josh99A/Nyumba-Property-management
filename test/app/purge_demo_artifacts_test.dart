import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  group('purge demo artifacts', () {
    // Rewritten around a maintenance request rather than a property, unit, or
    // listing. All three of those have moved to the server and no longer touch
    // the local mirror at all, so a sweep over it could not find them, and
    // asserting otherwise would have been testing the fixture rather than the
    // code.
    //
    // The mechanism itself still matters for the features that remain
    // mirrored, and it retires when the last of them moves.
    test('demo fixtures and their queued commands are both removed', () async {
      // Reproduces the real situation: an older deployed build seeded demo data
      // into the anonymous workspace through the normal repository path — so
      // entities AND outbox intents exist — the workspace name never changed,
      // and remote pulls only ever merge. Nothing removed the fixtures, so a
      // returning visitor kept seeing them.
      final database = OfflineDatabase(
        await databaseFactoryMemory.openDatabase('stale-anonymous.db'),
      );
      await database.initialize();
      addTearDown(database.close);

      final now = DateTime.utc(2026, 7, 29, 9);
      Future<void> seed({
        required String id,
        required String landlordId,
        required String mutationId,
      }) => database.putEntityAndEnqueue(
        entityType: OfflineEntityType.maintenanceRequest,
        entityId: id,
        entity: <String, Object?>{
          'id': id,
          // The `demo-` prefix is unambiguous ownership evidence: real
          // identities are Firebase UIDs or client UUIDs, and neither can
          // start with it.
          'landlordId': landlordId,
          'title': 'Leaking tap',
          'createdAt': now.toIso8601String(),
        },
        mutationId: mutationId,
        operation: OutboxOperation.create,
        createdAt: now,
        createOnly: true,
      );

      await seed(
        id: 'demo-request',
        landlordId: 'demo-landlord-001',
        mutationId: 'demo-mutation',
      );
      await seed(
        id: 'real-request',
        landlordId: 'x7Qm2LpV9aRt4KcW8bZnE5yGdJ1u',
        mutationId: 'real-mutation',
      );

      final removed = await database.purgeDemoArtifacts();

      // One entity plus its queued command.
      expect(removed, 2);
      final survivors = await database.readEntities(
        OfflineEntityType.maintenanceRequest,
      );
      expect(survivors.map((record) => record['id']), <String>['real-request']);
      // The fixture's sync intent must go with it: left behind it would retry a
      // command forever for an aggregate that no longer exists. The real
      // record's intent must stay.
      expect(
        (await database.readOutbox()).map((entry) => entry.entityId),
        <String>['real-request'],
      );

      // Re-running on a clean workspace is a no-op, since this executes on
      // every workspace open.
      expect(await database.purgeDemoArtifacts(), 0);
    });
  });
}
