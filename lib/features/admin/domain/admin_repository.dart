import 'admin_action.dart';
import 'managed_user.dart';

abstract interface class ManagedUserRepository {
  Stream<List<ManagedUser>> watchAll();
  Future<List<ManagedUser>> getAll();
  Future<ManagedUser?> getById(String id);
  Future<ManagedUser> invite(InviteManagedUserInput input);
  Future<ManagedUser> changeStatus({
    required String userId,
    required ManagedUserStatus status,
  });
}

abstract interface class AdminActionRepository {
  Stream<List<AdminActionRecord>> watchAll();
  Future<List<AdminActionRecord>> getAll();

  /// Appends an audit record ordered after the affected user aggregate so the
  /// audit entry can never reach the server before the change it describes.
  Future<AdminActionRecord> append({
    required String action,
    required String targetUserId,
    required String targetName,
    required String performedBy,
  });
}
