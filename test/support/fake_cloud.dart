import 'dart:async';

import 'package:nyumba_property_management/core/cloud/cloud_command.dart';
import 'package:nyumba_property_management/core/cloud/cloud_data.dart';
import 'package:nyumba_property_management/core/cloud/cloud_read_gateway.dart';
import 'package:nyumba_property_management/core/cloud/connection_status.dart';

/// A programmable stand-in for the server's read side.
///
/// Holds raw record maps per aggregate — the same shape
/// `FirestoreCloudReadGateway.toClientShape` produces — so tests exercise the
/// real mappers rather than a parallel decoding path.
final class FakeCloudReadGateway implements CloudReadGateway {
  final Map<CommandAggregate, List<Map<String, Object?>>> _records = {};
  final Map<
    CommandAggregate,
    StreamController<CloudData<List<Map<String, Object?>>>>
  >
  _controllers = {};

  /// Set when a scope should be refused or unreachable instead of answering.
  final Map<CommandAggregate, CloudReadError> failures = {};

  DateTime retrievedAt = DateTime.utc(2026, 7, 29, 9);

  /// How many times a one-shot fetch actually reached this gateway. Cache hits
  /// are exactly the calls that never arrive here, which is how a test proves
  /// the read-through cache did its job.
  int fetchCount = 0;

  void seed(CommandAggregate aggregate, List<Map<String, Object?>> records) {
    _records[aggregate] = [...records];
    _emit(aggregate);
  }

  /// Pushes a new server snapshot to any live listener, as a real collection
  /// change would.
  void emitUpdate(
    CommandAggregate aggregate,
    List<Map<String, Object?>> records,
  ) => seed(aggregate, records);

  /// Makes subsequent reads of [aggregate] fail, and tells live listeners.
  void fail(CommandAggregate aggregate, CloudReadError error) {
    failures[aggregate] = error;
    _controllers[aggregate]?.add(
      CloudData<List<Map<String, Object?>>>.failure(error),
    );
  }

  void recover(CommandAggregate aggregate) {
    failures.remove(aggregate);
    _emit(aggregate);
  }

  void _emit(CommandAggregate aggregate) {
    final controller = _controllers[aggregate];
    if (controller == null || controller.isClosed) return;
    controller.add(_snapshot(aggregate));
  }

  CloudData<List<Map<String, Object?>>> _snapshot(CommandAggregate aggregate) {
    final error = failures[aggregate];
    if (error != null) {
      return CloudData<List<Map<String, Object?>>>.failure(error);
    }
    final records = _records[aggregate] ?? const <Map<String, Object?>>[];
    return records.isEmpty
        ? CloudData<List<Map<String, Object?>>>.empty(
            records,
            retrievedAt: retrievedAt,
          )
        : CloudData<List<Map<String, Object?>>>.live(
            records,
            retrievedAt: retrievedAt,
          );
  }

  /// Delivers the current snapshot immediately and every later change, which is
  /// how a Firestore listener behaves — a subscriber never waits for a write
  /// before seeing what is already there.
  @override
  Stream<CloudData<List<Map<String, Object?>>>> watch(
    CommandAggregate aggregate,
    CloudScope scope,
  ) async* {
    yield _snapshot(aggregate);
    yield* _controllers
        .putIfAbsent(
          aggregate,
          () =>
              StreamController<
                CloudData<List<Map<String, Object?>>>
              >.broadcast(),
        )
        .stream;
  }

  @override
  Future<CloudData<List<Map<String, Object?>>>> fetch(
    CommandAggregate aggregate,
    CloudScope scope, {
    int limit = maximumScopedDocuments,
  }) async {
    fetchCount++;
    return _snapshot(aggregate);
  }

  @override
  Future<CloudData<List<Map<String, Object?>>>> fetchPublicReviews(
    String landlordToken, {
    int limit = 20,
  }) async => _snapshot(CommandAggregate.publicReview);

  Future<void> close() async {
    for (final controller in _controllers.values) {
      await controller.close();
    }
    _controllers.clear();
  }
}

/// Records every command that reaches the wire and answers however the test
/// tells it to.
final class RecordingCommandGateway implements CloudCommandGateway {
  RecordingCommandGateway({this.responder});

  final List<CloudCommand> sent = <CloudCommand>[];

  /// Return an outcome or throw a [CommandException]. Defaults to success.
  Future<CommandOutcome> Function(CloudCommand command, int attempt)? responder;

  CloudCommand get lastCommand => sent.last;

  @override
  Future<CommandOutcome> send(CloudCommand command) {
    sent.add(command);
    final handler = responder;
    if (handler != null) return handler(command, sent.length);
    return Future<CommandOutcome>.value(
      CommandOutcome(
        committedAt: DateTime.utc(2026, 7, 29, 9),
        serverVersion: '2',
      ),
    );
  }
}

final class StubConnection implements ConnectionStatus {
  StubConnection({this.online = true});

  bool online;

  @override
  Future<bool> get isOnline async => online;

  @override
  Stream<bool> get changes => const Stream<bool>.empty();
}
