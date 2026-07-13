import 'package:nyumba_property_management/core/offline/json_reader.dart';
import 'package:nyumba_property_management/core/offline/sync_metadata_mapper.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property.dart';

final class PropertyMapper {
  const PropertyMapper._();

  static Map<String, Object?> toJson(Property property) => <String, Object?>{
    'id': property.id,
    'landlordId': property.landlordId,
    'name': property.name,
    'addressLine': property.addressLine,
    'city': property.city,
    'country': property.country,
    'description': property.description,
    'createdAt': property.createdAt.toUtc().toIso8601String(),
    'updatedAt': property.updatedAt.toUtc().toIso8601String(),
    'syncMetadata': SyncMetadataMapper.toJson(property.syncMetadata),
  };

  static Property fromJson(Map<String, Object?> json) {
    final reader = JsonReader(json);
    return Property(
      id: reader.requiredString('id'),
      landlordId: reader.requiredString('landlordId'),
      name: reader.requiredString('name'),
      addressLine: reader.requiredString('addressLine'),
      city: reader.requiredString('city'),
      country: reader.requiredString('country'),
      description: reader.optionalString('description'),
      createdAt: reader.requiredDate('createdAt'),
      updatedAt: reader.requiredDate('updatedAt'),
      syncMetadata: SyncMetadataMapper.fromJson(json['syncMetadata']),
    );
  }
}
