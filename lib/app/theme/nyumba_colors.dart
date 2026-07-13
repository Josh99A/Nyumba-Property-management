import 'package:flutter/material.dart';

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

@immutable
class NyumbaSemanticColors extends ThemeExtension<NyumbaSemanticColors> {
  const NyumbaSemanticColors({
    required this.success,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.danger,
    required this.dangerContainer,
    required this.synced,
    required this.pending,
  });

  final Color success;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;
  final Color danger;
  final Color dangerContainer;
  final Color synced;
  final Color pending;

  static const light = NyumbaSemanticColors(
    success: NyumbaColors.sageDark,
    successContainer: NyumbaColors.sageTint,
    warning: NyumbaColors.terracottaDark,
    warningContainer: NyumbaColors.goldTint,
    danger: NyumbaColors.danger,
    dangerContainer: NyumbaColors.dangerTint,
    synced: NyumbaColors.sageDark,
    pending: NyumbaColors.terracottaDark,
  );

  @override
  NyumbaSemanticColors copyWith({
    Color? success,
    Color? successContainer,
    Color? warning,
    Color? warningContainer,
    Color? danger,
    Color? dangerContainer,
    Color? synced,
    Color? pending,
  }) {
    return NyumbaSemanticColors(
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      danger: danger ?? this.danger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      synced: synced ?? this.synced,
      pending: pending ?? this.pending,
    );
  }

  @override
  NyumbaSemanticColors lerp(covariant NyumbaSemanticColors? other, double t) {
    if (other == null) return this;
    return NyumbaSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      synced: Color.lerp(synced, other.synced, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
    );
  }
}
