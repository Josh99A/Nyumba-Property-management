import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../auth/application/session_controller.dart';
import '../../auth/domain/user_session.dart';
import '../../../app/bootstrap/app_dependencies.dart';
import '../domain/staff_permission.dart';
import '../domain/staff_repository.dart';

/// Live staff invites for the signed-in owner's workspace, newest first.
/// Revoked seats drop out. Empty for anyone who is not a landlord owner.
final staffInvitesProvider = StreamProvider<List<StaffInvite>>((ref) async* {
  final session = ref.watch(sessionControllerProvider);
  if (session == null ||
      session.role != AppRole.landlord ||
      !session.isWorkspaceOwner) {
    yield const [];
    return;
  }
  final dependencies = await ref.watch(appDependenciesProvider.future);
  yield* dependencies.staff.watchInvites();
});

/// The owner's staff seat limit and custom-role entitlement, from the public
/// `planCatalog/{tier}` document. Null while unknown (offline, unseeded, or no
/// tier yet) so the UI says "unavailable" rather than inventing a limit.
final staffPlanProvider = StreamProvider<StaffPlan?>((ref) async* {
  final session = ref.watch(sessionControllerProvider);
  final tier = session?.subscriptionTier;
  if (session == null ||
      session.role != AppRole.landlord ||
      tier == null ||
      !session.isWorkspaceOwner) {
    yield null;
    return;
  }
  final dependencies = await ref.watch(appDependenciesProvider.future);
  yield* dependencies.staff.watchPlan(tier);
});

final inviteStaffProvider = Provider<InviteStaff>(InviteStaff.new);
final revokeStaffProvider = Provider<RevokeStaff>(RevokeStaff.new);
final updateStaffPermissionsProvider = Provider<UpdateStaffPermissions>(
  UpdateStaffPermissions.new,
);

/// Invites a staff member through the server-authoritative `staff.invite`
/// command. Seat limits and Pro's standard-preset coercion are enforced by the
/// backend; this only guards the obvious client-side preconditions.
class InviteStaff {
  const InviteStaff(this._ref);

  final Ref _ref;

  Future<void> call({
    required String email,
    String? displayName,
    required Set<StaffPermission> permissions,
  }) async {
    final session = _ref.read(sessionControllerProvider);
    if (session == null || session.role != AppRole.landlord) {
      throw StateError('Sign in as a landlord to invite staff.');
    }
    if (Firebase.apps.isEmpty) {
      throw StateError('Connect to the internet to invite staff.');
    }
    if (permissions.isEmpty) {
      throw StateError('Choose at least one thing this person can do.');
    }
    final gateway = await _ref.read(authCommandGatewayProvider.future);
    await gateway.sendCommand(
      type: 'staff.invite',
      aggregateId: 'staffinv_${const Uuid().v7()}',
      expectedVersion: 0,
      payload: <String, Object?>{
        'email': email.trim(),
        if (displayName != null && displayName.trim().isNotEmpty)
          'displayName': displayName.trim(),
        'permissions': [for (final permission in permissions) permission.id],
      },
    );
  }
}

/// Revokes a staff seat through `staff.revoke`, freeing capacity and cutting
/// the person's access.
class RevokeStaff {
  const RevokeStaff(this._ref);

  final Ref _ref;

  Future<void> call(StaffInvite invite) async {
    final session = _ref.read(sessionControllerProvider);
    if (session == null || session.role != AppRole.landlord) {
      throw StateError('Sign in as a landlord to manage staff.');
    }
    if (Firebase.apps.isEmpty) {
      throw StateError('Connect to the internet to manage staff.');
    }
    final gateway = await _ref.read(authCommandGatewayProvider.future);
    await gateway.sendCommand(
      type: 'staff.revoke',
      aggregateId: invite.id,
      expectedVersion: invite.version,
      payload: const <String, Object?>{},
    );
  }
}

/// Changes a staff member's permissions through `staff.updatePermissions`.
/// Requires the owner's plan to allow custom roles; the backend rejects it with
/// CUSTOM_ROLES_UNAVAILABLE otherwise.
class UpdateStaffPermissions {
  const UpdateStaffPermissions(this._ref);

  final Ref _ref;

  Future<void> call(
    StaffInvite invite,
    Set<StaffPermission> permissions,
  ) async {
    final session = _ref.read(sessionControllerProvider);
    if (session == null || session.role != AppRole.landlord) {
      throw StateError('Sign in as a landlord to manage staff.');
    }
    if (Firebase.apps.isEmpty) {
      throw StateError('Connect to the internet to manage staff.');
    }
    if (permissions.isEmpty) {
      throw StateError('Choose at least one thing this person can do.');
    }
    final gateway = await _ref.read(authCommandGatewayProvider.future);
    await gateway.sendCommand(
      type: 'staff.updatePermissions',
      aggregateId: invite.id,
      expectedVersion: invite.version,
      payload: <String, Object?>{
        'permissions': [for (final permission in permissions) permission.id],
      },
    );
  }
}
