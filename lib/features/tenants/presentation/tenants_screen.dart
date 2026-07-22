import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/offline/aggregate_sync_status.dart';
import '../../../core/offline/offline_entity.dart';
import '../../../core/offline/outbox_entry.dart';
import '../../../core/presentation/page_header.dart';
import '../../../core/presentation/responsive.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/status_message.dart';
import '../../../core/presentation/surface.dart';
import '../../../core/presentation/sync_state_badge.dart';
import '../../portfolio/domain/property.dart';
import '../../portfolio/domain/unit.dart';
import '../../portfolio/application/rental_space_labels.dart';
import '../application/tenancy_providers.dart';
import '../domain/tenancy.dart';

final _ugx = NumberFormat.currency(
  locale: 'en_UG',
  symbol: 'UGX ',
  decimalDigits: 0,
);

class TenantsScreen extends ConsumerStatefulWidget {
  const TenantsScreen({super.key});

  @override
  ConsumerState<TenantsScreen> createState() => _TenantsScreenState();
}

class _TenantsScreenState extends ConsumerState<TenantsScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tenanciesValue = ref.watch(tenanciesProvider);
    final units = ref.watch(portfolioUnitsProvider).value ?? const <Unit>[];
    final properties =
        ref.watch(portfolioPropertiesProvider).value ?? const <Property>[];
    final outbox =
        ref.watch(outboxEntriesProvider).value ?? const <OutboxEntry>[];
    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.fromSTEB(
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
                  onPressed: () => _showAddTenant(context, units, properties),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text.localized('Add tenant'),
                ),
              ),
              const SizedBox(height: 24),
              tenanciesValue.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stack) => NyumbaStatusMessage.fromError(
                  error,
                  subject: 'tenants',
                  onRetry: () => ref.invalidate(tenanciesProvider),
                ),
                data: (tenancies) => _buildLoaded(context, tenancies, outbox),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoaded(
    BuildContext context,
    List<Tenancy> tenancies,
    List<OutboxEntry> outbox,
  ) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = tenancies.where((tenancy) {
      return query.isEmpty ||
          tenancy.tenantName.toLowerCase().contains(query) ||
          tenancy.propertyName.toLowerCase().contains(query) ||
          tenancy.unitLabel.toLowerCase().contains(query);
    }).toList();
    final active = tenancies
        .where((item) => item.status == TenancyStatus.active)
        .length;
    final upToDate = tenancies.where((item) => !item.balanceDue).length;
    final endingSoon = tenancies
        .where(
          (item) =>
              item.status == TenancyStatus.active &&
              item.leaseEnd.difference(DateTime.now()).inDays <= 90,
        )
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - 28) / 3;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                SizedBox(
                  width: context.isCompact ? constraints.maxWidth : width,
                  child: _TenantMetric(
                    label: 'Active tenants',
                    value: '$active',
                    icon: Icons.people_outline_rounded,
                    tone: context.nyumba.midnightNavy,
                  ),
                ),
                SizedBox(
                  width: context.isCompact ? constraints.maxWidth : width,
                  child: _TenantMetric(
                    label: 'Balances up to date',
                    value: '$upToDate',
                    icon: Icons.verified_outlined,
                    tone: context.nyumba.sageDark,
                  ),
                ),
                SizedBox(
                  width: context.isCompact ? constraints.maxWidth : width,
                  child: _TenantMetric(
                    label: 'Leases ending soon',
                    value: '$endingSoon',
                    icon: Icons.event_outlined,
                    tone: context.nyumba.terracottaDark,
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
                      child: Text.localized(
                        'Tenant directory',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    SizedBox(
                      width: context.isCompact ? 190 : 300,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: context.tr('Search tenants'),
                          prefixIcon: Icon(Icons.search_rounded),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(36),
                  child: Center(
                    child: Text.localized('No tenants match your search.'),
                  ),
                )
              else
                for (final tenancy in filtered)
                  _TenantRow(
                    tenancy: tenancy,
                    syncStatus: resolveAggregateSyncStatus(
                      entityType: OfflineEntityType.tenancy,
                      entityId: tenancy.id,
                      outbox: outbox,
                      syncMetadata: tenancy.syncMetadata,
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showAddTenant(
    BuildContext context,
    List<Unit> units,
    List<Property> properties,
  ) async {
    final propertyById = <String, Property>{
      for (final property in properties) property.id: property,
    };
    final vacantUnits = units
        .where((unit) => unit.status == UnitStatus.vacant)
        .toList();
    if (vacantUnits.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text.localized(
            'No vacant rental spaces are available for a new tenancy.',
          ),
        ),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final name = TextEditingController();
    final email = TextEditingController();
    final phone = TextEditingController();
    var selectedUnit = vacantUnits.first;
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text.localized('Add tenant'),
          content: SizedBox(
            width: 460,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    decoration: InputDecoration(
                      labelText: context.tr('Full name'),
                    ),
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'Enter the tenant name'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: context.tr('Email address'),
                    ),
                    validator: (value) => !(value?.contains('@') ?? false)
                        ? 'Enter a valid email'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: context.tr('Phone (optional)'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: selectedUnit.id,
                    decoration: InputDecoration(
                      labelText: context.tr('Vacant rental space'),
                    ),
                    items: [
                      for (final unit in vacantUnits)
                        DropdownMenuItem(
                          value: unit.id,
                          child: Text.localized(
                            '${unit.displayName} · '
                            '${propertyById[unit.propertyId]?.name ?? 'Property'}',
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      final match = vacantUnits.where(
                        (unit) => unit.id == value,
                      );
                      if (match.isNotEmpty) {
                        setDialogState(() => selectedUnit = match.first);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text.localized('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text.localized('Create tenant'),
            ),
          ],
        ),
      ),
    );
    if (created == true) {
      try {
        final now = DateTime.now();
        await ref.read(createTenancyProvider)(
          CreateTenancyInput(
            landlordId: selectedUnit.landlordId,
            tenantName: name.text.trim(),
            email: email.text.trim(),
            phone: phone.text.trim().isEmpty
                ? 'Not provided'
                : phone.text.trim(),
            unitId: selectedUnit.id,
            propertyId: selectedUnit.propertyId,
            unitLabel: selectedUnit.displayName,
            propertyName:
                propertyById[selectedUnit.propertyId]?.name ?? 'Property',
            monthlyRentMinor: selectedUnit.monthlyRentMinor,
            leaseStart: now,
            leaseEnd: DateTime(now.year + 1, now.month, now.day),
          ),
        );
        if (mounted) {
          ScaffoldMessenger.of(this.context).showSnackBar(
            const SnackBar(
              content: Text.localized(
                'Tenant saved locally. Invitation will send when online.',
              ),
            ),
          );
        }
      } on Object catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(this.context).showSnackBar(
            SnackBar(
              content: Text.localized('Could not create the tenancy: $error'),
            ),
          );
        }
      }
    }
    name.dispose();
    email.dispose();
    phone.dispose();
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
              Text.localized(
                value,
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(color: tone),
              ),
              Text.localized(
                label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TenantRow extends StatelessWidget {
  const _TenantRow({required this.tenancy, required this.syncStatus});

  final Tenancy tenancy;
  final AggregateSyncStatus syncStatus;

  @override
  Widget build(BuildContext context) {
    final balanceDue = tenancy.balanceDue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.nyumba.divider)),
      ),
      child: context.isCompact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TenantIdentity(tenancy: tenancy),
                const SizedBox(height: 12),
                Row(
                  children: [
                    StatusBadge(
                      label: balanceDue
                          ? '${_ugx.format(tenancy.balanceMinor / 100)} due'
                          : 'Up to date',
                      tone: balanceDue ? BadgeTone.warning : BadgeTone.success,
                    ),
                    const SizedBox(width: 8),
                    SyncStateBadge(status: syncStatus),
                    const Spacer(),
                    IconButton(
                      tooltip: context.tr('View tenant details'),
                      onPressed: () => _showTenantDetails(context, tenancy),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(flex: 4, child: _TenantIdentity(tenancy: tenancy)),
                Expanded(
                  flex: 3,
                  child: Text.localized(
                    '${tenancy.unitLabel} · ${tenancy.propertyName}',
                  ),
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
                  child: Text.localized(
                    'Ends ${DateFormat('d MMM y').format(tenancy.leaseEnd.toLocal())}',
                  ),
                ),
                SizedBox(width: 110, child: SyncStateBadge(status: syncStatus)),
                IconButton(
                  tooltip: context.tr('View tenant details'),
                  onPressed: () => _showTenantDetails(context, tenancy),
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
              ],
            ),
    );
  }
}

Future<void> _showTenantDetails(BuildContext context, Tenancy tenancy) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text.localized(tenancy.tenantName),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: Text.localized(
                '${tenancy.unitLabel} · ${tenancy.propertyName}',
              ),
              subtitle: Text.localized(
                '${DateFormat('d MMM y').format(tenancy.leaseStart.toLocal())} – '
                '${DateFormat('d MMM y').format(tenancy.leaseEnd.toLocal())}',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: Text.localized(tenancy.email),
              subtitle: Text.localized(tenancy.phone),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: Text.localized(
                _ugx.format(tenancy.monthlyRentMinor / 100),
              ),
              subtitle: Text.localized(
                tenancy.balanceDue
                    ? '${_ugx.format(tenancy.balanceMinor / 100)} awaiting payment'
                    : 'Balance up to date',
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text.localized('Close'),
        ),
      ],
    ),
  );
}

class _TenantIdentity extends StatelessWidget {
  const _TenantIdentity({required this.tenancy});

  final Tenancy tenancy;

  @override
  Widget build(BuildContext context) {
    final parts = tenancy.tenantName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty);
    final initials = parts.isEmpty
        ? '?'
        : parts.take(2).map((part) => part[0]).join().toUpperCase();
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: context.nyumba.navyTint,
          foregroundColor: context.nyumba.midnightNavy,
          child: Text.localized(
            initials,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: context.nyumba.midnightNavy,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.localized(
                tenancy.tenantName,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text.localized(
                tenancy.email,
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
