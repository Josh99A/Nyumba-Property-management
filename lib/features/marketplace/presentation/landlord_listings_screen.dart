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
import '../../../core/presentation/action_failure.dart';
import '../../../core/presentation/async_action_button.dart';
import '../../../core/presentation/page_header.dart';
import '../../../core/presentation/photo_editor_field.dart';
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
                    ? AsyncActionButton.filled(
                        onPressed:
                            unitsValue.value == null ||
                                propertiesValue.value == null
                            ? null
                            : () => _showCreateListing(
                                context,
                                unitsValue.value!,
                                propertiesValue.value!,
                              ),
                        showBusyIndicator: false,
                        icon: const Icon(Icons.add_rounded),
                        child: const Text.localized('Create listing'),
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
                  subject: appLocalizationsOf(
                    context,
                  ).statusSubjectYourListings,
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
    if (ref.read(landlordEntitlementProvider).value case EntitlementKnown(
      entitlement: final plan,
    )) {
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
    final fields = _ListingFields.from(listing);
    ActionFailure? failure;
    ModalRoute<bool>? dialogRoute;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        dialogRoute ??= ModalRoute.of<bool>(context);
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text.localized('Edit ${listing.title}'),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Form(
                      key: formKey,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: fields.build(
                            context,
                            setDialogState,
                            includeRentAndCity: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                  PickProblemsNotice(problems: fields.photoProblems),
                  if (failure != null) ActionFailureNotice(failure: failure!),
                ],
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
                    await ref.read(updateListingProvider)(
                      listing.copyWith(
                        title: fields.title.text.trim(),
                        description: fields.description.text.trim(),
                        monthlyRentMinor:
                            int.parse(fields.rent.text.replaceAll(',', '')) *
                            100,
                        city: fields.city.text.trim(),
                        neighborhood: fields.neighborhood.text.trim(),
                        clearNeighborhood: fields.neighborhood.text
                            .trim()
                            .isEmpty,
                        district: fields.district.text.trim(),
                        clearDistrict: fields.district.text.trim().isEmpty,
                        approximateLatitude: _optionalDouble(
                          fields.latitude.text,
                        ),
                        clearApproximateLatitude:
                            _optionalDouble(fields.latitude.text) == null,
                        approximateLongitude: _optionalDouble(
                          fields.longitude.text,
                        ),
                        clearApproximateLongitude:
                            _optionalDouble(fields.longitude.text) == null,
                        availableFrom: fields.availableFrom,
                        clearAvailableFrom: fields.availableFrom == null,
                        floorAreaSquareMetres: _optionalInt(
                          fields.floorArea.text,
                        ),
                        clearFloorAreaSquareMetres:
                            _optionalInt(fields.floorArea.text) == null,
                        furnished: fields.furnished,
                        parkingSpaces: _optionalInt(fields.parkingSpaces.text),
                        clearParkingSpaces:
                            _optionalInt(fields.parkingSpaces.text) == null,
                        minimumLeaseMonths: _optionalInt(
                          fields.minimumLeaseMonths.text,
                        ),
                        clearMinimumLeaseMonths:
                            _optionalInt(fields.minimumLeaseMonths.text) ==
                            null,
                        securityDepositMinor: _optionalMoneyMinor(
                          fields.securityDeposit.text,
                        ),
                        clearSecurityDepositMinor:
                            _optionalMoneyMinor(fields.securityDeposit.text) ==
                            null,
                        serviceChargeMinor: _optionalMoneyMinor(
                          fields.serviceCharge.text,
                        ),
                        clearServiceChargeMinor:
                            _optionalMoneyMinor(fields.serviceCharge.text) ==
                            null,
                        utilitiesIncluded: _splitCommaSeparated(
                          fields.utilities.text,
                        ),
                        accessibilityFeatures: _splitCommaSeparated(
                          fields.accessibility.text,
                        ),
                        petsPolicy: fields.petsPolicy.text.trim(),
                        clearPetsPolicy: fields.petsPolicy.text.trim().isEmpty,
                        smokingPolicy: fields.smokingPolicy.text.trim(),
                        clearSmokingPolicy: fields.smokingPolicy.text
                            .trim()
                            .isEmpty,
                        viewingInstructions: fields.viewingInstructions.text
                            .trim(),
                        clearViewingInstructions: fields
                            .viewingInstructions
                            .text
                            .trim()
                            .isEmpty,
                        imageUrls: fields.photos.toImageUrls(),
                        videoUrl: fields.videoUrl.text.trim(),
                        clearVideoUrl: fields.videoUrl.text.trim().isEmpty,
                        contactPhone: fields.phone.text.trim(),
                        clearContactPhone: fields.phone.text.trim().isEmpty,
                        contactEmail: fields.email.text.trim(),
                        clearContactEmail: fields.email.text.trim().isEmpty,
                      ),
                    );
                    if (context.mounted) Navigator.pop(context, true);
                  } on Object catch (caught) {
                    if (!context.mounted) return;
                    setDialogState(
                      () => failure = describeActionFailure(
                        caught,
                        action: context.tr('save these listing changes'),
                      ),
                    );
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
    fields.dispose();
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
    final fields = _ListingFields.blank(
      titleSeed:
          '${selectedUnit.displayName} at ${propertyById[selectedUnit.propertyId]?.name ?? 'My property'}',
      districtSeed: 'Kampala',
    );
    // Photo rejections and a refused save are different things and are shown
    // differently. Both are pinned below the scroll view, because a snack bar
    // raised from inside a dialog surfaces behind the modal barrier where it
    // is easy to miss entirely.
    ActionFailure? failure;
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text.localized('Create listing'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
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
                                fields.title.text =
                                    '${value.label} at ${propertyById[value.propertyId]?.name ?? 'My property'}';
                                fields.district.text =
                                    propertyById[value.propertyId]?.city ??
                                    'Kampala';
                              });
                            },
                          ),
                          const SizedBox(height: 14),
                          ...fields.build(
                            context,
                            setDialogState,
                            includeRentAndCity: false,
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
                                _ =>
                                  'Advertising follows your subscription plan',
                              },
                              tone: BadgeTone.success,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                PickProblemsNotice(problems: fields.photoProblems),
                if (failure != null) ActionFailureNotice(failure: failure!),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text.localized('Cancel'),
            ),
            AsyncActionButton.filled(
              // The draft is written here rather than after the dialog closes.
              // It used to be saved on the way out with nothing catching a
              // throw, so a rejected draft closed the dialog, discarded every
              // field the landlord had typed, and said nothing at all.
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  await ref.read(createListingDraftProvider)(
                    CreateListingInput(
                      unitId: selectedUnit.id,
                      propertyId: selectedUnit.propertyId,
                      landlordId: selectedUnit.landlordId,
                      title: fields.title.text.trim(),
                      description: fields.description.text.trim(),
                      monthlyRentMinor: selectedUnit.monthlyRentMinor,
                      currency: selectedUnit.currency,
                      city:
                          propertyById[selectedUnit.propertyId]?.city ??
                          'Kampala',
                      district: fields.district.text.trim(),
                      neighborhood: fields.neighborhood.text.trim(),
                      approximateLatitude: _optionalDouble(
                        fields.latitude.text,
                      ),
                      approximateLongitude: _optionalDouble(
                        fields.longitude.text,
                      ),
                      availableFrom: fields.availableFrom,
                      floorAreaSquareMetres: _optionalInt(
                        fields.floorArea.text,
                      ),
                      furnished: fields.furnished,
                      parkingSpaces: _optionalInt(fields.parkingSpaces.text),
                      minimumLeaseMonths: _optionalInt(
                        fields.minimumLeaseMonths.text,
                      ),
                      securityDepositMinor: _optionalMoneyMinor(
                        fields.securityDeposit.text,
                      ),
                      serviceChargeMinor: _optionalMoneyMinor(
                        fields.serviceCharge.text,
                      ),
                      utilitiesIncluded: _splitCommaSeparated(
                        fields.utilities.text,
                      ),
                      accessibilityFeatures: _splitCommaSeparated(
                        fields.accessibility.text,
                      ),
                      petsPolicy: fields.petsPolicy.text.trim(),
                      smokingPolicy: fields.smokingPolicy.text.trim(),
                      viewingInstructions: fields.viewingInstructions.text
                          .trim(),
                      imageUrls: fields.photos.toImageUrls(),
                      videoUrl: fields.videoUrl.text.trim(),
                      contactPhone: fields.phone.text.trim(),
                      contactEmail: fields.email.text.trim(),
                    ),
                  );
                  if (context.mounted) Navigator.pop(context, true);
                } on Object catch (caught) {
                  if (!context.mounted) return;
                  setDialogState(
                    () => failure = describeActionFailure(
                      caught,
                      action: context.tr('save this listing draft'),
                    ),
                  );
                }
              },
              child: const Text.localized('Save draft'),
            ),
          ],
        ),
      ),
    );
    if (created == true) {
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
    fields.dispose();
  }
}

