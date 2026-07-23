import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/async_action_button.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/user_session.dart';
import '../../marketplace/domain/listing.dart';
import '../../portfolio/domain/property.dart';
import '../../portfolio/domain/unit.dart';
import '../application/admin_directory_providers.dart';
import '../domain/platform_account.dart';
import 'widgets/admin_components.dart';

/// Every landlord's portfolio in one place, archived records included.
///
/// The Firestore rules already open `properties`, `units` and `privateListings`
/// to both administrator claims, and the workspace bootstrap already pulls them
/// with `administrativeScope: true` — this screen is the surface over data an
/// administrator could always read. Archived records are shown because they are
/// exactly what a super admin comes here to purge.
class AdminPortfolioScreen extends ConsumerStatefulWidget {
  const AdminPortfolioScreen({super.key});

  @override
  ConsumerState<AdminPortfolioScreen> createState() =>
      _AdminPortfolioScreenState();
}

class _AdminPortfolioScreenState extends ConsumerState<AdminPortfolioScreen> {
  bool _showArchived = false;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final isSuperAdmin = session?.role == AppRole.superAdmin;
    final properties =
        ref.watch(adminPropertiesProvider).value ?? const <Property>[];
    final units = ref.watch(adminUnitsProvider).value ?? const <Unit>[];
    final listings =
        ref.watch(landlordListingsProvider).value ?? const <Listing>[];
    final accountsByUid = <String, PlatformAccount>{
      for (final account
          in ref.watch(platformAccountsProvider).value ??
              const <PlatformAccount>[])
        account.uid: account,
    };

    final visibleProperties = properties
        .where((property) => _showArchived || !property.isArchived)
        .toList(growable: false);
    final archivedCount =
        properties.where((property) => property.isArchived).length +
        units.where((unit) => unit.isArchived).length;

    // Group by owner, so an administrator reads the platform the way it is
    // actually structured: one workspace per landlord.
    final landlordIds =
        <String>{
          ...visibleProperties.map((property) => property.landlordId),
          ...listings.map((listing) => listing.landlordId),
        }.toList(growable: false)..sort(
          (left, right) => accountLabelFor(left, accountsByUid)
              .toLowerCase()
              .compareTo(accountLabelFor(right, accountsByUid).toLowerCase()),
        );
    final query = _query.trim().toLowerCase();
    final matching = query.isEmpty
        ? landlordIds
        : landlordIds
              .where(
                (uid) =>
                    accountLabelFor(
                      uid,
                      accountsByUid,
                    ).toLowerCase().contains(query) ||
                    uid.toLowerCase().contains(query),
              )
              .toList(growable: false);

