import 'package:flutter/material.dart';

/// Brand-fixed constants. Use these only for surfaces that must keep the
/// brand color in both themes (hero panels, brand chips); everything else
/// should read the theme-aware [NyumbaPalette] via `context.nyumba`.
abstract final class NyumbaColors {
  static const midnightNavy = Color(0xFF123A6F);
  static const navyDark = Color(0xFF0B294F);
  static const navyTint = Color(0xFFEAF1F8);
  static const sageGreen = Color(0xFF5F8F6B);
  static const sageDark = Color(0xFF367248);
  static const sageTint = Color(0xFFEAF3EC);
  static const terracottaGold = Color(0xFFC98B2E);
  static const terracottaDark = Color(0xFF9B6315);
  static const goldTint = Color(0xFFFFF3E2);
  static const softIvory = Color(0xFFF7F4ED);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF17253A);
  static const mutedInk = Color(0xFF667085);
  static const outline = Color(0xFFE4E0D8);
  static const danger = Color(0xFFC64B2F);
  static const dangerTint = Color(0xFFFCEEEA);
  static const warning = Color(0xFFE88916);
  static const warningTint = Color(0xFFFFF4E5);
}

/// Theme-aware palette resolved per brightness. Field names mirror
/// [NyumbaColors] so call sites read the same in both themes.
@immutable
class NyumbaPalette extends ThemeExtension<NyumbaPalette> {
  const NyumbaPalette({
    required this.midnightNavy,
    required this.navyDark,
    required this.navyTint,
    required this.navyBorder,
    required this.sageGreen,
    required this.sageDark,
    required this.sageTint,
    required this.sageBorder,
    required this.terracottaGold,
    required this.terracottaDark,
    required this.goldTint,
    required this.goldBorder,
    required this.softIvory,
    required this.surface,
    required this.ink,
    required this.mutedInk,
    required this.outline,
    required this.divider,
    required this.neutralTint,
    required this.danger,
    required this.dangerTint,
    required this.dangerBorder,
    required this.warning,
    required this.warningTint,
  });

  final Color midnightNavy;
  final Color navyDark;
  final Color navyTint;
  final Color navyBorder;
  final Color sageGreen;
  final Color sageDark;
  final Color sageTint;
  final Color sageBorder;
  final Color terracottaGold;
  final Color terracottaDark;
  final Color goldTint;
  final Color goldBorder;
  final Color softIvory;
  final Color surface;
  final Color ink;
  final Color mutedInk;
  final Color outline;
  final Color divider;
  final Color neutralTint;
  final Color danger;
  final Color dangerTint;
  final Color dangerBorder;
  final Color warning;
  final Color warningTint;

  static const light = NyumbaPalette(
    midnightNavy: NyumbaColors.midnightNavy,
    navyDark: NyumbaColors.navyDark,
    navyTint: NyumbaColors.navyTint,
    navyBorder: Color(0xFFC9D9EB),
    sageGreen: NyumbaColors.sageGreen,
    sageDark: NyumbaColors.sageDark,
    sageTint: NyumbaColors.sageTint,
    sageBorder: Color(0xFFCDE4D2),
    terracottaGold: NyumbaColors.terracottaGold,
    terracottaDark: NyumbaColors.terracottaDark,
    goldTint: NyumbaColors.goldTint,
    goldBorder: Color(0xFFF0D5A7),
    softIvory: NyumbaColors.softIvory,
    surface: NyumbaColors.surface,
    ink: NyumbaColors.ink,
    mutedInk: NyumbaColors.mutedInk,
    outline: NyumbaColors.outline,
    divider: Color(0xFFEDE9E2),
    neutralTint: Color(0xFFF4F5F7),
    danger: NyumbaColors.danger,
    dangerTint: NyumbaColors.dangerTint,
    dangerBorder: Color(0xFFF2C2B7),
    warning: NyumbaColors.warning,
    warningTint: NyumbaColors.warningTint,
  );

