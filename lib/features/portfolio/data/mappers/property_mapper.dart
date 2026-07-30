import 'package:nyumba_property_management/core/config/market_config.dart';
import 'package:nyumba_property_management/core/domain/coordinates.dart';
import 'package:nyumba_property_management/core/domain/json_reader.dart';
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
    // Two flat scalars rather than a nested object, matching how the listing
    // aggregate carries its pin. `FirestoreCloudReadGateway.toClientShape`
    // flattens the server's nested `location` into the same pair.
    'latitude': property.location?.latitude,
    'longitude': property.location?.longitude,
    'imageUrls': property.imageUrls,
    'createdAt': property.createdAt.toUtc().toIso8601String(),
    'updatedAt': property.updatedAt.toUtc().toIso8601String(),
    'isDeleted': property.isArchived,
    'deletedAt': property.archivedAt?.toUtc().toIso8601String(),
    'version': property.serverVersion,
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
      // Lenient rather than strict: a half-written or out-of-range pair means
      // "no pin", not an unreadable property. A record that cannot decode
      // disappears from the landlord's portfolio, which is a far worse
      // outcome than a missing map.
      location: Coordinates.tryFrom(
        reader.optionalDouble('latitude'),
        reader.optionalDouble('longitude'),
      ),
      // Older local records may predate the two-photo property policy. Keep
      // the primary-first pair instead of making the property unreadable.
      imageUrls: reader
          .stringList('imageUrls')
          .take(NyumbaMarket.maxPropertyPhotos)
          .toList(growable: false),
      createdAt: reader.requiredDate('createdAt'),
      updatedAt: reader.requiredDate('updatedAt'),
      isArchived: reader.optionalBool('isDeleted'),
      archivedAt: reader.optionalDate('deletedAt'),
      // The server's optimistic-concurrency counter, echoed back on the next
      // edit. Optional because the public projection withholds it.
      serverVersion: reader.optionalInt('version'),
    );
  }
}
