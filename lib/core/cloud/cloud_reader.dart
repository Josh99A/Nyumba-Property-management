// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:developer' as developer;

import '../domain/clock.dart';
import 'cloud_cache.dart';
import 'cloud_command.dart';
import 'cloud_data.dart';
import 'cloud_read_gateway.dart';

/// Read-through access to cloud collections, shared by every feature
/// repository.
///
/// The contract in one line: **the cache can make data appear sooner, and can
/// never make it appear fresher than it is.** A cached list is emitted
/// immediately so a screen has something to draw, tagged
/// [CloudDataStatus.cachedAwaitingValidation]; the server's answer replaces it
/// and re-tags it [CloudDataStatus.live]; and if the server cannot be reached,
/// what is on screen stays but is re-tagged
/// [CloudDataStatus.cachedPotentiallyOutdated] with the error that caused it.
/// At no point does a cached value get presented as current.
final class CloudReader {
  CloudReader({
    required CloudCache cache,
    required CloudReadGateway gateway,
    required CachePartition partition,
    Clock clock = const SystemClock(),
  }) : _cache = cache,
       _gateway = gateway,
       _partition = partition,
       _clock = clock;

  final CloudCache _cache;
  final CloudReadGateway _gateway;
  final CachePartition _partition;
  final Clock _clock;

  CachePartition get partition => _partition;

  /// A live view of [aggregate] within [scope].
  ///
  /// [decode] turns one server record into a domain object. A record it
  /// rejects is dropped with a log rather than thrown: one malformed document
  /// must not blank a whole screen, and a mapper/projection mismatch is the
  /// most likely thing to go wrong across the Dart/TypeScript boundary.
  Stream<CloudData<List<T>>> watch<T>(
    CommandAggregate aggregate,
    CloudScope scope, {
    required T Function(Map<String, Object?> record) decode,
    String? cacheKey,
    Duration? timeToLive,
  }) {
    final key = cacheKey ?? aggregate.cacheNamespace;
    final controller = StreamController<CloudData<List<T>>>();
    StreamSubscription<CloudData<List<Map<String, Object?>>>>? subscription;

    controller.onListen = () {
      // Prime from cache so the first frame has content. Explicitly unvalidated
      // — the listener below is what proves it.
      final cached = _cache.read<List<T>>(
        _partition,
        key,
        timeToLive: timeToLive,
      );
      if (cached != null) {
        controller.add(
          CloudData<List<T>>.cached(cached.value, retrievedAt: cached.storedAt),
        );
      } else {
        controller.add(const CloudData.initialLoading());
      }

      var lastGood = cached?.value;
      var lastGoodAt = cached?.storedAt;
      // Carried alongside the rows themselves. A live result that dropped some
      // records, followed by a failed refresh, would otherwise show the same
      // incomplete list with the partial-data warning removed — the list would
      // look complete at exactly the moment it is least verifiable.
      var lastGoodDiscarded = 0;

      subscription = _gateway.watch(aggregate, scope).listen((snapshot) {
        switch (snapshot.status) {
          case CloudDataStatus.live:
          case CloudDataStatus.empty:
            final decoded = _decodeAll(snapshot.value!, decode, aggregate);
            final at = snapshot.retrievedAt ?? _clock.now().toUtc();
            _cache.write(_partition, key, decoded.values, retrievedAt: at);
            lastGood = decoded.values;
            lastGoodAt = at;
            lastGoodDiscarded = decoded.discardedCount;
            controller.add(
              decoded.values.isEmpty && decoded.discardedCount == 0
                  ? CloudData<List<T>>.empty(decoded.values, retrievedAt: at)
                  : CloudData<List<T>>.live(
                      decoded.values,
                      retrievedAt: at,
                      discardedRecordCount: decoded.discardedCount,
                    ),
            );
          case CloudDataStatus.connectionFailure:
          case CloudDataStatus.permissionDenied:
          case CloudDataStatus.serverRejection:
            final error = snapshot.error!;
            // A denied read must not keep serving this actor cached rows: the
            // server has just said they may not have them. Connection failures
            // are different — the data was legitimately theirs a moment ago.
            if (error.kind == CloudErrorKind.permissionDenied) {
              _cache.invalidate(_partition, key);
              lastGood = null;
              lastGoodAt = null;
              lastGoodDiscarded = 0;
              controller.add(CloudData<List<T>>.failure(error));
            } else if (lastGood != null && lastGoodAt != null) {
              controller.add(
                CloudData<List<T>>.stale(
                  lastGood!,
                  retrievedAt: lastGoodAt!,
                  error: error,
                  discardedRecordCount: lastGoodDiscarded,
                ),
              );
            } else {
              controller.add(CloudData<List<T>>.failure(error));
            }
          case CloudDataStatus.initialLoading:
          case CloudDataStatus.refreshing:
          case CloudDataStatus.cachedAwaitingValidation:
          case CloudDataStatus.cachedPotentiallyOutdated:
          case CloudDataStatus.reconnecting:
            // The gateway emits only settled states; nothing to forward.
            break;
        }
      });
    };

    controller.onCancel = () async {
      await subscription?.cancel();
      subscription = null;
    };

    return controller.stream;
  }

