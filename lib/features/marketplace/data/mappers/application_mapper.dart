import 'package:nyumba_property_management/core/offline/json_reader.dart';
import 'package:nyumba_property_management/core/offline/sync_metadata_mapper.dart';
import 'package:nyumba_property_management/features/marketplace/domain/application.dart';

final class ApplicationMapper {
  const ApplicationMapper._();

  static Map<String, Object?> toJson(RentalApplication application) =>
      <String, Object?>{
        'id': application.id,
        'listingId': application.listingId,
        'unitId': application.unitId,
        'propertyId': application.propertyId,
        'applicantId': application.applicantId,
        'applicantName': application.applicantName,
        'applicantEmail': application.applicantEmail,
        'applicantPhone': application.applicantPhone,
        'message': application.message,
        'desiredMoveIn': application.desiredMoveIn?.toUtc().toIso8601String(),
        'status': application.status.name,
        'createdAt': application.createdAt.toUtc().toIso8601String(),
        'updatedAt': application.updatedAt.toUtc().toIso8601String(),
        'syncMetadata': SyncMetadataMapper.toJson(application.syncMetadata),
      };

  static RentalApplication fromJson(Map<String, Object?> json) {
    final reader = JsonReader(json);
    return RentalApplication(
      id: reader.requiredString('id'),
      listingId: reader.requiredString('listingId'),
      unitId: reader.requiredString('unitId'),
      propertyId: reader.requiredString('propertyId'),
      applicantId: reader.requiredString('applicantId'),
      applicantName: reader.requiredString('applicantName'),
      applicantEmail: reader.requiredString('applicantEmail'),
      applicantPhone: reader.requiredString('applicantPhone'),
      message: reader.optionalString('message'),
      desiredMoveIn: reader.optionalDate('desiredMoveIn'),
      status: reader.enumValue('status', ApplicationStatus.values),
      createdAt: reader.requiredDate('createdAt'),
      updatedAt: reader.requiredDate('updatedAt'),
      syncMetadata: SyncMetadataMapper.fromJson(json['syncMetadata']),
    );
  }
}
