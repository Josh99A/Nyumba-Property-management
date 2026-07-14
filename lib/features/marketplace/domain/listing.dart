import '../../../core/domain/domain_validation.dart';
import '../../../core/domain/sync_metadata.dart';

enum ListingStatus { draft, published, paused, closed }

final class Listing {
  Listing({
    required this.id,
    required this.unitId,
    required this.propertyId,
    required this.landlordId,
    required this.title,
    required this.description,
    required this.monthlyRentMinor,
    required this.currency,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.syncMetadata,
    this.bedrooms,
    this.bathrooms,
    this.unitType,
    this.floor,
    this.floorAreaSquareMetres,
    this.furnished = false,
    this.parkingSpaces,
    List<String> amenities = const <String>[],
    List<String> accessibilityFeatures = const <String>[],
    required this.city,
    this.district,
    this.neighborhood,
    this.approximateLatitude,
    this.approximateLongitude,
    this.availableFrom,
    this.minimumLeaseMonths,
    this.securityDepositMinor,
    this.serviceChargeMinor,
    List<String> utilitiesIncluded = const <String>[],
    this.petsPolicy,
    this.smokingPolicy,
    this.viewingInstructions,
    List<String> imageUrls = const <String>[],
    this.videoUrl,
    this.contactPhone,
    this.contactEmail,
    this.publicContactToken,
    this.publishedAt,
    this.expiresAt,
    this.projectionVersion,
  }) : amenities = List.unmodifiable(amenities),
       accessibilityFeatures = List.unmodifiable(accessibilityFeatures),
       utilitiesIncluded = List.unmodifiable(utilitiesIncluded),
       imageUrls = List.unmodifiable(imageUrls) {
    validate();
  }

  final String id;
  final String unitId;
  final String propertyId;
  final String landlordId;
  final String title;
  final String description;
  final int monthlyRentMinor;
  final String currency;
  final ListingStatus status;

  /// Copied from the advertised unit when the draft is created; null on
  /// records that predate this projection field.
  final int? bedrooms;
  final int? bathrooms;
  final String? unitType;
  final int? floor;
  final int? floorAreaSquareMetres;
  final bool furnished;
  final int? parkingSpaces;
  final List<String> amenities;
  final List<String> accessibilityFeatures;
  final String city;
  final String? district;
  final String? neighborhood;
  final double? approximateLatitude;
  final double? approximateLongitude;
  final DateTime? availableFrom;
  final int? minimumLeaseMonths;
  final int? securityDepositMinor;
  final int? serviceChargeMinor;
  final List<String> utilitiesIncluded;
  final String? petsPolicy;
  final String? smokingPolicy;
  final String? viewingInstructions;
  final List<String> imageUrls;
  final String? videoUrl;

  /// Private routing details. Public projections use [publicContactToken]
  /// unless product policy explicitly opts in to exposing direct contact data.
  final String? contactPhone;
  final String? contactEmail;
  final String? publicContactToken;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? publishedAt;
  final DateTime? expiresAt;
  final int? projectionVersion;
  final SyncMetadata syncMetadata;

  /// Locally requested publication is not a public listing until the server
  /// has acknowledged and merged the canonical state.
  bool get isPublic =>
      status == ListingStatus.published &&
      syncMetadata.state == EntitySyncState.synced;

