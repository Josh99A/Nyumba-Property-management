import 'package:flutter/material.dart' as material;

import 'nyumba_localizations.dart';

/// Drop-in localized counterpart for Material's [material.Text].
///
/// Existing screens can keep const English source copy while translations are
/// resolved at build time from the ARB catalog. New code should prefer typed
/// generated localization getters when it needs plural/select semantics.
class Text extends material.StatelessWidget {
  const Text(
    String this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.semanticsIdentifier,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : textSpan = null;

  const Text.rich(
    material.InlineSpan this.textSpan, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.semanticsIdentifier,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : data = null;

  final String? data;
  final material.InlineSpan? textSpan;
  final material.TextStyle? style;
  final material.StrutStyle? strutStyle;
  final material.TextAlign? textAlign;
  final material.TextDirection? textDirection;
  final material.Locale? locale;
  final bool? softWrap;
  final material.TextOverflow? overflow;
  final material.TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final String? semanticsIdentifier;
  final material.TextWidthBasis? textWidthBasis;
  final material.TextHeightBehavior? textHeightBehavior;
  final material.Color? selectionColor;

  @override
  material.Widget build(material.BuildContext context) {
    final localizations = NyumbaLocalizations.maybeOf(context);
    final localizedSemantics = semanticsLabel == null
        ? null
        : localizations?.text(semanticsLabel!) ?? semanticsLabel;
    if (data != null) {
      return material.Text(
        localizations?.text(data!) ?? data!,
        style: style,
        strutStyle: strutStyle,
        textAlign: textAlign,
        textDirection: textDirection,
        locale: locale,
        softWrap: softWrap,
        overflow: overflow,
        textScaler: textScaler,
        maxLines: maxLines,
        semanticsLabel: localizedSemantics,
        semanticsIdentifier: semanticsIdentifier,
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        selectionColor: selectionColor,
      );
    }
    return material.Text.rich(
      textSpan!,
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: localizedSemantics,
      semanticsIdentifier: semanticsIdentifier,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}

/// Localizes plain Material tooltip messages at build time.
class Tooltip extends material.StatelessWidget {
  const Tooltip({
    super.key,
    this.message,
    this.richMessage,
    this.constraints,
    this.padding,
    this.margin,
    this.verticalOffset,
    this.preferBelow,
    this.excludeFromSemantics,
    this.decoration,
    this.textStyle,
    this.textAlign,
    this.waitDuration,
    this.showDuration,
    this.exitDuration,
    this.enableTapToDismiss = true,
    this.triggerMode,
    this.enableFeedback,
    this.onTriggered,
    this.mouseCursor,
    this.ignorePointer,
    this.child,
  }) : assert((message == null) != (richMessage == null));

  final String? message;
  final material.InlineSpan? richMessage;
  final material.BoxConstraints? constraints;
  final material.EdgeInsetsGeometry? padding;
  final material.EdgeInsetsGeometry? margin;
  final double? verticalOffset;
  final bool? preferBelow;
  final bool? excludeFromSemantics;
  final material.Decoration? decoration;
  final material.TextStyle? textStyle;
  final material.TextAlign? textAlign;
  final Duration? waitDuration;
  final Duration? showDuration;
  final Duration? exitDuration;
  final bool enableTapToDismiss;
  final material.TooltipTriggerMode? triggerMode;
  final bool? enableFeedback;
  final material.TooltipTriggeredCallback? onTriggered;
  final material.MouseCursor? mouseCursor;
  final bool? ignorePointer;
  final material.Widget? child;

  @override
  material.Widget build(material.BuildContext context) {
    final localizations = NyumbaLocalizations.maybeOf(context);
    return material.Tooltip(
      message: message == null
          ? null
          : localizations?.text(message!) ?? message,
      richMessage: richMessage,
      constraints: constraints,
      padding: padding,
      margin: margin,
      verticalOffset: verticalOffset,
      preferBelow: preferBelow,
      excludeFromSemantics: excludeFromSemantics,
      decoration: decoration,
      textStyle: textStyle,
      textAlign: textAlign,
      waitDuration: waitDuration,
      showDuration: showDuration,
      exitDuration: exitDuration,
      enableTapToDismiss: enableTapToDismiss,
      triggerMode: triggerMode,
      enableFeedback: enableFeedback,
      onTriggered: onTriggered,
      mouseCursor: mouseCursor,
      ignorePointer: ignorePointer,
      child: child,
    );
  }
}
