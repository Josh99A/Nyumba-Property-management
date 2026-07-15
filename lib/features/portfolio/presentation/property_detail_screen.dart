import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/domain/sync_metadata.dart';
import '../../../core/presentation/responsive.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import '../../marketplace/application/marketplace_use_cases.dart';
import '../../marketplace/domain/listing.dart';
import '../application/portfolio_use_cases.dart';
import '../application/rental_space_labels.dart';
import '../domain/property.dart';
import '../domain/unit.dart';
import 'portfolio_visuals.dart';

class PropertyDetailScreen extends ConsumerStatefulWidget {
  const PropertyDetailScreen({
    required this.propertyId,
    super.key,
    this.openAddUnitOnLoad = false,
  });

  final String propertyId;
  final bool openAddUnitOnLoad;

  @override
  ConsumerState<PropertyDetailScreen> createState() =>
      _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends ConsumerState<PropertyDetailScreen> {
  bool _dialogOpened = false;
  String _filter = 'All';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.openAddUnitOnLoad && !_dialogOpened) {
      _dialogOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showAddUnit());
    }
  }

  @override
  Widget build(BuildContext context) {
    final propertiesValue = ref.watch(portfolioPropertiesProvider);
    final unitsValue = ref.watch(portfolioUnitsProvider);
    final listingsValue = ref.watch(landlordListingsProvider);
    final properties = propertiesValue.value;
    if (propertiesValue.isLoading || properties == null) {
      return const Center(child: CircularProgressIndicator());
    }
    Property? property;
    for (final item in properties) {
      if (item.id == widget.propertyId) property = item;
    }
    if (property == null) {
      return _MissingProperty(onBack: () => context.go('/properties'));
    }

    final allUnits = (unitsValue.value ?? const <Unit>[])
        .where((unit) => unit.propertyId == property!.id)
        .toList();
    final listings = listingsValue.value ?? const <Listing>[];
    final filteredUnits = allUnits.where((unit) {
      return switch (_filter) {
        'Occupied' => unit.status == UnitStatus.occupied,
        'Vacant' => unit.status == UnitStatus.vacant,
        'Maintenance' => unit.status == UnitStatus.maintenance,
        _ => true,
      };
    }).toList();

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        context.pageGutter,
        22,
        context.pageGutter,
        40,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1360),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context.go('/properties'),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Properties'),
                ),
              ),
              const SizedBox(height: 8),
              _PropertyHero(property: property, units: allUnits),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Rental spaces',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _showAddUnit,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add rental space'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final filter in const [
                    'All',
                    'Occupied',
                    'Vacant',
                    'Maintenance',
                  ])
                    ChoiceChip(
                      label: Text(filter),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (unitsValue.isLoading)
                const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (filteredUnits.isEmpty)
                NyumbaSurface(
                  child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: Center(
                      child: Text(
                        allUnits.isEmpty
                            ? 'Add the first rental space in this property.'
                            : 'No rental spaces match this filter.',
                      ),
                    ),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1000
                        ? 3
                        : constraints.maxWidth >= 650
                        ? 2
                        : 1;
                    const gap = 14.0;
                    final width =
                        (constraints.maxWidth - gap * (columns - 1)) / columns;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final unit in filteredUnits)
                          SizedBox(
                            width: width,
                            child: _UnitCard(
                              unit: unit,
                              hasListing: listings.any(
                                (listing) => listing.unitId == unit.id,
                              ),
                              onAdvertise: () =>
                                  _createListing(property!, unit),
                            ),
                          ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddUnit() async {
    final property = await ref.read(getPropertyByIdProvider)(widget.propertyId);
    if (property == null || !mounted) return;

    final formKey = GlobalKey<FormState>();
    final label = TextEditingController();
    final rent = TextEditingController();
    final bedrooms = TextEditingController(text: '1');
    final bathrooms = TextEditingController(text: '1');
    var type = UnitType.apartment;
    var status = UnitStatus.vacant;
    String? error;
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Add rental space to ${property.name}'),
          content: SizedBox(
            width: 520,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: label,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Rental space name or number',
                      ),
                      validator: (value) => (value?.trim().isEmpty ?? true)
                          ? 'Enter a rental space name or number'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<UnitType>(
                      initialValue: type,
                      decoration: const InputDecoration(
                        labelText: 'Rental space type',
                      ),
                      items: [
                        for (final item in UnitType.values)
                          DropdownMenuItem(
                            value: item,
                            child: Text(_titleCase(item.name)),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setDialogState(() => type = value);
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: rent,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Monthly rent',
                        prefixText: 'UGX ',
                      ),
                      validator: (value) {
                        final amount = int.tryParse(
                          value?.replaceAll(',', '') ?? '',
                        );
                        return amount == null || amount <= 0
                            ? 'Enter a valid rent amount'
                            : null;
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: bedrooms,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Bedrooms',
                            ),
                            validator: (value) =>
                                int.tryParse(value ?? '') == null
                                ? 'Required'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: bathrooms,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Bathrooms',
                            ),
                            validator: (value) =>
                                int.tryParse(value ?? '') == null
                                ? 'Required'
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<UnitStatus>(
                      initialValue: status,
                      decoration: const InputDecoration(
                        labelText: 'Occupancy status',
                      ),
                      items: [
                        for (final item in UnitStatus.values)
                          DropdownMenuItem(
                            value: item,
                            child: Text(_titleCase(item.name)),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setDialogState(() => status = value);
                      },
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
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  await ref.read(createUnitProvider)(
                    CreateUnitInput(
                      propertyId: property.id,
                      landlordId: property.landlordId,
                      label: label.text.trim(),
                      type: type,
                      status: status,
                      monthlyRentMinor:
                          int.parse(rent.text.replaceAll(',', '')) * 100,
                      bedrooms: int.parse(bedrooms.text),
                      bathrooms: int.parse(bathrooms.text),
                    ),
                  );
                  if (context.mounted) Navigator.pop(context, true);
                } on Object catch (caught) {
                  setDialogState(() => error = caught.toString());
                }
              },
              child: const Text('Save rental space'),
            ),
          ],
        ),
      ),
    );
    label.dispose();
    rent.dispose();
    bedrooms.dispose();
    bathrooms.dispose();
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rental space saved locally and queued to sync.'),
        ),
      );
    }
  }

  Future<void> _createListing(Property property, Unit unit) async {
    final draft = await ref.read(createListingDraftProvider)(
      CreateListingInput(
        unitId: unit.id,
        propertyId: property.id,
        landlordId: property.landlordId,
        title: '${unit.displayName} at ${property.name}',
        description:
            'A well maintained ${unit.type.displayLabel.toLowerCase()} in ${property.city}.',
        monthlyRentMinor: unit.monthlyRentMinor,
        currency: unit.currency,
        city: property.city,
        neighborhood: property.city,
        contactPhone: '+256 772 000 100',
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${draft.title} saved as a local draft.')),
      );
      context.go('/listings');
    }
  }
}

