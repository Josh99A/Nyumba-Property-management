import 'tenancy.dart';

abstract interface class TenancyRepository {
  Stream<List<Tenancy>> watchAll({String? landlordId, String? tenantUserId});
  Future<List<Tenancy>> getAll({String? landlordId, String? tenantUserId});
  Future<Tenancy?> getById(String id);
  Future<Tenancy> create(CreateTenancyInput input);

  /// Applies a local balance adjustment (for example an offline-recorded rent
  /// payment). The delta may be negative to reduce what is owed; the stored
  /// balance never drops below zero.
  Future<Tenancy> adjustBalance({
    required String tenancyId,
    required int deltaMinor,
  });
}
