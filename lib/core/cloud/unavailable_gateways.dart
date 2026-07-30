import 'cloud_command.dart';
import 'cloud_data.dart';
import 'cloud_read_gateway.dart';

/// Reads for a build with no Firebase configuration.
///
/// This replaces the old in-memory fallback, and it behaves in exactly the
/// opposite way on purpose. The previous gateway accepted writes, acknowledged
/// them locally, and never contacted a server — so an anonymous visitor was
/// shown a successful submission that had gone nowhere. There is no honest way
/// to serve domain data without a server, so these report that plainly and let
/// the UI say so.
final class UnavailableCloudReadGateway implements CloudReadGateway {
  const UnavailableCloudReadGateway();

  static const _error = CloudReadError(
    kind: CloudErrorKind.connection,
    code: 'NO_CLOUD_CONFIGURED',
    detail: 'This build has no Firebase configuration.',
  );

  @override
  Stream<CloudData<List<Map<String, Object?>>>> watch(
    CommandAggregate aggregate,
    CloudScope scope,
  ) => Stream<CloudData<List<Map<String, Object?>>>>.value(
    CloudData<List<Map<String, Object?>>>.failure(_error),
  );

  @override
  Future<CloudData<List<Map<String, Object?>>>> fetch(
    CommandAggregate aggregate,
    CloudScope scope, {
    int limit = maximumScopedDocuments,
  }) async => CloudData<List<Map<String, Object?>>>.failure(_error);

  @override
  Future<CloudData<List<Map<String, Object?>>>> fetchPublicReviews(
    String landlordToken, {
    int limit = 20,
  }) async => CloudData<List<Map<String, Object?>>>.failure(_error);
}

/// Writes for a build with no Firebase configuration, and for anonymous
/// visitors.
///
/// Every command fails closed with a connection error. An unauthenticated
/// visitor browsing the public catalogue may read; nothing they do is ever
/// reported as saved, because nothing they do reaches a server.
final class UnavailableCommandGateway implements CloudCommandGateway {
  const UnavailableCommandGateway();

  @override
  Future<CommandOutcome> send(CloudCommand command) =>
      Future<CommandOutcome>.error(
        const CommandException(
          kind: CommandFailureKind.connection,
          code: 'NO_CLOUD_CONFIGURED',
          details: <String, Object?>{'reason': 'signInRequired'},
        ),
      );
}
