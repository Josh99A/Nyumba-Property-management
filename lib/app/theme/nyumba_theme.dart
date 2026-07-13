import 'package:flutter/material.dart';

import 'nyumba_colors.dart';

abstract final class NyumbaTheme {
  static ThemeData get light {
    const colorScheme = ColorScheme.light(
      primary: NyumbaColors.midnightNavy,
      onPrimary: Colors.white,
      primaryContainer: NyumbaColors.navyTint,
      onPrimaryContainer: NyumbaColors.navyDark,
      secondary: NyumbaColors.sageGreen,
      onSecondary: Colors.white,
      secondaryContainer: NyumbaColors.sageTint,
      onSecondaryContainer: NyumbaColors.sageDark,
      tertiary: NyumbaColors.terracottaGold,
      onTertiary: Colors.white,
      tertiaryContainer: NyumbaColors.goldTint,
      onTertiaryContainer: NyumbaColors.terracottaDark,
      error: NyumbaColors.danger,
      onError: Colors.white,
      errorContainer: NyumbaColors.dangerTint,
      onErrorContainer: NyumbaColors.danger,
      surface: NyumbaColors.surface,
      onSurface: NyumbaColors.ink,
      outline: NyumbaColors.outline,
      outlineVariant: Color(0xFFEDE9E2),
      shadow: Color(0x1A123A6F),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: NyumbaColors.softIvory,
      canvasColor: NyumbaColors.softIvory,
      visualDensity: VisualDensity.standard,
    );

    final textTheme = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        color: NyumbaColors.midnightNavy,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.1,
        height: 1.1,
      ),
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        color: NyumbaColors.midnightNavy,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.7,
        height: 1.18,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        color: NyumbaColors.midnightNavy,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.45,
        height: 1.2,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        color: NyumbaColors.midnightNavy,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        color: NyumbaColors.midnightNavy,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        color: NyumbaColors.ink,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        color: NyumbaColors.ink,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        color: NyumbaColors.ink,
        height: 1.45,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        color: NyumbaColors.ink,
        height: 1.45,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        color: NyumbaColors.mutedInk,
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
    final outline = BorderSide(color: colorScheme.outline);

    return base.copyWith(
      textTheme: textTheme,
      extensions: const [NyumbaSemanticColors.light],
      dividerColor: colorScheme.outlineVariant,
      dividerTheme: const DividerThemeData(
        color: Color(0xFFEDE9E2),
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: NyumbaColors.softIvory,
        foregroundColor: NyumbaColors.ink,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: NyumbaColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: NyumbaColors.outline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NyumbaColors.surface,
        hintStyle: textTheme.bodyMedium?.copyWith(color: NyumbaColors.mutedInk),
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
        focusedBorder: const OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: NyumbaColors.midnightNavy, width: 1.5),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: NyumbaColors.danger),
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
        backgroundColor: NyumbaColors.surface,
        selectedColor: NyumbaColors.navyTint,
        disabledColor: NyumbaColors.surface,
        side: outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      dialogTheme: const DialogThemeData(
        elevation: 8,
        backgroundColor: NyumbaColors.softIvory,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: NyumbaColors.navyDark,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: NyumbaColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: NyumbaColors.navyTint,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelMedium?.copyWith(
            color: selected ? NyumbaColors.midnightNavy : NyumbaColors.mutedInk,
            fontSize: 11,
            height: 1.1,
          );
        }),
      ),
      tooltipTheme: TooltipThemeData(
        textStyle: textTheme.bodySmall?.copyWith(color: Colors.white),
        decoration: const BoxDecoration(
          color: NyumbaColors.navyDark,
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
      ),
    );
  }
}
