import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations_adapter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/action_failure.dart';
import '../../../core/presentation/async_action_button.dart';
import '../../../core/presentation/operational_actions.dart';
import '../../../core/domain/sync_metadata.dart';
import '../../../core/presentation/page_header.dart';
import '../../../core/presentation/responsive.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/status_message.dart';
import '../../../core/presentation/surface.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/authorization_policy.dart';
import '../../auth/domain/user_session.dart';
import '../../subscriptions/application/subscription_providers.dart';
import '../../subscriptions/domain/landlord_entitlement.dart';
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
        AuthorizationPolicy.allowsSession(
          session,
          AppResource.property,
          CrudOperation.create,
        );
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
                title: 'Properties and rental spaces',
                description:
                    'Every rentable space has its own rent, occupancy, lease, and maintenance history.',
                primaryAction: canCreate
                    ? AsyncActionButton.filled(
                        onPressed: _createProperty,
                        showBusyIndicator: false,
                        icon: const Icon(Icons.add_rounded),
                        child: const Text.localized('Add property'),
                      )
                    : null,
              ),
              const SizedBox(height: 22),
              _PortfolioUsage(units: units),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text.localized(
                      'Your properties',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  SizedBox(
                    width: context.isCompact ? 190 : 300,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: context.tr('Search properties'),
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
                error: (error, stack) => NyumbaStatusMessage.fromError(
                  error,
                  localizations: appLocalizationsOf(context),
                  subject: appLocalizationsOf(
                    context,
                  ).statusSubjectYourProperties,
                  onRetry: () => ref.invalidate(portfolioPropertiesProvider),
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
                            Text.localized(
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
    // Kept apart on purpose: photos that were rejected are a warning about the
    // selection, while a failure is the save itself refusing. Both used to be
    // one string at the bottom of a scrolling column, where neither was seen.
    var photoProblems = const <String>[];
    ActionFailure? failure;
    final property = await showDialog<Property>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text.localized('Add property'),
          content: SizedBox(
            width: 500,
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
                          if (session.role == AppRole.admin ||
                              session.role == AppRole.superAdmin) ...[
                            TextFormField(
                              controller: landlordId,
                              decoration: InputDecoration(
                                labelText: context.tr(
                                  'Target landlord account ID',
                                ),
                                helperText: context.tr(
                                  'Staff actions are server-validated and audited.',
                                ),
                              ),
                              validator: (value) =>
                                  (value?.trim().isEmpty ?? true)
                                  ? context.tr('Enter the landlord account ID')
                                  : null,
                            ),
                            const SizedBox(height: 14),
                          ],
                          TextFormField(
                            controller: name,
                            autofocus: true,
                            decoration: InputDecoration(
                              labelText: context.tr('Property name'),
                            ),
                            validator: (value) =>
                                (value?.trim().length ?? 0) < 2
                                ? context.tr('Enter a property name')
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: address,
                            decoration: InputDecoration(
                              labelText: context.tr('Street address'),
                            ),
                            validator: (value) =>
                                (value?.trim().length ?? 0) < 3
                                ? context.tr('Enter the street address')
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: city,
                            decoration: InputDecoration(
                              labelText: context.tr('City or town'),
                            ),
                            validator: (value) =>
                                (value?.trim().isEmpty ?? true)
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
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text.localized(
                                      'Property photos',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                    ),
                                    Text.localized(
                                      selectedPhotos.isEmpty
                                          ? 'Add 1–5 photos. The primary photo appears first.'
                                          : '${selectedPhotos.length} of $propertyPhotoLimit photos added. The primary photo appears first.',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              AsyncActionButton.outlined(
                                onPressed:
                                    selectedPhotos.length >= propertyPhotoLimit
                                    ? null
                                    : () async {
                                        final result = await pickPropertyPhotos(
                                          remainingSlots:
                                              propertyPhotoLimit -
                                              selectedPhotos.length,
                                        );
                                        if (!context.mounted) return;
                                        // Backing out of the chooser is not an
                                        // event: leave whatever is on screen
                                        // exactly as it was.
                                        if (result.cancelled) return;
                                        setDialogState(() {
                                          selectedPhotos.addAll(result.images);
                                          photoProblems = result.problems;
                                          if (result.hasImages) failure = null;
                                        });
                                      },
                                showBusyIndicator: false,
                                icon: const Icon(
                                  Icons.add_photo_alternate_outlined,
                                ),
                                child: Text.localized(
                                  selectedPhotos.isEmpty
                                      ? 'Add photos'
                                      : 'Add more photos',
                                ),
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
                                            final photo = selectedPhotos
                                                .removeAt(index);
                                            selectedPhotos.insert(0, photo);
                                          }),
                                    onRemove: () => setDialogState(
                                      () => selectedPhotos.removeAt(index),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text.localized(
                                '$supportedPhotoFormats, up to 5 MB each. '
                                'Photos stay on this device until they sync.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Pinned below the scroll view so a rejection or a refused
                // save is on screen the moment it happens, whatever the form
                // is scrolled to.
                PickProblemsNotice(problems: photoProblems),
                if (failure != null) ActionFailureNotice(failure: failure!),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text.localized('Cancel'),
            ),
            AsyncActionButton.filled(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                if (selectedPhotos.isEmpty) {
                  setDialogState(
                    () => failure = const ActionFailure(
                      message:
                          'Add at least one photo of the property before '
                          'saving. Use "Add photos" above — the photo appears '
                          'as a thumbnail once it has been added.',
                    ),
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
                  if (!context.mounted) return;
                  setDialogState(
                    () => failure = describeActionFailure(
                      caught,
                      action: 'save this property',
                    ),
                  );
                }
              },
              child: const Text.localized('Save property'),
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
          content: Text.localized(
            'Property saved locally and added to the sync queue.',
          ),
        ),
      );
      context.go('/properties/${property.id}?addUnit=true');
    }
  }
}

/// Plan usage, shown only when the server has told us what the plan is.
///
/// This previously hard-coded a 50-unit "Pro plan" for every landlord, which
/// was a number no server ever agreed to — and directly contradicted its own
/// dialog copy about entitlements never being decided locally.
class _PortfolioUsage extends ConsumerWidget {
  const _PortfolioUsage({required this.units});

  final List<Unit> units;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(landlordEntitlementProvider).value;
    return switch (state) {
      // Nothing to say yet, or nothing to say at all (non-landlord).
      null || EntitlementNotApplicable() => const SizedBox.shrink(),
      EntitlementUnavailable(:final reason) => _UsageShell(
        title: 'Plan unavailable',
        trailing: Text.localized(
          '${units.length} rental spaces',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        detail: reason,
        dialogTitle: 'Plan unavailable',
        dialogMessage:
            '$reason You have ${units.length} rental space(s). Nyumba shows '
            'limits only once the server confirms your plan, so nothing here '
            'is guessed while it is unavailable.',
      ),
      EntitlementKnown(:final entitlement) => _UsageShell(
        title: '${entitlement.displayName} plan',
        trailing: Text.localized(
          '${units.length} of ${entitlement.unitLimit} rental spaces',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        progress: entitlement.unitLimit == 0
            ? 1
            : (units.length / entitlement.unitLimit).clamp(0, 1).toDouble(),
        dialogTitle: '${entitlement.displayName} plan usage',
        dialogMessage:
            '${units.length} of ${entitlement.unitLimit} rental spaces are '
            'currently in use, and up to ${entitlement.activeListingLimit} '
            'listings can be advertised at once. These limits come from your '
            'subscription on the server and are enforced there; this workspace '
            'never changes them locally.',
      ),
    };
  }
}

class _UsageShell extends StatelessWidget {
  const _UsageShell({
    required this.title,
    required this.trailing,
    required this.dialogTitle,
    required this.dialogMessage,
    this.progress,
    this.detail,
  });

  final String title;
  final Widget trailing;
  final String dialogTitle;
  final String dialogMessage;
  final double? progress;
  final String? detail;

  @override
  Widget build(BuildContext context) {
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
                      child: Text.localized(
                        title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    trailing,
                  ],
                ),
                const SizedBox(height: 8),
                if (progress != null)
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(4),
                    color: context.nyumba.sageGreen,
                    backgroundColor: context.nyumba.sageTint,
                  )
                else if (detail != null)
                  Text.localized(
                    detail!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.nyumba.mutedInk,
                    ),
                  ),
              ],
            ),
          ),
          if (!context.isCompact) ...[
            const SizedBox(width: 18),
            TextButton(
              onPressed: () => showNyumbaInfoDialog(
                context,
                title: dialogTitle,
                message: dialogMessage,
                icon: Icons.workspace_premium_outlined,
              ),
              child: const Text.localized('View plan'),
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
                PositionedDirectional(
                  start: 12,
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
                Text.localized(
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
                          Text.localized(
                            'Potential monthly rent',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text.localized(
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
              PositionedDirectional(
                end: 3,
                top: 3,
                child: IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  tooltip: context.tr('Remove ${photo.name}'),
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded, size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (isPrimary)
            Text.localized(
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
              child: const Text.localized('Make primary'),
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
        Text.localized(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
