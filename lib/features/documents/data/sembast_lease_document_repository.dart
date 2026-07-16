// ignore_for_file: prefer_initializing_formals

import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/id_generator.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/uuid_id_generator.dart';
import 'package:nyumba_property_management/features/documents/data/mappers/lease_document_mapper.dart';
import 'package:nyumba_property_management/features/documents/domain/lease_document.dart';
import 'package:nyumba_property_management/features/documents/domain/lease_document_repository.dart';

final class SembastLeaseDocumentRepository implements LeaseDocumentRepository {
  SembastLeaseDocumentRepository({
    required OfflineDatabase database,
    IdGenerator? idGenerator,
    Clock clock = const SystemClock(),
  }) : _database = database,
       _idGenerator = idGenerator ?? UuidIdGenerator(),
       _clock = clock;

  final OfflineDatabase _database;
  final IdGenerator _idGenerator;
  final Clock _clock;

  static String _prefix(LeaseDocumentType type) => switch (type) {
    LeaseDocumentType.invoice => 'INV',
    LeaseDocumentType.receipt => 'RCT',
    LeaseDocumentType.lease => 'LSE',
    LeaseDocumentType.notice => 'NTC',
  };

  @override
  Future<LeaseDocument> create(CreateLeaseDocumentInput input) async {
    final now = _clock.now().toUtc();
    final document = LeaseDocument(
      id: _idGenerator.generate(),
      number:
          '${_prefix(input.type)}-${now.year}-'
          '${(now.millisecondsSinceEpoch % 10000).toString().padLeft(4, '0')}',
      landlordId: input.landlordId.trim(),
      tenantId: input.tenantId?.trim(),
      type: input.type,
      recipient: input.recipient.trim(),
      propertyName: input.propertyName.trim(),
      unitLabel: input.unitLabel.trim(),
      amountMinor: input.amountMinor,
      statusLabel: input.statusLabel.trim(),
      issuedAt: now,
      createdAt: now,
      updatedAt: now,
      syncMetadata: const SyncMetadata.local(),
    );
    await _database.putLocalEntity(
      entityType: OfflineEntityType.leaseDocument,
      entityId: document.id,
      entity: LeaseDocumentMapper.toJson(document),
      reason: LocalOnlyReason.localWorkspaceOnly,
      createOnly: true,
    );
    return document;
  }

  @override
  Future<List<LeaseDocument>> getAll({
    String? landlordId,
    String? tenantId,
  }) async => _filterAndSort(
    (await _database.readEntities(
      OfflineEntityType.leaseDocument,
    )).map(LeaseDocumentMapper.fromJson),
    landlordId,
    tenantId,
  );

  @override
  Future<LeaseDocument?> getById(String id) async {
    final json = await _database.readEntity(
      OfflineEntityType.leaseDocument,
      id,
    );
    return json == null ? null : LeaseDocumentMapper.fromJson(json);
  }

  @override
  Stream<List<LeaseDocument>> watchAll({
    String? landlordId,
    String? tenantId,
  }) => _database
      .watchEntities(OfflineEntityType.leaseDocument)
      .map(
        (items) => _filterAndSort(
          items.map(LeaseDocumentMapper.fromJson),
          landlordId,
          tenantId,
        ),
      );

  static List<LeaseDocument> _filterAndSort(
    Iterable<LeaseDocument> items,
    String? landlordId,
    String? tenantId,
  ) {
    final result = items
        .where(
          (document) =>
              (landlordId == null || document.landlordId == landlordId) &&
              (tenantId == null || document.tenantId == tenantId),
        )
        .toList(growable: false);
    result.sort((left, right) => right.issuedAt.compareTo(left.issuedAt));
    return result;
  }
}