  /// A deliberate one-shot read.
  ///
  /// When [allowCached] and a live entry exists, the cached value is returned
  /// without a server round trip — that is the whole point of the cache. Pass
  /// `allowCached: false` for anything a user has just asked to see afresh.
  Future<CloudData<List<T>>> fetch<T>(
    CommandAggregate aggregate,
    CloudScope scope, {
    required T Function(Map<String, Object?> record) decode,
    String? cacheKey,
    Duration? timeToLive,
    bool allowCached = true,
    int limit = maximumScopedDocuments,
  }) async {
    final key = cacheKey ?? aggregate.cacheNamespace;
    final cached = allowCached
        ? _cache.read<List<T>>(_partition, key, timeToLive: timeToLive)
        : null;
    if (cached != null) {
      return CloudData<List<T>>.cached(
        cached.value,
        retrievedAt: cached.storedAt,
      );
    }

    final snapshot = await _gateway.fetch(aggregate, scope, limit: limit);
    if (snapshot.hasFailed) {
      final error = snapshot.error!;
      if (error.kind == CloudErrorKind.permissionDenied) {
        _cache.invalidate(_partition, key);
      }
      // Nothing validated arrived. If a (possibly expired) cached value exists,
      // showing it flagged as outdated beats showing nothing.
      final fallback = _cache.read<List<T>>(
        _partition,
        key,
        timeToLive: const Duration(days: 365),
      );
      return fallback == null || error.kind == CloudErrorKind.permissionDenied
          ? CloudData<List<T>>.failure(error)
          : CloudData<List<T>>.stale(
              fallback.value,
              retrievedAt: fallback.storedAt,
              error: error,
            );
    }

    final decoded = _decodeAll(snapshot.value!, decode, aggregate);
    final at = snapshot.retrievedAt ?? _clock.now().toUtc();
    _cache.write(_partition, key, decoded.values, retrievedAt: at);
    return decoded.values.isEmpty && decoded.discardedCount == 0
        ? CloudData<List<T>>.empty(decoded.values, retrievedAt: at)
        : CloudData<List<T>>.live(
            decoded.values,
            retrievedAt: at,
            discardedRecordCount: decoded.discardedCount,
          );
  }

  /// Drops every cache entry for [aggregate].
  ///
  /// Call after a server-confirmed mutation. Invalidating the whole namespace
  /// rather than one key is deliberate: a created unit changes the unit list,
  /// its property's detail view, and the dashboard counts, and enumerating
  /// those by hand is exactly the bookkeeping that silently misses one.
  void invalidate(CommandAggregate aggregate) =>
      _cache.invalidatePrefix(_partition, aggregate.cacheNamespace);

  void invalidateKey(String key) => _cache.invalidate(_partition, key);

  _DecodedRecords<T> _decodeAll<T>(
    List<Map<String, Object?>> records,
    T Function(Map<String, Object?> record) decode,
    CommandAggregate aggregate,
  ) {
    final result = <T>[];
    var rejected = 0;
    for (final record in records) {
      try {
        result.add(decode(record));
      } on Object catch (error) {
        rejected++;
        developer.log(
          'Dropped a ${aggregate.name} record this build cannot read: $error',
          name: 'cloud_reader',
        );
      }
    }
    if (rejected > 0) {
      developer.log(
        '$rejected of ${records.length} ${aggregate.name} records were '
        'undecodable; the projection and the mapper have drifted apart.',
        name: 'cloud_reader',
      );
    }
    return _DecodedRecords<T>(
      values: List<T>.unmodifiable(result),
      discardedCount: rejected,
    );
  }
}

final class _DecodedRecords<T> {
  const _DecodedRecords({required this.values, required this.discardedCount});

  final List<T> values;
  final int discardedCount;
}
