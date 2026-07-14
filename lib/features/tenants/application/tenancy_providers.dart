import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../domain/tenancy.dart';

final tenanciesProvider = StreamProvider<List<Tenancy>>((ref) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.tenancies.watchAll();
});

/// The signed-in tenant's own tenancy record, when one exists locally.
final myTenancyProvider = StreamProvider.family<Tenancy?, String>((
  ref,
  tenantUserId,
) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.tenancies
      .watchAll(tenantUserId: tenantUserId)
      .map((items) => items.isEmpty ? null : items.first);
});

final createTenancyProvider = Provider<CreateTenancy>(CreateTenancy.new);

class CreateTenancy {
  const CreateTenancy(this._ref);

  final Ref _ref;

  Future<Tenancy> call(CreateTenancyInput input) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.tenancies.create(input);
  }
}
