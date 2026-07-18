import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nyumba_property_management/core/localization/localized_material.dart';

import '../../../../app/bootstrap/app_dependencies.dart';
import '../../../../app/theme/nyumba_colors.dart';
import '../../../../core/domain/sync_metadata.dart';
import '../../../../core/presentation/status_badge.dart';
import '../../../../core/presentation/surface.dart';
import '../../../auth/application/session_controller.dart';
import '../../../auth/domain/authorization_policy.dart';
import '../../../marketplace/domain/listing.dart';
import '../../../portfolio/application/portfolio_use_cases.dart';
import '../../../portfolio/application/rental_space_labels.dart';
import '../../../portfolio/domain/property.dart';
import '../../../portfolio/domain/unit.dart';
import '../../../tenants/application/tenancy_providers.dart';
import '../../../tenants/domain/tenancy.dart';

enum _AvailabilityFilter { all, vacant, occupied, other }

/// A landlord-facing availability editor placed directly on the dashboard.
///
/// Unit and listing streams are still backed by the local Sembast mirror. A
/// status change is optimistic and visibly pending; a published listing is
/// retired before the unit change is queued so this device never advertises a
/// space it already knows is unavailable.
class RentalSpaceAvailabilityPanel extends ConsumerStatefulWidget {
  const RentalSpaceAvailabilityPanel({super.key});

  @override
  ConsumerState<RentalSpaceAvailabilityPanel> createState() =>
      _RentalSpaceAvailabilityPanelState();
}

