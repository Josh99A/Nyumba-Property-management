import 'property.dart';

abstract interface class PropertyRepository {
  Stream<List<Property>> watchAll({String? landlordId});
  Stream<Property?> watchById(String id);
  Future<List<Property>> getAll({String? landlordId});
  Future<Property?> getById(String id);
  Future<Property> create(CreatePropertyInput input);
  Future<Property> update(Property property);
}