class _PropertyHero extends StatelessWidget {
  const _PropertyHero({required this.property, required this.units});

  final Property property;
  final List<Unit> units;

  @override
  Widget build(BuildContext context) {
    final occupied = units
        .where((unit) => unit.status == UnitStatus.occupied)
        .length;
    return NyumbaSurface(
      padding: EdgeInsets.zero,
      child: context.isCompact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HeroImage(property: property),
                _HeroContent(
                  property: property,
                  units: units,
                  occupied: occupied,
                ),
              ],
            )
          : SizedBox(
              height: 250,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 5, child: _HeroImage(property: property)),
                  Expanded(
                    flex: 7,
                    child: _HeroContent(
                      property: property,
                      units: units,
                      occupied: occupied,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _HeroImage extends StatefulWidget {
  const _HeroImage({required this.property});

  final Property property;

  @override
  State<_HeroImage> createState() => _HeroImageState();
}

class _HeroImageState extends State<_HeroImage> {
  final _controller = PageController();
  int _currentIndex = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageCount = widget.property.imageUrls.isEmpty
        ? 1
        : widget.property.imageUrls.length;
    return ClipRRect(
      borderRadius: context.isCompact
          ? const BorderRadius.vertical(top: Radius.circular(11))
          : const BorderRadius.horizontal(left: Radius.circular(11)),
      child: AspectRatio(
        aspectRatio: context.isCompact ? 2 : 1.5,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Semantics(
              label: 'Property photos',
              child: PageView.builder(
                controller: _controller,
                itemCount: imageCount,
                onPageChanged: (index) => setState(() => _currentIndex = index),
                itemBuilder: (context, index) => propertyImage(
                  widget.property,
                  index: widget.property.imageUrls.isEmpty ? -1 : index,
                ),
              ),
            ),
            if (imageCount > 1) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: _CarouselButton(
                  tooltip: 'Previous photo',
                  icon: Icons.chevron_left_rounded,
                  onPressed: () =>
                      _goTo((_currentIndex - 1 + imageCount) % imageCount),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: _CarouselButton(
                  tooltip: 'Next photo',
                  icon: Icons.chevron_right_rounded,
                  onPressed: () => _goTo((_currentIndex + 1) % imageCount),
                ),
              ),
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var index = 0; index < imageCount; index++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: index == _currentIndex ? 18 : 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: index == _currentIndex
                              ? Colors.white
                              : Colors.white70,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_currentIndex + 1}/$imageCount',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _goTo(int index) {
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }
}

class _CarouselButton extends StatelessWidget {
  const _CarouselButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: IconButton.filled(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: Colors.black45,
          foregroundColor: Colors.white,
        ),
        icon: Icon(icon),
      ),
    );
  }
}