/// Every editable listing field, in one place.
///
/// The create and edit dialogs both build their form from this, so the two
/// cannot drift on what a landlord is allowed to change. That drift is exactly
/// why editing used to expose six fields out of twenty-odd, and offered no way
/// to touch the photos at all.
class _ListingFields {
  _ListingFields._();

  /// A new draft, pre-filled with the defaults the create dialog has always
  /// used.
  factory _ListingFields.blank({
    required String titleSeed,
    required String districtSeed,
  }) {
    final fields = _ListingFields._();
    fields.title.text = titleSeed;
    fields.description.text =
        'A well maintained home in a convenient Kampala location.';
    fields.district.text = districtSeed;
    fields.minimumLeaseMonths.text = '12';
    fields.petsPolicy.text = 'Ask the landlord';
    fields.smokingPolicy.text = 'No smoking indoors';
    fields.viewingInstructions.text = 'Request a viewing through Nyumba.';
    return fields;
  }

  /// An existing listing opened for editing.
  factory _ListingFields.from(Listing listing) {
    final fields = _ListingFields._();
    fields.title.text = listing.title;
    fields.description.text = listing.description;
    fields.rent.text = (listing.monthlyRentMinor ~/ 100).toString();
    fields.city.text = listing.city;
    fields.neighborhood.text = listing.neighborhood ?? '';
    fields.district.text = listing.district ?? '';
    fields.latitude.text = listing.approximateLatitude?.toString() ?? '';
    fields.longitude.text = listing.approximateLongitude?.toString() ?? '';
    fields.floorArea.text = listing.floorAreaSquareMetres?.toString() ?? '';
    fields.parkingSpaces.text = listing.parkingSpaces?.toString() ?? '';
    fields.minimumLeaseMonths.text =
        listing.minimumLeaseMonths?.toString() ?? '';
    fields.securityDeposit.text = listing.securityDepositMinor == null
        ? ''
        : (listing.securityDepositMinor! ~/ 100).toString();
    fields.serviceCharge.text = listing.serviceChargeMinor == null
        ? ''
        : (listing.serviceChargeMinor! ~/ 100).toString();
    fields.utilities.text = listing.utilitiesIncluded.join(', ');
    fields.accessibility.text = listing.accessibilityFeatures.join(', ');
    fields.petsPolicy.text = listing.petsPolicy ?? '';
    fields.smokingPolicy.text = listing.smokingPolicy ?? '';
    fields.viewingInstructions.text = listing.viewingInstructions ?? '';
    fields.videoUrl.text = listing.videoUrl ?? '';
    fields.phone.text = listing.contactPhone ?? '';
    fields.email.text = listing.contactEmail ?? '';
    fields.photos.existing.addAll(listing.imageUrls);
    fields.availableFrom = listing.availableFrom;
    fields.furnished = listing.furnished;
    return fields;
  }

