/// Generates client-owned identifiers so creation never depends on a network
/// round trip.
abstract interface class IdGenerator {
  String generate();
}
