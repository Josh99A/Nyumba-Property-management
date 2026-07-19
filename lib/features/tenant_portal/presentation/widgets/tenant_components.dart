import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/nyumba_colors.dart';
import '../../../../core/presentation/page_header.dart';
import '../../../../core/presentation/responsive.dart';
import '../../../../core/presentation/status_badge.dart';
import '../../../../core/presentation/surface.dart';

final NumberFormat _tenantCurrency = NumberFormat.currency(
  locale: 'en_UG',
  symbol: 'UGX ',
  decimalDigits: 0,
);

String formatTenantUgx(num amount) => _tenantCurrency.format(amount);

void showTenantMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text.localized(message)));
}

class TenantPage extends StatelessWidget {
  const TenantPage({
    required this.title,
    required this.children,
    super.key,
    this.description,
    this.primaryAction,
    this.secondaryAction,
    this.maxWidth = 1320,
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
      padding: EdgeInsetsDirectional.fromSTEB(
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

class TenantMetricGrid extends StatelessWidget {
  const TenantMetricGrid({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 930
            ? children.length.clamp(1, 4)
            : constraints.maxWidth >= 590
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

class TenantMetricCard extends StatelessWidget {
  const TenantMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    super.key,
    this.caption,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return NyumbaSurface(
      padding: const EdgeInsets.all(17),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 102),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 21, color: color),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text.localized(
                    label,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text.localized(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (caption != null) ...[
              const SizedBox(height: 4),
              Text.localized(
                caption!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class TenantPanel extends StatelessWidget {
  const TenantPanel({
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

class TenantBalanceHero extends StatelessWidget {
  const TenantBalanceHero({
    required this.amount,
    required this.dueLabel,
    required this.onPay,
    super.key,
    this.paid = false,
  });

  final int amount;
  final String dueLabel;
  final VoidCallback onPay;
  final bool paid;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        // Brand-fixed navy: the hero keeps white foregrounds in both themes,
        // so the theme-aware palette (light blue in dark mode) cannot be used.
        gradient: const LinearGradient(
          colors: [NyumbaColors.navyDark, NyumbaColors.midnightNavy],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2A123A6F),
            blurRadius: 26,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          const PositionedDirectional(
            end: -34,
            top: -42,
            child: _DecorativeCircle(size: 150),
          ),
          const PositionedDirectional(
            end: 90,
            bottom: -74,
            child: _DecorativeCircle(size: 130),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final summary = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          paid
                              ? Icons.check_circle_outline_rounded
                              : Icons.account_balance_wallet_outlined,
                          color: paid
                              ? NyumbaColors.sageTint
                              : const Color(0xFFFFD99D),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text.localized(
                            paid
                                ? 'Rent is up to date'
                                : 'Current rent balance',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: .82),
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text.localized(
                      formatTenantUgx(amount),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text.localized(
                      paid ? 'Your next invoice will appear here.' : dueLabel,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: .76),
                      ),
                    ),
                  ],
                );
                final action = FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: paid
                        ? NyumbaColors.sageGreen
                        : NyumbaColors.terracottaGold,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: onPay,
                  icon: Icon(
                    paid
                        ? Icons.receipt_long_outlined
                        : Icons.edit_note_rounded,
                  ),
                  // No payment provider is integrated yet, so this must never
                  // promise an in-app checkout: it records a payment made
                  // outside the app for server confirmation.
                  label: Text.localized(
                    paid ? 'View receipt' : 'Record a payment',
                  ),
                );
                if (constraints.maxWidth < 620) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [summary, const SizedBox(height: 22), action],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: summary),
                    const SizedBox(width: 24),
                    action,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DecorativeCircle extends StatelessWidget {
  const _DecorativeCircle({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        shape: BoxShape.circle,
      ),
    );
  }
}

class TenantQuickAction extends StatelessWidget {
  const TenantQuickAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    super.key,
    this.caption,
  });

  final String label;
  final String? caption;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NyumbaSurface(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .11),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.localized(
                  label,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                if (caption != null)
                  Text.localized(
                    caption!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_ios_rounded,
            size: 15,
            color: context.nyumba.mutedInk,
          ),
        ],
      ),
    );
  }
}

class TenantTimelineStep extends StatelessWidget {
  const TenantTimelineStep({
    required this.title,
    required this.detail,
    required this.complete,
    super.key,
    this.last = false,
  });

  final String title;
  final String detail;
  final bool complete;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final color = complete ? context.nyumba.sageDark : context.nyumba.outline;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: complete ? context.nyumba.sageTint : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: complete
                      ? Icon(
                          Icons.check_rounded,
                          size: 13,
                          color: context.nyumba.sageDark,
                        )
                      : null,
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: color,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 17),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.localized(
                    title,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 2),
                  Text.localized(
                    detail,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TenantInfoRow extends StatelessWidget {
  const TenantInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    super.key,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: context.nyumba.navyTint,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 19, color: context.nyumba.midnightNavy),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.localized(
                label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 2),
              Text.localized(
                value,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

class TenantEmptyState extends StatelessWidget {
  const TenantEmptyState({
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 42),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: context.nyumba.sageTint,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: context.nyumba.sageDark),
          ),
          const SizedBox(height: 14),
          Text.localized(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 5),
          Text.localized(
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

BadgeTone tenantToneForStatus(String status) => switch (status) {
  'Paid' || 'Resolved' || 'Completed' || 'Active' => BadgeTone.success,
  'Pending' ||
  'Scheduled' ||
  'Processing' ||
  'In progress' => BadgeTone.warning,
  'Overdue' || 'Cancelled' || 'Urgent' => BadgeTone.danger,
  _ => BadgeTone.info,
};

class TenantStatusBadge extends StatelessWidget {
  const TenantStatusBadge({required this.status, super.key, this.icon});

  final String status;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return StatusBadge(
      label: status,
      tone: tenantToneForStatus(status),
      icon: icon,
    );
  }
}
