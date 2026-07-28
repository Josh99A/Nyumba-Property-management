import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/bootstrap/app_dependencies.dart';
import 'package:nyumba_property_management/app/localization/locale_controller.dart';
import 'package:nyumba_property_management/app/theme/nyumba_colors.dart';
import 'package:nyumba_property_management/app/theme/nyumba_theme.dart';
import 'package:nyumba_property_management/core/localization/app_language.dart';
import 'package:nyumba_property_management/core/localization/generated/app_localizations.dart';
import 'package:nyumba_property_management/core/localization/luganda_localizations.dart';
import 'package:nyumba_property_management/core/presentation/cloud_status_badge.dart';
import 'package:nyumba_property_management/features/marketplace/presentation/public/marketplace_top_bar.dart';

/// The public bar is navy in both themes, so the light theme is the one that
/// catches tokens the hero surface forgot to override: they resolve to ink on
/// near-white there, which is invisible on the band.
void main() {
  Future<void> pumpTopBar(WidgetTester tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 900);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localePreferenceProvider.overrideWith(_EnglishLocaleController.new),
          cloudStatusProvider.overrideWith(
            (ref) => Stream.value(CloudStatus.live),
          ),
        ],
        child: MaterialApp(
          theme: NyumbaTheme.light,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: _delegates,
          home: Scaffold(
            appBar: MarketplaceTopBar(
              signedIn: false,
              accountLabel: 'Sign in',
              onAccount: () {},
              onBrowseHomes: () {},
              onForLandlords: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('light theme keeps the top bar action icons on the navy band', (
    tester,
  ) async {
    await pumpTopBar(tester);

    // `AppBar` paints its actions from the app bar theme, not the ambient icon
    // theme, so this stays dark ink over navy unless the hero surface says
    // otherwise.
    final iconTheme = IconTheme.of(
      tester.element(find.byIcon(Icons.translate_rounded)),
    );
    expect(iconTheme.color, Colors.white);
  });

  testWidgets('the selected-language tick follows the menu, not the band', (
    tester,
  ) async {
    await pumpTopBar(tester);

    await tester.tap(find.byIcon(Icons.translate_rounded));
    await tester.pumpAndSettle();

    // The menu inherits the theme of the button it hangs off — white icons, for
    // the navy band — but it lands on its own light surface, where a white tick
    // is invisible. Only the selected language draws one, so this is unique.
    final tick = find.byIcon(Icons.check_rounded);
    expect(tick, findsOneWidget);
    final scheme = Theme.of(tester.element(tick)).colorScheme;
    expect(tester.widget<Icon>(tick).color, scheme.onSurface);
    expect(_contrast(scheme.onSurface, scheme.surface), greaterThan(4.5));
  });

  testWidgets('light theme keeps the cloud badge readable on the navy band', (
    tester,
  ) async {
    await pumpTopBar(tester);

    final palette = tester.element(find.byType(CloudStatusBadge)).nyumba;
    // The badge fills come from the palette; on the band they sit over navy,
    // so the contrast that matters is against the composited fill.
    final fill = Color.alphaBlend(palette.sageTint, NyumbaColors.navyDark);
    expect(_contrast(palette.sageDark, fill), greaterThan(4.5));
    expect(
      _contrast(palette.midnightNavy, Color.alphaBlend(palette.navyTint, fill)),
      greaterThan(4.5),
    );
  });
}

double _contrast(Color foreground, Color background) {
  final lighter = math.max(
    foreground.computeLuminance(),
    background.computeLuminance(),
  );
  final darker = math.min(
    foreground.computeLuminance(),
    background.computeLuminance(),
  );
  return (lighter + 0.05) / (darker + 0.05);
}

const _delegates = <LocalizationsDelegate<dynamic>>[
  ...LugandaLocalizations.delegates,
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

final class _EnglishLocaleController extends LocalePreferenceController {
  @override
  AppLanguage build() => AppLanguage.english;

  @override
  Future<void> select(AppLanguage language) async {
    state = language;
  }
}
