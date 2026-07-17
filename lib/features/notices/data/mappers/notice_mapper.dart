import 'package:nyumba_property_management/core/offline/json_reader.dart';
import 'package:nyumba_property_management/core/offline/sync_metadata_mapper.dart';
import 'package:nyumba_property_management/features/notices/domain/notice.dart';

final class NoticeMapper {
  const NoticeMapper._();

  static Map<String, Object?> toJson(Notice notice) => <String, Object?>{
    'id': notice.id,
    'reference': notice.reference,
    'landlordId': notice.landlordId,
    'title': notice.title,
    'body': notice.body,
    'audience': notice.audience,
    'audienceType': notice.audienceType.name,
    'audienceId': notice.audienceId,
    'status': notice.status.name,
    'createdAt': notice.createdAt.toUtc().toIso8601String(),
    'updatedAt': notice.updatedAt.toUtc().toIso8601String(),
    'syncMetadata': SyncMetadataMapper.toJson(notice.syncMetadata),
  };

  static Notice fromJson(Map<String, Object?> json) {
    final reader = JsonReader(json);
    return Notice(
      id: reader.requiredString('id'),
      reference: reader.requiredString('reference'),
      landlordId: reader.requiredString('landlordId'),
      title: reader.requiredString('title'),
      body: reader.requiredString('body'),
      audience: reader.requiredString('audience'),
      audienceType: NoticeAudienceType.values.firstWhere(
        (value) => value.name == reader.optionalString('audienceType'),
        orElse: () => NoticeAudienceType.allActiveTenants,
      ),
      audienceId: reader.optionalString('audienceId'),
      status: reader.enumValue('status', NoticeStatus.values),
      createdAt: reader.requiredDate('createdAt'),
      updatedAt: reader.requiredDate('updatedAt'),
      syncMetadata: SyncMetadataMapper.fromJson(json['syncMetadata']),
    );
  }
}
