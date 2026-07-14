import '../../../core/domain/domain_validation.dart';
import '../../../core/domain/sync_metadata.dart';

enum UnitType { apartment, house, shop, office, bedsitter, room, other }

enum UnitStatus { vacant, occupied, reserved, maintenance, inactive }

final class Unit {
  Unit({
    required this.id,
    required this.propertyId,
    required this.landlordId,
    required this.label,
    required this.type,
    required this.status,
    required this.monthlyRentMinor,
    required this.currency,
    required this.createdAt,
    required this.updatedAt,
    required this.syncMetadata,
    this.bedrooms = 0,
    this.bathrooms = 0,
    this.floor,
    this.description,
    List<String> amenities = const <String>[],
  }) : amenities = List.unmodifiable(amenities) {
    validate();
  }

  final String id;
  final String propertyId;
  final String landlordId;
  final String label;
  final UnitType type;
  final UnitStatus status;

  /// Monthly rent in the currency's smallest unit (for example UGX cents).
  /// It is intentionally an [int] to avoid floating-point money errors.
  final int monthlyRentMinor;
  final String currency;
  final int bedrooms;
  final int bathrooms;
  final int? floor;
  final String? description;
  final List<String> amenities;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncMetadata syncMetadata;

  bool get canBeAdvertised => status == UnitStatus.vacant;

  void validate() {
    DomainValidation.check(<String, String?>{
      'id': DomainValidation.requiredText(id, maxLength: 100),
      'propertyId': DomainValidation.requiredText(propertyId, maxLength: 100),
      'landlordId': DomainValidation.requiredText(landlordId, maxLength: 100),
      'label': DomainValidation.requiredText(label, maxLength: 100),
      'monthlyRentMinor': DomainValidation.positiveMinorUnits(monthlyRentMinor),
      'currency': DomainValidation.currencyCode(currency),
      'bedrooms': DomainValidation.nonNegativeInt(bedrooms),
      'bathrooms': DomainValidation.nonNegativeInt(bathrooms),
      'description': DomainValidation.optionalText(description),
      'amenities': amenities.any((item) => item.trim().isEmpty)
          ? 'must not contain empty values'
          : null,
      'updatedAt': updatedAt.isBefore(createdAt)
          ? 'must not be before createdAt'
          : null,
    });
  }

  Unit copyWith({
    String? label,
    UnitType? type,
    UnitStatus? status,
    int? monthlyRentMinor,
    String? currency,
    int? bedrooms,
    int? bathrooms,
    int? floor,
    bool clearFloor = false,
    String? description,
    bool clearDescription = false,
    List<String>? amenities,
    DateTime? updatedAt,
    SyncMetadata? syncMetadata,
  }) => Unit(
    id: id,
    propertyId: propertyId,
    landlordId: landlordId,
    label: label ?? this.label,
    type: type ?? this.type,
    status: status ?? this.status,
    monthlyRentMinor: monthlyRentMinor ?? this.monthlyRentMinor,
    currency: currency ?? this.currency,
    bedrooms: bedrooms ?? this.bedrooms,
    bathrooms: bathrooms ?? this.bathrooms,
    floor: clearFloor ? null : (floor ?? this.floor),
    description: clearDescription ? null : (description ?? this.description),
    amenities: amenities ?? this.amenities,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    syncMetadata: syncMetadata ?? this.syncMetadata,
  );
}

final class CreateUnitInput {
  const CreateUnitInput({
    required this.propertyId,
    required this.landlordId,
    required this.label,
    required this.type,
    required this.monthlyRentMinor,
    this.currency = 'UGX',
    this.status = UnitStatus.vacant,
    this.bedrooms = 0,
    this.bathrooms = 0,
    this.floor,
    this.description,
    this.amenities = const <String>[],
  });

  final String propertyId;
  final String landlordId;
  final String label;
  final UnitType type;
  final UnitStatus status;
  final int monthlyRentMinor;
  final String currency;
  final int bedrooms;
  final int bathrooms;
  final int? floor;
  final String? description;
  final List<String> amenities;

  void validate() {
    final now = DateTime.utc(2000);
    Unit(
      id: 'validation-placeholder',
      propertyId: propertyId,
      landlordId: landlordId,
      label: label,
      type: type,
      status: status,
      monthlyRentMinor: monthlyRentMinor,
      currency: currency,
      bedrooms: bedrooms,
      bathrooms: bathrooms,
      floor: floor,
      description: description,
      amenities: amenities,
      createdAt: now,
      updatedAt: now,
      syncMetadata: const SyncMetadata.pending(),
    );
  }
}
