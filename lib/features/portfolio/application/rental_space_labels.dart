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
  String get displayName => '${type.displayLabel} $label';
}
