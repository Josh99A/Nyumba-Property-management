import 'package:flutter/material.dart';

import 'nyumba_colors.dart';

abstract final class NyumbaTheme {
  static ThemeData get light =>
      _build(palette: NyumbaPalette.light, brightness: Brightness.light);

  static ThemeData get dark =>
      _build(palette: NyumbaPalette.dark, brightness: Brightness.dark);

  static ThemeData _build({
    required NyumbaPalette palette,
    required Brightness brightness,
  }) {
    final isLight = brightness == Brightness.light;
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: palette.midnightNavy,
      onPrimary: isLight ? Colors.white : palette.navyDark,
      primaryContainer: palette.navyTint,
      onPrimaryContainer: isLight ? palette.navyDark : palette.midnightNavy,
      secondary: isLight ? palette.sageGreen : palette.sageDark,
      onSecondary: isLight ? Colors.white : const Color(0xFF12291A),
      secondaryContainer: palette.sageTint,
      onSecondaryContainer: palette.sageDark,
      tertiary: palette.terracottaGold,
      onTertiary: isLight ? Colors.white : const Color(0xFF2E2415),
      tertiaryContainer: palette.goldTint,
      onTertiaryContainer: palette.terracottaDark,
      error: palette.danger,
      onError: isLight ? Colors.white : const Color(0xFF321B14),
      errorContainer: palette.dangerTint,
      onErrorContainer: palette.danger,
      surface: palette.surface,
      onSurface: palette.ink,
      onSurfaceVariant: palette.mutedInk,
      outline: palette.outline,
      outlineVariant: palette.divider,
      shadow: isLight ? const Color(0x1A123A6F) : const Color(0x66000000),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.softIvory,
      canvasColor: palette.softIvory,
      visualDensity: VisualDensity.standard,
    );

    final headingColor = isLight ? palette.midnightNavy : palette.ink;
    final textTheme = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        color: headingColor,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.1,
        height: 1.1,
      ),
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        color: headingColor,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.7,
        height: 1.18,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        color: headingColor,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.45,
        height: 1.2,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        color: headingColor,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        color: headingColor,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        color: palette.ink,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        color: palette.ink,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        color: palette.ink,
        height: 1.45,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        color: palette.ink,
        height: 1.45,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        color: palette.mutedInk,
        height: 1.4,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      labelMedium: base.textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    );

    const radius = BorderRadius.all(Radius.circular(12));
    final outline = BorderSide(color: palette.outline);
    final snackBackground = isLight
        ? palette.navyDark
        : const Color(0xFF2A3B55);

    return base.copyWith(
      textTheme: textTheme,
      extensions: [palette],
      dividerColor: palette.divider,
      dividerTheme: DividerThemeData(
        color: palette.divider,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: palette.softIvory,
        foregroundColor: palette.ink,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: radius, side: outline),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        hintStyle: textTheme.bodyMedium?.copyWith(color: palette.mutedInk),
        labelStyle: textTheme.bodyMedium,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: const OutlineInputBorder(borderRadius: radius),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: outline,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: palette.midnightNavy, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: palette.danger),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: radius),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          side: outline,
          shape: const RoundedRectangleBorder(borderRadius: radius),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          textStyle: textTheme.labelLarge,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: palette.surface,
        selectedColor: palette.navyTint,
        disabledColor: palette.surface,
        side: outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      dialogTheme: DialogThemeData(
        elevation: 8,
        backgroundColor: palette.softIvory,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: snackBackground,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: palette.navyTint,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelMedium?.copyWith(
            color: selected
                ? (isLight ? palette.midnightNavy : palette.ink)
                : palette.mutedInk,
            fontSize: 11,
            height: 1.1,
          );
        }),
      ),
      tooltipTheme: TooltipThemeData(
        textStyle: textTheme.bodySmall?.copyWith(color: Colors.white),
        decoration: BoxDecoration(
          color: snackBackground,
          borderRadius: const BorderRadius.all(Radius.circular(6)),
        ),
      ),
    );
  }
}