  final title = TextEditingController();
  final description = TextEditingController();
  final rent = TextEditingController();
  final city = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  final neighborhood = TextEditingController();
  final district = TextEditingController();
  final latitude = TextEditingController();
  final longitude = TextEditingController();
  final floorArea = TextEditingController();
  final parkingSpaces = TextEditingController();
  final minimumLeaseMonths = TextEditingController();
  final securityDeposit = TextEditingController();
  final serviceCharge = TextEditingController();
  final utilities = TextEditingController();
  final accessibility = TextEditingController();
  final petsPolicy = TextEditingController();
  final smokingPolicy = TextEditingController();
  final viewingInstructions = TextEditingController();
  final videoUrl = TextEditingController();
  final photos = EditablePhotoSet();

  DateTime? availableFrom;
  bool furnished = false;

  /// Files the last chooser trip left out, surfaced by the host dialog.
  var photoProblems = const <String>[];

  /// The form body.
  ///
  /// [includeRentAndCity] is the one real difference between the two callers:
  /// a new draft takes its rent and city from the chosen unit and its
  /// property, while an existing listing carries its own and can edit them.
  List<Widget> build(
    BuildContext context,
    StateSetter setDialogState, {
    required bool includeRentAndCity,
  }) => [
    TextFormField(
      controller: title,
      decoration: InputDecoration(labelText: context.tr('Listing title')),
      validator: (value) => (value?.trim().length ?? 0) < 5
          ? context.tr('Enter a clear title')
          : null,
    ),
    const SizedBox(height: 14),
    TextFormField(
      controller: description,
      minLines: 3,
      maxLines: 5,
      decoration: InputDecoration(labelText: context.tr('Description')),
      validator: (value) => (value?.trim().length ?? 0) < 15
          ? context.tr('Add a little more detail')
          : null,
    ),
    if (includeRentAndCity) ...[
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: rent,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.tr('Monthly rent'),
                prefixText: 'UGX ',
              ),
              validator: (value) {
                final amount = int.tryParse(value?.replaceAll(',', '') ?? '');
                return amount == null || amount <= 0
                    ? context.tr('Enter a valid rent amount')
                    : null;
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: city,
              decoration: InputDecoration(labelText: context.tr('City')),
              validator: (value) => (value?.trim().isEmpty ?? true)
                  ? context.tr('Enter a city')
                  : null,
            ),
          ),
        ],
      ),
    ],
    const SizedBox(height: 14),
    Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: neighborhood,
            decoration: InputDecoration(
              labelText: context.tr('Neighborhood'),
              helperText: context.tr('Public; do not enter an exact address'),
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
              labelText: context.tr('Approx. latitude (optional)'),
            ),
            validator: (value) => _optionalLatitudeValidator(context, value),
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
              labelText: context.tr('Approx. longitude (optional)'),
            ),
            validator: (value) => _optionalLongitudeValidator(context, value),
          ),
        ),
      ],
    ),
    const SizedBox(height: 14),
    AsyncActionButton.outlined(
      showBusyIndicator: false,
      onPressed: () async {
        final now = DateTime.now();
        final date = await showDatePicker(
          context: context,
          initialDate: availableFrom,
          firstDate: DateTime(now.year, now.month, now.day),
          lastDate: now.add(const Duration(days: 730)),
        );
        if (date != null) setDialogState(() => availableFrom = date);
      },
      icon: const Icon(Icons.event_available_outlined),
      child: Text.localized(
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
                _optionalPositiveIntegerValidator(context, value),
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
                _optionalNonNegativeIntegerValidator(context, value),
          ),
        ),
      ],
    ),
    SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: const Text.localized('Furnished'),
      value: furnished,
      onChanged: (value) => setDialogState(() => furnished = value),
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
                _optionalPositiveIntegerValidator(context, value),
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
                _optionalNonNegativeIntegerValidator(context, value),
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
        helperText: context.tr('Comma-separated, for example water, internet'),
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
            decoration: InputDecoration(labelText: context.tr('Pets policy')),
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
      child: PhotoEditorField(
        label: 'Listing photos',
        photos: photos,
        limit: listingPhotoLimit,
        pick: pickListingPhotos,
        onChanged: (problems) => setDialogState(() => photoProblems = problems),
        helperText:
            'JPEG, PNG, or WebP; up to 5 MB each and 5 photos. The first '
            'photo is the cover image. Photos remain pending until upload '
            'is confirmed.',
      ),
    ),
    const SizedBox(height: 14),
    TextFormField(
      controller: videoUrl,
      keyboardType: TextInputType.url,
      decoration: InputDecoration(
        labelText: context.tr('Video or virtual-tour URL (optional)'),
      ),
    ),
    const SizedBox(height: 14),
    TextFormField(
      controller: phone,
      keyboardType: TextInputType.phone,
      decoration: InputDecoration(labelText: context.tr('Contact phone')),
      validator: (value) => (value?.trim().length ?? 0) < 7
          ? email.text.trim().isEmpty
                ? context.tr('Enter a phone or email for routed enquiries')
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
        labelText: context.tr('Private contact email (optional)'),
        helperText: context.tr('Used for routed enquiries; not shown publicly'),
      ),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (text.isEmpty && phone.text.trim().isEmpty) {
          return context.tr('Enter a phone or email for routed enquiries');
        }
        return text.isNotEmpty && !text.contains('@')
            ? context.tr('Enter a valid email')
            : null;
      },
    ),
  ];

  void dispose() {
    for (final controller in [
      title,
      description,
      rent,
      city,
      phone,
      email,
      neighborhood,
      district,
      latitude,
      longitude,
      floorArea,
      parkingSpaces,
      minimumLeaseMonths,
      securityDeposit,
      serviceCharge,
      utilities,
      accessibility,
      petsPolicy,
      smokingPolicy,
      viewingInstructions,
      videoUrl,
    ]) {
      controller.dispose();
    }
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