    return AdminPage(
      title: 'Landlord portfolios',
      description:
          'Every property, rental space, and listing on the platform, grouped '
          'by the landlord who owns it.',
      children: [
        AdminMetricGrid(
          children: [
            AdminMetricCard(
              label: 'Landlords with a portfolio',
              value: '${landlordIds.length}',
              caption: 'Owners of at least one property or listing',
              icon: Icons.real_estate_agent_outlined,
              tone: context.nyumba.midnightNavy,
            ),
            AdminMetricCard(
              label: 'Rental spaces',
              value:
                  '${units.where((unit) => _showArchived || !unit.isArchived).length}',
              caption: _showArchived
                  ? 'Including archived spaces'
                  : 'Active spaces only',
              icon: Icons.apartment_rounded,
              tone: context.nyumba.sageDark,
            ),
            AdminMetricCard(
              label: 'Listings',
              value: '${listings.length}',
              caption: 'Drafts, live adverts, and retired ones',
              icon: Icons.campaign_outlined,
              tone: context.nyumba.terracottaDark,
            ),
            AdminMetricCard(
              label: 'Archived records',
              value: '$archivedCount',
              caption: isSuperAdmin
                  ? 'Purgeable once nothing references them'
                  : 'A super admin can purge these',
              icon: Icons.inventory_2_outlined,
              tone: context.nyumba.mutedInk,
            ),
          ],
        ),
        const SizedBox(height: 18),
        NyumbaSurface(
          padding: const EdgeInsets.all(18),
          child: Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    labelText: context.tr('Search landlords'),
                    hintText: context.tr('Name, email, or account ID'),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              FilterChip(
                selected: _showArchived,
                onSelected: (value) => setState(() => _showArchived = value),
                avatar: const Icon(Icons.inventory_2_outlined, size: 18),
                label: Text.localized('Show archived'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (matching.isEmpty)
          const NyumbaSurface(
            child: AdminEmptyState(
              title: 'No portfolios to show',
              message:
                  'No landlord matches this search, or no portfolio data has '
                  'reached this device yet.',
              icon: Icons.domain_disabled_outlined,
            ),
          )
        else
          for (final landlordId in matching) ...[
            _LandlordPortfolioPanel(
              landlordId: landlordId,
              label: accountLabelFor(landlordId, accountsByUid),
              properties: visibleProperties
                  .where((property) => property.landlordId == landlordId)
                  .toList(growable: false),
              units: units
                  .where(
                    (unit) =>
                        unit.landlordId == landlordId &&
                        (_showArchived || !unit.isArchived),
                  )
                  .toList(growable: false),
              listings: listings
                  .where((listing) => listing.landlordId == landlordId)
                  .toList(growable: false),
              isSuperAdmin: isSuperAdmin,
              onPurge: _purge,
            ),
            const SizedBox(height: 14),
          ],
      ],
    );
  }

  /// Runs one purge behind a reason prompt. Every branch reports back through
  /// the snackbar: a purge that silently failed would leave an administrator
  /// believing a record was destroyed when it is still live.
  Future<void> _purge({
    required String kind,
    required String name,
    required int? expectedVersion,
    required Future<void> Function(AdminPurgeCommands commands, String reason)
    run,
  }) async {
    if (expectedVersion == null) {
      showAdminMessage(
        context,
        'This $kind has not finished syncing, so there is no server version '
        'to delete against. Try again once it has synced.',
      );
      return;
    }
    final reason = await _askReason(kind: kind, name: name);
    if (reason == null || !mounted) return;
    try {
      await run(ref.read(adminPurgeCommandsProvider), reason);
      if (!mounted) return;
      showAdminMessage(context, 'Deleted $name permanently.');
    } on Object catch (error) {
      if (!mounted) return;
      showAdminMessage(context, 'The server rejected the deletion: $error');
    }
  }

  Future<String?> _askReason({
    required String kind,
    required String name,
  }) async {
    var reason = purgeReasonCodes.first;
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text.localized('Delete this $kind permanently?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.localized(
                '“$name” will be destroyed on the server. This cannot be '
                'undone, and restoring it from the archive will no longer be '
                'possible.',
              ),
              const SizedBox(height: 14),
              Text.localized(
                'Reason recorded in the audit log',
                style: Theme.of(dialogContext).textTheme.labelLarge,
              ),
              RadioGroup<String>(
                groupValue: reason,
                onChanged: (value) =>
                    setDialogState(() => reason = value ?? reason),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final code in purgeReasonCodes)
                      RadioListTile<String>(
                        value: code,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text.localized(_reasonLabel(code)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text.localized('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text.localized('Delete permanently'),
            ),
          ],
        ),
      ),
    );
    return confirmed == true ? reason : null;
  }

  static String _reasonLabel(String code) => switch (code) {
    'DATA_RETENTION' => 'Retention policy',
    'USER_REQUESTED' => 'The account holder asked for it',
    'POLICY_VIOLATION' => 'Policy violation',
    'FRAUD_RISK' => 'Fraud risk',
    'ADMIN_CORRECTION' => 'Administrative correction',
    _ => code,
  };
}

typedef _PurgeRunner =
    Future<void> Function({
      required String kind,
      required String name,
      required int? expectedVersion,
      required Future<void> Function(AdminPurgeCommands commands, String reason)
      run,
    });

class _LandlordPortfolioPanel extends StatelessWidget {
  const _LandlordPortfolioPanel({
    required this.landlordId,
    required this.label,
    required this.properties,
    required this.units,
    required this.listings,
    required this.isSuperAdmin,
    required this.onPurge,
  });

  final String landlordId;
  final String label;
  final List<Property> properties;
  final List<Unit> units;
  final List<Listing> listings;
  final bool isSuperAdmin;
  final _PurgeRunner onPurge;

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      title: label,
      subtitle:
          '${properties.length} properties · ${units.length} rental spaces · '
          '${listings.length} listings',
      trailing: AdminAvatar(name: label),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (properties.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text.localized(
                'No properties on this account.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          for (final property in properties) ...[
            _PropertyTile(
              property: property,
              units: units
                  .where((unit) => unit.propertyId == property.id)
                  .toList(growable: false),
              isSuperAdmin: isSuperAdmin,
              onPurge: onPurge,
            ),
            const SizedBox(height: 6),
          ],
          if (listings.isNotEmpty) ...[
            const Divider(height: 26),
            Text.localized(
              'Listings',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            for (final listing in listings)
              _ListingRow(
                listing: listing,
                isSuperAdmin: isSuperAdmin,
                onPurge: onPurge,
              ),
          ],
        ],
      ),
    );
  }
}

class _PropertyTile extends StatelessWidget {
  const _PropertyTile({
    required this.property,
    required this.units,
    required this.isSuperAdmin,
    required this.onPurge,
  });

  final Property property;
  final List<Unit> units;
  final bool isSuperAdmin;
  final _PurgeRunner onPurge;

