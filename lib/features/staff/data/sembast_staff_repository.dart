import '../../../core/offline/offline_database.dart';
import '../../../core/offline/offline_entity.dart';
import '../domain/staff_permission.dart';
import '../domain/staff_repository.dart';

final class SembastStaffRepository implements StaffRepository {
  const SembastStaffRepository(this._database);

  final OfflineDatabase _database;

  @override
  Stream<List<StaffInvite>> watchInvites() =>
      _database.watchEntities(OfflineEntityType.staffInvite).map(_mapInvites);

  @override
  Stream<StaffPlan?> watchPlan(String tier) =>
      _database.watchEntity(OfflineEntityType.planCatalog, tier).map(_mapPlan);

  static List<StaffInvite> _mapInvites(List<Map<String, Object?>> records) {
    final current = <({StaffInvite invite, DateTime createdAt})>[];
    for (final record in records) {
      final invite = _mapInvite(record);
      if (invite == null || invite.state == StaffInviteState.revoked) continue;
      current.add((invite: invite, createdAt: _date(record['createdAt'])));
    }
    current.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return [for (final entry in current) entry.invite];
  }

  static StaffInvite? _mapInvite(Map<String, Object?> record) {
    final id = record['id'];
    final email = record['email'];
    if (id is! String || id.isEmpty || email is! String || email.isEmpty) {
      return null;
    }
    final displayName = record['displayName'];
    return StaffInvite(
      id: id,
      email: email,
      displayName: displayName is String && displayName.trim().isNotEmpty
          ? displayName.trim()
          : null,
      permissions: StaffPermission.parse(record['permissions']),
      state: switch (record['inviteState']) {
        'pending' => StaffInviteState.pending,
        'accepted' => StaffInviteState.accepted,
        'revoked' => StaffInviteState.revoked,
        _ => StaffInviteState.unknown,
      },
      version: (record['version'] as num?)?.toInt() ?? 1,
      linked: record['memberUid'] is String,
    );
  }

  static StaffPlan? _mapPlan(Map<String, Object?>? record) {
    final rawLimit = record?['staffSeatLimit'];
    if (rawLimit is! num) return null;
    final limit = rawLimit.toInt();
    if (limit < 0) return null;
    return StaffPlan(
      seatLimit: limit,
      customRoles: record?['customStaffRoles'] == true,
    );
  }

  static DateTime _date(Object? raw) =>
      DateTime.tryParse(raw?.toString() ?? '')?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
