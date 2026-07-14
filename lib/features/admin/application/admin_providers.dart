import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../auth/application/session_controller.dart';
import '../domain/admin_action.dart';
import '../domain/managed_user.dart';

final managedUsersProvider = StreamProvider<List<ManagedUser>>((ref) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.managedUsers.watchAll();
});

final adminActionsProvider = StreamProvider<List<AdminActionRecord>>((
  ref,
) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.adminActions.watchAll();
});

final changeUserStatusProvider = Provider<ChangeUserStatus>(
  ChangeUserStatus.new,
);
final inviteUserProvider = Provider<InviteUser>(InviteUser.new);

/// Applies an account-status change and appends the audit record as two
/// ordered offline mutations: the audit entry carries a durable dependency on
/// the user aggregate, so history can never arrive before the change itself.
class ChangeUserStatus {
  const ChangeUserStatus(this._ref);

  final Ref _ref;

  Future<ManagedUser> call({
    required String userId,
    required ManagedUserStatus status,
  }) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    final updated = await deps.managedUsers.changeStatus(
      userId: userId,
      status: status,
    );
    final actor =
        _ref.read(sessionControllerProvider)?.displayName ?? 'Platform admin';
    await deps.adminActions.append(
      action: switch (status) {
        ManagedUserStatus.active => 'Reactivated account',
        ManagedUserStatus.suspended => 'Suspended account',
        ManagedUserStatus.invited => 'Reissued invitation',
      },
      targetUserId: updated.id,
      targetName: updated.name,
      performedBy: actor,
    );
    return updated;
  }
}

class InviteUser {
  const InviteUser(this._ref);

  final Ref _ref;

  Future<ManagedUser> call(InviteManagedUserInput input) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    final user = await deps.managedUsers.invite(input);
    final actor =
        _ref.read(sessionControllerProvider)?.displayName ?? 'Platform admin';
    await deps.adminActions.append(
      action: 'Invited ${input.role.toLowerCase()}',
      targetUserId: user.id,
      targetName: user.name,
      performedBy: actor,
    );
    return user;
  }
}
