import 'package:nyumba_property_management/core/offline/json_reader.dart';
import 'package:nyumba_property_management/core/offline/sync_metadata_mapper.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';

final class ListingMapper {
  const ListingMapper._();

  static Map<String, Object?> toJson(Listing listing) => <String, Object?>{
    'id': listing.id,
    'unitId': listing.unitId,
    'propertyId': listing.propertyId,
    'landlordId': listing.landlordId,
    'title': listing.title,
    'description': listing.description,
    'monthlyRentMinor': listing.monthlyRentMinor,
    'currency': listing.currency,
    'status': listing.status.name,
    'bedrooms': listing.bedrooms,
    'bathrooms': listing.bathrooms,
    'availableFrom': listing.availableFrom?.toUtc().toIso8601String(),
    'imageUrls': listing.imageUrls,
    'contactPhone': listing.contactPhone,
    'contactEmail': listing.contactEmail,
    'createdAt': listing.createdAt.toUtc().toIso8601String(),
    'updatedAt': listing.updatedAt.toUtc().toIso8601String(),
    'publishedAt': listing.publishedAt?.toUtc().toIso8601String(),
    'syncMetadata': SyncMetadataMapper.toJson(listing.syncMetadata),
  };

  static Listing fromJson(Map<String, Object?> json) {
    final reader = JsonReader(json);
    return Listing(
      id: reader.requiredString('id'),
      unitId: reader.requiredString('unitId'),
      propertyId: reader.requiredString('propertyId'),
      landlordId: reader.requiredString('landlordId'),
      title: reader.requiredString('title'),
      description: reader.requiredString('description'),
      monthlyRentMinor: reader.requiredInt('monthlyRentMinor'),
      currency: reader.requiredString('currency'),
      status: reader.enumValue('status', ListingStatus.values),
      bedrooms: reader.optionalInt('bedrooms'),
      bathrooms: reader.optionalInt('bathrooms'),
      availableFrom: reader.optionalDate('availableFrom'),
      imageUrls: reader.stringList('imageUrls'),
      contactPhone: reader.optionalString('contactPhone'),
      contactEmail: reader.optionalString('contactEmail'),
      createdAt: reader.requiredDate('createdAt'),
      updatedAt: reader.requiredDate('updatedAt'),
      publishedAt: reader.optionalDate('publishedAt'),
      syncMetadata: SyncMetadataMapper.fromJson(json['syncMetadata']),
    );
  }
}
