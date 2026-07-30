import '../../../core/cloud/cloud_command.dart';
import '../../../core/cloud/cloud_data.dart';
import 'tenancy.dart';

/// Tenancies, read from the server-owned `landlordPortals` projection.
///
/// `adjustBalance` is deliberately gone. It applied a local balance change so
/// an offline-recorded payment could show as settled immediately — which meant
/// a tenant's arrears could drop on screen because of a write that had reached
/// nothing, and then spring back on the next read. What a tenancy owes is the
/// server's arithmetic, and it arrives with the tenancy.
abstract interface class TenancyRepository {
  Stream<CloudData<List<Tenancy>>> watchAll({
    String? landlordId,
    String? tenantUserId,
  });

  Future<CloudData<List<Tenancy>>> getAll({
    String? landlordId,
    String? tenantUserId,
    bool forceRefresh = false,
  });

  Future<CloudData<Tenancy?>> getById(String id, {bool forceRefresh = false});

  /// Sends `tenancy.establish`, the composite command that creates the tenant
  /// record, the lease, and its activation in one server transaction.
  Future<MutationResult> create(CreateTenancyInput input);
}
