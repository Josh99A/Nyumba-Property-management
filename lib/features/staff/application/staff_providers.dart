import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../auth/application/session_controller.dart';
import '../../auth/domain/user_session.dart';
import '../domain/staff_permission.dart';

enum StaffInviteState { pending, accepted, revoked, unknown }

StaffInviteState _stateFrom(Object? raw) => switch (raw) {
  'pending' => StaffInviteState.pending,
  'accepted' => StaffInviteState.accepted,
  'revoked' => StaffInviteState.revoked,
  _ => StaffInviteState.unknown,
};

/// A staff seat as the owner sees it on the Team screen.
class StaffInvite {
  const StaffInvite({
    required this.id,
    required this.email,
    required this.displayName,
    required this.permissions,
    required this.state,
    required this.version,
    required this.linked,
  });

  final String id;
  final String email;
  final String? displayName;
  final Set<StaffPermission> permissions;
  final StaffInviteState state;

  /// Concurrency token for staff.revoke / staff.updatePermissions.
  final int version;

  /// Whether someone has signed in and claimed this seat.
  final bool linked;
}

/// The owner's staff seat allowance and whether they can tailor permissions.
class StaffPlan {
  const StaffPlan({required this.seatLimit, required this.customRoles});

  /// Seats available beyond the owner. 0 means the tier has no staff seats.
  final int seatLimit;

  /// Whether the owner can grant a custom permission subset (Premium+); when
  /// false, every seat gets the fixed standard preset.
  final bool customRoles;
}

/// Live staff invites for the signed-in owner's workspace, newest first.
/// Revoked seats drop out. Empty for anyone who is not a landlord owner.
final staffInvitesProvider = StreamProvider<List<StaffInvite>>((ref) async* {
  final session = ref.watch(sessionControllerProvider);
  if (session == null ||
      session.role != AppRole.landlord ||
      Firebase.apps.isEmpty) {
    yield const [];
    return;
  }
  try {
    await for (final snapshot
        in FirebaseFirestore.instance
            .collection('staffInvites')
            .where('landlordId', isEqualTo: session.userId)
            .orderBy('createdAt', descending: true)
            .limit(100)
            .snapshots()) {
      final invites = <StaffInvite>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final state = _stateFrom(data['inviteState']);
        if (state == StaffInviteState.revoked) continue;
        final email = data['email'];
        if (email is! String || email.isEmpty) continue;
        final displayName = data['displayName'];
        invites.add(
          StaffInvite(
            id: doc.id,
            email: email,
            displayName: displayName is String && displayName.isNotEmpty
                ? displayName
                : null,
            permissions: StaffPermission.parse(data['permissions']),
            state: state,
            version: (data['version'] as num?)?.toInt() ?? 1,
            linked: data['memberUid'] is String,
          ),
        );
      }
      yield invites;
    }
  } on FirebaseException {
    // A denied or offline stream fails closed to an empty team rather than an
    // error state; the counter and upsell still render.
    yield const [];
  }
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
      Firebase.apps.isEmpty) {
    yield null;
    return;
  }
  try {
    await for (final snapshot
        in FirebaseFirestore.instance
            .collection('planCatalog')
            .doc(tier)
            .snapshots()) {
      final data = snapshot.data();
      final seatLimit = data?['staffSeatLimit'];
      if (seatLimit is! int) {
        yield null;
        continue;
      }
      yield StaffPlan(
        seatLimit: seatLimit,
        customRoles: data?['customStaffRoles'] == true,
      );
    }
  } on FirebaseException {
    yield null;
  }
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

  Future<void> call(StaffInvite invite, Set<StaffPermission> permissions) async {
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
