import 'unit.dart';

abstract interface class UnitRepository {
  Stream<List<Unit>> watchAll({String? propertyId, String? landlordId});
  Stream<Unit?> watchById(String id);
  Future<List<Unit>> getAll({
    String? propertyId,
    String? landlordId,
    bool includeArchived = false,
  });
  Future<Unit?> getById(String id);
  Future<Unit> create(CreateUnitInput input);
  Future<Unit> update(Unit unit);
  Future<Unit> archive(String unitId);
}
