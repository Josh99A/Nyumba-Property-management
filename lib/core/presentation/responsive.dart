import 'package:flutter/widgets.dart';

abstract final class NyumbaBreakpoints {
  static const compact = 720.0;
  static const expanded = 1120.0;
  static const wide = 1440.0;
}

enum WindowSizeClass { compact, medium, expanded }

WindowSizeClass windowSizeClassOf(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < NyumbaBreakpoints.compact) return WindowSizeClass.compact;
  if (width < NyumbaBreakpoints.expanded) return WindowSizeClass.medium;
  return WindowSizeClass.expanded;
}

extension ResponsiveContext on BuildContext {
  WindowSizeClass get windowSizeClass => windowSizeClassOf(this);
  bool get isCompact => windowSizeClass == WindowSizeClass.compact;
  bool get isExpanded => windowSizeClass == WindowSizeClass.expanded;

  double get pageGutter => switch (windowSizeClass) {
    WindowSizeClass.compact => 16,
    WindowSizeClass.medium => 24,
    WindowSizeClass.expanded => 30,
  };
}

/// Width of one item in a [columns]-across [Wrap] grid that fills [maxWidth]
/// with [gap] between items.
///
/// Never returns a negative width. A grid whose column count comes from
/// anywhere other than the box it is being laid out in — the window size
/// class, say, or a fixed number — can be handed a [maxWidth] too small to
/// seat that many columns. `(0 - 10) / 2` is `-5`, and a negative width
/// reaches `SizedBox` as a non-normalized `BoxConstraints`, which is a hard
/// assertion rather than a squashed layout. A `LayoutBuilder` gets a zero
/// maxWidth more often than it looks: mid-transition, inside a collapsed
/// parent, or on the first pass of a sheet that has not been measured yet.
double gridItemWidth(
  double maxWidth, {
  required int columns,
  required double gap,
}) {
  if (columns <= 1) return maxWidth < 0 ? 0 : maxWidth;
  final available = maxWidth - gap * (columns - 1);
  return available <= 0 ? 0 : available / columns;
}

class ResponsiveValue<T> {
  const ResponsiveValue({required this.compact, T? medium, T? expanded})
    : medium = medium ?? compact,
      expanded = expanded ?? medium ?? compact;

  final T compact;
  final T medium;
  final T expanded;

  T resolve(BuildContext context) => switch (context.windowSizeClass) {
    WindowSizeClass.compact => compact,
    WindowSizeClass.medium => medium,
    WindowSizeClass.expanded => expanded,
  };
}
