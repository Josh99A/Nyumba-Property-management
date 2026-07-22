import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/nyumba_colors.dart';
import '../../core/localization/app_localizations_adapter.dart';
import '../../core/offline/outbox_entry.dart';
import '../../core/presentation/cloud_status_badge.dart';
import '../../core/presentation/motion.dart';
import '../../core/presentation/nyumba_logo.dart';
import '../../core/presentation/language_menu_button.dart';
import '../../core/presentation/responsive.dart';
import '../../features/auth/application/session_controller.dart';
import '../../features/auth/domain/authorization_policy.dart';
import '../../features/auth/domain/user_session.dart';
import '../../features/auth/presentation/app_role_localizations.dart';
import '../../features/notifications/application/push_interactions.dart';
import '../../features/notifications/presentation/notification_center_sheet.dart';
import '../bootstrap/app_dependencies.dart';

class AppDestination {
  const AppDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.path,
    this.shortLabel,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;

  /// Label for the bottom bar, where each destination gets roughly a fifth of
  /// the screen: anything longer than one short word wraps and breaks the row.
  /// The sidebar and overflow sheet keep the descriptive [label].
  final String? shortLabel;

  String get compactLabel => shortLabel ?? label;
}

const _landlordDestinations = [
  AppDestination(
    label: 'Portfolio overview',
    shortLabel: 'Overview',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    path: '/dashboard',
  ),
  AppDestination(
    label: 'Properties',
    icon: Icons.apartment_outlined,
    selectedIcon: Icons.apartment_rounded,
    path: '/properties',
  ),
  AppDestination(
    label: 'Tenants',
    icon: Icons.people_outline_rounded,
    selectedIcon: Icons.people_rounded,
    path: '/tenants',
  ),
  AppDestination(
    label: 'Finances',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet_rounded,
    path: '/finances',
  ),
  AppDestination(
    label: 'Maintenance',
    icon: Icons.build_outlined,
    selectedIcon: Icons.build_rounded,
    path: '/maintenance',
  ),
  AppDestination(
    label: 'Listings',
    icon: Icons.sell_outlined,
    selectedIcon: Icons.sell_rounded,
    path: '/listings',
  ),
  AppDestination(
    label: 'Documents',
    icon: Icons.description_outlined,
    selectedIcon: Icons.description_rounded,
    path: '/documents',
  ),
];

const _tenantDestinations = [
  AppDestination(
    label: 'Home',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    path: '/tenant',
  ),
  AppDestination(
    label: 'Payments',
    icon: Icons.payments_outlined,
    selectedIcon: Icons.payments_rounded,
    path: '/tenant/payments',
  ),
  AppDestination(
    label: 'Maintenance',
    icon: Icons.build_outlined,
    selectedIcon: Icons.build_rounded,
    path: '/tenant/maintenance',
  ),
  AppDestination(
    label: 'Documents',
    icon: Icons.folder_outlined,
    selectedIcon: Icons.folder_rounded,
    path: '/tenant/documents',
  ),
];

const _adminDestinations = [
  AppDestination(
    label: 'Admin overview',
    shortLabel: 'Admin',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard_rounded,
    path: '/admin',
  ),
  AppDestination(
    label: 'Users',
    icon: Icons.manage_accounts_outlined,
    selectedIcon: Icons.manage_accounts_rounded,
    path: '/admin/users',
  ),
  AppDestination(
    label: 'Access & operations',
    shortLabel: 'Access',
    icon: Icons.policy_outlined,
    selectedIcon: Icons.policy_rounded,
    path: '/admin/access',
  ),
  AppDestination(
    label: 'Subscriptions',
    shortLabel: 'Plans',
    icon: Icons.workspace_premium_outlined,
    selectedIcon: Icons.workspace_premium_rounded,
    path: '/admin/subscriptions',
  ),
  AppDestination(
    label: 'Reports',
    icon: Icons.analytics_outlined,
    selectedIcon: Icons.analytics_rounded,
    path: '/admin/reports',
  ),
  AppDestination(
    label: 'Announcements',
    shortLabel: 'Notices',
    icon: Icons.campaign_outlined,
    selectedIcon: Icons.campaign_rounded,
    path: '/admin/broadcast',
  ),
];

