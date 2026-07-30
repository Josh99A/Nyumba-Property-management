import 'package:connectivity_plus/connectivity_plus.dart';

/// Whether this device currently has a usable network interface.
///
/// This gates whether a mutation may be *attempted*, which is a change of role
/// from the previous architecture: connectivity used to schedule a queue, and
/// now it decides whether a button is live at all. It remains a hint about the
/// interface, not proof of reachability — an available Wi-Fi radio behind a
/// captive portal reports online — so a command that gets past this gate can
/// still fail, and the command path treats that honestly rather than assuming
/// this check was authoritative.
abstract interface class ConnectionStatus {
  Future<bool> get isOnline;

  /// Emits on every transition. Screens use this to enable and disable
  /// server-dependent actions as the connection comes and goes.
  Stream<bool> get changes;
}

/// For tests and for builds with no Firebase configuration, where there is no
/// server to be disconnected from.
final class AlwaysOnlineConnectionStatus implements ConnectionStatus {
  const AlwaysOnlineConnectionStatus();

  @override
  Future<bool> get isOnline async => true;

  @override
  Stream<bool> get changes => const Stream<bool>.empty();
}

final class DeviceConnectionStatus implements ConnectionStatus {
  DeviceConnectionStatus({Connectivity? connectivity})
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
