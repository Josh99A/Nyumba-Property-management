import 'property.dart';

abstract interface class PropertyRepository {
  Stream<List<Property>> watchAll({
    String? landlordId,
    bool includeArchived = false,
  });
  Stream<Property?> watchById(String id);
  Future<List<Property>> getAll({
    String? landlordId,
    bool includeArchived = false,
  });
  Future<Property?> getById(String id);
  Future<Property> create(CreatePropertyInput input);
  Future<Property> update(Property property);
  Future<Property> archive(String propertyId);
}
