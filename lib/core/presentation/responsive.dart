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
