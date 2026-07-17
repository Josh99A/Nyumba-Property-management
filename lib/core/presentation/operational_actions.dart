import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';

Future<void> showNyumbaInfoDialog(
  BuildContext context, {
  required String title,
  required String message,
  IconData icon = Icons.info_outline_rounded,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(icon),
      title: Text(title),
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

Future<bool> exportTextFile({
  required String fileName,
  required String contents,
  String extension = 'csv',
}) async {
  final result = await FilePicker.platform.saveFile(
    dialogTitle: 'Save $fileName',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: [extension],
    bytes: Uint8List.fromList(utf8.encode(contents)),
  );
  return result != null;
}

String csvCell(Object? value) =>
    '"${(value ?? '').toString().replaceAll('"', '""')}"';
