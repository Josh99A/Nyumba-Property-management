import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/features/marketplace/data/sembast_listing_repository.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/portfolio/data/sembast_property_repository.dart';
import 'package:nyumba_property_management/features/portfolio/data/sembast_unit_repository.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  test('createDraft copies bedrooms and bathrooms from the unit', () async {
    final database = OfflineDatabase(
      await databaseFactoryMemory.openDatabase('listing-projection.db'),
    );
    addTearDown(database.close);
    await database.initialize();
    final properties = SembastPropertyRepository(database: database);
    final units = SembastUnitRepository(database: database);
    final repository = SembastListingRepository(
      database: database,
      units: units,
    );

    final property = await properties.create(
      const CreatePropertyInput(
        landlordId: 'landlord-1',
        name: 'Sunset Apartments',
        addressLine: 'Muthangari Drive',
        city: 'Kampala',
        description: 'Quiet apartment living with secure parking.',
      ),
    );

    final unit = await units.create(
      CreateUnitInput(
        propertyId: property.id,
        landlordId: 'landlord-1',
        label: 'C1',
        type: UnitType.apartment,
        status: UnitStatus.vacant,
        monthlyRentMinor: 150000000,
        bedrooms: 3,
        bathrooms: 2,
      ),
    );

    final draft = await repository.createDraft(
      CreateListingInput(
        unitId: unit.id,
        propertyId: property.id,
        landlordId: 'landlord-1',
        title: 'C1 at Sunset Apartments',
        description: 'A bright three-bedroom apartment.',
        monthlyRentMinor: unit.monthlyRentMinor,
        contactPhone: '+256 772 000 100',
      ),
    );

    expect(draft.bedrooms, 3);
    expect(draft.bathrooms, 2);

    final reloaded = await repository.getById(draft.id);
    expect(reloaded?.bedrooms, 3);
    expect(reloaded?.bathrooms, 2);
  });
}
