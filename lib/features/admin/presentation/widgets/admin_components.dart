import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/nyumba_colors.dart';
import '../../../../core/presentation/page_header.dart';
import '../../../../core/presentation/responsive.dart';
import '../../../../core/presentation/surface.dart';

final NumberFormat _adminCurrency = NumberFormat.currency(
  locale: 'en_KE',
  symbol: 'KES ',
  decimalDigits: 0,
);

String formatAdminKes(num amount) => _adminCurrency.format(amount);

void showAdminMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class AdminPage extends StatelessWidget {
  const AdminPage({
    required this.title,
    required this.children,
    super.key,
    this.description,
    this.primaryAction,
    this.secondaryAction,
    this.maxWidth = 1540,
  });

  final String title;
  final String? description;
  final Widget? primaryAction;
  final Widget? secondaryAction;
  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        context.pageGutter,
        26,
        context.pageGutter,
        42,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: title,
                description: description,
                primaryAction: primaryAction,
                secondaryAction: secondaryAction,
              ),
              const SizedBox(height: 22),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class AdminMetricGrid extends StatelessWidget {
  const AdminMetricGrid({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1120
            ? 4
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        const spacing = 14.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class AdminMetricCard extends StatelessWidget {
  const AdminMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
    super.key,
    this.caption,
    this.trend,
  });

  final String label;
  final String value;
  final String? caption;
  final String? trend;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return NyumbaSurface(
      padding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 104),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: tone, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (trend != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: NyumbaColors.sageTint,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      trend!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: NyumbaColors.sageDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (caption != null) ...[
              const SizedBox(height: 5),
              Text(caption!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class AdminPanel extends StatelessWidget {
  const AdminPanel({
    required this.title,
    required this.child,
    super.key,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(20),
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return NyumbaSurface(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NyumbaSectionHeader(
            title: title,
            subtitle: subtitle,
            trailing: trailing,
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class AdminAvatar extends StatelessWidget {
  const AdminAvatar({
    required this.name,
    super.key,
    this.color = NyumbaColors.midnightNavy,
    this.radius = 18,
  });

  final String name;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = parts
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0])
        .join()
        .toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: .12),
      foregroundColor: color,
      child: Text(
        initials,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class AdminBarChart extends StatelessWidget {
  const AdminBarChart({
    required this.values,
    required this.labels,
    super.key,
    this.color = NyumbaColors.midnightNavy,
    this.secondaryValues,
    this.secondaryColor = NyumbaColors.terracottaGold,
    this.height = 190,
  }) : assert(values.length == labels.length);

  final List<double> values;
  final List<double>? secondaryValues;
  final List<String> labels;
  final Color color;
  final Color secondaryColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final allValues = [...values, ...?secondaryValues];
    final maximum = allValues.fold<double>(1, (max, value) {
      return value > max ? value : max;
    });
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var index = 0; index < values.length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            Expanded(
              child: _AdminBarGroup(
                value: values[index],
                secondaryValue: secondaryValues?[index],
                maximum: maximum,
                label: labels[index],
                color: color,
                secondaryColor: secondaryColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AdminBarGroup extends StatelessWidget {
  const _AdminBarGroup({
    required this.value,
    required this.maximum,
    required this.label,
    required this.color,
    required this.secondaryColor,
    this.secondaryValue,
  });

  final double value;
  final double? secondaryValue;
  final double maximum;
  final String label;
  final Color color;
  final Color secondaryColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const labelHeight = 25.0;
        final chartHeight = constraints.maxHeight - labelHeight;
        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SizedBox(
              height: chartHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Tooltip(
                      message: value.toStringAsFixed(0),
                      child: Container(
                        width: 22,
                        height: (chartHeight * value / maximum).clamp(
                          5,
                          chartHeight,
                        ),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(5),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (secondaryValue != null) ...[
                    const SizedBox(width: 3),
                    Flexible(
                      child: Tooltip(
                        message: secondaryValue!.toStringAsFixed(0),
                        child: Container(
                          width: 22,
                          height: (chartHeight * secondaryValue! / maximum)
                              .clamp(5, chartHeight),
                          decoration: BoxDecoration(
                            color: secondaryColor,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        );
      },
    );
  }
}

class AdminProgressRow extends StatelessWidget {
  const AdminProgressRow({
    required this.label,
    required this.value,
    required this.trailing,
    super.key,
    this.color = NyumbaColors.midnightNavy,
  });

  final String label;
  final double value;
  final String trailing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.labelLarge),
            ),
            Text(trailing, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: value.clamp(0, 1),
            color: color,
            backgroundColor: color.withValues(alpha: .11),
          ),
        ),
      ],
    );
  }
}

class AdminEmptyState extends StatelessWidget {
  const AdminEmptyState({
    required this.title,
    required this.message,
    super.key,
    this.icon = Icons.search_off_rounded,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 44),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: NyumbaColors.navyTint,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: NyumbaColors.midnightNavy),
          ),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}
