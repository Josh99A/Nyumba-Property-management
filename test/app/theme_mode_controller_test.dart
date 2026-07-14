import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/theme/nyumba_theme.dart';
import 'package:nyumba_property_management/app/theme/theme_mode_controller.dart';
import 'package:nyumba_property_management/features/profile/domain/user_settings.dart';

void main() {
  testWidgets('appearance selection changes app brightness immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, _) {
            final preference = ref.watch(themePreferenceProvider);
            return MaterialApp(
              theme: NyumbaTheme.light,
              darkTheme: NyumbaTheme.dark,
              themeMode: switch (preference) {
                ThemePreference.light => ThemeMode.light,
                ThemePreference.dark => ThemeMode.dark,
                ThemePreference.system => ThemeMode.system,
              },
              home: Builder(
                builder: (context) => Scaffold(
                  body: Column(
                    children: [
                      Text(Theme.of(context).brightness.name),
                      FilledButton(
                        onPressed: () => ref
                            .read(themePreferenceProvider.notifier)
                            .select(ThemePreference.dark),
                        child: const Text('Use dark mode'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Use dark mode'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('dark'), findsOneWidget);
  });
}
