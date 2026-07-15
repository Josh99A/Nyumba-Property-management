import 'package:flutter/widgets.dart';

/// Lays summary cards out in equal-width columns, sizing every card in a row to
/// the tallest one.
///
/// A fixed row height is the obvious alternative, but it silently overflows as
/// soon as a label wraps to a second line or the reader turns up the system text
/// scale. Rows here grow with their content instead, and [minRowHeight] only
/// keeps short cards from collapsing.
class MetricGrid extends StatelessWidget {
  const MetricGrid({
    required this.children,
    required this.columnsForWidth,
    super.key,
    this.spacing = 14,
    this.minRowHeight = 0,
  });

  final List<Widget> children;

  /// Resolves the column count for the grid's own width, so callers keep their
  /// existing breakpoints.
  final int Function(double width) columnsForWidth;

  final double spacing;
  final double minRowHeight;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsForWidth(
          constraints.maxWidth,
        ).clamp(1, children.length);
        final rows = <Widget>[];
        for (var start = 0; start < children.length; start += columns) {
          final row = children.sublist(
            start,
            (start + columns).clamp(0, children.length),
          );
          if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
          rows.add(
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: minRowHeight),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var column = 0; column < columns; column++) ...[
                      if (column > 0) SizedBox(width: spacing),
                      // A short last row is padded with empty cells so its
                      // cards keep the width of the rows above.
                      Expanded(
                        child: column < row.length
                            ? row[column]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }
        return Column(mainAxisSize: MainAxisSize.min, children: rows);
      },
    );
  }
}
