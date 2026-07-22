import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations_adapter.dart';
import 'package:intl/intl.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import 'package:go_router/go_router.dart';
import '../../../core/domain/sync_metadata.dart';
import '../../../core/config/market_config.dart';
import '../../../core/presentation/page_header.dart';
import '../../../core/presentation/responsive.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/status_message.dart';
import '../../../core/presentation/surface.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/authorization_policy.dart';
import '../../portfolio/domain/property.dart';
import '../../portfolio/domain/unit.dart';
import '../../portfolio/application/rental_space_labels.dart';
import '../../subscriptions/application/subscription_providers.dart';
import '../../subscriptions/domain/landlord_entitlement.dart';
import '../../subscriptions/presentation/upgrade_prompt.dart';
import '../domain/application.dart';
import '../application/marketplace_use_cases.dart';
import '../domain/listing.dart';
import 'listing_visuals.dart';
import 'listing_photo_picker.dart';

class LandlordListingsScreen extends ConsumerStatefulWidget {
  const LandlordListingsScreen({super.key});

  @override
  ConsumerState<LandlordListingsScreen> createState() =>
      _LandlordListingsScreenState();
}

class _LandlordListingsScreenState
    extends ConsumerState<LandlordListingsScreen> {
  String _filter = 'All';
  bool _syncing = false;

  @override
  Widget build(BuildContext context) {
    final listingsValue = ref.watch(landlordListingsProvider);
    final unitsValue = ref.watch(portfolioUnitsProvider);
    final propertiesValue = ref.watch(portfolioPropertiesProvider);
    final outbox = ref.watch(outboxEntriesProvider);
    final applicationsValue = ref.watch(rentalApplicationsProvider);
    final applications = applicationsValue.value ?? const <RentalApplication>[];
    final pendingCount = outbox.value?.length ?? 0;
    final session = ref.watch(sessionControllerProvider);
    bool allows(CrudOperation operation) =>
        session != null &&
        AuthorizationPolicy.allowsSession(
          session,
          AppResource.privateListing,
          operation,
        );
    final canCreate = allows(CrudOperation.create);
    final canUpdate = allows(CrudOperation.update);
    final canUnpublish = allows(CrudOperation.delete);

    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.fromSTEB(
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
                title: 'Listings',
                description:
                    'Advertise vacant rental spaces and review incoming applications.',
                primaryAction: canCreate
                    ? FilledButton.icon(
                        onPressed:
                            unitsValue.value == null ||
                                propertiesValue.value == null
                            ? null
                            : () => _showCreateListing(
                                context,
                                unitsValue.value!,
                                propertiesValue.value!,
                              ),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text.localized('Create listing'),
                      )
                    : null,
                secondaryAction: OutlinedButton.icon(
                  onPressed: pendingCount == 0 || _syncing ? null : _sync,
                  icon: _syncing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded),
                  label: Text.localized(
                    pendingCount == 0
                        ? 'Everything synced'
                        : 'Sync $pendingCount',
                  ),
                ),
              ),
              const SizedBox(height: 22),
              if (pendingCount > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: NyumbaSurface(
                    backgroundColor: context.nyumba.goldTint,
                    borderColor: context.nyumba.goldBorder,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.cloud_upload_outlined,
                          color: context.nyumba.terracottaDark,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text.localized(
                            '$pendingCount local ${pendingCount == 1 ? 'change is' : 'changes are'} waiting to sync. Pending listings are never public before server acknowledgement.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (applications.isNotEmpty) ...[
                _ApplicationsInbox(applications: applications),
                const SizedBox(height: 18),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final filter in const [
                    'All',
                    'Published',
                    'Draft',
                    'Publishing',
                    'Paused',
                  ])
                    ChoiceChip(
                      label: Text.localized(filter),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              listingsValue.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stack) => NyumbaStatusMessage.fromError(
                  error,
                  localizations: appLocalizationsOf(context),
                  subject: appLocalizationsOf(context).statusSubjectYourListings,
                  onRetry: () => ref.invalidate(landlordListingsProvider),
                ),
                data: (allListings) {
                  final listings = allListings.where((listing) {
                    final publishing =
                        listing.status == ListingStatus.published &&
                        listing.syncMetadata.state != EntitySyncState.synced;
                    return switch (_filter) {
                      'Published' => listing.isPublic,
                      'Draft' => listing.status == ListingStatus.draft,
                      'Publishing' => publishing,
                      'Paused' => listing.status == ListingStatus.paused,
                      _ => true,
                    };
                  }).toList();
                  if (listings.isEmpty) {
                    return const NyumbaSurface(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: Text.localized(
                            'No listings match this filter.',
                          ),
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
                          for (final listing in listings)
                            SizedBox(
                              width: width,
                              child: _LandlordListingCard(
                                listing: listing,
                                applicationCount: applications
                                    .where(
                                      (item) => item.listingId == listing.id,
                                    )
                                    .length,
                                onPublish: () => _publish(listing),
                                onEdit: () => _editListing(listing),
                                onUnpublish: () => _unpublish(listing),
                                canPublish: canUpdate,
                                canEdit: canUpdate,
                                canUnpublish: canUnpublish,
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

  Future<void> _publish(Listing listing) async {
    // At the plan's active-listing limit, prompt for an upgrade instead of
    // queueing a publication the server would reject. Only a confirmed
    // entitlement blocks locally; an unknown plan leaves the server to judge.
    if (ref.read(landlordEntitlementProvider).value
        case EntitlementKnown(entitlement: final plan)) {
      final listings =
          ref.read(landlordListingsProvider).value ?? const <Listing>[];
      final activeCount = listings
          .where((l) => l.status == ListingStatus.published)
          .length;
      if (activeCount >= plan.activeListingLimit) {
        await showUpgradePrompt(
          context,
          title: 'Listing limit reached',
          message:
              'Your ${plan.displayName} plan allows up to '
              '${plan.activeListingLimit} active listings and all of them are '
              'in use. Unpublish a listing, or upgrade to advertise more at '
              'once.',
        );
        return;
      }
    }
    try {
      await ref.read(publishListingProvider)(listing.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text.localized(
              'Publication request saved locally. It will become public after server validation.',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text.localized('Could not publish: $error')),
        );
      }
    }
  }

  Future<void> _editListing(Listing listing) async {
    final formKey = GlobalKey<FormState>();
    final title = TextEditingController(text: listing.title);
    final description = TextEditingController(text: listing.description);
    final rent = TextEditingController(
      text: (listing.monthlyRentMinor ~/ 100).toString(),
    );
    final city = TextEditingController(text: listing.city);
    final neighborhood = TextEditingController(text: listing.neighborhood);
    final district = TextEditingController(text: listing.district);
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text.localized('Edit ${listing.title}'),
          content: SizedBox(
            width: 560,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: title,
                      decoration: InputDecoration(
                        labelText: context.tr('Listing title'),
                      ),
                      validator: (value) => (value?.trim().length ?? 0) < 3
                          ? context.tr('Enter a listing title')
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: description,
                      minLines: 3,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: context.tr('Description'),
                      ),
                      validator: (value) => (value?.trim().length ?? 0) < 10
                          ? context.tr('Add a useful description')
                          : null,
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
                    TextFormField(
                      controller: city,
                      decoration: InputDecoration(
                        labelText: context.tr('City'),
                      ),
                      validator: (value) => (value?.trim().isEmpty ?? true)
                          ? context.tr('Enter a city')
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: neighborhood,
                      decoration: InputDecoration(
                        labelText: context.tr('Neighborhood'),
                      ),
                      validator: (value) => (value?.trim().isEmpty ?? true)
                          ? context.tr('Enter a neighborhood')
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: district,
                      decoration: InputDecoration(
                        labelText: context.tr('District (optional)'),
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
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  await ref.read(updateListingProvider)(
                    listing.copyWith(
                      title: title.text.trim(),
                      description: description.text.trim(),
                      monthlyRentMinor:
                          int.parse(rent.text.replaceAll(',', '')) * 100,
                      city: city.text.trim(),
                      neighborhood: neighborhood.text.trim(),
                      district: district.text.trim(),
                      clearDistrict: district.text.trim().isEmpty,
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
      ),
    );
    title.dispose();
    description.dispose();
    rent.dispose();
    city.dispose();
    neighborhood.dispose();
    district.dispose();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text.localized(
            'Listing changes saved locally and queued to sync.',
          ),
        ),
      );
    }
  }

  Future<void> _unpublish(Listing listing) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text.localized('Unpublish ${listing.title}?'),
        content: const Text.localized(
          'The listing stays marked as unpublishing until the server removes '
          'its public projection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text.localized('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text.localized('Unpublish listing'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(unpublishListingProvider)(listing.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text.localized(
            'Unpublish request saved locally and awaiting server confirmation.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text.localized('Could not unpublish: $error')),
      );
    }
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final report = await ref.read(manualSyncProvider)();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text.localized(
              report.succeeded == 0
                  ? 'No changes were ready to sync.'
                  : '${report.succeeded} ${report.succeeded == 1 ? 'change' : 'changes'} synced successfully.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _showCreateListing(
    BuildContext context,
    List<Unit> units,
    List<Property> properties,
  ) async {
    final vacant = units.where((unit) => unit.canBeAdvertised).toList();
    if (vacant.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text.localized(
            'Add a vacant rental space before creating a listing.',
          ),
        ),
      );
      return;
    }
    final formKey = GlobalKey<FormState>();
    Unit selectedUnit = vacant.first;
    final propertyById = {
      for (final property in properties) property.id: property,
    };
    final title = TextEditingController(
      text:
          '${selectedUnit.displayName} at ${propertyById[selectedUnit.propertyId]?.name ?? 'My property'}',
    );
    final description = TextEditingController(
      text: 'A well maintained home in a convenient Kampala location.',
    );
    final phone = TextEditingController();
    final email = TextEditingController();
    final neighborhood = TextEditingController();
    final district = TextEditingController(text: 'Kampala');
    final latitude = TextEditingController();
    final longitude = TextEditingController();
    final floorArea = TextEditingController();
    final parkingSpaces = TextEditingController();
    final minimumLeaseMonths = TextEditingController(text: '12');
    final securityDeposit = TextEditingController();
    final serviceCharge = TextEditingController();
    final utilities = TextEditingController();
    final accessibility = TextEditingController();
    final petsPolicy = TextEditingController(text: 'Ask the landlord');
    final smokingPolicy = TextEditingController(text: 'No smoking indoors');
    final viewingInstructions = TextEditingController(
      text: 'Request a viewing through Nyumba.',
    );
    final selectedPhotos = <PickedListingPhoto>[];
    final videoUrl = TextEditingController();
    DateTime? availableFrom;
    bool furnished = false;
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text.localized('Create listing'),
          content: SizedBox(
            width: 520,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<Unit>(
                      initialValue: selectedUnit,
                      decoration: InputDecoration(
                        labelText: context.tr('Vacant rental space'),
                      ),
                      items: [
                        for (final unit in vacant)
                          DropdownMenuItem(
                            value: unit,
                            child: Text.localized(
                              '${unit.displayName} · ${propertyById[unit.propertyId]?.name ?? ''}',
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          selectedUnit = value;
                          title.text =
                              '${value.label} at ${propertyById[value.propertyId]?.name ?? 'My property'}';
                          district.text =
                              propertyById[value.propertyId]?.city ?? 'Kampala';
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: title,
                      decoration: InputDecoration(
                        labelText: context.tr('Listing title'),
                      ),
                      validator: (value) => (value?.trim().length ?? 0) < 5
                          ? context.tr('Enter a clear title')
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: description,
                      minLines: 3,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: context.tr('Description'),
                      ),
                      validator: (value) => (value?.trim().length ?? 0) < 15
                          ? context.tr('Add a little more detail')
                          : null,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: neighborhood,
                            decoration: InputDecoration(
                              labelText: context.tr('Neighborhood'),
                              helperText: context.tr(
                                'Public; do not enter an exact address',
                              ),
                            ),
                            validator: (value) => value?.trim().isEmpty ?? true
                                ? context.tr('Enter a public neighborhood')
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: district,
                            decoration: InputDecoration(
                              labelText: context.tr('District or city area'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: latitude,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            decoration: InputDecoration(
                              labelText: context.tr(
                                'Approx. latitude (optional)',
                              ),
                            ),
                            validator: (value) =>
                                _optionalLatitudeValidator(context, value),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: longitude,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            decoration: InputDecoration(
                              labelText: context.tr(
                                'Approx. longitude (optional)',
                              ),
                            ),
                            validator: (value) =>
                                _optionalLongitudeValidator(context, value),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final now = DateTime.now();
                        final date = await showDatePicker(
                          context: context,
                          firstDate: DateTime(now.year, now.month, now.day),
                          lastDate: now.add(const Duration(days: 730)),
                        );
                        if (date != null) {
                          setDialogState(() => availableFrom = date);
                        }
                      },
                      icon: const Icon(Icons.event_available_outlined),
                      label: Text.localized(
                        availableFrom == null
                            ? 'Choose availability date'
                            : 'Available ${DateFormat('d MMM y').format(availableFrom!)}',
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: floorArea,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: context.tr('Floor area (m²)'),
                            ),
                            validator: (value) =>
                                _optionalPositiveIntegerValidator(
                                  context,
                                  value,
                                ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: parkingSpaces,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: context.tr('Parking spaces'),
                            ),
                            validator: (value) =>
                                _optionalNonNegativeIntegerValidator(
                                  context,
                                  value,
                                ),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text.localized('Furnished'),
                      value: furnished,
                      onChanged: (value) =>
                          setDialogState(() => furnished = value),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: minimumLeaseMonths,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: context.tr('Minimum lease (months)'),
                            ),
                            validator: (value) =>
                                _optionalPositiveIntegerValidator(
                                  context,
                                  value,
                                ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: securityDeposit,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: context.tr('Security deposit (UGX)'),
                            ),
                            validator: (value) =>
                                _optionalNonNegativeIntegerValidator(
                                  context,
                                  value,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: serviceCharge,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.tr('Monthly service charge (UGX)'),
                      ),
                      validator: (value) =>
                          _optionalNonNegativeIntegerValidator(context, value),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: utilities,
                      decoration: InputDecoration(
                        labelText: context.tr('Utilities included'),
                        helperText: context.tr(
                          'Comma-separated, for example water, internet',
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: accessibility,
                      decoration: InputDecoration(
                        labelText: context.tr('Accessibility features'),
                        helperText: context.tr('Comma-separated'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: petsPolicy,
                            decoration: InputDecoration(
                              labelText: context.tr('Pets policy'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: smokingPolicy,
                            decoration: InputDecoration(
                              labelText: context.tr('Smoking policy'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: viewingInstructions,
                      minLines: 2,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: context.tr('Viewing instructions'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text.localized(
                        'Listing photos',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: OutlinedButton.icon(
                        onPressed: selectedPhotos.length >= listingPhotoLimit
                            ? null
                            : () async {
                                final result = await pickListingPhotos(
                                  remainingSlots:
                                      listingPhotoLimit - selectedPhotos.length,
                                );
                                if (!context.mounted) return;
                                setDialogState(
                                  () => selectedPhotos.addAll(result.photos),
                                );
                                if (result.rejectedMessages.isNotEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text.localized(
                                        result.rejectedMessages.join('\n'),
                                      ),
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: Text.localized(
                          selectedPhotos.isEmpty
                              ? 'Choose photos'
                              : 'Add more (${selectedPhotos.length}/$listingPhotoLimit)',
                        ),
                      ),
                    ),
                    if (selectedPhotos.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final photo in selectedPhotos)
                            InputChip(
                              avatar: CircleAvatar(
                                backgroundImage: MemoryImage(photo.bytes),
                              ),
                              label: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 150,
                                ),
                                child: Text(
                                  photo.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              onDeleted: () => setDialogState(
                                () => selectedPhotos.remove(photo),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    const Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text.localized(
                        'JPEG, PNG, or WebP; up to 5 MB each and 10 photos. '
                        'Selections stay in this local draft. Publishing stays '
                        'blocked until the production upload service replaces '
                        'them with server-owned media references.',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: videoUrl,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: context.tr(
                          'Video or virtual-tour URL (optional)',
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: context.tr('Contact phone'),
                      ),
                      validator: (value) => (value?.trim().length ?? 0) < 7
                          ? email.text.trim().isEmpty
                                ? context.tr(
                                    'Enter a phone or email for routed enquiries',
                                  )
                                : null
                          : !NyumbaMarket.isValidPhone(value!.trim())
                          ? context.tr('Use the Ugandan +256 format')
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: context.tr(
                          'Private contact email (optional)',
                        ),
                        helperText: context.tr(
                          'Used for routed enquiries; not shown publicly',
                        ),
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty && phone.text.trim().isEmpty) {
                          return context.tr(
                            'Enter a phone or email for routed enquiries',
                          );
                        }
                        return text.isNotEmpty && !text.contains('@')
                            ? context.tr('Enter a valid email')
                            : null;
                      },
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: StatusBadge(
                        label: switch (ref
                            .read(landlordEntitlementProvider)
                            .value) {
                          EntitlementKnown(entitlement: final plan) =>
                            'Advertising enabled · ${plan.displayName} plan',
                          _ => 'Advertising follows your subscription plan',
                        },
                        tone: BadgeTone.success,
                      ),
                    ),
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
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text.localized('Save draft'),
            ),
          ],
        ),
      ),
    );
    if (created == true) {
      await ref.read(createListingDraftProvider)(
        CreateListingInput(
          unitId: selectedUnit.id,
          propertyId: selectedUnit.propertyId,
          landlordId: selectedUnit.landlordId,
          title: title.text.trim(),
          description: description.text.trim(),
          monthlyRentMinor: selectedUnit.monthlyRentMinor,
          currency: selectedUnit.currency,
          city: propertyById[selectedUnit.propertyId]?.city ?? 'Kampala',
          district: district.text.trim(),
          neighborhood: neighborhood.text.trim(),
          approximateLatitude: _optionalDouble(latitude.text),
          approximateLongitude: _optionalDouble(longitude.text),
          availableFrom: availableFrom,
          floorAreaSquareMetres: _optionalInt(floorArea.text),
          furnished: furnished,
          parkingSpaces: _optionalInt(parkingSpaces.text),
          minimumLeaseMonths: _optionalInt(minimumLeaseMonths.text),
          securityDepositMinor: _optionalMoneyMinor(securityDeposit.text),
          serviceChargeMinor: _optionalMoneyMinor(serviceCharge.text),
          utilitiesIncluded: _splitCommaSeparated(utilities.text),
          accessibilityFeatures: _splitCommaSeparated(accessibility.text),
          petsPolicy: petsPolicy.text.trim(),
          smokingPolicy: smokingPolicy.text.trim(),
          viewingInstructions: viewingInstructions.text.trim(),
          imageUrls: selectedPhotos.map((photo) => photo.dataUri).toList(),
          videoUrl: videoUrl.text.trim(),
          contactPhone: phone.text.trim(),
          contactEmail: email.text.trim(),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          const SnackBar(
            content: Text.localized(
              'Draft saved locally. You can publish it when ready.',
            ),
          ),
        );
      }
    }
    title.dispose();
    description.dispose();
    phone.dispose();
    email.dispose();
    neighborhood.dispose();
    district.dispose();
    latitude.dispose();
    longitude.dispose();
    floorArea.dispose();
    parkingSpaces.dispose();
    minimumLeaseMonths.dispose();
    securityDeposit.dispose();
    serviceCharge.dispose();
    utilities.dispose();
    accessibility.dispose();
    petsPolicy.dispose();
    smokingPolicy.dispose();
    viewingInstructions.dispose();
    videoUrl.dispose();
  }
}

int? _optionalInt(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : int.tryParse(normalized);
}

double? _optionalDouble(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : double.tryParse(normalized);
}

int? _optionalMoneyMinor(String value) {
  final amount = _optionalInt(value.replaceAll(',', ''));
  return amount == null ? null : amount * 100;
}

List<String> _splitCommaSeparated(String value) => value
    .split(',')
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toList(growable: false);

String? _optionalPositiveIntegerValidator(BuildContext context, String? value) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) return null;
  final number = int.tryParse(normalized);
  return number == null || number <= 0
      ? context.tr('Enter a positive whole number')
      : null;
}

String? _optionalNonNegativeIntegerValidator(
  BuildContext context,
  String? value,
) {
  final normalized = value?.trim().replaceAll(',', '') ?? '';
  if (normalized.isEmpty) return null;
  final number = int.tryParse(normalized);
  return number == null || number < 0
      ? context.tr('Enter zero or a positive number')
      : null;
}

String? _optionalLatitudeValidator(BuildContext context, String? value) =>
    _optionalCoordinateValidator(context, value, -90, 90);

String? _optionalLongitudeValidator(BuildContext context, String? value) =>
    _optionalCoordinateValidator(context, value, -180, 180);

String? _optionalCoordinateValidator(
  BuildContext context,
  String? value,
  double minimum,
  double maximum,
) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) return null;
  final number = double.tryParse(normalized);
  return number == null || number < minimum || number > maximum
      ? context.tr('Enter a value from $minimum to $maximum')
      : null;
}

class _LandlordListingCard extends StatelessWidget {
  const _LandlordListingCard({
    required this.listing,
    required this.applicationCount,
    required this.onPublish,
    required this.onEdit,
    required this.onUnpublish,
    required this.canPublish,
    required this.canEdit,
    required this.canUnpublish,
  });

  final Listing listing;
  final int applicationCount;
  final VoidCallback onPublish;
  final VoidCallback onEdit;
  final VoidCallback onUnpublish;
  final bool canPublish;
  final bool canEdit;
  final bool canUnpublish;

  @override
  Widget build(BuildContext context) {
    final publishing =
        listing.status == ListingStatus.published &&
        listing.syncMetadata.state != EntitySyncState.synced;
    final unpublishing =
        listing.status == ListingStatus.paused &&
        listing.syncMetadata.state != EntitySyncState.synced;
    final (label, tone) = publishing
        ? ('Publishing', BadgeTone.warning)
        : unpublishing
        ? ('Unpublishing', BadgeTone.warning)
        : listing.isPublic
        ? ('Published', BadgeTone.success)
        : listing.status == ListingStatus.paused
        ? ('Paused', BadgeTone.neutral)
        : ('Draft', BadgeTone.neutral);
    final currency = NumberFormat.currency(
      locale: 'en_UG',
      symbol: 'UGX ',
      decimalDigits: 0,
    );
    return NyumbaSurface(
      padding: EdgeInsets.zero,
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
                  aspectRatio: 3 / 2,
                  child: listingImage(listing, fit: BoxFit.cover),
                ),
              ),
              PositionedDirectional(
                start: 12,
                top: 12,
                child: StatusBadge(label: label, tone: tone),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  listing.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text.localized(
                  currency.format(listing.monthlyRentMinor / 100),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: context.nyumba.midnightNavy,
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.people_outline_rounded,
                      size: 18,
                      color: context.nyumba.mutedInk,
                    ),
                    const SizedBox(width: 6),
                    Text.localized(
                      '$applicationCount ${applicationCount == 1 ? 'application' : 'applications'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    if (canPublish &&
                        (listing.status == ListingStatus.draft ||
                            (listing.status == ListingStatus.paused &&
                                listing.syncMetadata.state ==
                                    EntitySyncState.synced)))
                      TextButton(
                        onPressed: onPublish,
                        child: const Text.localized('Publish'),
                      ),
                    PopupMenuButton<String>(
                      tooltip: context.tr('Listing actions'),
                      onSelected: (value) {
                        if (value == 'view') {
                          context.go('/listing/${listing.id}');
                        } else if (value == 'details') {
                          showDialog<void>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: Text(listing.title),
                              content: Text.localized(
                                '${listingLocationFor(listing)}\n\n'
                                '$applicationCount application${applicationCount == 1 ? '' : 's'}\n'
                                '${listing.isPublic ? 'Server-confirmed public listing.' : 'Awaiting server acknowledgement.'}',
                              ),
                              actions: [
                                FilledButton(
                                  onPressed: () => Navigator.pop(dialogContext),
                                  child: const Text.localized('Close'),
                                ),
                              ],
                            ),
                          );
                        } else if (value == 'unpublish') {
                          onUnpublish();
                        } else if (value == 'edit') {
                          onEdit();
                        }
                      },
                      itemBuilder: (context) => [
                        if (listing.isPublic)
                          const PopupMenuItem(
                            value: 'view',
                            child: Text.localized('View public listing'),
                          ),
                        const PopupMenuItem(
                          value: 'details',
                          child: Text.localized('Listing details'),
                        ),
                        if (canEdit &&
                            listing.status != ListingStatus.published &&
                            !unpublishing)
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text.localized('Edit listing'),
                          ),
                        if (listing.status == ListingStatus.published &&
                            canUnpublish)
                          const PopupMenuItem(
                            value: 'unpublish',
                            child: Text.localized('Unpublish listing'),
                          ),
                      ],
                    ),
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

class _ApplicationsInbox extends StatelessWidget {
  const _ApplicationsInbox({required this.applications});

  final List<RentalApplication> applications;

  @override
  Widget build(BuildContext context) {
    final latest = applications.first;
    return NyumbaSurface(
      backgroundColor: context.nyumba.navyTint,
      borderColor: context.nyumba.navyBorder,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: context.nyumba.midnightNavy,
            foregroundColor: context.nyumba.surface,
            child: const Icon(Icons.mark_email_unread_outlined, size: 20),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.localized(
                  '${applications.length} ${applications.length == 1 ? 'application' : 'applications'} received',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 3),
                Text.localized(
                  'Latest from ${latest.applicantName} · ${latest.applicantPhone}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (!context.isCompact)
            TextButton(
              onPressed: () => _showApplications(context, applications),
              child: const Text.localized('Review applications'),
            )
          else
            IconButton(
              tooltip: context.tr('Review applications'),
              onPressed: () => _showApplications(context, applications),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
        ],
      ),
    );
  }
}

void _showApplications(
  BuildContext context,
  List<RentalApplication> applications,
) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 640),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text.localized(
                'Rental applications',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: applications.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final application = applications[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: context.nyumba.navyTint,
                        foregroundColor: context.nyumba.midnightNavy,
                        child: Text(application.applicantName[0].toUpperCase()),
                      ),
                      title: Text(application.applicantName),
                      subtitle: Text.localized(
                        '${application.applicantEmail}\n${application.applicantPhone}${application.message == null ? '' : ' · ${application.message}'}',
                      ),
                      isThreeLine: true,
                      trailing: StatusBadge(
                        label:
                            application.syncMetadata.state ==
                                EntitySyncState.synced
                            ? 'Received'
                            : 'Pending sync',
                        tone:
                            application.syncMetadata.state ==
                                EntitySyncState.synced
                            ? BadgeTone.success
                            : BadgeTone.warning,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
