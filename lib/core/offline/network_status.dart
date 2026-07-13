import 'package:connectivity_plus/connectivity_plus.dart';

abstract interface class NetworkStatus {
  Future<bool> get isOnline;
  Stream<bool> get changes;
}

final class AlwaysOnlineNetworkStatus implements NetworkStatus {
  const AlwaysOnlineNetworkStatus();

  @override
  Future<bool> get isOnline async => true;

  @override
  Stream<bool> get changes => const Stream<bool>.empty();
}

/// Connectivity is a scheduling hint only. Failed remote calls are still
/// handled by the durable retry policy because an available interface does not
/// guarantee internet reachability.
final class ConnectivityNetworkStatus implements NetworkStatus {
  ConnectivityNetworkStatus({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<bool> get isOnline async =>
      _hasConnection(await _connectivity.checkConnectivity());

  @override
  Stream<bool> get changes =>
      _connectivity.onConnectivityChanged.map(_hasConnection).distinct();

  static bool _hasConnection(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);
}
