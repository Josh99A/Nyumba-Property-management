import '../../../core/cloud/cloud_command.dart';
import '../../../core/cloud/cloud_data.dart';
import 'unit.dart';

/// Reads and writes rentable units against the server. Same contract shape as
/// `PropertyRepository`: reads carry their own freshness, writes land only on
/// server confirmation.
abstract interface class UnitRepository {
  Stream<CloudData<List<Unit>>> watchAll({
    String? propertyId,
    String? landlordId,
    bool includeArchived = false,
  });

  Stream<CloudData<Unit?>> watchById(String id);

  Future<CloudData<List<Unit>>> getAll({
    String? propertyId,
    String? landlordId,
    bool includeArchived = false,
    bool forceRefresh = false,
  });

  Future<CloudData<Unit?>> getById(String id, {bool forceRefresh = false});

  Future<MutationResult> create(CreateUnitInput input);

  Future<MutationResult> update(Unit unit);

  Future<MutationResult> archive(Unit unit);
}
