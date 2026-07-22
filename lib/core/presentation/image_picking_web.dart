import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'picked_file.dart';

/// How long after the page regains focus we look to see whether the chooser
/// closed empty-handed. Long enough for the browser to populate `input.files`
/// and fire `change`, short enough that a real cancel is not left hanging.
const Duration _cancelProbeDelay = Duration(milliseconds: 1200);

/// Drives the browser's file chooser directly instead of going through
/// file_picker's web backend.
///
/// file_picker treats the page regaining focus as a cancelled pick: it arms a
/// one-second timer on `window`'s `focus` event and, when that fires, completes
/// the pick with null *and* latches a flag that makes it discard the real
/// `change` event when it finally arrives. In a Flutter web app the canvas
/// takes focus back as soon as the chooser opens, so a pick that takes longer
/// than a second — which is every pick a human makes — came back as "the
/// landlord cancelled": no photo, and no error either, because cancelling is
/// not a failure. That is the whole of the "I added a photo and nothing
/// happened" bug on web, and the flag is not reachable through
/// `FilePicker.platform.pickFiles` in file_picker 10, so owning the input
/// element here is the fix rather than a workaround.
///
/// Cancellation is decided by things the browser actually tells us: the
/// `cancel` event, or — for browsers that do not fire it — a focus probe that
/// only gives up once the *document* has focus again (an open chooser is an OS
/// modal, so the document does not) and the input is still empty. The probe
/// re-arms on every focus event, so a slow pick is never mistaken for a
/// cancelled one.
///
/// Returns null when the landlord dismissed the chooser without picking.
Future<List<PickedFile>?> pickImageFiles({
  required List<String> extensions,
  required bool allowMultiple,
}) async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = allowMultiple
    ..accept = extensions.map((extension) => '.$extension').join(',')
    ..style.display = 'none';

  final completer = Completer<web.FileList?>();
  void finish(web.FileList? files) {
    if (!completer.isCompleted) completer.complete(files);
  }

  final onChange = ((web.Event _) {
    final files = input.files;
    // A change event carrying nothing is a cancel on the browsers that report
    // it that way.
    finish(files == null || files.length == 0 ? null : files);
  }).toJS;

  final onCancel = ((web.Event _) => finish(null)).toJS;

  final onFocus = ((web.Event _) {
    Timer(_cancelProbeDelay, () {
      if (completer.isCompleted) return;
      // The chooser is an OS-level modal: while it is open the document does
      // not hold focus, so this stays quiet until it has genuinely closed.
      if (!web.document.hasFocus()) return;
      final files = input.files;
      if (files != null && files.length > 0) {
        finish(files);
      } else {
        finish(null);
      }
    });
  }).toJS;

  input.addEventListener('change', onChange);
  input.addEventListener('cancel', onCancel);
  web.window.addEventListener('focus', onFocus);

  // The input stays in the document for the lifetime of the pick. file_picker
  // detaches it immediately after clicking, which is another way the change
  // event can go missing.
  web.document.body!.appendChild(input);

  try {
    input.click();
    final files = await completer.future;
    return files == null ? null : await _read(files);
  } finally {
    input
      ..removeEventListener('change', onChange)
      ..removeEventListener('cancel', onCancel)
      ..remove();
    web.window.removeEventListener('focus', onFocus);
  }
}

Future<List<PickedFile>> _read(web.FileList files) async {
  final picked = <PickedFile>[];
  for (var index = 0; index < files.length; index++) {
    final file = files.item(index);
    if (file == null) continue;
    try {
      final buffer = await file.arrayBuffer().toDart;
      picked.add(
        PickedFile(name: file.name, bytes: buffer.toDart.asUint8List()),
      );
    } on Object catch (error) {
      // Reading can fail on its own — a file removed from a USB stick between
      // choosing and reading, or one the browser refuses to open. Carry the
      // reason so the landlord learns which photo dropped out and why.
      picked.add(
        PickedFile(
          name: file.name,
          readError: 'the browser could not read it ($error)',
        ),
      );
    }
  }
  return picked;
}
