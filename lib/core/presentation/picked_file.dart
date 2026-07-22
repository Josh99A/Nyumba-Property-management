import 'dart:typed_data';

/// One file handed back by a platform file chooser, before Nyumba has decided
/// whether it is an image it will accept.
///
/// [bytes] and [readError] are mutually exclusive: a file the platform could
/// not read carries the reason instead of its contents, so the caller can tell
/// the landlord *which* photo failed and why rather than dropping it silently.
final class PickedFile {
  const PickedFile({required this.name, this.bytes, this.readError});

  final String name;
  final Uint8List? bytes;

  /// Why the contents could not be read, in a fragment that completes the
  /// sentence "`<name>` could not be added because …".
  final String? readError;
}
