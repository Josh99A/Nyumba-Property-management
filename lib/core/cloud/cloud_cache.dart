// ignore_for_file: prefer_initializing_formals

/// In-memory read-through cache for cloud reads.
///
/// This is an optimisation and nothing else. It makes navigation and repeated
/// reads within a session fast; it is never consulted to decide what an actor
/// may do, what they owe, what they have paid, or what state their account is
/// in. Those answers come from the server on every ask.
///
/// **Nothing here is persisted to disk.** That is a deliberate design choice
/// rather than an omission. Protected records that never leave RAM cannot
/// outlive a session, cannot be read by the next account on a shared browser,
/// and cannot be recovered from a stolen device — which turns "clear protected
/// cached data on logout" from a routine we must remember to run correctly
/// into a property of the storage medium. The cost is a cold first read after
/// launch; the benefit is that the entire class of cross-account cache leakage
/// is unreachable. If a future change adds disk persistence, it must partition
/// by [CachePartition] exactly as this does, and public data must be the only
/// thing that survives a sign-out.
library;

import 'dart:collection';

import '../domain/clock.dart';

/// Identifies whose data an entry belongs to.
///
/// Two entries with different partitions never see each other, so a landlord's
/// tenancies cannot surface in the same person's admin session, and the
/// previous account's records cannot surface in the next one's.
///
/// [environment] is the Firebase project id. It is part of the key so a build
/// pointed at a different project can never read a cache filled by another —
/// the failure that would otherwise look like phantom records from nowhere.
final class CachePartition {
  const CachePartition({
    required this.environment,
    this.userId,
    this.role,
    this.workspaceId,
  });

  /// The partition for unauthenticated reads of world-readable projections.
  /// Survives sign-out because nothing in it is protected.
  const CachePartition.public({required String environment})
    : this(environment: environment);

  final String environment;
  final String? userId;
  final String? role;
  final String? workspaceId;

  /// Whether this partition holds data belonging to a signed-in actor.
  /// Protected partitions are dropped on any identity or authorization change.
  bool get isProtected => userId != null;

  @override
  bool operator ==(Object other) =>
      other is CachePartition &&
      other.environment == environment &&
      other.userId == userId &&
      other.role == role &&
      other.workspaceId == workspaceId;

  @override
  int get hashCode => Object.hash(environment, userId, role, workspaceId);

  @override
  String toString() =>
      'CachePartition($environment/${userId ?? 'anonymous'}'
      '${role == null ? '' : '/$role'}'
      '${workspaceId == null ? '' : '/$workspaceId'})';
}

/// A cached value plus everything needed to judge whether it may still be used.
final class CacheEntry<T> {
  const CacheEntry({
    required this.value,
    required this.storedAt,
    required this.schemaVersion,
  });

  final T value;

  /// When the server produced this value. Surfaced to users as "last updated",
  /// so it must be the server-read time, never the cache-write time.
  final DateTime storedAt;

  /// The shape version this value was decoded under. An entry written by a
  /// previous build is discarded rather than handed to a mapper that no longer
  /// understands it.
  final int schemaVersion;
}

/// A bounded, partitioned, expiring cache of decoded cloud reads.
///
/// Values are stored decoded rather than as JSON: re-decoding on every screen
/// visit was a measurable cost, and holding objects removes it. The trade is
/// that entries are only as shareable as the objects are immutable, which the
/// domain aggregates are.
final class CloudCache {
  CloudCache({
    Clock clock = const SystemClock(),
    int maximumEntries = _defaultMaximumEntries,
    Duration defaultTimeToLive = const Duration(minutes: 5),
  }) : _clock = clock,
       _maximumEntries = maximumEntries,
       _defaultTimeToLive = defaultTimeToLive,
       assert(maximumEntries > 0, 'a cache with no room is not a cache');

  /// Sized to hold a working session's screens, not a workspace's data. The
  /// cache is a navigation accelerator; a landlord with two thousand units
  /// should evict, not consume unbounded memory on a low-end phone.
  static const int _defaultMaximumEntries = 256;

