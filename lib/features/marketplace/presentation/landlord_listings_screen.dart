import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations_adapter.dart';
import 'package:intl/intl.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../core/cloud/cloud_async.dart';
import '../../../app/theme/nyumba_colors.dart';
import 'package:go_router/go_router.dart';
import '../../../core/domain/coordinates.dart';
import '../../../core/domain/domain_exception.dart';
import '../../../core/domain/sync_metadata.dart';
import '../../../core/presentation/action_failure.dart';
import '../../../core/presentation/async_action_button.dart';
import '../../../core/presentation/cloud_data_view.dart';
import '../../../core/presentation/location_picker.dart';
import '../../../core/presentation/page_header.dart';
import '../../../core/presentation/photo_editor_field.dart';
import '../../../core/presentation/responsive.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/status_message.dart';
import '../../../core/presentation/surface.dart';
import '../../../core/presentation/toast.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/authorization_policy.dart';
import '../../portfolio/domain/property.dart';
import '../../portfolio/domain/unit.dart';
import '../../portfolio/application/rental_space_labels.dart';
import '../../subscriptions/application/subscription_providers.dart';
import '../../subscriptions/domain/landlord_entitlement.dart';
import '../domain/application.dart';
import '../application/marketplace_use_cases.dart';
import '../domain/listing.dart';
import 'listing_publication.dart';
import 'listing_visuals.dart';
import 'listing_photo_picker.dart';
import 'publish_actions.dart';

class LandlordListingsScreen extends ConsumerStatefulWidget {
  const LandlordListingsScreen({super.key, this.initialUnitId});

  /// Opens the create editor for this vacant space once its cloud context has
  /// loaded. Used by the property detail "Advertise" action.
  final String? initialUnitId;

  @override
  ConsumerState<LandlordListingsScreen> createState() =>
      _LandlordListingsScreenState();
}

