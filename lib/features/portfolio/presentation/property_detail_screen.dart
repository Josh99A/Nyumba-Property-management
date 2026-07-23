import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/domain/sync_metadata.dart';
import '../../../core/presentation/async_action_button.dart';
import '../../../core/presentation/responsive.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/authorization_policy.dart';
import '../../marketplace/application/marketplace_use_cases.dart';
import '../../marketplace/domain/listing.dart';
import '../../subscriptions/application/subscription_providers.dart';
import '../../subscriptions/domain/landlord_entitlement.dart';
import '../../subscriptions/presentation/upgrade_prompt.dart';
import '../application/portfolio_use_cases.dart';
import '../application/rental_space_labels.dart';
import '../domain/property.dart';
import '../domain/unit.dart';
import 'portfolio_visuals.dart';
import 'property_archive_button.dart';

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
    final session = ref.watch(sessionControllerProvider);
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
    bool allows(AppResource resource, CrudOperation operation) =>
        session != null &&
        AuthorizationPolicy.allowsSession(session, resource, operation);
    final canUpdateProperty = allows(
      AppResource.property,
      CrudOperation.update,
    );
    final canArchiveProperty = allows(
      AppResource.property,
      CrudOperation.delete,
    );
    final canCreateUnit = allows(AppResource.unit, CrudOperation.create);
    final canUpdateUnit = allows(AppResource.unit, CrudOperation.update);
    final canArchiveUnit = allows(AppResource.unit, CrudOperation.delete);
    final canCreateListing = allows(
      AppResource.privateListing,
      CrudOperation.create,
    );
    final filteredUnits = allUnits.where((unit) {
      return switch (_filter) {
        'Occupied' => unit.status == UnitStatus.occupied,
        'Vacant' => unit.status == UnitStatus.vacant,
        'Maintenance' => unit.status == UnitStatus.maintenance,
        _ => true,
      };
    }).toList();
    final propertyActions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (canUpdateProperty && !property.isArchived)
          OutlinedButton.icon(
            key: const ValueKey('edit-property'),
            onPressed: () => _editProperty(property!),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text.localized('Edit property'),
          ),
        if (canArchiveProperty && !property.isArchived)
          PropertyArchiveButton(
            propertyName: property.name,
            activeRentalSpaceCount: allUnits.length,
            onArchive: () => _archiveProperty(property!),
          ),
      ],
    );

    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.fromSTEB(
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
              if (context.isCompact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextButton.icon(
                      onPressed: () => context.go('/properties'),
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const Text.localized('Properties'),
                    ),
                    const SizedBox(height: 8),
                    propertyActions,
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: () => context.go('/properties'),
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: const Text.localized('Properties'),
                        ),
                      ),
                    ),
                    propertyActions,
                  ],
                ),
              const SizedBox(height: 8),
              _PropertyHero(property: property, units: allUnits),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Text.localized(
                      'Rental spaces',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  if (canCreateUnit)
                    AsyncActionButton.filled(
                      onPressed: _showAddUnit,
                      showBusyIndicator: false,
                      icon: const Icon(Icons.add_rounded),
                      child: const Text.localized('Add rental space'),
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
                      label: Text.localized(filter),
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
                      child: Text.localized(
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
                              canAdvertise: canCreateListing,
                              canUpdate: canUpdateUnit,
                              canArchive: canArchiveUnit,
                              onAdvertise: () =>
                                  _createListing(property!, unit),
                              onEdit: () => _editUnit(unit),
                              onArchive: () => _archiveUnit(unit, listings),
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

  Future<void> _editProperty(Property property) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController(text: property.name);
    final address = TextEditingController(text: property.addressLine);
    final city = TextEditingController(text: property.city);
    final description = TextEditingController(text: property.description ?? '');
    String? error;
    ModalRoute<bool>? dialogRoute;
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) {
        dialogRoute ??= ModalRoute.of<bool>(context);
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text.localized('Edit ${property.name}'),
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
                        decoration: InputDecoration(
                          labelText: context.tr('Property name'),
                        ),
                        validator: (value) => (value?.trim().length ?? 0) < 2
                            ? context.tr('Enter a property name')
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: address,
                        decoration: InputDecoration(
                          labelText: context.tr('Street address'),
                        ),
                        validator: (value) => (value?.trim().length ?? 0) < 3
                            ? context.tr('Enter the street address')
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: city,
                        decoration: InputDecoration(
                          labelText: context.tr('City or town'),
                        ),
                        validator: (value) => (value?.trim().isEmpty ?? true)
                            ? context.tr('Enter a city or town')
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: description,
                        minLines: 2,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: context.tr('Description (optional)'),
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
                onPressed: () => Navigator.pop(context, false),
                child: const Text.localized('Cancel'),
              ),
              AsyncActionButton.filled(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  try {
                    await ref.read(updatePropertyProvider)(
                      property.copyWith(
                        name: name.text.trim(),
                        addressLine: address.text.trim(),
                        city: city.text.trim(),
                        description: description.text.trim(),
                        clearDescription: description.text.trim().isEmpty,
                      ),
                    );
                    if (context.mounted) Navigator.pop(context, true);
                  } on Object catch (caught) {
                    setDialogState(() => error = caught.toString());
                  }
                },
                child: const Text.localized('Save changes'),
              ),
            ],
          ),
        );
      },
    );
    await dialogRoute?.completed;
    name.dispose();
    address.dispose();
    city.dispose();
    description.dispose();
    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text.localized(
            'Property changes saved locally and queued to sync.',
          ),
        ),
      );
    }
  }

  Future<void> _showAddUnit() async {
    final property = await ref.read(getPropertyByIdProvider)(widget.propertyId);
    if (property == null || !mounted) return;

    // Hitting the plan's rental-space limit prompts an upgrade instead of a
    // form that the server would reject. Only a confirmed entitlement blocks
    // here — when the plan is unknown the server stays the judge.
    if (ref.read(landlordEntitlementProvider).value case EntitlementKnown(
      entitlement: final plan,
    )) {
      final unitCount = ref.read(portfolioUnitsProvider).value?.length ?? 0;
      if (unitCount >= plan.unitLimit) {
        await showUpgradePrompt(
          context,
          title: 'Rental space limit reached',
          message:
              'Your ${plan.displayName} plan includes up to '
              '${plan.unitLimit} rental spaces and all of them are in use. '
              'Upgrade to a higher plan to add more.',
        );
        return;
      }
    }

    final formKey = GlobalKey<FormState>();
    final label = TextEditingController();
    final rent = TextEditingController();
    final bedrooms = TextEditingController(text: '1');
    final bathrooms = TextEditingController(text: '1');
    var type = UnitType.apartment;
    var status = UnitStatus.vacant;
    String? error;
    ModalRoute<bool>? dialogRoute;
    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        dialogRoute ??= ModalRoute.of<bool>(context);
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text.localized('Add rental space to ${property.name}'),
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
                        decoration: InputDecoration(
                          labelText: context.tr('Rental space name or number'),
                        ),
                        validator: (value) => (value?.trim().isEmpty ?? true)
                            ? context.tr('Enter a rental space name or number')
                            : null,
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<UnitType>(
                        initialValue: type,
                        decoration: InputDecoration(
                          labelText: context.tr('Rental space type'),
                        ),
                        items: [
                          for (final item in UnitType.values)
                            DropdownMenuItem(
                              value: item,
                              child: Text.localized(_titleCase(item.name)),
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
                        decoration: InputDecoration(
                          labelText: context.tr('Monthly rent'),
                          prefixText: 'UGX ',
                        ),
                        validator: (value) {
                          final amount = int.tryParse(
                            value?.replaceAll(',', '') ?? '',
                          );
                          return amount == null || amount <= 0
                              ? context.tr('Enter a valid rent amount')
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
                              decoration: InputDecoration(
                                labelText: context.tr('Bedrooms'),
                              ),
                              validator: (value) =>
                                  int.tryParse(value ?? '') == null
                                  ? context.tr('Required')
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: bathrooms,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: context.tr('Bathrooms'),
                              ),
                              validator: (value) =>
                                  int.tryParse(value ?? '') == null
                                  ? context.tr('Required')
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<UnitStatus>(
                        initialValue: status,
                        decoration: InputDecoration(
                          labelText: context.tr('Availability'),
                          helperText: context.tr(status.helperText),
                        ),
                        items: [
                          for (final item in UnitStatus.values)
                            if (item != UnitStatus.occupied)
                              DropdownMenuItem(
                                value: item,
                                child: Text.localized(item.displayLabel),
                              ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => status = value);
                          }
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
                child: const Text.localized('Cancel'),
              ),
              AsyncActionButton.filled(
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
                child: const Text.localized('Save rental space'),
              ),
            ],
          ),
        );
      },
    );
    await dialogRoute?.completed;
    label.dispose();
    rent.dispose();
    bedrooms.dispose();
    bathrooms.dispose();
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text.localized(
            'Rental space saved locally and queued to sync.',
          ),
        ),
      );
    }
  }

  Future<void> _editUnit(Unit unit) async {
    final listingsValue = ref.read(landlordListingsProvider);
    if (listingsValue.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text.localized(
            'Listings could not be loaded. Try again before changing availability.',
          ),
        ),
      );
      return;
    }
    final listings = listingsValue.isLoading ? null : listingsValue.value;
    if (listings == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text.localized(
            'Listings are still loading. Try again in a moment.',
          ),
        ),
      );
      return;
    }
    final formKey = GlobalKey<FormState>();
    final label = TextEditingController(text: unit.label);
    final rent = TextEditingController(
      text: (unit.monthlyRentMinor ~/ 100).toString(),
    );
    final bedrooms = TextEditingController(text: unit.bedrooms.toString());
    final bathrooms = TextEditingController(text: unit.bathrooms.toString());
    var type = unit.type;
    var status = unit.status;
    final hasPublishedListing = listings.any(
      (listing) =>
          listing.unitId == unit.id &&
          listing.status == ListingStatus.published,
    );
    UpdateUnitResult? result;
    String? error;
    ModalRoute<bool>? dialogRoute;
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) {
        dialogRoute ??= ModalRoute.of<bool>(context);
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text.localized('Edit ${unit.displayName}'),
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
                        decoration: InputDecoration(
                          labelText: context.tr('Rental space name or number'),
                        ),
                        validator: (value) => (value?.trim().isEmpty ?? true)
                            ? context.tr('Enter a rental space name or number')
                            : null,
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<UnitType>(
                        initialValue: type,
                        decoration: InputDecoration(
                          labelText: context.tr('Rental space type'),
                        ),
                        items: [
                          for (final item in UnitType.values)
                            DropdownMenuItem(
                              value: item,
                              child: Text.localized(_titleCase(item.name)),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) setDialogState(() => type = value);
                        },
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<UnitStatus>(
                        initialValue: status,
                        decoration: InputDecoration(
                          labelText: context.tr('Availability'),
                          helperText: context.tr(
                            unit.status == UnitStatus.occupied
                                ? 'Managed by active tenancy'
                                : status.helperText,
                          ),
                        ),
                        items: [
                          for (final item in UnitStatus.values)
                            if (item != UnitStatus.occupied ||
                                unit.status == UnitStatus.occupied)
                              DropdownMenuItem(
                                value: item,
                                enabled: item != UnitStatus.occupied,
                                child: Text.localized(item.displayLabel),
                              ),
                        ],
                        onChanged: unit.status == UnitStatus.occupied
                            ? null
                            : (value) {
                                if (value != null) {
                                  setDialogState(() => status = value);
                                }
                              },
                      ),
                      if (hasPublishedListing &&
                          status != UnitStatus.vacant) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: context.nyumba.goldTint,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: context.nyumba.goldBorder,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.public_off_outlined,
                                size: 18,
                                color: context.nyumba.terracottaDark,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text.localized(
                                  'This change will remove the rental space from the public screen after server confirmation.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: rent,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: context.tr('Monthly rent'),
                          prefixText: 'UGX ',
                        ),
                        validator: (value) {
                          final amount = int.tryParse(
                            value?.replaceAll(',', '') ?? '',
                          );
                          return amount == null || amount <= 0
                              ? context.tr('Enter a valid rent amount')
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
                              decoration: InputDecoration(
                                labelText: context.tr('Bedrooms'),
                              ),
                              validator: (value) =>
                                  int.tryParse(value ?? '') == null
                                  ? context.tr('Required')
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: bathrooms,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: context.tr('Bathrooms'),
                              ),
                              validator: (value) =>
                                  int.tryParse(value ?? '') == null
                                  ? context.tr('Required')
                                  : null,
                            ),
                          ),
                        ],
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
                child: const Text.localized('Cancel'),
              ),
              AsyncActionButton.filled(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  try {
                    result = await ref.read(updateUnitProvider)(
                      unit.copyWith(
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
                child: const Text.localized('Save changes'),
              ),
            ],
          ),
        );
      },
    );
    await dialogRoute?.completed;
    label.dispose();
    rent.dispose();
    bedrooms.dispose();
    bathrooms.dispose();
    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text.localized(
            result?.unpublishedListing == null
                ? 'Rental space changes saved locally and queued to sync.'
                : 'Availability saved locally. The public listing is being removed.',
          ),
        ),
      );
    }
  }

  Future<void> _archiveUnit(Unit unit, List<Listing> listings) async {
    final blockingListing = listings.any(
      (listing) =>
          listing.unitId == unit.id &&
          (listing.status == ListingStatus.published ||
              (listing.status == ListingStatus.paused &&
                  listing.syncMetadata.state != EntitySyncState.synced)),
    );
    String? blocker;
    if (unit.status != UnitStatus.vacant) {
      blocker = 'End the active tenancy and return the space to vacant first.';
    } else if (blockingListing) {
      blocker = 'Unpublish the listing and wait for server confirmation first.';
    }
    if (blocker != null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text.localized('Rental space cannot be archived yet'),
          content: Text.localized(blocker!),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text.localized('Got it'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text.localized('Archive ${unit.displayName}?'),
        content: const Text.localized(
          'The rental space stays marked as archive pending until the server '
          'confirms it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text.localized('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: context.nyumba.danger,
            ),
            child: const Text.localized('Archive rental space'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(archiveUnitProvider)(unit.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text.localized(
            'Archive queued for ${unit.displayName}; awaiting server confirmation.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text.localized('Could not archive rental space: $error'),
        ),
      );
    }
  }

  Future<void> _archiveProperty(Property property) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(archivePropertyProvider)(property.id);
      if (!mounted) return;
      context.go('/properties');
      messenger.showSnackBar(
        SnackBar(
          content: Text.localized(
            'Archive queued for ${property.name}; awaiting server confirmation.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text.localized('Could not archive property: $error')),
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
        SnackBar(
          content: Text.localized('${draft.title} saved as a local draft.'),
        ),
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
          : const BorderRadiusDirectional.horizontal(
              start: Radius.circular(11),
            ),
      child: AspectRatio(
        aspectRatio: context.isCompact ? 2 : 1.5,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Semantics(
              label: context.tr('Property photos'),
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
                alignment: AlignmentDirectional.centerStart,
                child: _CarouselButton(
                  tooltip: context.tr('Previous photo'),
                  icon: Icons.chevron_left_rounded,
                  onPressed: () =>
                      _goTo((_currentIndex - 1 + imageCount) % imageCount),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _CarouselButton(
                  tooltip: context.tr('Next photo'),
                  icon: Icons.chevron_right_rounded,
                  onPressed: () => _goTo((_currentIndex + 1) % imageCount),
                ),
              ),
              PositionedDirectional(
                bottom: 12,
                start: 0,
                end: 0,
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
              PositionedDirectional(
                end: 12,
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
                  child: Text.localized(
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
          Text.localized(
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
        Text.localized(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _UnitCard extends StatelessWidget {
  const _UnitCard({
    required this.unit,
    required this.hasListing,
    required this.canAdvertise,
    required this.canUpdate,
    required this.canArchive,
    required this.onAdvertise,
    required this.onEdit,
    required this.onArchive,
  });

  final Unit unit;
  final bool hasListing;
  final bool canAdvertise;
  final bool canUpdate;
  final bool canArchive;
  final Future<void> Function() onAdvertise;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'en_UG',
      symbol: 'UGX ',
      decimalDigits: 0,
    );
    final (statusLabel, tone) = unit.isArchived
        ? unit.syncMetadata.state == EntitySyncState.failed ||
                  unit.syncMetadata.state == EntitySyncState.conflicted
              ? ('Archive needs attention', BadgeTone.danger)
              : ('Archive pending', BadgeTone.warning)
        : switch (unit.status) {
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
              if (!unit.isArchived && (canUpdate || canArchive)) ...[
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  tooltip: context.tr('Rental space actions'),
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'archive') onArchive();
                  },
                  itemBuilder: (context) => [
                    if (canUpdate)
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text.localized('Edit rental space'),
                      ),
                    if (canArchive)
                      const PopupMenuItem(
                        value: 'archive',
                        child: Text.localized('Archive rental space'),
                      ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          const SizedBox(height: 4),
          Text.localized(
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
              Text.localized(
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
              Text.localized(
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
              if (canAdvertise && unit.canBeAdvertised && !hasListing)
                AsyncActionButton.text(
                  onPressed: onAdvertise,
                  icon: const Icon(Icons.campaign_outlined, size: 18),
                  child: const Text.localized('Advertise'),
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
          const Text.localized('Property not found'),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onBack,
            child: const Text.localized('Back to properties'),
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
