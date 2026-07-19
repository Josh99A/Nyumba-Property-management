import 'package:nyumba_property_management/core/offline/json_reader.dart';
import 'package:nyumba_property_management/core/offline/sync_metadata_mapper.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';

final class ListingMapper {
  const ListingMapper._();

  /// Explicit server-projection allowlist. Production Functions must derive
  /// these values from canonical records and validated public media; this
  /// helper documents and tests the client-side shape without treating it as
  /// authoritative.
  static Map<String, Object?> toPublicProjection(Listing listing) =>
      <String, Object?>{
        'id': listing.id,
        'publicContactToken': listing.publicContactToken,
        'title': listing.title,
        'description': listing.description,
        'unitType': listing.unitType,
        'amenities': listing.amenities,
        'accessibilityFeatures': listing.accessibilityFeatures,
        'bedrooms': listing.bedrooms,
        'bathrooms': listing.bathrooms,
        'floor': listing.floor,
        'floorAreaSquareMetres': listing.floorAreaSquareMetres,
        'furnished': listing.furnished,
        'parkingSpaces': listing.parkingSpaces,
        'city': listing.city,
        'district': listing.district,
        'neighborhood': listing.neighborhood,
        'approximateLatitude': listing.approximateLatitude,
        'approximateLongitude': listing.approximateLongitude,
        'monthlyRentMinor': listing.monthlyRentMinor,
        'currency': listing.currency,
        'securityDepositMinor': listing.securityDepositMinor,
        'serviceChargeMinor': listing.serviceChargeMinor,
        'utilitiesIncluded': listing.utilitiesIncluded,
        'availableFrom': listing.availableFrom?.toUtc().toIso8601String(),
        'minimumLeaseMonths': listing.minimumLeaseMonths,
        'petsPolicy': listing.petsPolicy,
        'smokingPolicy': listing.smokingPolicy,
        'viewingInstructions': listing.viewingInstructions,
        'imageUrls': listing.imageUrls,
        'videoUrl': listing.videoUrl,
        'status': listing.status.name,
        'publishedAt': listing.publishedAt?.toUtc().toIso8601String(),
        'expiresAt': listing.expiresAt?.toUtc().toIso8601String(),
        'projectionVersion': listing.projectionVersion,
      };

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
    'unitType': listing.unitType,
    'floor': listing.floor,
    'floorAreaSquareMetres': listing.floorAreaSquareMetres,
    'furnished': listing.furnished,
    'parkingSpaces': listing.parkingSpaces,
    'amenities': listing.amenities,
    'accessibilityFeatures': listing.accessibilityFeatures,
    'city': listing.city,
    'district': listing.district,
    'neighborhood': listing.neighborhood,
    'approximateLatitude': listing.approximateLatitude,
    'approximateLongitude': listing.approximateLongitude,
    'availableFrom': listing.availableFrom?.toUtc().toIso8601String(),
    'minimumLeaseMonths': listing.minimumLeaseMonths,
    'securityDepositMinor': listing.securityDepositMinor,
    'serviceChargeMinor': listing.serviceChargeMinor,
    'utilitiesIncluded': listing.utilitiesIncluded,
    'petsPolicy': listing.petsPolicy,
    'smokingPolicy': listing.smokingPolicy,
    'viewingInstructions': listing.viewingInstructions,
    'imageUrls': listing.imageUrls,
    'videoUrl': listing.videoUrl,
    'contactPhone': listing.contactPhone,
    'contactEmail': listing.contactEmail,
    'publicContactToken': listing.publicContactToken,
    'createdAt': listing.createdAt.toUtc().toIso8601String(),
    'updatedAt': listing.updatedAt.toUtc().toIso8601String(),
    'publishedAt': listing.publishedAt?.toUtc().toIso8601String(),
    'expiresAt': listing.expiresAt?.toUtc().toIso8601String(),
    'projectionVersion': listing.projectionVersion,
    'syncMetadata': SyncMetadataMapper.toJson(listing.syncMetadata),
  };

  /// Whether [fromJson] can read this record. Used by the workspace-open sweep
  /// to drop cached records written under an older pull shape.
  static bool canDecode(Map<String, Object?> json) {
    try {
      fromJson(json);
      return true;
    } on Object {
      return false;
    }
  }

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
      unitType: reader.optionalString('unitType') ?? 'other',
      floor: reader.optionalInt('floor'),
      floorAreaSquareMetres: reader.optionalInt('floorAreaSquareMetres'),
      furnished: reader.optionalBool('furnished'),
      parkingSpaces: reader.optionalInt('parkingSpaces'),
      amenities: reader.stringList('amenities'),
      accessibilityFeatures: reader.stringList('accessibilityFeatures'),
      city: reader.optionalString('city') ?? 'Kampala',
      district: reader.optionalString('district'),
      neighborhood:
          reader.optionalString('neighborhood') ??
          reader.optionalString('city') ??
          'Kampala',
      approximateLatitude: reader.optionalDouble('approximateLatitude'),
      approximateLongitude: reader.optionalDouble('approximateLongitude'),
      availableFrom: reader.optionalDate('availableFrom'),
      minimumLeaseMonths: reader.optionalInt('minimumLeaseMonths'),
      securityDepositMinor: reader.optionalInt('securityDepositMinor'),
      serviceChargeMinor: reader.optionalInt('serviceChargeMinor'),
      utilitiesIncluded: reader.stringList('utilitiesIncluded'),
      petsPolicy: reader.optionalString('petsPolicy'),
      smokingPolicy: reader.optionalString('smokingPolicy'),
      viewingInstructions: reader.optionalString('viewingInstructions'),
      imageUrls: reader.stringList('imageUrls'),
      videoUrl: reader.optionalString('videoUrl'),
      contactPhone: reader.optionalString('contactPhone'),
      contactEmail: reader.optionalString('contactEmail'),
      publicContactToken: reader.optionalString('publicContactToken'),
      createdAt: reader.requiredDate('createdAt'),
      updatedAt: reader.requiredDate('updatedAt'),
      publishedAt: reader.optionalDate('publishedAt'),
      expiresAt: reader.optionalDate('expiresAt'),
      projectionVersion: reader.optionalInt('projectionVersion'),
      syncMetadata: SyncMetadataMapper.fromJson(json['syncMetadata']),
    );
  }
}
