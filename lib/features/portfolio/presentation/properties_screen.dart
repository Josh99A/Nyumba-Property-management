import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/operational_actions.dart';
import '../../../core/domain/sync_metadata.dart';
import '../../../core/presentation/page_header.dart';
import '../../../core/presentation/responsive.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/authorization_policy.dart';
import '../../auth/domain/user_session.dart';
import '../application/portfolio_use_cases.dart';
import '../domain/property.dart';
import '../domain/unit.dart';
import 'portfolio_visuals.dart';
import 'property_photo_picker.dart';

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
    final session = ref.watch(sessionControllerProvider);
    final units = unitsValue.value ?? const <Unit>[];
    final canCreate =
        session != null &&
        AuthorizationPolicy.allows(
          session.role,
          AppResource.property,
          CrudOperation.create,
        );
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
                title: 'Properties and rental spaces',
                description:
                    'Every rentable space has its own rent, occupancy, lease, and maintenance history.',
                primaryAction: canCreate
                    ? FilledButton.icon(
                        onPressed: _createProperty,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add property'),
                      )
                    : null,
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
    final session = ref.read(sessionControllerProvider);
    if (session == null) return;
    final knownLandlordIds =
        (ref.read(portfolioPropertiesProvider).value ?? [])
            .map((property) => property.landlordId)
            .toSet()
            .toList(growable: false)
          ..sort();
    final formKey = GlobalKey<FormState>();
    final landlordId = TextEditingController(
      text: session.role == AppRole.landlord
          ? session.userId
          : knownLandlordIds.isEmpty
          ? ''
          : knownLandlordIds.first,
    );
    final name = TextEditingController();
    final address = TextEditingController();
    final city = TextEditingController(text: 'Kampala');
    final description = TextEditingController();
    final selectedPhotos = <PickedPropertyPhoto>[];
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
                    if (session.role == AppRole.admin ||
                        session.role == AppRole.superAdmin) ...[
                      TextFormField(
                        controller: landlordId,
                        decoration: const InputDecoration(
                          labelText: 'Target landlord account ID',
                          helperText:
                              'Staff actions are server-validated and audited.',
                        ),
                        validator: (value) => (value?.trim().isEmpty ?? true)
                            ? 'Enter the landlord account ID'
                            : null,
                      ),
                      const SizedBox(height: 14),
                    ],
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
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Property photos',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              Text(
                                'Add 1–5 photos. The primary photo appears first.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: selectedPhotos.length >= propertyPhotoLimit
                              ? null
                              : () async {
                                  final result = await pickPropertyPhotos(
                                    remainingSlots:
                                        propertyPhotoLimit -
                                        selectedPhotos.length,
                                  );
                                  if (!context.mounted) return;
                                  setDialogState(() {
                                    selectedPhotos.addAll(result.photos);
                                    error = result.rejectedMessages.isEmpty
                                        ? null
                                        : result.rejectedMessages.join(' ');
                                  });
                                },
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: const Text('Add photos'),
                        ),
                      ],
                    ),
                    if (selectedPhotos.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (
                            var index = 0;
                            index < selectedPhotos.length;
                            index++
                          )
                            _SelectedPropertyPhoto(
                              photo: selectedPhotos[index],
                              isPrimary: index == 0,
                              onSetPrimary: index == 0
                                  ? null
                                  : () => setDialogState(() {
                                      final photo = selectedPhotos.removeAt(
                                        index,
                                      );
                                      selectedPhotos.insert(0, photo);
                                    }),
                              onRemove: () => setDialogState(
                                () => selectedPhotos.removeAt(index),
                              ),
                            ),
                        ],
                      ),
                    ],
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
                if (selectedPhotos.isEmpty) {
                  setDialogState(
                    () => error = 'Add at least one property photo.',
                  );
                  return;
                }
                try {
                  final created = await ref.read(createPropertyProvider)(
                    CreatePropertyInput(
                      landlordId: landlordId.text.trim(),
                      name: name.text.trim(),
                      addressLine: address.text.trim(),
                      city: city.text.trim(),
                      description: description.text.trim(),
                      imageUrls: selectedPhotos
                          .map((photo) => photo.dataUri)
                          .toList(),
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
    landlordId.dispose();
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
                      '${units.length} of $limit rental spaces',
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
            TextButton(
              onPressed: () => showNyumbaInfoDialog(
                context,
                title: 'Pro plan usage',
                message:
                    '${units.length} of $limit rental spaces are currently in use. '
                    'Plan changes require server-owned billing configuration; '
                    'this workspace will never change entitlements locally.',
                icon: Icons.workspace_premium_outlined,
              ),
              child: const Text('View plan'),
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
    final archiveNeedsAttention =
        property.isArchived &&
        (property.syncMetadata.state == EntitySyncState.failed ||
            property.syncMetadata.state == EntitySyncState.conflicted);
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
                  child: propertyImage(property),
                ),
              ),
              if (pending)
                Positioned(
                  left: 12,
                  top: 12,
                  child: StatusBadge(
                    label: property.isArchived
                        ? archiveNeedsAttention
                              ? 'Archive needs attention'
                              : 'Archive pending'
                        : 'Pending sync',
                    tone: archiveNeedsAttention
                        ? BadgeTone.danger
                        : BadgeTone.warning,
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
                        label: 'Rental spaces',
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

class _SelectedPropertyPhoto extends StatelessWidget {
  const _SelectedPropertyPhoto({
    required this.photo,
    required this.isPrimary,
    required this.onSetPrimary,
    required this.onRemove,
  });

  final PickedPropertyPhoto photo;
  final bool isPrimary;
  final VoidCallback? onSetPrimary;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      child: Column(
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Image.memory(
                  photo.bytes,
                  width: 104,
                  height: 76,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                right: 3,
                top: 3,
                child: IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Remove ${photo.name}',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded, size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (isPrimary)
            Text(
              'Primary',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.nyumba.sageGreen,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            TextButton(
              onPressed: onSetPrimary,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
              child: const Text('Make primary'),
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
