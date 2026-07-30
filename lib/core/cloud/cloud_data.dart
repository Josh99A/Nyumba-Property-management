/// Honest read states for cloud-authoritative data.
///
/// Firebase owns every domain record. Anything this client holds locally is a
/// performance copy whose freshness is either proven, being proven, or unknown
/// — and the difference is always visible. The states below are exhaustive by
/// design: a screen that cannot say which one it is in is a screen that will
/// eventually present a cached record as current server state.
library;

/// Why a cloud read did not produce current data.
///
/// Kept separate from the transport status code on purpose. A caller decides
/// what to show from [kind]; [code] exists for logs and tests. Branching on a
/// raw `FirebaseException` plugin code in presentation is how "permission
/// denied" ends up rendering as "no results".
enum CloudErrorKind {
  /// The request never reached the server, or the answer never came back.
  /// Retrying later is meaningful.
  connection,

  /// The server understood the request and refused it for this actor.
  /// Retrying unchanged is not meaningful.
  permissionDenied,

  /// The server accepted the request and rejected its content or state.
  serverRejection,
}

final class CloudReadError {
  const CloudReadError({required this.kind, required this.code, this.detail});

  const CloudReadError.connection({String code = 'unavailable', String? detail})
    : this(kind: CloudErrorKind.connection, code: code, detail: detail);

  const CloudReadError.permissionDenied({String? detail})
    : this(
        kind: CloudErrorKind.permissionDenied,
        code: 'permission-denied',
        detail: detail,
      );

  const CloudReadError.serverRejection({required String code, String? detail})
    : this(kind: CloudErrorKind.serverRejection, code: code, detail: detail);

  final CloudErrorKind kind;

  /// Stable machine-readable code. Never rendered to a user as-is.
  final String code;

  /// Safe supplementary text. Must never carry another actor's record.
  final String? detail;

  /// Whether a plain retry of the same request could succeed.
  bool get isRetryable => kind == CloudErrorKind.connection;

  @override
  bool operator ==(Object other) =>
      other is CloudReadError &&
      other.kind == kind &&
      other.code == code &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(kind, code, detail);

  @override
  String toString() => 'CloudReadError($kind, $code)';
}

/// The state of one cloud read, as the UI must present it.
///
/// Every value is reachable and every value means something different to a
/// user. In particular [empty] is *only* a confirmed empty server result: it
/// is never used for loading, for failure, or for a scope the actor may not
/// read. Collapsing those into "no data" is the specific bug this enum exists
/// to make impossible.
enum CloudDataStatus {
  /// Nothing has been shown yet and the first read is in flight.
  initialLoading,

  /// Data is on screen and a freshness check is running against the server.
  refreshing,

  /// Current server data, validated this session.
  live,

  /// Cached data rendered immediately; validation has not started or not yet
  /// returned. Honest label: "checking for updates".
  cachedAwaitingValidation,

  /// Cached data whose refresh failed. Must be shown with a freshness warning,
  /// the underlying [CloudReadError], and a retry affordance.
  cachedPotentiallyOutdated,

  /// The server answered, and the answer was "none". A real, current result.
  empty,

  /// The request could not reach the server and nothing cached is available.
  connectionFailure,

  /// The server refused this actor's read.
  permissionDenied,

  /// The server rejected the request itself.
  serverRejection,

  /// A dropped listener is being re-established.
  reconnecting,
}

/// An immutable snapshot of one cloud read: what to show, how fresh it is, and
/// what went wrong if anything did.
final class CloudData<T> {
  const CloudData._({
    required this.status,
    this.value,
    this.retrievedAt,
    this.error,
  });

  /// First read in flight, nothing to show.
  const CloudData.initialLoading()
    : this._(status: CloudDataStatus.initialLoading);

  /// Validated current server data.
  const CloudData.live(T value, {required DateTime retrievedAt})
    : this._(
        status: CloudDataStatus.live,
        value: value,
        retrievedAt: retrievedAt,
      );

