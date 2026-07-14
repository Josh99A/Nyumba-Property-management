import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/coming_soon.dart';
import '../../../core/domain/sync_metadata.dart';
import '../../../core/presentation/page_header.dart';
import '../../../core/presentation/responsive.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import '../domain/property.dart';
import '../domain/unit.dart';
import 'portfolio_visuals.dart';

class PropertiesScreen extends ConsumerStatefulWidget {
  const PropertiesScreen({super.key, this.openCreateOnLoad = false});

  final bool openCreateOnLoad;

  @override
  ConsumerState<PropertiesScreen> createState() => _PropertiesScreenState();
}

class _PropertiesScreenState extends ConsumerState<PropertiesScreen> {
  final _searchController = TextEditingController();
  bool _createOpened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.openCreateOnLoad && !_createOpened) {
      _createOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _createProperty());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final propertiesValue = ref.watch(portfolioPropertiesProvider);
    final unitsValue = ref.watch(portfolioUnitsProvider);
    final units = unitsValue.value ?? const <Unit>[];
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        context.pageGutter,
        26,
        context.pageGutter,
        40,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1360),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Properties and units',
                description:
                    'Every rentable space has its own rent, occupancy, lease, and maintenance history.',
                primaryAction: FilledButton.icon(
                  onPressed: _createProperty,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add property'),
                ),
              ),
              const SizedBox(height: 22),
              _PortfolioUsage(units: units),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Your properties',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  SizedBox(
                    width: context.isCompact ? 190 : 300,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Search properties',
                        prefixIcon: Icon(Icons.search_rounded),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              propertiesValue.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stack) => NyumbaSurface(
                  child: Text('Could not load the local portfolio: $error'),
                ),
                data: (allProperties) {
                  final query = _searchController.text.trim().toLowerCase();
                  final properties = allProperties.where((property) {
                    return query.isEmpty ||
                        property.name.toLowerCase().contains(query) ||
                        property.city.toLowerCase().contains(query) ||
                        property.addressLine.toLowerCase().contains(query);
                  }).toList();
                  if (properties.isEmpty) {
                    return NyumbaSurface(
                      child: Padding(
                        padding: const EdgeInsets.all(34),
                        child: Column(
                          children: [
                            Icon(
                              Icons.apartment_outlined,
                              size: 44,
                              color: context.nyumba.mutedInk,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              query.isEmpty
                                  ? 'Add your first property'
                                  : 'No properties match your search.',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 1050
                          ? 3
                          : constraints.maxWidth >= 650
                          ? 2
                          : 1;
                      const gap = 18.0;
                      final width =
                          (constraints.maxWidth - gap * (columns - 1)) /
                          columns;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final property in properties)
                            SizedBox(
                              width: width,
                              child: _PropertyCard(
                                property: property,
                                units: units
                                    .where(
                                      (unit) => unit.propertyId == property.id,
                                    )
                                    .toList(),
                              ),
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createProperty() async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController();
    final address = TextEditingController();
    final city = TextEditingController(text: 'Kampala');
    final description = TextEditingController();
    String? error;
    final property = await showDialog<Property>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add property'),
          content: SizedBox(
            width: 500,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: name,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Property name',
                      ),
                      validator: (value) => (value?.trim().length ?? 0) < 2
                          ? 'Enter a property name'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: address,
                      decoration: const InputDecoration(
                        labelText: 'Street address',
                      ),
                      validator: (value) => (value?.trim().length ?? 0) < 3
                          ? 'Enter the street address'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: city,
                      decoration: const InputDecoration(
                        labelText: 'City or town',
                      ),
                      validator: (value) => (value?.trim().isEmpty ?? true)
                          ? 'Enter a city or town'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: description,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        style: TextStyle(color: context.nyumba.danger),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  final created = await ref
                      .read(appDependenciesProvider)
                      .properties
                      .create(
                        CreatePropertyInput(
                          landlordId: 'demo-landlord-001',
                          name: name.text.trim(),
                          addressLine: address.text.trim(),
                          city: city.text.trim(),
                          description: description.text.trim(),
                        ),
                      );
                  if (context.mounted) Navigator.pop(context, created);
                } on Object catch (caught) {
                  setDialogState(() => error = caught.toString());
                }
              },
              child: const Text('Save property'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    address.dispose();
    city.dispose();
    description.dispose();
    if (property != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Property saved locally and added to the sync queue.'),
        ),
      );
      context.go('/properties/${property.id}?addUnit=true');
    }
  }
}

class _PortfolioUsage extends StatelessWidget {
  const _PortfolioUsage({required this.units});

  final List<Unit> units;

  @override
  Widget build(BuildContext context) {
    const limit = 50;
    final usage = (units.length / limit).clamp(0, 1).toDouble();
    return NyumbaSurface(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: context.nyumba.navyTint,
            child: Icon(
              Icons.workspace_premium_outlined,
              color: context.nyumba.midnightNavy,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Pro plan',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Text(
                      '${units.length} of $limit units',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: usage,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(4),
                  color: context.nyumba.sageGreen,
                  backgroundColor: context.nyumba.sageTint,
                ),
              ],
            ),
          ),
          if (!context.isCompact) ...[
            const SizedBox(width: 18),
            const ComingSoon(
              message: 'Plan management coming soon',
              child: TextButton(onPressed: null, child: Text('View plan')),
            ),
          ],
        ],
      ),
    );
  }
}

class _PropertyCard extends StatelessWidget {
  const _PropertyCard({required this.property, required this.units});

  final Property property;
  final List<Unit> units;

  @override
  Widget build(BuildContext context) {
    final occupied = units
        .where((unit) => unit.status == UnitStatus.occupied)
        .length;
    final monthlyMinor = units.fold<int>(
      0,
      (total, unit) => total + unit.monthlyRentMinor,
    );
    final currency = NumberFormat.currency(
      locale: 'en_UG',
      symbol: 'UGX ',
      decimalDigits: 0,
    );
    final pending = property.syncMetadata.state != EntitySyncState.synced;
    return NyumbaSurface(
      padding: EdgeInsets.zero,
      onTap: () => context.go('/properties/${property.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(11),
                ),
                child: AspectRatio(
                  aspectRatio: 3 / 1.45,
                  child: Image.asset(
                    propertyAssetForName(property.name),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              if (pending)
                const Positioned(
                  left: 12,
                  top: 12,
                  child: StatusBadge(
                    label: 'Pending sync',
                    tone: BadgeTone.warning,
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  property.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${property.addressLine}, ${property.city}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                      child: _PropertyFact(
                        value: '${units.length}',
                        label: 'Units',
                      ),
                    ),
                    Expanded(
                      child: _PropertyFact(
                        value: '$occupied',
                        label: 'Occupied',
                      ),
                    ),
                    Expanded(
                      child: _PropertyFact(
                        value: '${units.length - occupied}',
                        label: 'Available',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                const Divider(),
                const SizedBox(height: 11),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Potential monthly rent',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            currency.format(monthlyMinor / 100),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_rounded, size: 19),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PropertyFact extends StatelessWidget {
  const _PropertyFact({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: context.nyumba.midnightNavy),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
