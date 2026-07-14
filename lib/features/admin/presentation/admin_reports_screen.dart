import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/coming_soon.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import 'widgets/admin_components.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  String _period = 'Last 30 days';
  String _reportView = 'Platform';
  String _district = 'All districts';
  final List<_GeneratedReport> _generated = [..._seedGeneratedReports];

  _ReportMetrics get _metrics {
    final multiplier = switch (_period) {
      'Last 7 days' => .28,
      'This quarter' => 2.78,
      'Year to date' => 6.42,
      _ => 1.0,
    };
    final districtMultiplier = _district == 'All districts' ? 1.0 : .34;
    return _ReportMetrics(
      paymentVolume: (126800000 * multiplier * districtMultiplier).round(),
      newUnits: (684 * multiplier * districtMultiplier).round(),
      applications: (924 * multiplier * districtMultiplier).round(),
      resolutionRate: _district == 'All districts' ? 91.4 : 88.7,
    );
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _metrics;
    return AdminPage(
      title: 'Reports & insights',
      description: 'Explore operational trends and generate auditable exports.',
      secondaryAction: ComingSoon(
        message: 'Scheduled reports coming soon',
        child: OutlinedButton.icon(
          onPressed: null,
          icon: Icon(Icons.schedule_send_outlined),
          label: Text('Schedule report'),
        ),
      ),
      primaryAction: FilledButton.icon(
        onPressed: () => _generateReport(_reportTemplates.first),
        icon: const Icon(Icons.file_download_outlined),
        label: const Text('Export snapshot'),
      ),
      children: [
        NyumbaSurface(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth < 620
                  ? constraints.maxWidth
                  : 210.0;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: width,
                    child: _ReportDropdown(
                      label: 'Date range',
                      value: _period,
                      values: const [
                        'Last 7 days',
                        'Last 30 days',
                        'This quarter',
                        'Year to date',
                      ],
                      icon: Icons.calendar_today_outlined,
                      onChanged: (value) => setState(() => _period = value),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _ReportDropdown(
                      label: 'Insight view',
                      value: _reportView,
                      values: const [
                        'Platform',
                        'Subscriptions',
                        'Payments',
                        'Maintenance',
                      ],
                      icon: Icons.analytics_outlined,
                      onChanged: (value) => setState(() => _reportView = value),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _ReportDropdown(
                      label: 'District',
                      value: _district,
                      values: const [
                        'All districts',
                        'Kampala',
                        'Wakiso',
                        'Mbarara',
                        'Gulu',
                      ],
                      icon: Icons.location_on_outlined,
                      onChanged: (value) => setState(() => _district = value),
                    ),
                  ),
                  StatusBadge(
                    label: 'Cached through 13 Jul, 09:42',
                    tone: BadgeTone.success,
                    icon: Icons.offline_pin_outlined,
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        AdminMetricGrid(
          children: [
            AdminMetricCard(
              label: 'Rent payment volume',
              value: formatAdminUgx(metrics.paymentVolume),
              caption: 'Across recorded tenant payments',
              trend: '+11.8%',
              icon: Icons.payments_outlined,
              tone: context.nyumba.sageDark,
            ),
            AdminMetricCard(
              label: 'New managed units',
              value: '${metrics.newUnits}',
              caption: 'Added in the selected period',
              trend: '+6.2%',
              icon: Icons.apartment_outlined,
              tone: context.nyumba.midnightNavy,
            ),
            AdminMetricCard(
              label: 'Listing applications',
              value: '${metrics.applications}',
              caption: 'From public property listings',
              trend: '+9.1%',
              icon: Icons.assignment_outlined,
              tone: context.nyumba.terracottaDark,
            ),
            AdminMetricCard(
              label: 'Requests resolved',
              value: '${metrics.resolutionRate.toStringAsFixed(1)}%',
              caption: 'Maintenance closed within SLA',
              trend: '+2.4%',
              icon: Icons.task_alt_rounded,
              tone: context.nyumba.sageDark,
            ),
          ],
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final trend = _TrendPanel(reportView: _reportView, period: _period);
            final footprint = _DistrictFootprint(selectedDistrict: _district);
            if (constraints.maxWidth < 980) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [trend, const SizedBox(height: 20), footprint],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: trend),
                const SizedBox(width: 20),
                Expanded(flex: 4, child: footprint),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Report library',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Generate role-safe PDF or CSV documents.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const StatusBadge(
              label: 'Print ready',
              tone: BadgeTone.info,
              icon: Icons.print_outlined,
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1050
                ? 3
                : constraints.maxWidth >= 640
                ? 2
                : 1;
            const spacing = 14.0;
            final width =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final template in _reportTemplates)
                  SizedBox(
                    width: width,
                    child: _ReportTemplateCard(
                      template: template,
                      onGenerate: () => _generateReport(template),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        _GeneratedReportsPanel(reports: _generated),
      ],
    );
  }

  Future<void> _generateReport(_ReportTemplate template) async {
    var format = 'PDF';
    var includeDetails = true;
    final shouldGenerate = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Generate ${template.title}'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: context.nyumba.navyTint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$_period • $_district • $_reportView view',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Document format',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final item in const ['PDF', 'CSV'])
                      ChoiceChip(
                        label: Text(item),
                        selected: format == item,
                        showCheckmark: false,
                        onSelected: (_) => setDialogState(() => format = item),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: includeDetails,
                  title: const Text('Include detailed records'),
                  subtitle: const Text('Adds item-level rows where permitted'),
                  onChanged: (value) =>
                      setDialogState(() => includeDetails = value),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 18,
                      color: context.nyumba.sageDark,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Personal data is limited according to the admin role '
                        'and included in the export audit log.',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.file_download_outlined),
              label: Text('Generate $format'),
            ),
          ],
        ),
      ),
    );
    if (shouldGenerate != true || !mounted) return;
    setState(() {
      _generated.insert(
        0,
        _GeneratedReport(
          name: '${template.title} • $_period',
          format: format,
          generatedBy: 'Daniel Musoke',
          generatedAt: DateFormat('d MMM, HH:mm').format(DateTime.now()),
        ),
      );
    });
    showAdminMessage(
      context,
      '${template.title} generated as $format and saved locally.',
    );
  }
}

