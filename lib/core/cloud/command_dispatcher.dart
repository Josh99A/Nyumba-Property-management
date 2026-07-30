// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import '../domain/clock.dart';
import 'cloud_command.dart';
import 'connection_status.dart';

/// The single path every protected mutation takes.
///
/// It enforces the three write rules that the old durable outbox violated by
/// construction:
///
/// 1. **Nothing is stored for later.** A command that cannot be sent now fails
///    now, visibly, and the user decides what to do.
/// 2. **A user's action is submitted once.** A second tap while the first is in
///    flight joins the first request rather than issuing a second.
/// 3. **An unknown outcome is not a failure.** If the connection drops after
///    submission the command may well have applied, so it is held as
///    *unresolved* and the only way forward is reconciliation against the
///    server — never a blind resend.
final class CommandDispatcher {
  CommandDispatcher({
    required CloudCommandGateway gateway,
    required ConnectionStatus connection,
    Clock clock = const SystemClock(),
  }) : _gateway = gateway,
       _connection = connection,
       _clock = clock;

  final CloudCommandGateway _gateway;
  final ConnectionStatus _connection;
  final Clock _clock;

  /// Requests currently awaiting a server answer, keyed by command id.
  final Map<String, Future<CommandOutcome>> _inFlight =
      <String, Future<CommandOutcome>>{};

  /// Commands that were submitted but whose outcome never came back. These are
  /// the dangerous ones: the server may hold them as applied. They are kept so
  /// a retry can reuse the original command id and let server idempotency
  /// resolve the question.
  final Map<String, CloudCommand> _unresolved = <String, CloudCommand>{};

  /// Whether [commandId] is awaiting a server answer right now.
  bool isInFlight(String commandId) => _inFlight.containsKey(commandId);

  /// Whether any submitted command has an unknown outcome. A UI offering a
  /// fresh attempt at the same intent must resolve this first.
  bool get hasUnresolvedCommands => _unresolved.isNotEmpty;

  /// Command ids whose outcome is unknown.
  Iterable<String> get unresolvedCommandIds => _unresolved.keys;

  /// Submits [command] and waits for the server.
  ///
  /// Throws [CommandException] and never returns a locally-fabricated success.
  /// A returned [CommandOutcome] means the server acknowledged the write.
  Future<CommandOutcome> submit(CloudCommand command) {
    // Rule 2. Joining the existing future rather than rejecting the caller
    // makes a double-tap harmless without the caller having to track state:
    // both awaits settle on the one real answer.
    final active = _inFlight[command.commandId];
    if (active != null) return active;

    // Rule 3, first half. A command already submitted and unaccounted for must
    // not be issued again as if it were new. `reconcile` is the way through.
    if (_unresolved.containsKey(command.commandId)) {
      return Future<CommandOutcome>.error(
        CommandException(
          kind: CommandFailureKind.uncertain,
          code: 'COMMAND_OUTCOME_UNKNOWN',
          details: const <String, Object?>{'reason': 'awaitingReconciliation'},
        ),
      );
    }

    final run = _send(command).whenComplete(() {
      _inFlight.remove(command.commandId);
    });
    _inFlight[command.commandId] = run;
    return run;
  }

  /// Re-asks the server about a command whose outcome was lost.
  ///
  /// This resends the *same* command id on purpose. The backend persists
  /// command ids and answers duplicates with the original result, so this is a
  /// question ("did you apply this?") rather than a second write. An outcome
  /// with `wasAlreadyApplied` means the first attempt did land, and the caller
  /// must report success rather than repeating the user's work.
  Future<CommandOutcome> reconcile(String commandId) {
    final pending = _unresolved[commandId];
    if (pending == null) {
      return Future<CommandOutcome>.error(
        CommandException(
          kind: CommandFailureKind.rejected,
          code: 'NO_SUCH_UNRESOLVED_COMMAND',
        ),
      );
    }
    final active = _inFlight[commandId];
    if (active != null) return active;

    final run = _send(pending, reconciling: true).whenComplete(() {
      _inFlight.remove(commandId);
    });
    _inFlight[commandId] = run;
    return run;
  }

  /// Abandons tracking of an unresolved command.
  ///
  /// Only for a caller that has confirmed the true outcome by other means, such
  /// as observing the aggregate arrive on a live listener.
  void forget(String commandId) => _unresolved.remove(commandId);

  /// Drops all in-memory command tracking. Called on sign-out and account
  /// switch so one account's unresolved work cannot follow another's session.
  void reset() {
    _inFlight.clear();
    _unresolved.clear();
  }

  Future<CommandOutcome> _send(
    CloudCommand command, {
    bool reconciling = false,
  }) async {
    // Rule 1. Checked before dispatch so that "offline" is a clean, certain
    // non-event: nothing was sent, so nothing can have applied, and the user
    // can be told so without hedging.
    if (!await _connection.isOnline) {
      throw const CommandException.connection(code: 'OFFLINE');
    }

    try {
      final outcome = await _gateway.send(command);
      _unresolved.remove(command.commandId);
      return outcome;
    } on CommandException catch (error) {
      switch (error.kind) {
        case CommandFailureKind.rejected:
        case CommandFailureKind.permissionDenied:
          // The server answered. Whatever it decided, it decided definitively,
          // so there is nothing left hanging.
          _unresolved.remove(command.commandId);
        case CommandFailureKind.connection:
        case CommandFailureKind.uncertain:
          // We asked and did not hear back. Past this point the honest answer
          // is "unknown", and it stays unknown until the server tells us
          // otherwise. Recording it here is what stops the next attempt from
          // silently duplicating the user's work.
          _unresolved[command.commandId] = command;
          throw CommandException(
            kind: CommandFailureKind.uncertain,
            code: error.code,
            details: <String, Object?>{
              ...?error.details,
              'reason': reconciling
                  ? 'reconciliationFailed'
                  : 'submissionInterrupted',
              'issuedAt': command.issuedAt.toUtc().toIso8601String(),
              'observedAt': _clock.now().toUtc().toIso8601String(),
            },
            cause: error.cause,
          );
      }
      rethrow;
    }
  }
}
