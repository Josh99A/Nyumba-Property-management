import '../../../core/config/market_config.dart';
import '../../../core/domain/coordinates.dart';
import '../../../core/domain/domain_validation.dart';

final class Property {
  Property({
    required this.id,
    required this.landlordId,
    required this.name,
    required this.addressLine,
    required this.city,
    required this.country,
    required this.createdAt,
    required this.updatedAt,
    this.serverVersion,
    this.description,
    this.location,
    this.isArchived = false,
    this.archivedAt,
    List<String> imageUrls = const <String>[],
  }) : imageUrls = List.unmodifiable(imageUrls) {
    validate();
  }

  final String id;
  final String landlordId;
  final String name;
  final String addressLine;
  final String city;
  final String country;
  final String? description;

  /// Where the property is, as precisely as the landlord placed it.
  ///
  /// Private, and stays private: this is the exact point staff navigate to and
  /// the starting point a new advert inherits, but a public listing only ever
  /// carries the coarsened copy the server produces at publication.
  final Coordinates? location;

  /// Ordered property images. The first image is the primary image.
  final List<String> imageUrls;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The server's aggregate version this copy was read at.
  ///
  /// Sent back as `expectedVersion` so the backend can reject an edit composed
  /// against a stale read. Null only for a record the server has not yet
  /// confirmed — which, now that every write goes straight to the server,
  /// means a record that does not exist rather than one waiting to be sent.
  final int? serverVersion;
  final bool isArchived;
  final DateTime? archivedAt;

  void validate() {
    DomainValidation.check(<String, String?>{
      'id': DomainValidation.requiredText(id, maxLength: 100),
      'landlordId': DomainValidation.requiredText(landlordId, maxLength: 100),
      'name': DomainValidation.requiredText(name, maxLength: 120),
      'addressLine': DomainValidation.requiredText(addressLine, maxLength: 250),
      'city': DomainValidation.requiredText(city, maxLength: 100),
      'country': DomainValidation.requiredText(country, maxLength: 100),
      'description': DomainValidation.optionalText(description),
      'imageUrls': imageUrls.any((url) => url.trim().isEmpty)
          ? 'must not contain empty image references'
          : imageUrls.length > NyumbaMarket.maxPropertyPhotos
          ? 'must contain at most ${NyumbaMarket.maxPropertyPhotos} images'
          : null,
      'updatedAt': updatedAt.isBefore(createdAt)
          ? 'must not be before createdAt'
          : null,
      'archivedAt': isArchived && archivedAt == null
          ? 'is required for an archived property'
          : !isArchived && archivedAt != null
          ? 'must be empty for an active property'
          : null,
    });
  }

  Property copyWith({
    String? name,
    String? addressLine,
    String? city,
    String? country,
    String? description,
    bool clearDescription = false,
    Coordinates? location,
    bool clearLocation = false,
    List<String>? imageUrls,
    DateTime? updatedAt,
    int? serverVersion,
    bool? isArchived,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
  }) => Property(
    id: id,
    landlordId: landlordId,
    name: name ?? this.name,
    addressLine: addressLine ?? this.addressLine,
    city: city ?? this.city,
    country: country ?? this.country,
    description: clearDescription ? null : (description ?? this.description),
    location: clearLocation ? null : (location ?? this.location),
    imageUrls: imageUrls ?? this.imageUrls,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    serverVersion: serverVersion ?? this.serverVersion,
    isArchived: isArchived ?? this.isArchived,
    archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
  );
}

final class CreatePropertyInput {
  const CreatePropertyInput({
    required this.landlordId,
    required this.name,
    required this.addressLine,
    required this.city,
    this.country = 'Uganda',
    this.description,
    this.location,
    this.imageUrls = const <String>[],
  });

  final String landlordId;
  final String name;
  final String addressLine;
  final String city;
  final String country;
  final String? description;
  final Coordinates? location;
  final List<String> imageUrls;

  void validate() {
    DomainValidation.check(<String, String?>{
      'landlordId': DomainValidation.requiredText(landlordId, maxLength: 100),
      'name': DomainValidation.requiredText(name, maxLength: 120),
      'addressLine': DomainValidation.requiredText(addressLine, maxLength: 250),
      'city': DomainValidation.requiredText(city, maxLength: 100),
      'country': DomainValidation.requiredText(country, maxLength: 100),
      'description': DomainValidation.optionalText(description),
      'imageUrls': imageUrls.any((url) => url.trim().isEmpty)
          ? 'must not contain empty image references'
          : imageUrls.length > NyumbaMarket.maxPropertyPhotos
          ? 'must contain at most ${NyumbaMarket.maxPropertyPhotos} images'
          : null,
    });
  }
}