class _RentalSpaceAvailabilityPanelState
    extends ConsumerState<RentalSpaceAvailabilityPanel> {
  _AvailabilityFilter _filter = _AvailabilityFilter.all;

  @override
  Widget build(BuildContext context) {
    final propertiesValue = ref.watch(portfolioPropertiesProvider);
    final unitsValue = ref.watch(portfolioUnitsProvider);
    final listingsValue = ref.watch(landlordListingsProvider);
    final tenanciesValue = ref.watch(tenanciesProvider);
    final session = ref.watch(sessionControllerProvider);
    final properties = _resolvedAsyncValue(propertiesValue);
    final units = _resolvedAsyncValue(unitsValue);
    final listings = _resolvedAsyncValue(listingsValue);
    final tenancies = _resolvedAsyncValue(tenanciesValue);
    final dataResolved =
        properties != null &&
        units != null &&
        listings != null &&
        tenancies != null;
    final hasLoadError =
        propertiesValue.hasError ||
        unitsValue.hasError ||
        listingsValue.hasError ||
        tenanciesValue.hasError;
    final canUpdate =
        dataResolved &&
        session != null &&
        AuthorizationPolicy.allows(
          session.role,
          AppResource.unit,
          CrudOperation.update,
        );
    Map<String, Property>? propertyById;
    List<Unit>? sortedUnits;
    List<Unit>? filteredUnits;
    Set<String>? activeTenancyUnitIds;
    if (dataResolved) {
      propertyById = <String, Property>{
        for (final property in properties) property.id: property,
      };
      sortedUnits = [...units]
        ..sort((left, right) {
          final propertyComparison =
              (propertyById![left.propertyId]?.name ?? '').compareTo(
                propertyById[right.propertyId]?.name ?? '',
              );
          return propertyComparison != 0
              ? propertyComparison
              : left.displayName.compareTo(right.displayName);
        });
      filteredUnits = sortedUnits.where(_matchesFilter).toList(growable: false);
      activeTenancyUnitIds = tenancies
          .where((tenancy) => tenancy.status != TenancyStatus.ended)
          .map((tenancy) => tenancy.unitId)
          .whereType<String>()
          .toSet();
    }

    return NyumbaSurface(
      key: const ValueKey('rental-space-availability-panel'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final title = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.localized(
                          'Rental space availability',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text.localized(
                          'Update availability here. Only vacant spaces can appear on the public marketplace, and occupied status is set by an active tenancy.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    );
                    final actions = Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        TextButton(
                          onPressed: () => context.go('/properties'),
                          child: const Text.localized('Manage properties'),
                        ),
                        TextButton.icon(
                          onPressed: () => context.go('/listings'),
                          icon: const Icon(Icons.public_rounded, size: 18),
                          label: const Text.localized('Manage listings'),
                        ),
                      ],
                    );
                    if (constraints.maxWidth < 760) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [title, const SizedBox(height: 10), actions],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: title),
                        const SizedBox(width: 16),
                        actions,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final filter in _AvailabilityFilter.values)
                      ChoiceChip(
                        label: Text.localized(_filterLabel(filter)),
                        selected: _filter == filter,
                        onSelected: dataResolved
                            ? (_) => setState(() => _filter = filter)
                            : null,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (hasLoadError)
            const _AvailabilityLoadError()
          else if (!dataResolved)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (sortedUnits!.isEmpty)
            _AvailabilityEmptyState(
              message:
                  'Add a property and rental space to start managing availability.',
              actionLabel: 'Add property',
              onAction: () => context.go('/properties/new'),
            )
          else if (filteredUnits!.isEmpty)
            const _AvailabilityEmptyState(
              message: 'No rental spaces match this availability filter.',
            )
          else
            for (final (index, unit) in filteredUnits.indexed) ...[
              _AvailabilityRow(
                unit: unit,
                propertyName:
                    propertyById![unit.propertyId]?.name ?? 'Property',
                listingState: _publicListingState(unit, listings),
                leaseManaged:
                    unit.status == UnitStatus.occupied ||
                    activeTenancyUnitIds!.contains(unit.id),
                canUpdate: canUpdate,
                onChanged: (status) =>
                    _changeAvailability(unit, status, listings),
              ),
              if (index != filteredUnits.length - 1) const Divider(height: 1),
            ],
        ],
      ),
    );
  }

  bool _matchesFilter(Unit unit) => switch (_filter) {
    _AvailabilityFilter.all => true,
    _AvailabilityFilter.vacant => unit.status == UnitStatus.vacant,
    _AvailabilityFilter.occupied => unit.status == UnitStatus.occupied,
    _AvailabilityFilter.other =>
      unit.status != UnitStatus.vacant && unit.status != UnitStatus.occupied,
  };

  Future<void> _changeAvailability(
    Unit unit,
    UnitStatus status,
    List<Listing> listings,
  ) async {
    if (status == unit.status) return;
    final hasPublishedListing = listings.any(
      (listing) =>
          listing.unitId == unit.id &&
          listing.status == ListingStatus.published,
    );
    if (unit.status == UnitStatus.vacant &&
        status != UnitStatus.vacant &&
        hasPublishedListing) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text.localized(
            'Remove this space from the public screen?',
          ),
          content: const Text.localized(
            'Changing this space from vacant will unpublish its listing. The public screen updates after server confirmation.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text.localized('Keep vacant'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text.localized('Change availability'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      final result = await ref.read(updateUnitProvider)(
        unit.copyWith(status: status),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text.localized(
            result.unpublishedListing == null
                ? 'Availability saved locally and queued to sync.'
                : 'Availability saved locally. The public listing is being removed.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text.localized('Could not update availability: $error'),
        ),
      );
    }
  }
}

T? _resolvedAsyncValue<T>(AsyncValue<T> value) {
  if (value.isLoading || value.hasError) return null;
  return value.value;
}

class _AvailabilityRow extends StatelessWidget {
  const _AvailabilityRow({
    required this.unit,
    required this.propertyName,
    required this.listingState,
    required this.leaseManaged,
    required this.canUpdate,
    required this.onChanged,
  });

