import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../core/cloud/cloud_command.dart';
import '../../../core/cloud/cloud_data.dart';
import '../domain/tenancy.dart';

final tenanciesProvider = StreamProvider<CloudData<List<Tenancy>>>((
  ref,
) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.tenancies.watchAll();
});

/// The signed-in tenant's own tenancy record.
///
/// The read's states are preserved rather than flattened to a nullable: this
/// backs a tenant's balance, and "we could not load your tenancy" must not
/// render the same as "you have no tenancy".
final myTenancyProvider = StreamProvider.family<CloudData<Tenancy?>, String>((
  ref,
  tenantUserId,
) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.tenancies
      .watchAll(tenantUserId: tenantUserId)
      .map((data) => data.map((items) => items.isEmpty ? null : items.first));
});

final createTenancyProvider = Provider<CreateTenancy>(CreateTenancy.new);

class CreateTenancy {
  const CreateTenancy(this._ref);

  final Ref _ref;

  Future<MutationResult> call(CreateTenancyInput input) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.tenancies.create(input);
  }
}
