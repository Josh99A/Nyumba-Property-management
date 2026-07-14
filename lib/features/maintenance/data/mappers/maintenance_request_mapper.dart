import 'package:nyumba_property_management/core/offline/json_reader.dart';
import 'package:nyumba_property_management/core/offline/sync_metadata_mapper.dart';
import 'package:nyumba_property_management/features/maintenance/domain/maintenance_request.dart';

final class MaintenanceRequestMapper {
  const MaintenanceRequestMapper._();

  static Map<String, Object?> toJson(MaintenanceRequest request) =>
      <String, Object?>{
        'id': request.id,
        'reference': request.reference,
        'landlordId': request.landlordId,
        'tenantId': request.tenantId,
        'propertyId': request.propertyId,
        'unitId': request.unitId,
        'title': request.title,
        'description': request.description,
        'location': request.location,
        'category': request.category,
        'priority': request.priority.name,
        'status': request.status.name,
        'reporterName': request.reporterName,
        'assignee': request.assignee,
        'appointment': request.appointment,
        'allowAccess': request.allowAccess,
        'photoCount': request.photoCount,
        'reportedAt': request.reportedAt.toUtc().toIso8601String(),
        'resolvedAt': request.resolvedAt?.toUtc().toIso8601String(),
        'createdAt': request.createdAt.toUtc().toIso8601String(),
        'updatedAt': request.updatedAt.toUtc().toIso8601String(),
        'syncMetadata': SyncMetadataMapper.toJson(request.syncMetadata),
      };

  static MaintenanceRequest fromJson(Map<String, Object?> json) {
    final reader = JsonReader(json);
    return MaintenanceRequest(
      id: reader.requiredString('id'),
      reference: reader.requiredString('reference'),
      landlordId: reader.requiredString('landlordId'),
      tenantId: reader.optionalString('tenantId'),
      propertyId: reader.optionalString('propertyId'),
      unitId: reader.optionalString('unitId'),
      title: reader.requiredString('title'),
      description: reader.requiredString('description'),
      location: reader.requiredString('location'),
      category: reader.requiredString('category'),
      priority: reader.enumValue('priority', MaintenancePriority.values),
      status: reader.enumValue('status', MaintenanceStatus.values),
      reporterName: reader.requiredString('reporterName'),
      assignee: reader.optionalString('assignee'),
      appointment: reader.optionalString('appointment'),
      allowAccess: reader.optionalBool('allowAccess'),
      photoCount: reader.optionalInt('photoCount') ?? 0,
      reportedAt: reader.requiredDate('reportedAt'),
      resolvedAt: reader.optionalDate('resolvedAt'),
      createdAt: reader.requiredDate('createdAt'),
      updatedAt: reader.requiredDate('updatedAt'),
      syncMetadata: SyncMetadataMapper.fromJson(json['syncMetadata']),
    );
  }
}
