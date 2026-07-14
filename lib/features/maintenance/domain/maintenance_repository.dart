import 'maintenance_request.dart';

abstract interface class MaintenanceRepository {
  Stream<List<MaintenanceRequest>> watchAll({
    String? landlordId,
    String? tenantId,
  });
  Future<List<MaintenanceRequest>> getAll({
    String? landlordId,
    String? tenantId,
  });
  Future<MaintenanceRequest?> getById(String id);
  Future<MaintenanceRequest> create(CreateMaintenanceRequestInput input);
  Future<MaintenanceRequest> transition(TransitionMaintenanceInput input);
}
