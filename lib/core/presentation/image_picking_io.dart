import 'package:file_picker/file_picker.dart';

import 'picked_file.dart';

/// Opens the host platform's file chooser through file_picker.
///
/// Returns null when the landlord dismissed the chooser without picking
/// anything. file_picker's native backends report that faithfully, so unlike
/// the web backend they need no help from us.
Future<List<PickedFile>?> pickImageFiles({
  required List<String> extensions,
  required bool allowMultiple,
}) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: extensions,
    allowMultiple: allowMultiple,
    withData: true,
  );
  if (result == null) return null;
  return [
    for (final file in result.files)
      PickedFile(
        name: file.name,
        bytes: file.bytes,
        readError: file.bytes == null
            ? 'its contents could not be read from this device'
            : null,
      ),
  ];
}