  final Unit unit;
  final String propertyName;
  final _PublicListingState listingState;
  final bool leaseManaged;
  final bool canUpdate;
  final ValueChanged<UnitStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    final identity = Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: context.nyumba.navyTint,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            Icons.meeting_room_outlined,
            size: 20,
            color: context.nyumba.midnightNavy,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                unit.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                propertyName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
    final picker = _AvailabilityPicker(
      unit: unit,
      enabled: canUpdate && !leaseManaged,
      onChanged: onChanged,
    );
    final publicState = Align(
      alignment: AlignmentDirectional.centerStart,
      child: StatusBadge(
        label: listingState.label,
        tone: listingState.tone,
        icon: listingState.icon,
      ),
    );

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 20, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 720) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: 12),
                Text.localized(
                  'Availability',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 5),
                picker,
                if (leaseManaged) ...[
                  const SizedBox(height: 5),
                  Text.localized(
                    'Managed by active tenancy',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                Text.localized(
                  'Public screen',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 5),
                publicState,
              ],
            );
          }
          return Row(
            children: [
              Expanded(flex: 5, child: identity),
              const SizedBox(width: 18),
              SizedBox(
                width: 210,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    picker,
                    if (leaseManaged) ...[
                      const SizedBox(height: 4),
                      Text.localized(
                        'Managed by active tenancy',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 18),
              SizedBox(width: 210, child: publicState),
            ],
          );
        },
      ),
    );
  }
}

class _AvailabilityPicker extends StatelessWidget {
  const _AvailabilityPicker({
    required this.unit,
    required this.enabled,
    required this.onChanged,
  });

  final Unit unit;
  final bool enabled;
  final ValueChanged<UnitStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<UnitStatus>(
          value: unit.status,
          isDense: true,
          isExpanded: true,
          onChanged: enabled
              ? (value) {
                  if (value != null) onChanged(value);
                }
              : null,
          items: [
            for (final status in UnitStatus.values)
              if (status != UnitStatus.occupied ||
                  unit.status == UnitStatus.occupied)
                DropdownMenuItem(
                  value: status,
                  enabled: status != UnitStatus.occupied,
                  child: Text.localized(status.displayLabel),
                ),
          ],
        ),
      ),
    );
  }
}

class _AvailabilityEmptyState extends StatelessWidget {
  const _AvailabilityEmptyState({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(
            Icons.domain_disabled_outlined,
            size: 38,
            color: context.nyumba.mutedInk,
          ),
          const SizedBox(height: 10),
          Text.localized(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 10),
            FilledButton(
              onPressed: onAction,
              child: Text.localized(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _AvailabilityLoadError extends StatelessWidget {
  const _AvailabilityLoadError();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 38,
            color: context.nyumba.danger,
          ),
          const SizedBox(height: 10),
          const Text.localized(
            'Rental space availability could not be loaded. Try again.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PublicListingState {
  const _PublicListingState(this.label, this.tone, this.icon);

  final String label;
  final BadgeTone tone;
  final IconData icon;
}

_PublicListingState _publicListingState(Unit unit, List<Listing> listings) {
  final unitListings = listings
      .where((listing) => listing.unitId == unit.id)
      .toList(growable: false);
  if (unitListings.any((listing) => listing.isPublic)) {
    return unit.status == UnitStatus.vacant
        ? const _PublicListingState(
            'Live on public screen',
            BadgeTone.success,
            Icons.public_rounded,
          )
        : const _PublicListingState(
            'Public removal required',
            BadgeTone.danger,
            Icons.error_outline_rounded,
          );
  }
  if (unitListings.any(
    (listing) =>
        listing.status == ListingStatus.published &&
        listing.syncMetadata.state != EntitySyncState.synced,
  )) {
    return const _PublicListingState(
      'Publishing pending',
      BadgeTone.warning,
      Icons.cloud_upload_outlined,
    );
  }
  if (unitListings.any(
    (listing) =>
        listing.status == ListingStatus.paused &&
        listing.syncMetadata.state != EntitySyncState.synced,
  )) {
    return const _PublicListingState(
      'Removal pending',
      BadgeTone.warning,
      Icons.hourglass_top_rounded,
    );
  }
  if (unitListings.isNotEmpty) {
    return const _PublicListingState(
      'Not public',
      BadgeTone.neutral,
      Icons.visibility_off_outlined,
    );
  }
  return const _PublicListingState(
    'No listing',
    BadgeTone.neutral,
    Icons.remove_circle_outline_rounded,
  );
}

String _filterLabel(_AvailabilityFilter filter) => switch (filter) {
  _AvailabilityFilter.all => 'All',
  _AvailabilityFilter.vacant => 'Vacant',
  _AvailabilityFilter.occupied => 'Occupied',
  _AvailabilityFilter.other => 'Other',
};