class _LandlordListingsScreenState
    extends ConsumerState<LandlordListingsScreen> {
  String _filter = 'All';
  bool _initialCreateHandled = false;

  @override
  Widget build(BuildContext context) {
    final listingsValue = ref.watch(landlordListingsProvider);
    final unitsValue = ref.watch(portfolioUnitsProvider);
    final propertiesValue = ref.watch(portfolioPropertiesProvider);
    final applicationsValue = ref.watch(rentalApplicationsProvider);
    final applications = applicationsValue.value ?? const <RentalApplication>[];
    // The outbox counters that used to live here are gone. "Sync 3", "3
    // uploading", "1 stuck" all described adverts whose changes had not reached
    // the server; a publish now either lands while the landlord waits or fails
    // in front of them, so there is nothing left to count.
    final copy = appLocalizationsOf(context);
    // Resolved once for the whole page so the banner, the filter chips and the
    // cards can never disagree about which adverts are actually live.
    final publications = <String, ListingPublication>{
      for (final listing in listingsValue.supportingRecords)
        listing.id: resolveListingPublication(listing: listing, copy: copy),
    };
    // The "Needs attention" and "Going live" chips are gone with the states
    // they filtered on. Both described adverts mid-delivery, and delivery is no
    // longer something an advert can be in the middle of.
    if (_filter == 'Needs attention' || _filter == 'Going live') {
      _filter = 'All';
    }
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

    if (!_initialCreateHandled &&
        widget.initialUnitId != null &&
        unitsValue.value != null &&
        propertiesValue.value != null) {
      _initialCreateHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _showCreateListing(
          this.context,
          unitsValue.supportingRecords,
          propertiesValue.supportingRecords,
          initialUnitId: widget.initialUnitId,
        );
        if (mounted) {
          // Clear the one-shot query after the editor closes, so later rebuilds
          // cannot reopen a form the landlord already handled.
          this.context.replace('/listings');
        }
      });
    }

    // Counted once instead of re-scanning every application for every card.
    final applicationsByListing = <String, int>{};
    for (final item in applications) {
      applicationsByListing[item.listingId] =
          (applicationsByListing[item.listingId] ?? 0) + 1;
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1360),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsetsDirectional.fromSTEB(
                context.pageGutter,
                26,
                context.pageGutter,
                0,
              ),
              sliver: SliverList.list(
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
                                    unitsValue.supportingRecords,
                                    propertiesValue.supportingRecords,
                                  ),
                            showBusyIndicator: false,
                            icon: const Icon(Icons.add_rounded),
                            child: const Text.localized('Create listing'),
                          )
                        : null,
                    // The manual "Sync" button is gone. It existed to flush a
                    // queue of adverts waiting to reach the server; there is no
                    // queue now, so pressing it could only ever have been a
                    // no-op dressed up as an action.
                  ),
                  const SizedBox(height: 22),
                  if (listingsValue.cloudData case final cloud?) ...[
                    CloudFreshnessBanner<List<Listing>>(
                      data: cloud,
                      onRetry: () async =>
                          ref.invalidate(landlordListingsProvider),
                    ),
                    const SizedBox(height: 14),
                  ],
                  // The 'adverts did not go through' banner is gone with the
                  // outbox that produced it. A refusal is now shown at the
                  // moment the landlord attempts the change, not as a standing
                  // condition on a card they have to go hunting for.
                  if (applications.isNotEmpty) ...[
                    _ApplicationsInbox(applications: applications),
                    const SizedBox(height: 18),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final filter in <String>[
                        'All',
                        'Published',
                        'Draft',
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
                ],
              ),
            ),
            SliverPadding(
              padding: EdgeInsetsDirectional.fromSTEB(
                context.pageGutter,
                0,
                context.pageGutter,
                40,
              ),
              sliver: SliverMainAxisGroup(
                slivers: listingsValue.when(
                  loading: () => const [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                  ],
                  error: (error, stack) => [
                    SliverToBoxAdapter(
                      child: NyumbaStatusMessage.fromError(
                        error,
                        localizations: appLocalizationsOf(context),
                        subject: appLocalizationsOf(
                          context,
                        ).statusSubjectYourListings,
                        onRetry: () => ref.invalidate(landlordListingsProvider),
                      ),
                    ),
                  ],
                  data: (allListings) {
                    ListingPublication publicationOf(Listing listing) =>
                        publications[listing.id] ??
                        resolveListingPublication(listing: listing, copy: copy);
                    final listings = allListings.value!.where((listing) {
                      final publication = publicationOf(listing);
                      return switch (_filter) {
                        'Published' => publication.isLive,
                        'Draft' => listing.status == ListingStatus.draft,
                        'Paused' => listing.status == ListingStatus.paused,
                        _ => true,
                      };
                    }).toList();
                    if (listings.isEmpty) {
                      return const [
                        SliverToBoxAdapter(
                          child: NyumbaSurface(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(
                                child: Text.localized(
                                  'No listings match this filter.',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ];
                    }
                    return [
                      // A row at a time, so a card below the fold never builds
                      // and never starts fetching its photo. Rows rather than a
                      // SliverGrid because card height follows its content.
                      SliverLayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.crossAxisExtent >= 1050
                              ? 3
                              : constraints.crossAxisExtent >= 650
                              ? 2
                              : 1;
                          const gap = 18.0;
                          final rows =
                              (listings.length + columns - 1) ~/ columns;
                          return SliverList.builder(
                            itemCount: rows,
                            itemBuilder: (context, rowIndex) {
                              final first = rowIndex * columns;
                              return Padding(
                                padding: EdgeInsets.only(
                                  bottom: rowIndex == rows - 1 ? 0 : gap,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (
                                      var column = 0;
                                      column < columns;
                                      column++
                                    ) ...[
                                      if (column > 0)
                                        const SizedBox(width: gap),
                                      Expanded(
                                        child: first + column < listings.length
                                            ? _listingCard(
                                                listings[first + column],
                                                applicationsByListing,
                                                publication: publicationOf(
                                                  listings[first + column],
                                                ),
                                                canUpdate: canUpdate,
                                                canUnpublish: canUnpublish,
                                              )
                                            : const SizedBox.shrink(),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ];
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listingCard(
    Listing listing,
    Map<String, int> applicationsByListing, {
    required ListingPublication publication,
    required bool canUpdate,
    required bool canUnpublish,
  }) => _LandlordListingCard(
    listing: listing,
    publication: publication,
    applicationCount: applicationsByListing[listing.id] ?? 0,
    onPublish: () => _publish(listing),
    onEdit: () => _editListing(listing),
    onUnpublish: () => _unpublish(listing),
    onRemove: () => _removeListing(listing),
    // No per-advert retry. A refused command is reported when it is refused,
    // and the action that failed is still right there to try again.
    onRetry: null,
    canPublish: canUpdate,
    canEdit: canUpdate,
    canUnpublish: canUnpublish,
    canRemove: canUnpublish,
  );

  /// Recovery for an advert the server refused. The failed command is put back
  /// in the queue and pushed straight away, so the landlord finds out in the
  /// same breath whether whatever they fixed was enough.
  Future<void> _publish(Listing listing) async {
    // Both the domain and the server refuse a photoless advert, but their
    // rejection reads as a raw validation exception. Naming the missing thing
    // here — and opening the editor on it — is the difference between a
    // landlord fixing this in one tap and not knowing what went wrong.
    if (!listing.hasPhotos) {
      final addNow = await showDialog<bool>(
        context: context,
        builder: (context) {
          final copy = appLocalizationsOf(context);
          return AlertDialog(
            title: Text(copy.listingPhotoRequiredTitle),
            content: Text(copy.listingPhotosRequiredToPublish),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(copy.listingPhotoRequiredDismiss),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(copy.listingPhotoRequiredConfirm),
              ),
            ],
          );
        },
      );
      if (addNow == true && mounted) await _editListing(listing);
      return;
    }

    // The plan limit, the publication itself, and the confirmation copy live
    // with the vacancy prompt, so both surfaces enforce and say the same thing.
    await publishListingWithinPlan(context, ref, listing);
  }

  /// The rule that was broken, without the exception's class name and field
  /// path in front of it — `DomainValidationException: unit.status: …` is a
  /// stack trace wearing a sentence's clothes.
  static String _reason(Object error) => switch (error) {
    DomainValidationException(:final errors) => errors.values.join(' '),
    _ => error.toString(),
  };

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
            insetPadding: EdgeInsets.symmetric(
              horizontal: context.isCompact ? 16 : 40,
              vertical: 24,
            ),
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
        SnackBar(
          content: Text(appLocalizationsOf(context).listingChangesSaved),
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
          'Tenants stop seeing this advert as soon as the server confirms, '
          'and the card tells you when that has happened. You can publish it '
          'again at any time.',
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
        SnackBar(
          content: Text.localized(
            ref.read(cloudStatusProvider).value == CloudStatus.live
                ? 'Taking ${listing.title} out of search now.'
                : '${listing.title} comes out of search as soon as you are back online.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text.localized('Could not unpublish: ${_reason(error)}'),
        ),
      );
    }
  }

  Future<void> _removeListing(Listing listing) async {
    final copy = appLocalizationsOf(context);
    if (listing.status == ListingStatus.published) {
      showNyumbaToast(
        copy.removeListingPublishedGuidance,
        variant: NyumbaToastVariant.info,
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(copy.removeListingDialogTitle(listing.title)),
        content: Text(copy.removeListingDialogMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text.localized('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: dialogContext.nyumba.danger,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(copy.removeListingConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(removeListingProvider)(listing.id);
      if (!mounted) return;
      showNyumbaToast(
        appLocalizationsOf(context).removeListingSuccessName(listing.title),
        variant: NyumbaToastVariant.success,
      );
    } on Object catch (error) {
      if (!mounted) return;
      final copy = appLocalizationsOf(context);
      final message =
          error is StateError &&
              error.message.toString().contains('Unpublish this listing')
          ? copy.removeListingPublishedGuidance
          : describeActionFailure(
              error,
              action: copy.actionFailureActionRemoveListing,
            ).message;
      showNyumbaToast(message, variant: NyumbaToastVariant.error);
    }
  }

  Future<void> _showCreateListing(
    BuildContext context,
    List<Unit> units,
    List<Property> properties, {
    String? initialUnitId,
  }) async {
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
    Unit selectedUnit = vacant.firstWhere(
      (unit) => unit.id == initialUnitId,
      orElse: () => vacant.first,
    );
    final propertyById = {
      for (final property in properties) property.id: property,
    };
    final fields = _ListingFields.blank(
      titleSeed:
          '${selectedUnit.displayName} at ${propertyById[selectedUnit.propertyId]?.name ?? 'My property'}',
      districtSeed: 'Kampala',
      // The property already knows where it is, so a draft starts from that pin
      // rather than from an empty pair of coordinate fields. Filling it in here
      // means the landlord can see and move the point their advert will use,
      // instead of discovering after publication that the home is missing from
      // the map. `listing.publish` inherits it server-side as well, which is
      // what repairs drafts written before this existed.
      locationSeed: propertyById[selectedUnit.propertyId]?.location,
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
          insetPadding: EdgeInsets.symmetric(
            horizontal: context.isCompact ? 16 : 40,
            vertical: 24,
          ),
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
          SnackBar(
            content: Text(
              appLocalizationsOf(this.context).listingDraftSavedPublishHint,
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
    Coordinates? locationSeed,
  }) {
    final fields = _ListingFields._();
    if (locationSeed != null) {
      fields.latitude.text = locationSeed.latitude.toString();
      fields.longitude.text = locationSeed.longitude.toString();
    }
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
    fields.photos.existing.addAll(listing.imageUrls);
    fields.availableFrom = listing.availableFrom;
    fields.furnished = listing.furnished;
    return fields;
  }

  final title = TextEditingController();
  final description = TextEditingController();
  final rent = TextEditingController();
  final city = TextEditingController();
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
    const SizedBox(height: 14),
    // Photos sit third, directly under the copy they illustrate, because they
    // are the field a renter actually decides on. Buried at the far end of the
    // form — after twenty other inputs — this was routinely never reached, and
    // adverts went public showing an empty tile.
    Align(
      alignment: AlignmentDirectional.centerStart,
      child: PhotoEditorField(
        label: appLocalizationsOf(context).listingPhotosLabelRequired,
        photos: photos,
        limit: listingPhotoLimit,
        pick: pickListingPhotos,
        onChanged: (problems) => setDialogState(() => photoProblems = problems),
        helperText: appLocalizationsOf(context).listingPhotoGuidance,
      ),
    ),
    // A draft saves happily without photos; only publication is blocked. The
    // tone is therefore a warning rather than an error — the landlord has not
    // done anything wrong yet, they are being told what publishing will need.
    if (photos.isEmpty) ...[
      const SizedBox(height: 8),
      Text(
        appLocalizationsOf(context).listingPhotosRequiredNudge,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: context.nyumba.warning),
      ),
    ],
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
    // Was a pair of raw decimal text boxes. The controllers remain the storage
    // so nothing downstream had to change, but a landlord now places the point
    // on a map instead of being asked to type a coordinate — which is why the
    // field was empty on essentially every advert.
    LocationPickerField(
      value: Coordinates.tryFrom(
        _optionalDouble(latitude.text),
        _optionalDouble(longitude.text),
      ),
      showPublicPrivacyNotice: true,
      onChanged: (picked) => setDialogState(() {
        latitude.text = picked?.latitude.toString() ?? '';
        longitude.text = picked?.longitude.toString() ?? '';
      }),
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
    TextFormField(
      controller: videoUrl,
      keyboardType: TextInputType.url,
      decoration: InputDecoration(
        labelText: context.tr('Video or virtual-tour URL (optional)'),
      ),
    ),
    const SizedBox(height: 14),
    Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsetsDirectional.all(12),
        decoration: BoxDecoration(
          color: context.nyumba.navyTint,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.nyumba.navyBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.privacy_tip_outlined,
              size: 20,
              color: context.nyumba.midnightNavy,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.localized(
                appLocalizationsOf(context).listingContactRoutingNotice,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    ),
  ];

  void dispose() {
    for (final controller in [
      title,
      description,
      rent,
      city,
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

class _LandlordListingCard extends StatelessWidget {
  const _LandlordListingCard({
    required this.listing,
    required this.publication,
    required this.applicationCount,
    required this.onPublish,
    required this.onEdit,
    required this.onUnpublish,
    required this.onRemove,
    required this.onRetry,
    required this.canPublish,
    required this.canEdit,
    required this.canUnpublish,
    required this.canRemove,
  });

  final Listing listing;
  final ListingPublication publication;
  final int applicationCount;
  final VoidCallback onPublish;
  final VoidCallback onEdit;
  final VoidCallback onUnpublish;
  final VoidCallback onRemove;

  /// Null when there is no refused command to re-queue.
  final Future<void> Function()? onRetry;
  final bool canPublish;
  final bool canEdit;
  final bool canUnpublish;
  final bool canRemove;

  @override
  Widget build(BuildContext context) {
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
                  child: listingImage(
                    listing,
                    fit: BoxFit.cover,
                    cacheWidth: 640,
                    preferThumbnail: true,
                  ),
                ),
              ),
              PositionedDirectional(
                start: 12,
                top: 12,
                child: Tooltip(
                  message: publication.detail,
                  child: StatusBadge(
                    label: publication.label,
                    tone: publication.tone,
                    icon: publication.icon,
                  ),
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
                // The per-card failure panel is gone with the outbox. It
                // existed to explain a refusal discovered long after the fact,
                // when the landlord had already moved on; a refusal is now
                // raised on the action itself, where the fix is to hand.
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
                    Expanded(
                      child: Text.localized(
                        '$applicationCount ${applicationCount == 1 ? 'application' : 'applications'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    // A paused advert can only be republished once its removal
                    // has settled; publishing over an in-flight unpublish would
                    // race the server for the same aggregate.
                    if (canPublish &&
                        (listing.status == ListingStatus.draft ||
                            listing.status == ListingStatus.paused))
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
                                '$applicationCount application${applicationCount == 1 ? '' : 's'}\n\n'
                                '${publication.detail}',
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
                        } else if (value == 'remove') {
                          onRemove();
                        } else if (value == 'edit') {
                          onEdit();
                        }
                      },
                      itemBuilder: (context) => [
                        // Named for what it opens: the same page tenants get
                        // once it is live, and a preview of it before then.
                        PopupMenuItem(
                          value: 'view',
                          child: Text.localized(
                            publication.isLive
                                ? 'View public listing'
                                : 'Preview advert',
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'details',
                          child: Text.localized('Listing details'),
                        ),
                        // A refused publication leaves the advert reading as
                        // published locally, which used to hide Edit and left
                        // the landlord no way to fix whatever the server
                        // objected to.
                        if (canEdit &&
                            listing.status != ListingStatus.published)
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
                        if (canRemove &&
                            (listing.status == ListingStatus.draft ||
                                listing.status == ListingStatus.paused))
                          PopupMenuItem(
                            value: 'remove',
                            child: Text(
                              appLocalizationsOf(context).removeListingMenu,
                            ),
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
