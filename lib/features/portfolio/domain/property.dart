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
  }) {
    validate();
  }

  final String id;
  final String landlordId;
  final String name;
  final String addressLine;
  final String city;
  final String country;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncMetadata syncMetadata;

  void validate() {
    DomainValidation.check(<String, String?>{
      'id': DomainValidation.requiredText(id, maxLength: 100),
      'landlordId': DomainValidation.requiredText(landlordId, maxLength: 100),
      'name': DomainValidation.requiredText(name, maxLength: 120),
      'addressLine': DomainValidation.requiredText(addressLine, maxLength: 250),
      'city': DomainValidation.requiredText(city, maxLength: 100),
      'country': DomainValidation.requiredText(country, maxLength: 100),
      'description': DomainValidation.optionalText(description),
      'updatedAt': updatedAt.isBefore(createdAt)
          ? 'must not be before createdAt'
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
    DateTime? updatedAt,
    SyncMetadata? syncMetadata,
  }) => Property(
    id: id,
    landlordId: landlordId,
    name: name ?? this.name,
    addressLine: addressLine ?? this.addressLine,
    city: city ?? this.city,
    country: country ?? this.country,
    description: clearDescription ? null : (description ?? this.description),
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    syncMetadata: syncMetadata ?? this.syncMetadata,
  );
}

final class CreatePropertyInput {
  const CreatePropertyInput({
    required this.landlordId,
    required this.name,
    required this.addressLine,
    required this.city,
    this.country = 'Kenya',
    this.description,
  });

  final String landlordId;
  final String name;
  final String addressLine;
  final String city;
  final String country;
  final String? description;

  void validate() {
    DomainValidation.check(<String, String?>{
      'landlordId': DomainValidation.requiredText(landlordId, maxLength: 100),
      'name': DomainValidation.requiredText(name, maxLength: 120),
      'addressLine': DomainValidation.requiredText(addressLine, maxLength: 250),
      'city': DomainValidation.requiredText(city, maxLength: 100),
      'country': DomainValidation.requiredText(country, maxLength: 100),
      'description': DomainValidation.optionalText(description),
    });
  }
}