  void validate() {
    DomainValidation.check(<String, String?>{
      'id': DomainValidation.requiredText(id, maxLength: 100),
      'unitId': DomainValidation.requiredText(unitId, maxLength: 100),
      'propertyId': DomainValidation.requiredText(propertyId, maxLength: 100),
      'landlordId': DomainValidation.requiredText(landlordId, maxLength: 100),
      'title': DomainValidation.requiredText(title, maxLength: 140),
      'description': DomainValidation.optionalText(
        description,
        maxLength: 5000,
      ),
      'monthlyRentMinor': DomainValidation.positiveMinorUnits(monthlyRentMinor),
      'currency': DomainValidation.currencyCode(currency),
      'unitType': DomainValidation.optionalText(unitType, maxLength: 80),
      'floor': floor == null ? null : DomainValidation.nonNegativeInt(floor!),
      'floorAreaSquareMetres': floorAreaSquareMetres == null
          ? null
          : DomainValidation.nonNegativeInt(floorAreaSquareMetres!),
      'parkingSpaces': parkingSpaces == null
          ? null
          : DomainValidation.nonNegativeInt(parkingSpaces!),
      'city': DomainValidation.requiredText(city, maxLength: 100),
      'district': DomainValidation.optionalText(district, maxLength: 100),
      'neighborhood': DomainValidation.optionalText(
        neighborhood,
        maxLength: 100,
      ),
      'approximateLatitude': _coordinateError(
        approximateLatitude,
        minimum: -90,
        maximum: 90,
      ),
      'approximateLongitude': _coordinateError(
        approximateLongitude,
        minimum: -180,
        maximum: 180,
      ),
      'minimumLeaseMonths': minimumLeaseMonths == null
          ? null
          : DomainValidation.nonNegativeInt(minimumLeaseMonths!),
      'securityDepositMinor': securityDepositMinor == null
          ? null
          : DomainValidation.positiveMinorUnits(
              securityDepositMinor!,
              allowZero: true,
            ),
      'serviceChargeMinor': serviceChargeMinor == null
          ? null
          : DomainValidation.positiveMinorUnits(
              serviceChargeMinor!,
              allowZero: true,
            ),
      'petsPolicy': DomainValidation.optionalText(petsPolicy, maxLength: 300),
      'smokingPolicy': DomainValidation.optionalText(
        smokingPolicy,
        maxLength: 300,
      ),
      'viewingInstructions': DomainValidation.optionalText(
        viewingInstructions,
        maxLength: 1000,
      ),
      'videoUrl': DomainValidation.optionalText(videoUrl, maxLength: 1000),
      'contactEmail': contactEmail == null
          ? null
          : DomainValidation.email(contactEmail!, required: false),
      'contactPhone': DomainValidation.optionalText(
        contactPhone,
        maxLength: 40,
      ),
      'imageUrls': imageUrls.any((url) => url.trim().isEmpty)
          ? 'must not contain empty URLs'
          : imageUrls.length > 10
          ? 'must contain at most 10 images'
          : null,
      'amenities': _listError(amenities, maxItems: 40),
      'accessibilityFeatures': _listError(accessibilityFeatures, maxItems: 20),
      'utilitiesIncluded': _listError(utilitiesIncluded, maxItems: 20),
      'updatedAt': updatedAt.isBefore(createdAt)
          ? 'must not be before createdAt'
          : null,
      'publishedAt': status == ListingStatus.published && publishedAt == null
          ? 'is required for published listings'
          : null,
      'expiresAt':
          expiresAt != null &&
              publishedAt != null &&
              !expiresAt!.isAfter(publishedAt!)
          ? 'must be after publishedAt'
          : null,
      'projectionVersion': projectionVersion == null
          ? null
          : DomainValidation.nonNegativeInt(projectionVersion!),
    });
    if (status == ListingStatus.published) validateForPublishing();
  }

  void validateForPublishing() {
    DomainValidation.check(<String, String?>{
      'description': DomainValidation.requiredText(
        description,
        maxLength: 5000,
      ),
      'unitType': DomainValidation.requiredText(unitType ?? '', maxLength: 80),
      'location':
          (neighborhood == null || neighborhood!.trim().isEmpty) &&
              (district == null || district!.trim().isEmpty)
          ? 'a neighborhood or district is required'
          : null,
      'contact':
          (contactPhone == null || contactPhone!.trim().isEmpty) &&
              (contactEmail == null || contactEmail!.trim().isEmpty)
          ? 'a phone number or email address is required'
          : null,
      'status': status == ListingStatus.closed
          ? 'closed listings cannot be published'
          : null,
    });
  }

  Listing publish({required DateTime at}) {
    validateForPublishing();
    return copyWith(
      status: ListingStatus.published,
      publishedAt: at.toUtc(),
      updatedAt: at.toUtc(),
    );
  }