class _ReportDropdown extends StatelessWidget {
  const _ReportDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.icon,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> values;
  final IconData icon;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          items: [
            for (final item in values)
              DropdownMenuItem(value: item, child: Text(item)),
          ],
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}

class _TrendPanel extends StatelessWidget {
  const _TrendPanel({required this.reportView, required this.period});

  final String reportView;
  final String period;

  @override
  Widget build(BuildContext context) {
    final List<double> base = switch (reportView) {
      'Subscriptions' => const [62.0, 76, 74, 91, 103, 118, 127],
      'Payments' => const [74.0, 89, 81, 112, 108, 131, 146],
      'Maintenance' => const [48.0, 52, 61, 76, 82, 88, 94],
      _ => const [58.0, 69, 83, 91, 108, 121, 139],
    };
    return AdminPanel(
      title: '$reportView trend',
      subtitle: '$period • indexed operational activity',
      trailing: const StatusBadge(
        label: '+11.8%',
        tone: BadgeTone.success,
        icon: Icons.trending_up_rounded,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              _ChartLegend(
                color: context.nyumba.midnightNavy,
                label: 'Current period',
              ),
              _ChartLegend(
                color: context.nyumba.terracottaGold,
                label: 'Previous period',
              ),
            ],
          ),
          const SizedBox(height: 16),
          AdminBarChart(
            values: base,
            secondaryValues: base
                .map((value) => (value * .82).toDouble())
                .toList(),
            labels: const ['W1', 'W2', 'W3', 'W4', 'W5', 'W6', 'W7'],
            height: 210,
          ),
        ],
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _DistrictFootprint extends StatelessWidget {
  const _DistrictFootprint({required this.selectedDistrict});

  final String selectedDistrict;

  @override
  Widget build(BuildContext context) {
    final districts = selectedDistrict == 'All districts'
        ? const [
            ('Kampala', .78, '7,840 units'),
            ('Wakiso', .56, '3,420 units'),
            ('Mbarara', .41, '2,160 units'),
            ('Gulu', .31, '1,470 units'),
            ('Jinja', .24, '1,105 units'),
          ]
        : [(selectedDistrict, .72, 'Selected district detail')];
    return AdminPanel(
      title: 'Managed-unit footprint',
      subtitle: selectedDistrict == 'All districts'
          ? 'Top districts by active unit count'
          : 'Filtered to $selectedDistrict',
      child: Column(
        children: [
          for (var index = 0; index < districts.length; index++) ...[
            AdminProgressRow(
              label: districts[index].$1,
              value: districts[index].$2,
              trailing: districts[index].$3,
              color: index.isEven
                  ? context.nyumba.midnightNavy
                  : context.nyumba.sageDark,
            ),
            if (index < districts.length - 1) const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }
}

class _ReportTemplateCard extends StatelessWidget {
  const _ReportTemplateCard({required this.template, required this.onGenerate});

  final _ReportTemplate template;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return NyumbaSurface(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 190),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: template.color.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(template.icon, color: template.color),
                ),
                const Spacer(),
                StatusBadge(label: template.format, tone: BadgeTone.neutral),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              template.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 5),
            Text(
              template.description,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            const SizedBox(height: 15),
            OutlinedButton.icon(
              onPressed: onGenerate,
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('Generate report'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GeneratedReportsPanel extends StatelessWidget {
  const _GeneratedReportsPanel({required this.reports});

  final List<_GeneratedReport> reports;

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      title: 'Recent exports',
      subtitle: 'Audit trail for generated and printed reports',
      trailing: StatusBadge(
        label: '${reports.length} locally available',
        tone: BadgeTone.info,
      ),
      child: Column(
        children: [
          for (var index = 0; index < reports.take(5).length; index++) ...[
            _GeneratedReportRow(report: reports[index]),
            if (index < reports.take(5).length - 1) const Divider(height: 25),
          ],
        ],
      ),
    );
  }
}

class _GeneratedReportRow extends StatelessWidget {
  const _GeneratedReportRow({required this.report});

  final _GeneratedReport report;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: context.nyumba.navyTint,
            shape: BoxShape.circle,
          ),
          child: Icon(
            report.format == 'PDF'
                ? Icons.picture_as_pdf_outlined
                : Icons.table_chart_outlined,
            size: 21,
            color: context.nyumba.midnightNavy,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(report.name, style: Theme.of(context).textTheme.labelLarge),
              Text(
                'By ${report.generatedBy} • ${report.generatedAt}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        StatusBadge(label: report.format, tone: BadgeTone.neutral),
        const SizedBox(width: 6),
        const ComingSoon(
          message: 'Re-download coming soon',
          child: IconButton(
            onPressed: null,
            icon: Icon(Icons.download_rounded),
          ),
        ),
      ],
    );
  }
}

class _ReportMetrics {
  const _ReportMetrics({
    required this.paymentVolume,
    required this.newUnits,
    required this.applications,
    required this.resolutionRate,
  });

  final int paymentVolume;
  final int newUnits;
  final int applications;
  final double resolutionRate;
}

class _ReportTemplate {
  const _ReportTemplate({
    required this.title,
    required this.description,
    required this.format,
    required this.icon,
    required this.color,
  });

  final String title;
  final String description;
  final String format;
  final IconData icon;
  final Color color;
}

class _GeneratedReport {
  const _GeneratedReport({
    required this.name,
    required this.format,
    required this.generatedBy,
    required this.generatedAt,
  });

  final String name;
  final String format;
  final String generatedBy;
  final String generatedAt;
}

const _reportTemplates = [
  _ReportTemplate(
    title: 'Platform performance',
    description:
        'Users, units, occupancy, payment volume, and listing adoption.',
    format: 'PDF / CSV',
    icon: Icons.monitor_heart_outlined,
    color: NyumbaColors.midnightNavy,
  ),
  _ReportTemplate(
    title: 'Subscription revenue',
    description: 'Plan mix, renewals, trial conversion, and recurring revenue.',
    format: 'PDF / CSV',
    icon: Icons.workspace_premium_outlined,
    color: NyumbaColors.terracottaDark,
  ),
  _ReportTemplate(
    title: 'Landlord compliance',
    description: 'Approval decisions, suspensions, and verification activity.',
    format: 'PDF',
    icon: Icons.verified_user_outlined,
    color: NyumbaColors.sageDark,
  ),
  _ReportTemplate(
    title: 'Payment operations',
    description: 'Rent transaction totals, exceptions, and receipt coverage.',
    format: 'CSV',
    icon: Icons.payments_outlined,
    color: NyumbaColors.sageDark,
  ),
  _ReportTemplate(
    title: 'Maintenance service',
    description: 'Request volume, priorities, SLA performance, and resolution.',
    format: 'PDF / CSV',
    icon: Icons.home_repair_service_outlined,
    color: NyumbaColors.danger,
  ),
  _ReportTemplate(
    title: 'Marketplace activity',
    description: 'Published units, views, applications, and landlord contacts.',
    format: 'PDF / CSV',
    icon: Icons.storefront_outlined,
    color: NyumbaColors.midnightNavy,
  ),
];

const _seedGeneratedReports = [
  _GeneratedReport(
    name: 'Monthly platform performance • June 2026',
    format: 'PDF',
    generatedBy: 'Daniel Musoke',
    generatedAt: '1 Jul, 08:20',
  ),
  _GeneratedReport(
    name: 'Subscription revenue • Q2 2026',
    format: 'CSV',
    generatedBy: 'Mary Achola',
    generatedAt: '30 Jun, 17:46',
  ),
  _GeneratedReport(
    name: 'Landlord approvals • June 2026',
    format: 'PDF',
    generatedBy: 'Daniel Musoke',
    generatedAt: '30 Jun, 16:10',
  ),
];
