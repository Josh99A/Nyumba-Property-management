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
    this.availableFrom,
    List<String> imageUrls = const <String>[],
    this.contactPhone,
    this.contactEmail,
    this.publishedAt,
  }) : imageUrls = List.unmodifiable(imageUrls) {
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
  final DateTime? availableFrom;
  final List<String> imageUrls;
  final String? contactPhone;
  final String? contactEmail;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? publishedAt;
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
      'contactEmail': contactEmail == null
          ? null
          : DomainValidation.email(contactEmail!, required: false),
      'contactPhone': DomainValidation.optionalText(
        contactPhone,
        maxLength: 40,
      ),
      'imageUrls': imageUrls.any((url) => url.trim().isEmpty)
          ? 'must not contain empty URLs'
          : null,
      'updatedAt': updatedAt.isBefore(createdAt)
          ? 'must not be before createdAt'
          : null,
      'publishedAt': status == ListingStatus.published && publishedAt == null
          ? 'is required for published listings'
          : null,
    });
    if (status == ListingStatus.published) validateForPublishing();
  }

  void validateForPublishing() {
    DomainValidation.check(<String, String?>{
      'description': DomainValidation.requiredText(
        description,
        maxLength: 5000,
      ),
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
    DateTime? availableFrom,
    bool clearAvailableFrom = false,
    List<String>? imageUrls,
    String? contactPhone,
    bool clearContactPhone = false,
    String? contactEmail,
    bool clearContactEmail = false,
    DateTime? updatedAt,
    DateTime? publishedAt,
    bool clearPublishedAt = false,
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
    availableFrom: clearAvailableFrom
        ? null
        : (availableFrom ?? this.availableFrom),
    imageUrls: imageUrls ?? this.imageUrls,
    contactPhone: clearContactPhone
        ? null
        : (contactPhone ?? this.contactPhone),
    contactEmail: clearContactEmail
        ? null
        : (contactEmail ?? this.contactEmail),
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    publishedAt: clearPublishedAt ? null : (publishedAt ?? this.publishedAt),
    syncMetadata: syncMetadata ?? this.syncMetadata,
  );
}

final class CreateListingInput {
  const CreateListingInput({
    required this.unitId,
    required this.propertyId,
    required this.landlordId,
    required this.title,
    required this.description,
    required this.monthlyRentMinor,
    this.currency = 'UGX',
    this.availableFrom,
    this.imageUrls = const <String>[],
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
  final DateTime? availableFrom;
  final List<String> imageUrls;
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
      availableFrom: availableFrom,
      imageUrls: imageUrls,
      contactPhone: contactPhone,
      contactEmail: contactEmail,
      createdAt: now,
      updatedAt: now,
      syncMetadata: const SyncMetadata.pending(),
    );
  }
}