  Listing copyWith({
    String? title,
    String? description,
    int? monthlyRentMinor,
    String? currency,
    ListingStatus? status,
    String? unitType,
    int? floor,
    bool clearFloor = false,
    int? floorAreaSquareMetres,
    bool clearFloorAreaSquareMetres = false,
    bool? furnished,
    int? parkingSpaces,
    bool clearParkingSpaces = false,
    List<String>? amenities,
    List<String>? accessibilityFeatures,
    String? city,
    String? district,
    bool clearDistrict = false,
    String? neighborhood,
    bool clearNeighborhood = false,
    double? approximateLatitude,
    bool clearApproximateLatitude = false,
    double? approximateLongitude,
    bool clearApproximateLongitude = false,
    DateTime? availableFrom,
    bool clearAvailableFrom = false,
    int? minimumLeaseMonths,
    bool clearMinimumLeaseMonths = false,
    int? securityDepositMinor,
    bool clearSecurityDepositMinor = false,
    int? serviceChargeMinor,
    bool clearServiceChargeMinor = false,
    List<String>? utilitiesIncluded,
    String? petsPolicy,
    bool clearPetsPolicy = false,
    String? smokingPolicy,
    bool clearSmokingPolicy = false,
    String? viewingInstructions,
    bool clearViewingInstructions = false,
    List<String>? imageUrls,
    String? videoUrl,
    bool clearVideoUrl = false,
    String? contactPhone,
    bool clearContactPhone = false,
    String? contactEmail,
    bool clearContactEmail = false,
    String? publicContactToken,
    bool clearPublicContactToken = false,
    DateTime? updatedAt,
    DateTime? publishedAt,
    bool clearPublishedAt = false,
    DateTime? expiresAt,
    bool clearExpiresAt = false,
    int? projectionVersion,
    SyncMetadata? syncMetadata,
  }) => Listing(
    id: id,
    unitId: unitId,
    propertyId: propertyId,
    landlordId: landlordId,
    title: title ?? this.title,
    description: description ?? this.description,
    monthlyRentMinor: monthlyRentMinor ?? this.monthlyRentMinor,
    currency: currency ?? this.currency,
    status: status ?? this.status,
    bedrooms: bedrooms,
    bathrooms: bathrooms,
    unitType: unitType ?? this.unitType,
    floor: clearFloor ? null : (floor ?? this.floor),
    floorAreaSquareMetres: clearFloorAreaSquareMetres
        ? null
        : (floorAreaSquareMetres ?? this.floorAreaSquareMetres),
    furnished: furnished ?? this.furnished,
    parkingSpaces: clearParkingSpaces
        ? null
        : (parkingSpaces ?? this.parkingSpaces),
    amenities: amenities ?? this.amenities,
    accessibilityFeatures: accessibilityFeatures ?? this.accessibilityFeatures,
    city: city ?? this.city,
    district: clearDistrict ? null : (district ?? this.district),
    neighborhood: clearNeighborhood
        ? null
        : (neighborhood ?? this.neighborhood),
    approximateLatitude: clearApproximateLatitude
        ? null
        : (approximateLatitude ?? this.approximateLatitude),
    approximateLongitude: clearApproximateLongitude
        ? null
        : (approximateLongitude ?? this.approximateLongitude),
    availableFrom: clearAvailableFrom
        ? null
        : (availableFrom ?? this.availableFrom),
    minimumLeaseMonths: clearMinimumLeaseMonths
        ? null
        : (minimumLeaseMonths ?? this.minimumLeaseMonths),
    securityDepositMinor: clearSecurityDepositMinor
        ? null
        : (securityDepositMinor ?? this.securityDepositMinor),
    serviceChargeMinor: clearServiceChargeMinor
        ? null
        : (serviceChargeMinor ?? this.serviceChargeMinor),
    utilitiesIncluded: utilitiesIncluded ?? this.utilitiesIncluded,
    petsPolicy: clearPetsPolicy ? null : (petsPolicy ?? this.petsPolicy),
    smokingPolicy: clearSmokingPolicy
        ? null
        : (smokingPolicy ?? this.smokingPolicy),
    viewingInstructions: clearViewingInstructions
        ? null
        : (viewingInstructions ?? this.viewingInstructions),
    imageUrls: imageUrls ?? this.imageUrls,
    videoUrl: clearVideoUrl ? null : (videoUrl ?? this.videoUrl),
    contactPhone: clearContactPhone
        ? null
        : (contactPhone ?? this.contactPhone),
    contactEmail: clearContactEmail
        ? null
        : (contactEmail ?? this.contactEmail),
    publicContactToken: clearPublicContactToken
        ? null
        : (publicContactToken ?? this.publicContactToken),
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    publishedAt: clearPublishedAt ? null : (publishedAt ?? this.publishedAt),
    expiresAt: clearExpiresAt ? null : (expiresAt ?? this.expiresAt),
    projectionVersion: projectionVersion ?? this.projectionVersion,
    syncMetadata: syncMetadata ?? this.syncMetadata,
  );

