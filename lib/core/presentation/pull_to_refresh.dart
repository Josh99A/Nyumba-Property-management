import 'package:flutter/material.dart';

import '../../app/theme/nyumba_colors.dart';

/// Nyumba's shared pull-to-refresh affordance.
///
/// The scroll behavior is intentionally always scrollable so the gesture still
/// works for empty states and short pages. The refresh action remains outside
/// this presentation primitive because public feeds and authenticated
/// workspaces refresh different authorized scopes.
class NyumbaRefreshIndicator extends StatelessWidget {
  const NyumbaRefreshIndicator({
    required this.onRefresh,
    required this.child,
    super.key,
  });

  final RefreshCallback onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator.adaptive(
      color: context.nyumba.midnightNavy,
      backgroundColor: context.nyumba.surface,
      displacement: 32,
      onRefresh: onRefresh,
      child: ScrollConfiguration(
        behavior: const _AlwaysScrollableRefreshBehavior(),
        child: child,
      ),
    );
  }
}

extension NyumbaRefreshableWidget on Widget {
  Widget withNyumbaPullToRefresh({required RefreshCallback onRefresh}) {
    return NyumbaRefreshIndicator(onRefresh: onRefresh, child: this);
  }
}

final class _AlwaysScrollableRefreshBehavior extends MaterialScrollBehavior {
  const _AlwaysScrollableRefreshBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      AlwaysScrollableScrollPhysics(parent: super.getScrollPhysics(context));
}
