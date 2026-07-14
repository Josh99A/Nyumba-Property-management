// ignore_for_file: prefer_initializing_formals

import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/core/domain/id_generator.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/core/offline/uuid_id_generator.dart';
import 'package:nyumba_property_management/features/maintenance/data/mappers/maintenance_request_mapper.dart';
import 'package:nyumba_property_management/features/maintenance/domain/maintenance_request.dart';
import 'package:nyumba_property_management/features/maintenance/domain/maintenance_repository.dart';

final class SembastMaintenanceRepository implements MaintenanceRepository {
  SembastMaintenanceRepository({
    required OfflineDatabase database,
    IdGenerator? idGenerator,
    Clock clock = const SystemClock(),
  }) : _database = database,
       _idGenerator = idGenerator ?? UuidIdGenerator(),
       _clock = clock;

  final OfflineDatabase _database;
  final IdGenerator _idGenerator;
  final Clock _clock;

  @override
  Future<MaintenanceRequest> create(CreateMaintenanceRequestInput input) async {
    final now = _clock.now().toUtc();
    final request = MaintenanceRequest(
      id: _idGenerator.generate(),
      reference: 'MNT-${now.millisecondsSinceEpoch % 100000}',
      landlordId: input.landlordId.trim(),
      tenantId: _optional(input.tenantId),
      propertyId: _optional(input.propertyId),
      unitId: _optional(input.unitId),
      title: input.title.trim(),
      description: input.description.trim(),
      location: input.location.trim(),
      category: input.category.trim(),
      priority: input.priority,
      status: MaintenanceStatus.submitted,
      reporterName: input.reporterName.trim(),
      allowAccess: input.allowAccess,
      photoCount: input.photoCount,
      reportedAt: now,
      createdAt: now,
      updatedAt: now,
      syncMetadata: const SyncMetadata.pending(),
    );
    await _database.putEntityAndEnqueue(
      entityType: OfflineEntityType.maintenanceRequest,
      entityId: request.id,
      entity: MaintenanceRequestMapper.toJson(request),
      mutationId: _idGenerator.generate(),
      operation: OutboxOperation.create,
      createdAt: now,
      createOnly: true,
    );
    return request;
  }

  @override
  Future<MaintenanceRequest> transition(
    TransitionMaintenanceInput input,
  ) async {
    final current = await getById(input.requestId);
    if (current == null) {
      throw EntityNotFoundException('maintenance request', input.requestId);
    }
    if (current.status.isTerminal && input.status != current.status) {
      throw DomainValidationException(<String, String>{
        'status': 'a ${current.status.name} request cannot change state',
      });
    }
    final now = _clock.now().toUtc();
    final updated = current.copyWith(
      status: input.status,
      assignee: input.assignee?.trim(),
      appointment: input.appointment?.trim(),
      resolvedAt: input.status == MaintenanceStatus.resolved ? now : null,
      updatedAt: now,
      syncMetadata: current.syncMetadata.markPending(),
    );
    await _database.putEntityAndEnqueue(
      entityType: OfflineEntityType.maintenanceRequest,
      entityId: updated.id,
      entity: MaintenanceRequestMapper.toJson(updated),
      mutationId: _idGenerator.generate(),
      operation: OutboxOperation.update,
      createdAt: now,
    );
    return updated;
  }

  @override
  Future<List<MaintenanceRequest>> getAll({
    String? landlordId,
    String? tenantId,
  }) async => _filterAndSort(
    (await _database.readEntities(
      OfflineEntityType.maintenanceRequest,
    )).map(MaintenanceRequestMapper.fromJson),
    landlordId,
    tenantId,
  );

  @override
  Future<MaintenanceRequest?> getById(String id) async {
    final json = await _database.readEntity(
      OfflineEntityType.maintenanceRequest,
      id,
    );
    return json == null ? null : MaintenanceRequestMapper.fromJson(json);
  }

  @override
  Stream<List<MaintenanceRequest>> watchAll({
    String? landlordId,
    String? tenantId,
  }) => _database
      .watchEntities(OfflineEntityType.maintenanceRequest)
      .map(
        (items) => _filterAndSort(
          items.map(MaintenanceRequestMapper.fromJson),
          landlordId,
          tenantId,
        ),
      );

  static List<MaintenanceRequest> _filterAndSort(
    Iterable<MaintenanceRequest> items,
    String? landlordId,
    String? tenantId,
  ) {
    final result = items
        .where(
          (request) =>
              (landlordId == null || request.landlordId == landlordId) &&
              (tenantId == null || request.tenantId == tenantId),
        )
        .toList(growable: false);
    result.sort((left, right) => right.reportedAt.compareTo(left.reportedAt));
    return result;
  }

  static String? _optional(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