  /// The shape version of everything this build writes. Bump when a mapper's
  /// accepted fields change, so entries the new code cannot read are dropped
  /// instead of decoded into something wrong.
  static const int schemaVersion = 1;

  final Clock _clock;
  final int _maximumEntries;
  final Duration _defaultTimeToLive;

  /// Insertion-ordered so the oldest touched entry is the first evicted.
  /// Re-inserting on read is what makes the ordering least-recently-used.
  final LinkedHashMap<_CacheKey, CacheEntry<Object?>> _entries =
      LinkedHashMap<_CacheKey, CacheEntry<Object?>>();

  int get length => _entries.length;

  /// Returns the entry for [key] when it is present, unexpired, and written by
  /// a build with the current [schemaVersion]; otherwise null and the stale
  /// entry is evicted.
  ///
  /// A caller must treat a hit as *unvalidated* until a refresh confirms it.
  CacheEntry<T>? read<T>(
    CachePartition partition,
    String key, {
    Duration? timeToLive,
  }) {
    final cacheKey = _CacheKey(partition, key);
    final entry = _entries.remove(cacheKey);
    if (entry == null) return null;

    if (entry.schemaVersion != schemaVersion) return null;

    final age = _clock.now().toUtc().difference(entry.storedAt);
    if (age >= (timeToLive ?? _defaultTimeToLive)) return null;

    final value = entry.value;
    // A type mismatch means two callers chose the same key for different
    // shapes. Dropping the entry is safer than casting into a crash on a
    // screen far from the collision.
    if (value is! T) return null;

    // Re-insert to mark most-recently-used.
    _entries[cacheKey] = entry;
    return CacheEntry<T>(
      value: value,
      storedAt: entry.storedAt,
      schemaVersion: entry.schemaVersion,
    );
  }

  /// Stores [value] against [key], evicting the least recently used entry when
  /// the cache is full.
  ///
  /// [retrievedAt] must be when the server produced the value.
  void write<T>(
    CachePartition partition,
    String key,
    T value, {
    required DateTime retrievedAt,
  }) {
    final cacheKey = _CacheKey(partition, key);
    _entries.remove(cacheKey);
    _entries[cacheKey] = CacheEntry<Object?>(
      value: value,
      storedAt: retrievedAt.toUtc(),
      schemaVersion: schemaVersion,
    );
    while (_entries.length > _maximumEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Drops one entry. Call after a confirmed mutation touching it.
  void invalidate(CachePartition partition, String key) =>
      _entries.remove(_CacheKey(partition, key));

  /// Drops every entry in [partition] whose key starts with [prefix].
  ///
  /// Confirmed mutations usually invalidate a family rather than one key: a
  /// created unit changes the unit list, the owning property's detail, and the
  /// dashboard counts.
  void invalidatePrefix(CachePartition partition, String prefix) =>
      _entries.removeWhere(
        (key, _) => key.partition == partition && key.key.startsWith(prefix),
      );

  /// Drops everything belonging to [partition].
  void clearPartition(CachePartition partition) =>
      _entries.removeWhere((key, _) => key.partition == partition);

  /// Drops every protected entry, keeping public ones.
  ///
  /// This is the sign-out, account-switch, role-change, suspension,
  /// authorization-failure and account-deletion path. It is deliberately
  /// indiscriminate: enumerating which caches a departing session touched is
  /// exactly the kind of bookkeeping that silently misses one.
  void clearProtected() =>
      _entries.removeWhere((key, _) => key.partition.isProtected);

  void clear() => _entries.clear();
}

final class _CacheKey {
  const _CacheKey(this.partition, this.key);

  final CachePartition partition;
  final String key;

  @override
  bool operator ==(Object other) =>
      other is _CacheKey && other.partition == partition && other.key == key;

  @override
  int get hashCode => Object.hash(partition, key);
}
