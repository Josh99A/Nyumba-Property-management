import 'picked_file.dart';

Future<List<PickedFile>?> pickImageFiles({
  required List<String> extensions,
  required bool allowMultiple,
}) => throw UnsupportedError(
  'Choosing photos is not supported on this platform.',
);