  /// A confirmed empty server result. [value] carries the caller's empty
  /// collection so widgets need not special-case null.
  const CloudData.empty(T value, {required DateTime retrievedAt})
    : this._(
        status: CloudDataStatus.empty,
        value: value,
        retrievedAt: retrievedAt,
      );

  /// Cached data shown before validation has returned.
  const CloudData.cached(T value, {required DateTime retrievedAt})
    : this._(
        status: CloudDataStatus.cachedAwaitingValidation,
        value: value,
        retrievedAt: retrievedAt,
      );

  /// Cached data whose refresh failed. [retrievedAt] is when the *data* was
  /// obtained, not when the failed refresh ran — that is what makes a
  /// "last updated" label truthful.
  const CloudData.stale(
    T value, {
    required DateTime retrievedAt,
    required CloudReadError error,
  }) : this._(
         status: CloudDataStatus.cachedPotentiallyOutdated,
         value: value,
         retrievedAt: retrievedAt,
         error: error,
       );

  /// A failure with nothing to fall back on.
  factory CloudData.failure(CloudReadError error) => CloudData<T>._(
    status: switch (error.kind) {
      CloudErrorKind.connection => CloudDataStatus.connectionFailure,
      CloudErrorKind.permissionDenied => CloudDataStatus.permissionDenied,
      CloudErrorKind.serverRejection => CloudDataStatus.serverRejection,
    },
    error: error,
  );

  /// A dropped subscription is being re-established. Any [value] already on
  /// screen is retained: a reconnect is not a reason to blank a list.
  const CloudData.reconnecting({T? value, DateTime? retrievedAt})
    : this._(
        status: CloudDataStatus.reconnecting,
        value: value,
        retrievedAt: retrievedAt,
      );

  final CloudDataStatus status;

  /// The data to render, when there is any. Present for cached and stale
  /// states as well as live ones — losing visible data to a background refresh
  /// is a regression, not a safety measure.
  final T? value;

  /// When [value] was obtained from the server. Drives "last updated".
  final DateTime? retrievedAt;

  /// Why the most recent attempt failed, when it did.
  final CloudReadError? error;

  bool get hasValue => value != null;

  /// Whether a request is currently in flight.
  bool get isBusy =>
      status == CloudDataStatus.initialLoading ||
      status == CloudDataStatus.refreshing ||
      status == CloudDataStatus.reconnecting;

  /// Whether what is on screen may no longer match the server. UI must pair
  /// this with a warning and a retry action.
  bool get isPotentiallyOutdated =>
      status == CloudDataStatus.cachedPotentiallyOutdated;

  /// Whether the data on screen has been validated against the server this
  /// session. Never use this to authorize an action — it describes freshness,
  /// not permission.
  bool get isValidated =>
      status == CloudDataStatus.live || status == CloudDataStatus.empty;

  /// Whether the read ended in a failure with nothing to show.
  bool get hasFailed =>
      status == CloudDataStatus.connectionFailure ||
      status == CloudDataStatus.permissionDenied ||
      status == CloudDataStatus.serverRejection;

  /// Marks an in-flight freshness check over data already on screen.
  CloudData<T> asRefreshing() => hasValue
      ? CloudData._(
          status: CloudDataStatus.refreshing,
          value: value,
          retrievedAt: retrievedAt,
        )
      : const CloudData.initialLoading();

  /// Applies a failed refresh: keeps visible data but marks it unvalidated.
  /// With nothing to keep, the failure stands alone.
  CloudData<T> asFailed(CloudReadError error) => hasValue && retrievedAt != null
      ? CloudData.stale(value as T, retrievedAt: retrievedAt!, error: error)
      : CloudData.failure(error);

  CloudData<R> map<R>(R Function(T value) transform) => CloudData._(
    status: status,
    value: value == null ? null : transform(value as T),
    retrievedAt: retrievedAt,
    error: error,
  );

  @override
  String toString() =>
      'CloudData(${status.name}, hasValue: $hasValue, at: $retrievedAt)';
}
