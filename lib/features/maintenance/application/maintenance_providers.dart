import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../domain/maintenance_request.dart';

/// Landlord-side stream of every request in the workspace.
final maintenanceRequestsProvider = StreamProvider<List<MaintenanceRequest>>((
  ref,
) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.maintenance.watchAll();
});

/// Tenant-side stream restricted to the reporting tenant's requests.
final tenantMaintenanceRequestsProvider =
    StreamProvider.family<List<MaintenanceRequest>, String>((
      ref,
      tenantId,
    ) async* {
      final deps = await ref.watch(appDependenciesProvider.future);
      yield* deps.maintenance.watchAll(tenantId: tenantId);
    });

final createMaintenanceRequestProvider = Provider<CreateMaintenanceRequest>(
  CreateMaintenanceRequest.new,
);
final transitionMaintenanceRequestProvider =
    Provider<TransitionMaintenanceRequest>(TransitionMaintenanceRequest.new);

class CreateMaintenanceRequest {
  const CreateMaintenanceRequest(this._ref);

  final Ref _ref;

  Future<MaintenanceRequest> call(CreateMaintenanceRequestInput input) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.maintenance.create(input);
  }
}

class TransitionMaintenanceRequest {
  const TransitionMaintenanceRequest(this._ref);

  final Ref _ref;

  Future<MaintenanceRequest> call(TransitionMaintenanceInput input) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.maintenance.transition(input);
  }
}
