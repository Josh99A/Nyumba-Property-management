import '../domain/sync_metadata.dart';

final class SyncMetadataMapper {
  const SyncMetadataMapper._();

  static Map<String, Object?> toJson(SyncMetadata value) => <String, Object?>{
    'state': value.state.name,
    'serverRevision': value.serverRevision,
    'lastSyncedAt': value.lastSyncedAt?.toUtc().toIso8601String(),
    'lastError': value.lastError,
  };

  static SyncMetadata fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('syncMetadata must be a map.');
    }
    final json = Map<String, Object?>.from(value);
    final stateName = json['state'];
    if (stateName is! String) {
      throw const FormatException('syncMetadata.state must be a string.');
    }
    final state = EntitySyncState.values.firstWhere(
      (candidate) => candidate.name == stateName,
      orElse: () =>
          throw FormatException('Unknown syncMetadata.state "$stateName".'),
    );
    final lastSyncedAt = json['lastSyncedAt'];
    return SyncMetadata(
      state: state,
      serverRevision: json['serverRevision'] as String?,
      lastSyncedAt: lastSyncedAt == null
          ? null
          : DateTime.parse(lastSyncedAt as String).toUtc(),
      lastError: json['lastError'] as String?,
    );
  }
}
