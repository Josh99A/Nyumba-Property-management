import 'staff_permission.dart';

enum StaffInviteState { pending, accepted, revoked, unknown }

/// A staff seat as the owner sees it on the Team screen.
final class StaffInvite {
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
final class StaffPlan {
  const StaffPlan({required this.seatLimit, required this.customRoles});

  /// Seats available beyond the owner. 0 means the tier has no staff seats.
  final int seatLimit;

  /// Whether the owner can grant a custom permission subset (Premium+); when
  /// false, every seat gets the fixed standard preset.
  final bool customRoles;
}

/// Local source of truth for server-owned staff access projections.
abstract interface class StaffRepository {
  Stream<List<StaffInvite>> watchInvites();

  Stream<StaffPlan?> watchPlan(String tier);
}
