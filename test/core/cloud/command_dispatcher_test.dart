import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/cloud/cloud_command.dart';
import 'package:nyumba_property_management/core/cloud/command_dispatcher.dart';
import 'package:nyumba_property_management/core/cloud/connection_status.dart';
import 'package:nyumba_property_management/core/domain/clock.dart';

final class _StubConnection implements ConnectionStatus {
  _StubConnection({this.online = true});

  bool online;

  @override
  Future<bool> get isOnline async => online;

  @override
  Stream<bool> get changes => const Stream<bool>.empty();
}

/// Records every send so duplicate-submission claims can be checked against
/// what actually reached the wire, not against what the caller believed.
final class _RecordingGateway implements CloudCommandGateway {
  _RecordingGateway({this.responder});

  final List<CloudCommand> sent = <CloudCommand>[];
  Future<CommandOutcome> Function(CloudCommand command, int attempt)? responder;

  @override
  Future<CommandOutcome> send(CloudCommand command) {
    sent.add(command);
    final handler = responder;
    if (handler != null) return handler(command, sent.length);
    return Future<CommandOutcome>.value(
      CommandOutcome(committedAt: DateTime.utc(2026, 7, 29)),
    );
  }
}

CloudCommand _command({String id = 'cmd-1'}) => CloudCommand(
  commandId: id,
  type: 'property.create',
  aggregate: CommandAggregate.property,
  aggregateId: 'property-1',
  operation: CommandOperation.create,
  payload: const <String, Object?>{'name': 'Kololo Garden Court'},
  issuedAt: DateTime.utc(2026, 7, 29, 9),
);

