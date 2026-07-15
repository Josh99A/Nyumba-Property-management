import '../../../core/domain/domain_validation.dart';
import '../../../core/domain/sync_metadata.dart';

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
    required this.syncMetadata,
    this.description,
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

  /// Ordered property images. The first image is the primary image.
  final List<String> imageUrls;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncMetadata syncMetadata;
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
          : imageUrls.length > 5
          ? 'must contain at most 5 images'
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
    List<String>? imageUrls,
    DateTime? updatedAt,
    SyncMetadata? syncMetadata,
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
    imageUrls: imageUrls ?? this.imageUrls,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    syncMetadata: syncMetadata ?? this.syncMetadata,
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
    this.imageUrls = const <String>[],
  });

  final String landlordId;
  final String name;
  final String addressLine;
  final String city;
  final String country;
  final String? description;
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
          : imageUrls.length > 5
          ? 'must contain at most 5 images'
          : null,
    });
  }
}
