/// Generates client-owned identifiers.
///
/// The client still names its own aggregates, but for a different reason than
/// it used to. Creation is no longer independent of the network — every write
/// waits for the server. What a client-generated id buys now is idempotency:
/// the id is fixed before the request leaves, so a command whose answer was
/// lost can be re-asked against the same target and recognised as the same
/// work rather than duplicated.
abstract interface class IdGenerator {
  String generate();
}
