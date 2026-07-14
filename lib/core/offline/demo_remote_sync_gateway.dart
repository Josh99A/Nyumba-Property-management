import 'remote_sync_gateway.dart';

/// Idempotent in-process transport used only by explicitly selected demos.
final class DemoRemoteSyncGateway implements RemoteSyncGateway {
  final Set<String> _applied = <String>{};

  @override
  Future<RemoteWriteResult> push(RemoteMutation mutation) async {
    await Future<void>.delayed(const Duration(milliseconds: 8));
    final duplicate = !_applied.add(mutation.idempotencyKey);
    return RemoteWriteResult(
      committedAt: DateTime.now().toUtc(),
      serverRevision: 'demo-${mutation.mutationId}',
      wasAlreadyApplied: duplicate,
    );
  }
}
