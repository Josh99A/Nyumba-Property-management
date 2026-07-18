import '../domain/unit.dart';

extension RentalSpaceLabels on UnitType {
  String get displayLabel => switch (this) {
    UnitType.apartment => 'Apartment',
    UnitType.house => 'House',
    UnitType.shop => 'Shop',
    UnitType.office => 'Office',
    UnitType.bedsitter => 'Bedsitter',
    UnitType.room => 'Room',
    UnitType.other => 'Rental space',
  };
}

extension RentalSpaceDisplayName on Unit {
  String get displayName {
    final normalizedLabel = label.trim();
    final typeLabel = type.displayLabel;
    final lowerLabel = normalizedLabel.toLowerCase();
    final lowerType = typeLabel.toLowerCase();
    if (lowerLabel == lowerType || lowerLabel.startsWith('$lowerType ')) {
      return normalizedLabel;
    }
    return '$typeLabel $normalizedLabel';
  }
}

extension RentalSpaceStatusLabels on UnitStatus {
  String get displayLabel => switch (this) {
    UnitStatus.vacant => 'Vacant',
    UnitStatus.occupied => 'Occupied',
    UnitStatus.reserved => 'Reserved',
    UnitStatus.maintenance => 'Maintenance',
    UnitStatus.inactive => 'Inactive',
  };

  /// One-line explanation shown when a landlord picks an occupancy status.
  String get helperText => switch (this) {
    UnitStatus.vacant => 'Available to rent and can be advertised.',
    UnitStatus.occupied => 'A tenant is living or working in this space.',
    UnitStatus.reserved => 'Held for a tenant who has not moved in yet.',
    UnitStatus.maintenance => 'Temporarily closed for repairs.',
    UnitStatus.inactive => 'Not offered for rent at the moment.',
  };
}
