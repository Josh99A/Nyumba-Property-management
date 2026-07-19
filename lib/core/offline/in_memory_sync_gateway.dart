import 'remote_sync_gateway.dart';

/// Idempotent in-process transport for workspaces that have no server link:
/// anonymous public browsing and any build without an authenticated session.
/// Writes are accepted and acknowledged locally but never leave the device.
final class InMemorySyncGateway implements RemoteSyncGateway {
  final Set<String> _applied = <String>{};

  @override
  Future<RemoteWriteResult> push(RemoteMutation mutation) async {
    await Future<void>.delayed(const Duration(milliseconds: 8));
    final duplicate = !_applied.add(mutation.idempotencyKey);
    return RemoteWriteResult(
      committedAt: DateTime.now().toUtc(),
      serverRevision: 'local-${mutation.mutationId}',
      wasAlreadyApplied: duplicate,
    );
  }
}