const _staffDestinations = [..._adminDestinations, ..._landlordDestinations];

/// Managing staff seats and their permissions. Owner-only: a staff member
/// cannot manage the team, so this never appears in their navigation.
AppDestination _teamDestination(String label) => AppDestination(
  label: label,
  icon: Icons.groups_outlined,
  selectedIcon: Icons.groups_rounded,
  path: '/team',
);

/// The landlord's own plan — the payment gate before activation and the
/// self-service upgrade path afterwards. Landlord-only: platform staff
/// manage subscriptions from the admin workspace instead.
const _subscriptionDestination = AppDestination(
  label: 'My subscription',
  shortLabel: 'Plan',
  icon: Icons.workspace_premium_outlined,
  selectedIcon: Icons.workspace_premium_rounded,
  path: '/subscription',
);

/// The public marketplace, reachable from every workspace: landlords check how
/// their advertisements actually look, tenants and staff browse what is
/// available. The route lives outside the shell — the explore page carries its
/// own "My workspace" affordance back in.
const _exploreDestination = AppDestination(
  label: 'Explore homes',
  shortLabel: 'Explore',
  icon: Icons.travel_explore_outlined,
  selectedIcon: Icons.travel_explore_rounded,
  path: '/explore',
);

class NyumbaAppShell extends ConsumerWidget {
  const NyumbaAppShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    if (session == null) return child;
    final copy = appLocalizationsOf(context);
    ref.listen(pushInteractionProvider(copy.newNotification), (_, next) {
      next.whenData((interaction) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          if (interaction.opensRoute && interaction.route != null) {
            context.go(interaction.route!);
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text.localized(
                interaction.body.isEmpty
                    ? interaction.title
                    : '${interaction.title}: ${interaction.body}',
              ),
              action: interaction.route == null
                  ? null
                  : SnackBarAction(
                      label: context.tr('Open'),
                      onPressed: () => context.go(interaction.route!),
                    ),
            ),
          );
        });
      });
    });
    final destinations = _destinationsFor(session, copy.teamLabel);
    final path = GoRouterState.of(context).uri.path;

    if (context.isCompact) {
      return _MobileShell(
        session: session,
        destinations: destinations,
        currentPath: path,
        child: child,
      );
    }

    final collapsed = context.windowSizeClass == WindowSizeClass.medium;
    return Scaffold(
      backgroundColor: context.nyumba.softIvory,
      body: Row(
        children: [
          _DesktopSidebar(
            session: session,
            destinations: destinations,
            currentPath: path,
            collapsed: collapsed,
          ),
          Expanded(
            child: Column(
              children: [
                _DesktopTopBar(session: session, destinations: destinations),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<AppDestination> _destinationsFor(
    UserSession session,
    String teamLabel,
  ) => switch (session.role) {
    AppRole.landlord => [
      ..._landlordDestinations,
      _teamDestination(teamLabel),
      _subscriptionDestination,
      _exploreDestination,
    ],
    AppRole.staff => [
      for (final destination in _landlordDestinations)
        if (_staffCanOpen(session, destination.path)) destination,
      _exploreDestination,
    ],
    AppRole.tenant => const [..._tenantDestinations, _exploreDestination],
    AppRole.superAdmin ||
    AppRole.admin => const [..._staffDestinations, _exploreDestination],
    AppRole.client => const <AppDestination>[],
  };

  bool _staffCanOpen(UserSession session, String path) {
    if (path == '/dashboard') return session.permissions.isNotEmpty;
    final resource = switch (path) {
      '/properties' => AppResource.property,
      '/tenants' => AppResource.tenantRecord,
      '/finances' => AppResource.payment,
      '/maintenance' => AppResource.maintenanceRequest,
      '/listings' => AppResource.privateListing,
      '/documents' => AppResource.document,
      _ => null,
    };
    return resource != null &&
        AuthorizationPolicy.allowsSession(
          session,
          resource,
          CrudOperation.read,
        );
  }
}

class _DesktopSidebar extends ConsumerWidget {
  const _DesktopSidebar({
    required this.session,
    required this.destinations,
    required this.currentPath,
    required this.collapsed,
  });

  final UserSession session;
  final List<AppDestination> destinations;
  final String currentPath;
  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AnimatedContainer(
      duration: NyumbaMotion.reducedMotion(context)
          ? Duration.zero
          : NyumbaMotion.medium,
      curve: NyumbaMotion.easeOut,
      width: collapsed ? 84 : 232,
      decoration: BoxDecoration(
        color: context.nyumba.surface,
        border: BorderDirectional(
          end: BorderSide(color: context.nyumba.outline),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                collapsed ? 19 : 18,
                20,
                collapsed ? 19 : 18,
                22,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: NyumbaLogo(
                  compact: collapsed,
                  height: collapsed ? 44 : 45,
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                itemCount: destinations.length,
                separatorBuilder: (_, _) => const SizedBox(height: 5),
                itemBuilder: (context, index) {
                  final destination = destinations[index];
                  return _SidebarItem(
                    destination: destination,
                    selected: _isSelected(currentPath, destination.path),
                    collapsed: collapsed,
                    onTap: () => context.go(destination.path),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: _SidebarSyncStatus(collapsed: collapsed),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(11, 0, 11, 14),
              child: _SidebarProfile(
                session: session,
                collapsed: collapsed,
                onSignOut: () =>
                    ref.read(sessionControllerProvider.notifier).signOut(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final AppDestination destination;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final duration = NyumbaMotion.reducedMotion(context)
        ? Duration.zero
        : NyumbaMotion.medium;
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.onPrimary : context.nyumba.ink;
    return Tooltip(
      message: widget.collapsed ? widget.destination.label : '',
      child: Semantics(
        button: true,
        selected: selected,
        label: context.tr(widget.destination.label),
        child: AnimatedContainer(
          duration: duration,
          curve: NyumbaMotion.easeOut,
          height: 48,
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary
                : _hovered
                ? context.nyumba.navyTint
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              onHover: (value) => setState(() => _hovered = value),
              borderRadius: BorderRadius.circular(9),
              child: Row(
                mainAxisAlignment: widget.collapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  if (!widget.collapsed) const SizedBox(width: 14),
                  AnimatedScale(
                    scale: _hovered && !selected ? 1.08 : 1,
                    duration: duration,
                    curve: NyumbaMotion.easeOut,
                    child: Icon(
                      selected
                          ? widget.destination.selectedIcon
                          : widget.destination.icon,
                      size: 21,
                      color: selected
                          ? scheme.onPrimary
                          : context.nyumba.mutedInk,
                    ),
                  ),
                  if (!widget.collapsed) ...[
                    const SizedBox(width: 13),
                    Expanded(
                      child: AnimatedDefaultTextStyle(
                        duration: duration,
                        style:
                            Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: foreground,
                            ) ??
                            TextStyle(color: foreground),
                        child: Text.localized(widget.destination.label),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Live sync summary driven by the durable outbox instead of static copy.
class _SidebarSyncStatus extends ConsumerWidget {
  const _SidebarSyncStatus({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(outboxEntriesProvider);
    final (icon, tint, borderColor, iconColor, message) = entries.when(
      loading: () => (
        Icons.sync_rounded,
        context.nyumba.neutralTint,
        context.nyumba.outline,
        context.nyumba.mutedInk,
        'Checking sync status…',
      ),
      error: (_, _) => (
        Icons.cloud_off_outlined,
        context.nyumba.neutralTint,
        context.nyumba.outline,
        context.nyumba.mutedInk,
        'Sync status unavailable',
      ),
      data: (outbox) {
        final failed = outbox
            .where((entry) => entry.state == OutboxState.permanentlyFailed)
            .length;
        final pending = outbox.length - failed;
        if (failed > 0) {
          return (
            Icons.error_outline_rounded,
            context.nyumba.dangerTint,
            context.nyumba.dangerBorder,
            context.nyumba.danger,
            '$failed change${failed == 1 ? '' : 's'} failed to sync',
          );
        }
        if (pending > 0) {
          return (
            Icons.cloud_upload_outlined,
            context.nyumba.goldTint,
            context.nyumba.goldBorder,
            context.nyumba.terracottaDark,
            '$pending change${pending == 1 ? '' : 's'} waiting to sync',
          );
        }
        return (
          Icons.check_circle_outline_rounded,
          context.nyumba.sageTint,
          context.nyumba.sageBorder,
          context.nyumba.sageDark,
          'All changes synced',
        );
      },
    );

    return Tooltip(
      message: collapsed ? message : '',
      child: AnimatedContainer(
        duration: NyumbaMotion.reducedMotion(context)
            ? Duration.zero
            : NyumbaMotion.medium,
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: borderColor),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: collapsed ? 0 : 12,
          vertical: 11,
        ),
        child: Row(
          mainAxisAlignment: collapsed
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 19),
            if (!collapsed) ...[
              const SizedBox(width: 9),
              Expanded(
                child: Text.localized(
                  message,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SidebarProfile extends StatelessWidget {
  const _SidebarProfile({
    required this.session,
    required this.collapsed,
    required this.onSignOut,
  });

  final UserSession session;
  final bool collapsed;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: context.tr('Account menu'),
      onSelected: (value) {
        if (value == 'profile') context.go('/settings');
        if (value == 'sign-out') onSignOut();
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'profile',
          child: ListTile(
            leading: Icon(Icons.manage_accounts_outlined),
            title: Text.localized('Profile settings'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'sign-out',
          child: ListTile(
            leading: Icon(Icons.logout_rounded),
            title: Text.localized('Sign out'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      child: Container(
        height: 52,
        padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 9),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(9)),
        child: Row(
          mainAxisAlignment: collapsed
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            _Avatar(session: session, radius: 17),
            if (!collapsed) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.localized(
                      session.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    Text.localized(
                      localizedAppRole(
                        appLocalizationsOf(context),
                        session.role,
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.expand_more_rounded, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}

class _DesktopTopBar extends StatelessWidget {
  const _DesktopTopBar({required this.session, required this.destinations});

  final UserSession session;
  final List<AppDestination> destinations;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 30),
      decoration: BoxDecoration(
        color: context.nyumba.surface,
        border: Border(bottom: BorderSide(color: context.nyumba.outline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text.localized(
              '${_greeting()}, ${session.firstName}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (MediaQuery.sizeOf(context).width >= 1040)
            SizedBox(
              width: 300,
              child: TextField(
                textInputAction: TextInputAction.search,
                onSubmitted: (value) {
                  final query = value.trim().toLowerCase();
                  if (query.isEmpty) return;
                  final matches = destinations.where(
                    (item) =>
                        context.tr(item.label).toLowerCase().contains(query),
                  );
                  if (matches.isNotEmpty) {
                    context.go(matches.first.path);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text.localized(
                          'No workspace page matches "$value".',
                        ),
                      ),
                    );
                  }
                },
                decoration: InputDecoration(
                  hintText: context.tr('Search workspace'),
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
              ),
            ),
          const SizedBox(width: 14),
          const NotificationBell(),
          const SizedBox(width: 10),
          const LanguageMenuButton(compact: true),
          const SizedBox(width: 12),
          Tooltip(
            message: 'Profile settings',
            child: InkWell(
              onTap: () => context.go('/settings'),
              customBorder: const CircleBorder(),
              child: _Avatar(session: session),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileShell extends ConsumerWidget {
  const _MobileShell({
    required this.session,
    required this.destinations,
    required this.currentPath,
    required this.child,
  });

  final UserSession session;
  final List<AppDestination> destinations;
  final String currentPath;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = destinations.length <= 5
        ? destinations
        : [destinations[0], destinations[1], destinations[3], destinations[4]];
    final overflow = destinations
        .where((item) => !primary.contains(item))
        .toList();
    final selectedIndex = primary.indexWhere(
      (destination) => _isSelected(currentPath, destination.path),
    );
    final overflowSelected = overflow.any(
      (destination) => _isSelected(currentPath, destination.path),
    );

    return Scaffold(
      backgroundColor: context.nyumba.softIvory,
      appBar: AppBar(
        toolbarHeight: 68,
        backgroundColor: context.nyumba.surface,
        titleSpacing: 16,
        // Compact bars carry the cloud badge, notifications, language and
        // account actions; collapse to the mark-only lockup so nothing
        // overflows beside them.
        title: NyumbaLogo(compact: context.isCompact, height: 38),
        actions: [
          const CloudStatusBadge(),
          const NotificationBell(),
          const LanguageMenuButton(compact: true),
          PopupMenuButton<String>(
            tooltip: context.tr('Account menu'),
            onSelected: (value) {
              if (value == 'profile') context.go('/settings');
              if (value == 'sign-out') {
                ref.read(sessionControllerProvider.notifier).signOut();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  leading: Icon(Icons.manage_accounts_outlined),
                  title: Text.localized('Profile settings'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'sign-out',
                child: ListTile(
                  leading: Icon(Icons.logout_rounded),
                  title: Text.localized('Sign out'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _Avatar(session: session, radius: 17),
            ),
          ),
        ],
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: overflowSelected
            ? primary.length
            : selectedIndex < 0
            ? 0
            : selectedIndex,
        onDestinationSelected: (index) {
          if (index < primary.length) {
            context.go(primary[index].path);
            return;
          }
          _showMoreDestinations(context, overflow);
        },
        destinations: [
          for (final destination in primary)
            NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: context.tr(destination.compactLabel),
              tooltip: context.tr(destination.label),
            ),
          if (overflow.isNotEmpty)
            NavigationDestination(
              icon: const Icon(Icons.more_horiz_rounded),
              selectedIcon: const Icon(Icons.more_rounded),
              label: context.tr('More'),
            ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.session, this.radius = 20});

  final UserSession session;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final parts = session.displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty);
    final initials = parts
        .take(2)
        .map((part) => part.characters.first)
        .join()
        .toUpperCase();
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      // An account with no name yet still needs a recognisable account
      // affordance; a "?" reads as an unanswered question, not as "you".
      child: initials.isEmpty
          ? Icon(
              Icons.person_rounded,
              size: radius * 1.1,
              color: scheme.onPrimary,
            )
          : Text.localized(
              initials,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: scheme.onPrimary),
            ),
    );
  }
}

String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

bool _isSelected(String currentPath, String destinationPath) {
  if (currentPath == destinationPath) return true;
  if (destinationPath == '/dashboard' ||
      destinationPath == '/tenant' ||
      destinationPath == '/admin') {
    return false;
  }
  return currentPath.startsWith('$destinationPath/');
}

void _showMoreDestinations(
  BuildContext context,
  List<AppDestination> destinations,
) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(24, 4, 24, 10),
            child: Text.localized(
              'More',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          // Staff sessions route eight destinations through this sheet, more
          // than a phone-height sheet can show at once, so the list scrolls
          // within the sheet instead of overflowing past it.
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 20),
              children: [
                for (final destination in destinations)
                  ListTile(
                    leading: Icon(destination.icon),
                    title: Text.localized(destination.label),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.pop(context);
                      context.go(destination.path);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
