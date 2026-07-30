import '../../../core/cloud/cloud_command.dart';
import '../../../core/cloud/cloud_data.dart';
import 'property.dart';

/// Reads and writes properties against the server.
///
/// Reads return [CloudData] so a caller can tell current data from cached data,
/// an empty portfolio from a denied read, and a connection failure from a
/// server rejection. Writes return only after the server has confirmed them.
abstract interface class PropertyRepository {
  Stream<CloudData<List<Property>>> watchAll({
    String? landlordId,
    bool includeArchived = false,
  });

  Stream<CloudData<Property?>> watchById(String id);

  /// A deliberate read. [forceRefresh] bypasses the cache for a user who has
  /// explicitly asked to see the current state.
  Future<CloudData<List<Property>>> getAll({
    String? landlordId,
    bool includeArchived = false,
    bool forceRefresh = false,
  });

  Future<CloudData<Property?>> getById(String id, {bool forceRefresh = false});

  /// Sends `property.create` and waits for the server.
  ///
  /// Throws [CommandException] when the server refuses, cannot be reached, or
  /// answers ambiguously. It never returns on a local write alone.
  Future<MutationResult> create(CreatePropertyInput input);

  /// Sends `property.update`, guarded by the server version [property] was
  /// read at, so an edit composed against a stale copy is rejected rather than
  /// silently overwriting someone else's change.
  Future<MutationResult> update(Property property);

  Future<MutationResult> archive(Property property);
}