  static const dark = NyumbaPalette(
    midnightNavy: Color(0xFFA7C2E8),
    navyDark: Color(0xFF0E2140),
    navyTint: Color(0xFF1C2A3E),
    navyBorder: Color(0xFF31486B),
    sageGreen: Color(0xFF7FAF8B),
    sageDark: Color(0xFF8FC49D),
    sageTint: Color(0xFF1B2A20),
    sageBorder: Color(0xFF31543C),
    terracottaGold: Color(0xFFD9A85C),
    terracottaDark: Color(0xFFE0B36A),
    goldTint: Color(0xFF2E2415),
    goldBorder: Color(0xFF57431F),
    softIvory: Color(0xFF0F1620),
    surface: Color(0xFF17212E),
    ink: Color(0xFFE7ECF3),
    mutedInk: Color(0xFF9AA7B8),
    outline: Color(0xFF2B3648),
    divider: Color(0xFF243040),
    neutralTint: Color(0xFF202B3A),
    danger: Color(0xFFE58974),
    dangerTint: Color(0xFF321B14),
    dangerBorder: Color(0xFF5C2F22),
    warning: Color(0xFFEDA84F),
    warningTint: Color(0xFF2E2415),
  );

  @override
  NyumbaPalette copyWith({
    Color? midnightNavy,
    Color? navyDark,
    Color? navyTint,
    Color? navyBorder,
    Color? sageGreen,
    Color? sageDark,
    Color? sageTint,
    Color? sageBorder,
    Color? terracottaGold,
    Color? terracottaDark,
    Color? goldTint,
    Color? goldBorder,
    Color? softIvory,
    Color? surface,
    Color? ink,
    Color? mutedInk,
    Color? outline,
    Color? divider,
    Color? neutralTint,
    Color? danger,
    Color? dangerTint,
    Color? dangerBorder,
    Color? warning,
    Color? warningTint,
  }) {
    return NyumbaPalette(
      midnightNavy: midnightNavy ?? this.midnightNavy,
      navyDark: navyDark ?? this.navyDark,
      navyTint: navyTint ?? this.navyTint,
      navyBorder: navyBorder ?? this.navyBorder,
      sageGreen: sageGreen ?? this.sageGreen,
      sageDark: sageDark ?? this.sageDark,
      sageTint: sageTint ?? this.sageTint,
      sageBorder: sageBorder ?? this.sageBorder,
      terracottaGold: terracottaGold ?? this.terracottaGold,
      terracottaDark: terracottaDark ?? this.terracottaDark,
      goldTint: goldTint ?? this.goldTint,
      goldBorder: goldBorder ?? this.goldBorder,
      softIvory: softIvory ?? this.softIvory,
      surface: surface ?? this.surface,
      ink: ink ?? this.ink,
      mutedInk: mutedInk ?? this.mutedInk,
      outline: outline ?? this.outline,
      divider: divider ?? this.divider,
      neutralTint: neutralTint ?? this.neutralTint,
      danger: danger ?? this.danger,
      dangerTint: dangerTint ?? this.dangerTint,
      dangerBorder: dangerBorder ?? this.dangerBorder,
      warning: warning ?? this.warning,
      warningTint: warningTint ?? this.warningTint,
    );
  }

  @override
  NyumbaPalette lerp(covariant NyumbaPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return NyumbaPalette(
      midnightNavy: mix(midnightNavy, other.midnightNavy),
      navyDark: mix(navyDark, other.navyDark),
      navyTint: mix(navyTint, other.navyTint),
      navyBorder: mix(navyBorder, other.navyBorder),
      sageGreen: mix(sageGreen, other.sageGreen),
      sageDark: mix(sageDark, other.sageDark),
      sageTint: mix(sageTint, other.sageTint),
      sageBorder: mix(sageBorder, other.sageBorder),
      terracottaGold: mix(terracottaGold, other.terracottaGold),
      terracottaDark: mix(terracottaDark, other.terracottaDark),
      goldTint: mix(goldTint, other.goldTint),
      goldBorder: mix(goldBorder, other.goldBorder),
      softIvory: mix(softIvory, other.softIvory),
      surface: mix(surface, other.surface),
      ink: mix(ink, other.ink),
      mutedInk: mix(mutedInk, other.mutedInk),
      outline: mix(outline, other.outline),
      divider: mix(divider, other.divider),
      neutralTint: mix(neutralTint, other.neutralTint),
      danger: mix(danger, other.danger),
      dangerTint: mix(dangerTint, other.dangerTint),
      dangerBorder: mix(dangerBorder, other.dangerBorder),
      warning: mix(warning, other.warning),
      warningTint: mix(warningTint, other.warningTint),
    );
  }
}

extension NyumbaPaletteContext on BuildContext {
  /// The brightness-resolved Nyumba palette for this context.
  NyumbaPalette get nyumba =>
      Theme.of(this).extension<NyumbaPalette>() ?? NyumbaPalette.light;
}