void main() {
  final clock = FixedClock(DateTime.utc(2026, 7, 29, 9, 30));

  CommandDispatcher dispatcherFor(
    _RecordingGateway gateway, {
    bool online = true,
  }) => CommandDispatcher(
    gateway: gateway,
    connection: _StubConnection(online: online),
    clock: clock,
  );

  group('connection loss before submission', () {
    test('fails immediately without reaching the gateway', () async {
      final gateway = _RecordingGateway();
      final dispatcher = dispatcherFor(gateway, online: false);

      await expectLater(
        dispatcher.submit(_command()),
        throwsA(
          isA<CommandException>()
              .having((e) => e.kind, 'kind', CommandFailureKind.connection)
              .having((e) => e.code, 'code', 'OFFLINE'),
        ),
      );

      // Nothing was sent, so nothing can have applied — and nothing is left
      // hanging for the user to reconcile.
      expect(gateway.sent, isEmpty);
      expect(dispatcher.hasUnresolvedCommands, isFalse);
    });

    test('nothing is queued for later delivery', () async {
      final gateway = _RecordingGateway();
      final connection = _StubConnection(online: false);
      final dispatcher = CommandDispatcher(
        gateway: gateway,
        connection: connection,
        clock: clock,
      );

      await expectLater(dispatcher.submit(_command()), throwsA(anything));

      // Coming back online must not resurrect the abandoned attempt.
      connection.online = true;
      await Future<void>.delayed(Duration.zero);
      expect(gateway.sent, isEmpty);
    });
  });

  group('duplicate submission', () {
    test('a second submit while in flight joins the first request', () async {
      final completer = Completer<CommandOutcome>();
      final gateway = _RecordingGateway(responder: (_, _) => completer.future);
      final dispatcher = dispatcherFor(gateway);

      final first = dispatcher.submit(_command());
      final second = dispatcher.submit(_command());
      expect(dispatcher.isInFlight('cmd-1'), isTrue);

      completer.complete(
        CommandOutcome(committedAt: DateTime.utc(2026, 7, 29)),
      );
      await Future.wait([first, second]);

      expect(gateway.sent, hasLength(1));
    });
  });

  group('server rejection', () {
    test('is definitive and leaves nothing unresolved', () async {
      final gateway = _RecordingGateway(
        responder: (_, _) => Future<CommandOutcome>.error(
          const CommandException(
            kind: CommandFailureKind.rejected,
            code: 'VALIDATION_FAILED',
            details: <String, Object?>{'reason': 'unitNotVacant'},
          ),
        ),
      );
      final dispatcher = dispatcherFor(gateway);

      await expectLater(
        dispatcher.submit(_command()),
        throwsA(
          isA<CommandException>()
              .having((e) => e.kind, 'kind', CommandFailureKind.rejected)
              .having((e) => e.reason, 'reason', 'unitNotVacant'),
        ),
      );
      expect(dispatcher.hasUnresolvedCommands, isFalse);
    });

    test('permission denial is not reported as a connection problem', () async {
      final gateway = _RecordingGateway(
        responder: (_, _) => Future<CommandOutcome>.error(
          const CommandException(
            kind: CommandFailureKind.permissionDenied,
            code: 'PERMISSION_DENIED',
          ),
        ),
      );
      final dispatcher = dispatcherFor(gateway);

      await expectLater(
        dispatcher.submit(_command()),
        throwsA(
          isA<CommandException>().having(
            (e) => e.kind,
            'kind',
            CommandFailureKind.permissionDenied,
          ),
        ),
      );
      expect(dispatcher.hasUnresolvedCommands, isFalse);
    });
  });

  group('connection lost during submission', () {
    test('is uncertain, not failed', () async {
      final gateway = _RecordingGateway(
        responder: (_, _) => Future<CommandOutcome>.error(
          const CommandException.connection(code: 'unavailable'),
        ),
      );
      final dispatcher = dispatcherFor(gateway);

      await expectLater(
        dispatcher.submit(_command()),
        throwsA(
          isA<CommandException>()
              .having((e) => e.kind, 'kind', CommandFailureKind.uncertain)
              .having((e) => e.reason, 'reason', 'submissionInterrupted'),
        ),
      );
      expect(dispatcher.unresolvedCommandIds, contains('cmd-1'));
    });

    test('a plain resubmit is refused until reconciled', () async {
      final gateway = _RecordingGateway(
        responder: (_, _) =>
            Future<CommandOutcome>.error(const CommandException.connection()),
      );
      final dispatcher = dispatcherFor(gateway);
      await expectLater(dispatcher.submit(_command()), throwsA(anything));

      await expectLater(
        dispatcher.submit(_command()),
        throwsA(
          isA<CommandException>()
              .having((e) => e.kind, 'kind', CommandFailureKind.uncertain)
              .having((e) => e.reason, 'reason', 'awaitingReconciliation'),
        ),
      );
      // The refused attempt never reached the wire, so the user's work cannot
      // have been duplicated.
      expect(gateway.sent, hasLength(1));
    });

    test(
      'reconciliation reuses the command id and reports the original outcome',
      () async {
        final gateway = _RecordingGateway(
          responder: (_, attempt) => attempt == 1
              ? Future<CommandOutcome>.error(
                  const CommandException.connection(),
                )
              : Future<CommandOutcome>.value(
                  CommandOutcome(
                    committedAt: DateTime.utc(2026, 7, 29),
                    wasAlreadyApplied: true,
                  ),
                ),
        );
        final dispatcher = dispatcherFor(gateway);
        await expectLater(dispatcher.submit(_command()), throwsA(anything));

        final outcome = await dispatcher.reconcile('cmd-1');

        // The first attempt did apply. Server idempotency is what told us so.
        expect(outcome.wasAlreadyApplied, isTrue);
        expect(gateway.sent.map((c) => c.commandId), ['cmd-1', 'cmd-1']);
        expect(dispatcher.hasUnresolvedCommands, isFalse);
      },
    );

    test('a failed reconciliation stays unresolved', () async {
      final gateway = _RecordingGateway(
        responder: (_, _) =>
            Future<CommandOutcome>.error(const CommandException.connection()),
      );
      final dispatcher = dispatcherFor(gateway);
      await expectLater(dispatcher.submit(_command()), throwsA(anything));

      await expectLater(
        dispatcher.reconcile('cmd-1'),
        throwsA(
          isA<CommandException>().having(
            (e) => e.reason,
            'reason',
            'reconciliationFailed',
          ),
        ),
      );
      expect(dispatcher.unresolvedCommandIds, contains('cmd-1'));
    });
  });

  group('session teardown', () {
    test(
      'reset drops unresolved commands so they cannot follow a switch',
      () async {
        final gateway = _RecordingGateway(
          responder: (_, _) =>
              Future<CommandOutcome>.error(const CommandException.connection()),
        );
        final dispatcher = dispatcherFor(gateway);
        await expectLater(dispatcher.submit(_command()), throwsA(anything));
        expect(dispatcher.hasUnresolvedCommands, isTrue);

        dispatcher.reset();

        expect(dispatcher.hasUnresolvedCommands, isFalse);
      },
    );
  });
}
