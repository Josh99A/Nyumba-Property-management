import 'package:flutter/material.dart';

import 'responsive.dart';

class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.title,
    super.key,
    this.description,
    this.primaryAction,
    this.secondaryAction,
  });

  final String title;
  final String? description;
  final Widget? primaryAction;
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: context.isCompact
              ? Theme.of(context).textTheme.headlineSmall
              : Theme.of(context).textTheme.headlineMedium,
        ),
        if (description != null) ...[
          const SizedBox(height: 6),
          Text(description!, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    );

    final actions = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [?secondaryAction, ?primaryAction],
    );

    if (context.isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          text,
          if (primaryAction != null || secondaryAction != null) ...[
            const SizedBox(height: 18),
            Align(alignment: Alignment.centerLeft, child: actions),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: text),
        if (primaryAction != null || secondaryAction != null) ...[
          const SizedBox(width: 24),
          actions,
        ],
      ],
    );
  }
}
