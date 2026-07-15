import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/authorization_policy.dart';
import '../domain/subscription_plan_draft.dart';

final subscriptionPlansProvider = StreamProvider<List<SubscriptionPlanDraft>>((
  ref,
) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.subscriptionPlans.watchAll();
});

final updatePlanDraftProvider = Provider<UpdatePlanDraft>(UpdatePlanDraft.new);

class UpdatePlanDraft {
  const UpdatePlanDraft(this._ref);

  final Ref _ref;

  Future<SubscriptionPlanDraft> call(UpdatePlanDraftInput input) async {
    final session = _ref.read(sessionControllerProvider);
    if (session == null ||
        !AuthorizationPolicy.allows(
          session.role,
          AppResource.planCatalog,
          CrudOperation.update,
        )) {
      throw StateError('Administrator permission is required.');
    }
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.subscriptionPlans.update(input);
  }
}
