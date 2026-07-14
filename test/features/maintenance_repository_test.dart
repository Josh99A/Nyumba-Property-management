import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/features/maintenance/data/sembast_maintenance_repository.dart';
import 'package:nyumba_property_management/features/maintenance/domain/maintenance_request.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  Future<OfflineDatabase> openDatabase(String name) async {
    final database = OfflineDatabase(
      await databaseFactoryMemory.openDatabase(name),
    );
    await database.initialize();
    return database;
  }

  test(
    'create persists the request and its outbox command atomically',
    () async {
      final database = await openDatabase('maintenance-create.db');
      addTearDown(database.close);
      final repository = SembastMaintenanceRepository(database: database);

      final request = await repository.create(
        const CreateMaintenanceRequestInput(
          landlordId: 'landlord-1',
          tenantId: 'tenant-1',
          title: 'Leaking tap in kitchen',
          description: 'Drips continuously even when fully closed.',
          location: 'Unit A2 · Greenview Court',
          reporterName: 'Alice Namutebi',
          category: 'Plumbing',
          priority: MaintenancePriority.urgent,
        ),
      );

      final outbox = await database.readOutbox();
      expect(outbox, hasLength(1));
      expect(outbox.single.entityType, OfflineEntityType.maintenanceRequest);
      expect(outbox.single.entityId, request.id);
      expect(outbox.single.operation, OutboxOperation.create);
      expect(request.syncMetadata.needsSync, isTrue);

      final stored = await repository.getById(request.id);
      expect(stored?.title, 'Leaking tap in kitchen');
      expect(stored?.status, MaintenanceStatus.submitted);
    },
  );

  test('transition enqueues an update and rejects terminal changes', () async {
    final database = await openDatabase('maintenance-transition.db');
    addTearDown(database.close);
    final repository = SembastMaintenanceRepository(database: database);

    final request = await repository.create(
      const CreateMaintenanceRequestInput(
        landlordId: 'landlord-1',
        title: 'No power in the living room',
        description: 'Wall sockets stopped working overnight.',
        location: 'Unit D3 · Riverside Heights',
        reporterName: 'John M.',
        category: 'Electrical',
      ),
    );

    final resolved = await repository.transition(
      TransitionMaintenanceInput(
        requestId: request.id,
        status: MaintenanceStatus.resolved,
      ),
    );
    expect(resolved.status, MaintenanceStatus.resolved);
    expect(resolved.resolvedAt, isNotNull);
    expect(await database.outboxCount(), 2);

    await expectLater(
      repository.transition(
        TransitionMaintenanceInput(
          requestId: request.id,
          status: MaintenanceStatus.inProgress,
        ),
      ),
      throwsA(isA<DomainValidationException>()),
    );
  });

  test('tenant filter only returns the reporting tenant requests', () async {
    final database = await openDatabase('maintenance-filter.db');
    addTearDown(database.close);
    final repository = SembastMaintenanceRepository(database: database);

    await repository.create(
      const CreateMaintenanceRequestInput(
        landlordId: 'landlord-1',
        tenantId: 'tenant-1',
        title: 'Bedroom door lock is loose',
        description: 'Lock barrel turns without engaging.',
        location: 'Unit C1 · Nyumbani Gardens',
        reporterName: 'David Kato',
      ),
    );
    await repository.create(
      const CreateMaintenanceRequestInput(
        landlordId: 'landlord-1',
        title: 'Water not draining in bathroom',
        description: 'The shower drain backs up quickly.',
        location: 'Unit B1 · Sunset Apartments',
        reporterName: 'Sarah W.',
      ),
    );

    final tenantRequests = await repository.getAll(tenantId: 'tenant-1');
    expect(tenantRequests, hasLength(1));
    expect(tenantRequests.single.tenantId, 'tenant-1');

    final landlordRequests = await repository.getAll(landlordId: 'landlord-1');
    expect(landlordRequests, hasLength(2));
  });
}
