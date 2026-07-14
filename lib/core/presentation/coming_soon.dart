import 'package:flutter/material.dart';

/// Wraps a deliberately disabled control whose feature is not implemented
/// yet. Pass the child with a null handler so it renders in the disabled
/// style; this adds the explanatory tooltip. Grep for [ComingSoon] to find
/// every feature waiting on implementation.
class ComingSoon extends StatelessWidget {
  const ComingSoon({required this.child, super.key, this.message});

  final Widget child;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Tooltip(message: message ?? 'Coming soon', child: child);
  }
}
