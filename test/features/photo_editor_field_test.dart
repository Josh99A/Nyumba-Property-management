import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/theme/nyumba_theme.dart';
import 'package:nyumba_property_management/core/localization/generated/app_localizations.dart';
import 'package:nyumba_property_management/core/localization/luganda_localizations.dart';
import 'package:nyumba_property_management/core/presentation/image_picking.dart';
import 'package:nyumba_property_management/core/presentation/photo_editor_field.dart';

/// A 1x1 transparent PNG, small enough to inline and real enough to decode.
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

String _dataUri(Uint8List bytes) =>
    'data:image/png;base64,${base64Encode(bytes)}';

PickedImage _picked(String name) =>
    PickedImage(name: name, mimeType: 'image/png', bytes: _pngBytes);

void main() {
  group('EditablePhotoSet', () {
    test('keeps saved photos ahead of newly picked ones', () {
      final set = EditablePhotoSet(
        existing: [_dataUri(_pngBytes), 'https://example.test/a.png'],
        picked: [_picked('new.png')],
      );

      expect(set.length, 3);
      // The first photo is the primary image, so the order the record already
      // had must survive an edit that only appends.
      expect(set.toImageUrls().take(2), [
        _dataUri(_pngBytes),
        'https://example.test/a.png',
      ]);
      expect(set.toImageUrls().last, _picked('new.png').dataUri);
    });

    test('copies its inputs so the caller cannot mutate the record', () {
      final original = <String>[_dataUri(_pngBytes)];
      final set = EditablePhotoSet(existing: original);

      set.existing.clear();

      expect(
        original,
        hasLength(1),
        reason: 'clearing the editable set must not touch the source list',
      );
    });

    test('an empty set reports itself empty', () {
      final set = EditablePhotoSet();
      expect(set.isEmpty, isTrue);
      expect(set.isNotEmpty, isFalse);
      expect(set.toImageUrls(), isEmpty);
    });
  });

  group('PhotoEditorField', () {
    testWidgets('renders saved photos as removable chips', (tester) async {
      final set = EditablePhotoSet(
        existing: [_dataUri(_pngBytes), _dataUri(_pngBytes)],
        picked: [_picked('kitchen.png')],
      );
      await _pump(tester, photos: set, limit: 5);

      // Saved photos have no filename to show, so they are numbered.
      expect(find.text('Photo 1'), findsOneWidget);
      expect(find.text('Photo 2'), findsOneWidget);
      expect(find.text('kitchen.png'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(InputChip, 'Photo 1'),
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      await tester.pumpAndSettle();

      expect(set.existing, hasLength(1));
      expect(set.picked, hasLength(1));
    });

    testWidgets('a photo that will not decode stays removable', (tester) async {
      // An https URL or a corrupt data URI must not silently vanish from the
      // editor — that would strand it on the record with no way to drop it.
      final set = EditablePhotoSet(existing: ['https://example.test/a.png']);
      await _pump(tester, photos: set, limit: 5);

      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(set.existing, isEmpty);
    });

    testWidgets('the add button is disabled once the limit is reached', (
      tester,
    ) async {
      await _pump(
        tester,
        photos: EditablePhotoSet(existing: [_dataUri(_pngBytes)]),
        limit: 1,
      );

      expect(find.text('Add more (1/1)'), findsOneWidget);
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Add more (1/1)'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('an empty set invites a first photo', (tester) async {
      await _pump(tester, photos: EditablePhotoSet(), limit: 5);
      expect(find.text('Choose photos'), findsOneWidget);
    });
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required EditablePhotoSet photos,
  required int limit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: NyumbaTheme.light,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        ...LugandaLocalizations.delegates,
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => PhotoEditorField(
            label: 'Photos',
            photos: photos,
            limit: limit,
            // The chooser is never opened in these tests; removal and the
            // limit are what this widget owns.
            pick: ({required int remainingSlots}) async =>
                const ImagePickOutcome(cancelled: true),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