  static String? _coordinateError(
    double? value, {
    required double minimum,
    required double maximum,
  }) {
    if (value == null) return null;
    if (!value.isFinite || value < minimum || value > maximum) {
      return 'must be between $minimum and $maximum';
    }
    return null;
  }

  static String? _listError(List<String> values, {required int maxItems}) {
    if (values.length > maxItems) return 'must contain at most $maxItems items';
    if (values.any((value) => value.trim().isEmpty)) {
      return 'must not contain empty values';
    }
    return null;
  }
}

final class CreateListingInput {
  const CreateListingInput({
    required this.unitId,
    required this.propertyId,
    required this.landlordId,
    required this.title,
    required this.description,
    required this.monthlyRentMinor,
    required this.city,
    this.currency = 'UGX',
    this.district,
    this.neighborhood,
    this.approximateLatitude,
    this.approximateLongitude,
    this.availableFrom,
    this.floorAreaSquareMetres,
    this.furnished = false,
    this.parkingSpaces,
    this.minimumLeaseMonths,
    this.securityDepositMinor,
    this.serviceChargeMinor,
    this.utilitiesIncluded = const <String>[],
    this.accessibilityFeatures = const <String>[],
    this.petsPolicy,
    this.smokingPolicy,
    this.viewingInstructions,
    this.imageUrls = const <String>[],
    this.videoUrl,
    this.contactPhone,
    this.contactEmail,
  });

  final String unitId;
  final String propertyId;
  final String landlordId;
  final String title;
  final String description;
  final int monthlyRentMinor;
  final String currency;
  final String city;
  final String? district;
  final String? neighborhood;
  final double? approximateLatitude;
  final double? approximateLongitude;
  final DateTime? availableFrom;
  final int? floorAreaSquareMetres;
  final bool furnished;
  final int? parkingSpaces;
  final int? minimumLeaseMonths;
  final int? securityDepositMinor;
  final int? serviceChargeMinor;
  final List<String> utilitiesIncluded;
  final List<String> accessibilityFeatures;
  final String? petsPolicy;
  final String? smokingPolicy;
  final String? viewingInstructions;
  final List<String> imageUrls;
  final String? videoUrl;
  final String? contactPhone;
  final String? contactEmail;

  void validate() {
    final now = DateTime.utc(2000);
    Listing(
      id: 'validation-placeholder',
      unitId: unitId,
      propertyId: propertyId,
      landlordId: landlordId,
      title: title,
      description: description,
      monthlyRentMinor: monthlyRentMinor,
      currency: currency,
      status: ListingStatus.draft,
      city: city,
      district: district,
      neighborhood: neighborhood,
      approximateLatitude: approximateLatitude,
      approximateLongitude: approximateLongitude,
      availableFrom: availableFrom,
      floorAreaSquareMetres: floorAreaSquareMetres,
      furnished: furnished,
      parkingSpaces: parkingSpaces,
      minimumLeaseMonths: minimumLeaseMonths,
      securityDepositMinor: securityDepositMinor,
      serviceChargeMinor: serviceChargeMinor,
      utilitiesIncluded: utilitiesIncluded,
      accessibilityFeatures: accessibilityFeatures,
      petsPolicy: petsPolicy,
      smokingPolicy: smokingPolicy,
      viewingInstructions: viewingInstructions,
      imageUrls: imageUrls,
      videoUrl: videoUrl,
      contactPhone: contactPhone,
      contactEmail: contactEmail,
      createdAt: now,
      updatedAt: now,
      syncMetadata: const SyncMetadata.pending(),
    );
  }
}