  @override
  Widget build(BuildContext context) {
    // A property can only be purged once nothing references it, matching the
    // server's own precondition — offering the action otherwise would just
    // produce a rejection the administrator cannot act on.
    final purgeable = isSuperAdmin && property.isArchived && units.isEmpty;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsetsDirectional.only(start: 16, bottom: 8),
      shape: const Border(),
      collapsedShape: const Border(),
      leading: Icon(
        Icons.home_work_outlined,
        color: property.isArchived
            ? context.nyumba.mutedInk
            : context.nyumba.midnightNavy,
      ),
      title: Text.localized(property.name),
      subtitle: Text.localized(
        '${property.city} · ${units.length} rental spaces',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (property.isArchived)
            const StatusBadge(label: 'Archived', tone: BadgeTone.neutral),
          if (purgeable) ...[
            const SizedBox(width: 6),
            _PurgeButton(
              tooltip: 'Delete this property permanently',
              onPressed: () => onPurge(
                kind: 'property',
                name: property.name,
                expectedVersion: _serverVersion(
                  property.syncMetadata.serverRevision,
                ),
                run: (commands, reason) => commands.deleteProperty(
                  propertyId: property.id,
                  expectedVersion: _serverVersion(
                    property.syncMetadata.serverRevision,
                  )!,
                  reasonCode: reason,
                ),
              ),
            ),
          ],
        ],
      ),
      children: [
        if (units.isEmpty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text.localized(
              'No rental spaces.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        for (final unit in units)
          _UnitRow(unit: unit, isSuperAdmin: isSuperAdmin, onPurge: onPurge),
      ],
    );
  }
}

class _UnitRow extends StatelessWidget {
  const _UnitRow({
    required this.unit,
    required this.isSuperAdmin,
    required this.onPurge,
  });

  final Unit unit;
  final bool isSuperAdmin;
  final _PurgeRunner onPurge;

  @override
  Widget build(BuildContext context) {
    final purgeable = isSuperAdmin && unit.isArchived;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        Icons.meeting_room_outlined,
        size: 20,
        color: unit.isArchived
            ? context.nyumba.mutedInk
            : context.nyumba.sageDark,
      ),
      title: Text.localized(unit.label),
      subtitle: Text.localized(
        '${unit.status.name} · ${formatAdminUgx(unit.monthlyRentMinor)}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (unit.isArchived)
            const StatusBadge(label: 'Archived', tone: BadgeTone.neutral),
          if (purgeable) ...[
            const SizedBox(width: 6),
            _PurgeButton(
              tooltip: 'Delete this rental space permanently',
              onPressed: () => onPurge(
                kind: 'rental space',
                name: unit.label,
                expectedVersion: _serverVersion(
                  unit.syncMetadata.serverRevision,
                ),
                run: (commands, reason) => commands.deleteUnit(
                  unitId: unit.id,
                  expectedVersion: _serverVersion(
                    unit.syncMetadata.serverRevision,
                  )!,
                  reasonCode: reason,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ListingRow extends StatelessWidget {
  const _ListingRow({
    required this.listing,
    required this.isSuperAdmin,
    required this.onPurge,
  });

  final Listing listing;
  final bool isSuperAdmin;
  final _PurgeRunner onPurge;

  @override
  Widget build(BuildContext context) {
    // Mirrors the server: a live advert must be unpublished first, so the
    // ordinary retirement path clears the unit pointer and the plan counter.
    final purgeable = isSuperAdmin && listing.status != ListingStatus.published;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        Icons.campaign_outlined,
        size: 20,
        color: listing.isPublic
            ? context.nyumba.terracottaDark
            : context.nyumba.mutedInk,
      ),
      title: Text.localized(listing.title),
      subtitle: Text.localized(
        listing.status.name,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusBadge(
            label: listing.isPublic ? 'Live' : 'Off market',
            tone: listing.isPublic ? BadgeTone.success : BadgeTone.neutral,
          ),
          if (purgeable) ...[
            const SizedBox(width: 6),
            _PurgeButton(
              tooltip: 'Delete this listing permanently',
              onPressed: () => onPurge(
                kind: 'listing',
                name: listing.title,
                expectedVersion: _serverVersion(
                  listing.syncMetadata.serverRevision,
                ),
                run: (commands, reason) => commands.deleteListing(
                  listingId: listing.id,
                  expectedVersion: _serverVersion(
                    listing.syncMetadata.serverRevision,
                  )!,
                  reasonCode: reason,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PurgeButton extends StatelessWidget {
  const _PurgeButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return AsyncActionIconButton(
      onPressed: onPressed,
      tooltip: context.tr(tooltip),
      icon: Icon(Icons.delete_forever_outlined, color: context.nyumba.danger),
    );
  }
}

/// The server's optimistic-concurrency token, which the mirror stores as text.
/// A record that has never synced has none, and cannot be addressed by a
/// command at all.
int? _serverVersion(String? revision) => int.tryParse(revision ?? '');
