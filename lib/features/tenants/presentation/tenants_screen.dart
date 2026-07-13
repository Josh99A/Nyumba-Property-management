import 'package:flutter/material.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/page_header.dart';
import '../../../core/presentation/responsive.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';

class _TenantRecord {
  const _TenantRecord({
    required this.name,
    required this.email,
    required this.phone,
    required this.unit,
    required this.property,
    required this.balanceMinor,
    required this.leaseEnd,
  });

  final String name;
  final String email;
  final String phone;
  final String unit;
  final String property;
  final int balanceMinor;
  final DateTime leaseEnd;
}

class TenantsScreen extends StatefulWidget {
  const TenantsScreen({super.key});

  @override
  State<TenantsScreen> createState() => _TenantsScreenState();
}

class _TenantsScreenState extends State<TenantsScreen> {
  final _searchController = TextEditingController();
  final List<_TenantRecord> _tenants = [
    _TenantRecord(
      name: 'Brian Otieno',
      email: 'brian.otieno@example.com',
      phone: '+254 712 345 678',
      unit: 'B4',
      property: 'Sunset Apartments',
      balanceMinor: 0,
      leaseEnd: DateTime(2027, 2, 28),
    ),
    _TenantRecord(
      name: 'Grace Wanjiku',
      email: 'grace.wanjiku@example.com',
      phone: '+254 724 113 886',
      unit: 'D1',
      property: 'Riverside Heights',
      balanceMinor: 0,
      leaseEnd: DateTime(2026, 11, 30),
    ),
    _TenantRecord(
      name: 'Peter Mwangi',
      email: 'peter.mwangi@example.com',
      phone: '+254 733 902 118',
      unit: 'A1',
      property: 'Greenview Court',
      balanceMinor: 4000000,
      leaseEnd: DateTime(2026, 12, 31),
    ),
    _TenantRecord(
      name: 'Mary Muthoni',
      email: 'mary.muthoni@example.com',
      phone: '+254 701 822 470',
      unit: 'C2',
      property: 'Nyumbani Gardens',
      balanceMinor: 1250000,
      leaseEnd: DateTime(2027, 4, 30),
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final tenants = _tenants.where((tenant) {
      return query.isEmpty ||
          tenant.name.toLowerCase().contains(query) ||
          tenant.property.toLowerCase().contains(query) ||
          tenant.unit.toLowerCase().contains(query);
    }).toList();

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        context.pageGutter,
        26,
        context.pageGutter,
        40,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Tenants',
                description:
                    'Manage tenant records, leases, balances, and contact details.',
                primaryAction: FilledButton.icon(
                  onPressed: () => _showAddTenant(context),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Add tenant'),
                ),
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = (constraints.maxWidth - 28) / 3;
                  return Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      SizedBox(
                        width: context.isCompact ? constraints.maxWidth : width,
                        child: const _TenantMetric(
                          label: 'Active tenants',
                          value: '20',
                          icon: Icons.people_outline_rounded,
                          tone: NyumbaColors.midnightNavy,
                        ),
                      ),
                      SizedBox(
                        width: context.isCompact ? constraints.maxWidth : width,
                        child: const _TenantMetric(
                          label: 'Balances up to date',
                          value: '17',
                          icon: Icons.verified_outlined,
                          tone: NyumbaColors.sageDark,
                        ),
                      ),
                      SizedBox(
                        width: context.isCompact ? constraints.maxWidth : width,
                        child: const _TenantMetric(
                          label: 'Leases ending soon',
                          value: '3',
                          icon: Icons.event_outlined,
                          tone: NyumbaColors.terracottaDark,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 22),
              NyumbaSurface(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Tenant directory',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          SizedBox(
                            width: context.isCompact ? 190 : 300,
                            child: TextField(
                              controller: _searchController,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                hintText: 'Search tenants',
                                prefixIcon: Icon(Icons.search_rounded),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    if (tenants.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(36),
                        child: Center(
                          child: Text('No tenants match your search.'),
                        ),
                      )
                    else
                      for (final tenant in tenants) _TenantRow(tenant: tenant),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddTenant(BuildContext context) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController();
    final email = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add tenant'),
        content: SizedBox(
          width: 460,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Enter the tenant name'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email address'),
                  validator: (value) => !(value?.contains('@') ?? false)
                      ? 'Enter a valid email'
                      : null,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: 'A3 · Greenview Court',
                  decoration: const InputDecoration(labelText: 'Vacant unit'),
                  items: const [
                    DropdownMenuItem(
                      value: 'A3 · Greenview Court',
                      child: Text('A3 · Greenview Court'),
                    ),
                    DropdownMenuItem(
                      value: 'B5 · Sunset Apartments',
                      child: Text('B5 · Sunset Apartments'),
                    ),
                  ],
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Create tenant'),
          ),
        ],
      ),
    );
    if (created == true) {
      setState(() {
        _tenants.add(
          _TenantRecord(
            name: name.text.trim(),
            email: email.text.trim(),
            phone: 'Not provided',
            unit: 'A3',
            property: 'Greenview Court',
            balanceMinor: 0,
            leaseEnd: DateTime.now().add(const Duration(days: 365)),
          ),
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tenant saved locally. Invitation will send when online.',
            ),
          ),
        );
      }
    }
    name.dispose();
    email.dispose();
  }
}

class _TenantMetric extends StatelessWidget {
  const _TenantMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return NyumbaSurface(
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: tone.withValues(alpha: .1),
            child: Icon(icon, color: tone),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(color: tone),
              ),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _TenantRow extends StatelessWidget {
  const _TenantRow({required this.tenant});

  final _TenantRecord tenant;

  @override
  Widget build(BuildContext context) {
    final balanceDue = tenant.balanceMinor > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEDE9E2))),
      ),
      child: context.isCompact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TenantIdentity(tenant: tenant),
                const SizedBox(height: 12),
                Row(
                  children: [
                    StatusBadge(
                      label: balanceDue
                          ? 'KES ${tenant.balanceMinor ~/ 100} due'
                          : 'Up to date',
                      tone: balanceDue ? BadgeTone.warning : BadgeTone.success,
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(flex: 4, child: _TenantIdentity(tenant: tenant)),
                Expanded(
                  flex: 3,
                  child: Text('${tenant.unit} · ${tenant.property}'),
                ),
                Expanded(
                  flex: 2,
                  child: StatusBadge(
                    label: balanceDue ? 'Balance due' : 'Up to date',
                    tone: balanceDue ? BadgeTone.warning : BadgeTone.success,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Ends ${tenant.leaseEnd.day}/${tenant.leaseEnd.month}/${tenant.leaseEnd.year}',
                  ),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
              ],
            ),
    );
  }
}

class _TenantIdentity extends StatelessWidget {
  const _TenantIdentity({required this.tenant});

  final _TenantRecord tenant;

  @override
  Widget build(BuildContext context) {
    final initials = tenant.name
        .split(' ')
        .take(2)
        .map((part) => part[0])
        .join();
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: NyumbaColors.navyTint,
          foregroundColor: NyumbaColors.midnightNavy,
          child: Text(
            initials,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: NyumbaColors.midnightNavy),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tenant.name, style: Theme.of(context).textTheme.titleSmall),
              Text(
                tenant.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
