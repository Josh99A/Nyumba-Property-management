import 'package:nyumba_property_management/core/offline/json_reader.dart';
import 'package:nyumba_property_management/core/offline/sync_metadata_mapper.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit.dart';

final class UnitMapper {
  const UnitMapper._();

  static Map<String, Object?> toJson(Unit unit) => <String, Object?>{
    'id': unit.id,
    'propertyId': unit.propertyId,
    'landlordId': unit.landlordId,
    'label': unit.label,
    'type': unit.type.name,
    'status': unit.status.name,
    'monthlyRentMinor': unit.monthlyRentMinor,
    'currency': unit.currency,
    'bedrooms': unit.bedrooms,
    'bathrooms': unit.bathrooms,
    'floor': unit.floor,
    'description': unit.description,
    'amenities': unit.amenities,
    'createdAt': unit.createdAt.toUtc().toIso8601String(),
    'updatedAt': unit.updatedAt.toUtc().toIso8601String(),
    'syncMetadata': SyncMetadataMapper.toJson(unit.syncMetadata),
  };

  static Unit fromJson(Map<String, Object?> json) {
    final reader = JsonReader(json);
    return Unit(
      id: reader.requiredString('id'),
      propertyId: reader.requiredString('propertyId'),
      landlordId: reader.requiredString('landlordId'),
      label: reader.requiredString('label'),
      type: reader.enumValue('type', UnitType.values),
      status: reader.enumValue('status', UnitStatus.values),
      monthlyRentMinor: reader.requiredInt('monthlyRentMinor'),
      currency: reader.requiredString('currency'),
      bedrooms: reader.requiredInt('bedrooms'),
      bathrooms: reader.requiredInt('bathrooms'),
      floor: reader.optionalInt('floor'),
      description: reader.optionalString('description'),
      amenities: reader.stringList('amenities'),
      createdAt: reader.requiredDate('createdAt'),
      updatedAt: reader.requiredDate('updatedAt'),
      syncMetadata: SyncMetadataMapper.fromJson(json['syncMetadata']),
    );
  }
}
