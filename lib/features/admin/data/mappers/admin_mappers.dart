import 'package:nyumba_property_management/core/offline/json_reader.dart';
import 'package:nyumba_property_management/core/offline/sync_metadata_mapper.dart';
import 'package:nyumba_property_management/features/admin/domain/admin_action.dart';
import 'package:nyumba_property_management/features/admin/domain/managed_user.dart';

final class ManagedUserMapper {
  const ManagedUserMapper._();

  static Map<String, Object?> toJson(ManagedUser user) => <String, Object?>{
    'id': user.id,
    'reference': user.reference,
    'name': user.name,
    'email': user.email,
    'role': user.role,
    'location': user.location,
    'status': user.status.name,
    'lastActiveLabel': user.lastActiveLabel,
    'joinedLabel': user.joinedLabel,
    'createdAt': user.createdAt.toUtc().toIso8601String(),
    'updatedAt': user.updatedAt.toUtc().toIso8601String(),
    'syncMetadata': SyncMetadataMapper.toJson(user.syncMetadata),
  };

  static ManagedUser fromJson(Map<String, Object?> json) {
    final reader = JsonReader(json);
    return ManagedUser(
      id: reader.requiredString('id'),
      reference: reader.requiredString('reference'),
      name: reader.requiredString('name'),
      email: reader.requiredString('email'),
      role: reader.requiredString('role'),
      location: reader.requiredString('location'),
      status: reader.enumValue('status', ManagedUserStatus.values),
      lastActiveLabel: reader.requiredString('lastActiveLabel'),
      joinedLabel: reader.requiredString('joinedLabel'),
      createdAt: reader.requiredDate('createdAt'),
      updatedAt: reader.requiredDate('updatedAt'),
      syncMetadata: SyncMetadataMapper.fromJson(json['syncMetadata']),
    );
  }
}

final class AdminActionMapper {
  const AdminActionMapper._();

  static Map<String, Object?> toJson(AdminActionRecord record) =>
      <String, Object?>{
        'id': record.id,
        'reference': record.reference,
        'action': record.action,
        'targetUserId': record.targetUserId,
        'targetName': record.targetName,
        'performedBy': record.performedBy,
        'performedAt': record.performedAt.toUtc().toIso8601String(),
        'createdAt': record.createdAt.toUtc().toIso8601String(),
        'syncMetadata': SyncMetadataMapper.toJson(record.syncMetadata),
      };

  static AdminActionRecord fromJson(Map<String, Object?> json) {
    final reader = JsonReader(json);
    return AdminActionRecord(
      id: reader.requiredString('id'),
      reference: reader.requiredString('reference'),
      action: reader.requiredString('action'),
      targetUserId: reader.requiredString('targetUserId'),
      targetName: reader.requiredString('targetName'),
      performedBy: reader.requiredString('performedBy'),
      performedAt: reader.requiredDate('performedAt'),
      createdAt: reader.requiredDate('createdAt'),
      syncMetadata: SyncMetadataMapper.fromJson(json['syncMetadata']),
    );
  }
}
