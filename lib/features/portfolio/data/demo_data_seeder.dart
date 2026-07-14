// ignore_for_file: prefer_initializing_formals

import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing_repository.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property_repository.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit_repository.dart';

final class DemoSeedResult {
  const DemoSeedResult({
    required this.seeded,
    this.property,
    this.units = const <Unit>[],
    this.listings = const <Listing>[],
  });

  final bool seeded;
  final Property? property;
  final List<Unit> units;
  final List<Listing> listings;
}

/// Creates a small but relationally valid portfolio through normal repository
/// APIs. Consequently demo writes exercise the same atomic outbox path as user
/// data and can sync later when a remote gateway is configured.
final class DemoDataSeeder {
  const DemoDataSeeder({
    required PropertyRepository properties,
    required UnitRepository units,
    required ListingRepository listings,
  }) : _properties = properties,
       _units = units,
       _listings = listings;

  static const String _demoPropertyName = 'Kololo Garden Court';

  final PropertyRepository _properties;
  final UnitRepository _units;
  final ListingRepository _listings;

  /// Seeds only an empty landlord portfolio by default. If a prior seed was
  /// interrupted, the recognizable demo property is resumed safely.
  Future<DemoSeedResult> seedIfEmpty({
    required String landlordId,
    bool onlyWhenEmpty = true,
  }) async {
    final currentProperties = await _properties.getAll(landlordId: landlordId);
    Property? property = _firstWhereOrNull(
      currentProperties,
      (item) => item.name == _demoPropertyName,
    );
    if (onlyWhenEmpty && currentProperties.isNotEmpty && property == null) {
      return const DemoSeedResult(seeded: false);
    }

    var changed = false;
    property ??= await _properties.create(
      CreatePropertyInput(
        landlordId: landlordId,
        name: _demoPropertyName,
        addressLine: 'Argwings Kodhek Road',
        city: 'Kampala',
        description: 'A secure mixed-unit property close to local amenities.',
      ),
    );
    changed = currentProperties.every((item) => item.id != property!.id);

    final existingUnits = await _units.getAll(propertyId: property.id);
    final units = <Unit>[];
    for (final specification in _unitSpecifications) {
      var unit = _firstWhereOrNull(
        existingUnits,
        (item) => item.label == specification.label,
      );
      if (unit == null) {
        unit = await _units.create(
          CreateUnitInput(
            propertyId: property.id,
            landlordId: landlordId,
            label: specification.label,
            type: specification.type,
            status: specification.status,
            monthlyRentMinor: specification.monthlyRentMinor,
            bedrooms: specification.bedrooms,
            bathrooms: specification.bathrooms,
            amenities: specification.amenities,
          ),
        );
        changed = true;
      }
      units.add(unit);
    }

    final existingListings = await _listings.getAll(
      propertyId: property.id,
      landlordId: landlordId,
    );
    final listings = <Listing>[];
    for (final unit in units.where((item) => item.canBeAdvertised)) {
      var listing = _firstWhereOrNull(
        existingListings,
        (item) => item.unitId == unit.id,
      );
      if (listing == null) {
        listing = await _listings.createDraft(
          CreateListingInput(
            unitId: unit.id,
            propertyId: property.id,
            landlordId: landlordId,
            title: '${unit.label} at ${property.name}',
            description:
                'A well maintained ${unit.type.name} in ${property.city}.',
            monthlyRentMinor: unit.monthlyRentMinor,
            currency: unit.currency,
            city: property.city,
            neighborhood: 'Kampala Central',
            minimumLeaseMonths: 12,
            securityDepositMinor: unit.monthlyRentMinor,
            parkingSpaces: 1,
            contactPhone: '+256 700 000 000',
          ),
        );
        listing = await _listings.publish(listing.id);
        changed = true;
      }
      listings.add(listing);
    }

    return DemoSeedResult(
      seeded: changed,
      property: property,
      units: List.unmodifiable(units),
      listings: List.unmodifiable(listings),
    );
  }

  static T? _firstWhereOrNull<T>(
    Iterable<T> values,
    bool Function(T value) test,
  ) {
    for (final value in values) {
      if (test(value)) return value;
    }
    return null;
  }

  static const List<_DemoUnitSpecification> _unitSpecifications =
      <_DemoUnitSpecification>[
        _DemoUnitSpecification(
          label: 'Apartment A1',
          type: UnitType.apartment,
          status: UnitStatus.vacant,
          monthlyRentMinor: 120000000,
          bedrooms: 2,
          bathrooms: 2,
          amenities: <String>['Parking', 'Balcony', 'Backup water'],
        ),
        _DemoUnitSpecification(
          label: 'Bedsitter B3',
          type: UnitType.bedsitter,
          status: UnitStatus.vacant,
          monthlyRentMinor: 50000000,
          bedrooms: 0,
          bathrooms: 1,
          amenities: <String>['Backup water'],
        ),
        _DemoUnitSpecification(
          label: 'Shop G2',
          type: UnitType.shop,
          status: UnitStatus.occupied,
          monthlyRentMinor: 95000000,
          bedrooms: 0,
          bathrooms: 1,
          amenities: <String>['Street frontage'],
        ),
      ];
}

final class _DemoUnitSpecification {
  const _DemoUnitSpecification({
    required this.label,
    required this.type,
    required this.status,
    required this.monthlyRentMinor,
    required this.bedrooms,
    required this.bathrooms,
    required this.amenities,
  });

  final String label;
  final UnitType type;
  final UnitStatus status;
  final int monthlyRentMinor;
  final int bedrooms;
  final int bathrooms;
  final List<String> amenities;
}
