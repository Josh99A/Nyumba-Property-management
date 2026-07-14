import 'package:nyumba_property_management/core/offline/json_reader.dart';
import 'package:nyumba_property_management/core/offline/sync_metadata_mapper.dart';
import 'package:nyumba_property_management/features/documents/domain/lease_document.dart';

final class LeaseDocumentMapper {
  const LeaseDocumentMapper._();

  static Map<String, Object?> toJson(LeaseDocument document) =>
      <String, Object?>{
        'id': document.id,
        'number': document.number,
        'landlordId': document.landlordId,
        'tenantId': document.tenantId,
        'type': document.type.name,
        'recipient': document.recipient,
        'propertyName': document.propertyName,
        'unitLabel': document.unitLabel,
        'amountMinor': document.amountMinor,
        'statusLabel': document.statusLabel,
        'issuedAt': document.issuedAt.toUtc().toIso8601String(),
        'createdAt': document.createdAt.toUtc().toIso8601String(),
        'updatedAt': document.updatedAt.toUtc().toIso8601String(),
        'syncMetadata': SyncMetadataMapper.toJson(document.syncMetadata),
      };

  static LeaseDocument fromJson(Map<String, Object?> json) {
    final reader = JsonReader(json);
    return LeaseDocument(
      id: reader.requiredString('id'),
      number: reader.requiredString('number'),
      landlordId: reader.requiredString('landlordId'),
      tenantId: reader.optionalString('tenantId'),
      type: reader.enumValue('type', LeaseDocumentType.values),
      recipient: reader.requiredString('recipient'),
      propertyName: reader.requiredString('propertyName'),
      unitLabel: reader.requiredString('unitLabel'),
      amountMinor: reader.requiredInt('amountMinor'),
      statusLabel: reader.requiredString('statusLabel'),
      issuedAt: reader.requiredDate('issuedAt'),
      createdAt: reader.requiredDate('createdAt'),
      updatedAt: reader.requiredDate('updatedAt'),
      syncMetadata: SyncMetadataMapper.fromJson(json['syncMetadata']),
    );
  }
}