class _HeroContent extends StatelessWidget {
  const _HeroContent({
    required this.property,
    required this.units,
    required this.occupied,
  });

  final Property property;
  final List<Unit> units;
  final int occupied;

  @override
  Widget build(BuildContext context) {
    final pending = property.syncMetadata.state != EntitySyncState.synced;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  property.name,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              StatusBadge(
                label: pending ? 'Pending sync' : 'Synced',
                tone: pending ? BadgeTone.warning : BadgeTone.success,
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            '${property.addressLine}, ${property.city}',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (property.description != null) ...[
            const SizedBox(height: 10),
            Text(
              property.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          if (context.isCompact) const SizedBox(height: 18) else const Spacer(),
          Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              _HeroMetric(label: 'Rental spaces', value: '${units.length}'),
              _HeroMetric(label: 'Occupied', value: '$occupied'),
              _HeroMetric(
                label: 'Available',
                value: '${units.length - occupied}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(color: context.nyumba.midnightNavy),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _UnitCard extends StatelessWidget {
  const _UnitCard({
    required this.unit,
    required this.hasListing,
    required this.onAdvertise,
  });

  final Unit unit;
  final bool hasListing;
  final VoidCallback onAdvertise;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'en_UG',
      symbol: 'UGX ',
      decimalDigits: 0,
    );
    final (statusLabel, tone) = switch (unit.status) {
      UnitStatus.occupied => ('Occupied', BadgeTone.success),
      UnitStatus.vacant => ('Vacant', BadgeTone.info),
      UnitStatus.reserved => ('Reserved', BadgeTone.warning),
      UnitStatus.maintenance => ('Maintenance', BadgeTone.danger),
      UnitStatus.inactive => ('Inactive', BadgeTone.neutral),
    };
    return NyumbaSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: context.nyumba.navyTint,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  _unitIcon(unit.type),
                  color: context.nyumba.midnightNavy,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  unit.displayName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              StatusBadge(label: statusLabel, tone: tone),
            ],
          ),
          const SizedBox(height: 16),
          const SizedBox(height: 4),
          Text(
            currency.format(unit.monthlyRentMinor / 100),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Icon(
                Icons.bed_outlined,
                size: 18,
                color: context.nyumba.mutedInk,
              ),
              const SizedBox(width: 5),
              Text(
                '${unit.bedrooms} bed',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 14),
              Icon(
                Icons.bathtub_outlined,
                size: 18,
                color: context.nyumba.mutedInk,
              ),
              const SizedBox(width: 5),
              Text(
                '${unit.bathrooms} bath',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 9),
          Row(
            children: [
              if (unit.syncMetadata.state != EntitySyncState.synced)
                const StatusBadge(
                  label: 'Pending sync',
                  tone: BadgeTone.warning,
                )
              else
                const StatusBadge(label: 'Synced', tone: BadgeTone.success),
              const Spacer(),
              if (unit.canBeAdvertised && !hasListing)
                TextButton.icon(
                  onPressed: onAdvertise,
                  icon: const Icon(Icons.campaign_outlined, size: 18),
                  label: const Text('Advertise'),
                )
              else if (hasListing)
                const StatusBadge(
                  label: 'Listing created',
                  tone: BadgeTone.info,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MissingProperty extends StatelessWidget {
  const _MissingProperty({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.apartment_outlined, size: 50),
          const SizedBox(height: 14),
          const Text('Property not found'),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onBack,
            child: const Text('Back to properties'),
          ),
        ],
      ),
    );
  }
}

IconData _unitIcon(UnitType type) => switch (type) {
  UnitType.apartment => Icons.apartment_outlined,
  UnitType.house => Icons.house_outlined,
  UnitType.shop => Icons.storefront_outlined,
  UnitType.office => Icons.business_center_outlined,
  UnitType.bedsitter => Icons.single_bed_outlined,
  UnitType.room => Icons.meeting_room_outlined,
  UnitType.other => Icons.home_work_outlined,
};

String _titleCase(String value) => value.isEmpty
    ? value
    : '${value[0].toUpperCase()}${value.substring(1).replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(1)}')}';
