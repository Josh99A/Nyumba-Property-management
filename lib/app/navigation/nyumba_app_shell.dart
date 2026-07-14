import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/nyumba_colors.dart';
import '../../core/offline/outbox_entry.dart';
import '../../core/presentation/motion.dart';
import '../../core/presentation/nyumba_logo.dart';
import '../../core/presentation/responsive.dart';
import '../../features/auth/application/session_controller.dart';
import '../../features/auth/domain/user_session.dart';
import '../bootstrap/app_dependencies.dart';

class AppDestination {
  const AppDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.path,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;
}

const _landlordDestinations = [
  AppDestination(
    label: 'Overview',
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
    label: 'Overview',
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
    label: 'Subscriptions',
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
];

class NyumbaAppShell extends ConsumerWidget {
  const NyumbaAppShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    if (session == null) return child;
    final destinations = _destinationsFor(session.role);
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

  List<AppDestination> _destinationsFor(AppRole role) => switch (role) {
    AppRole.landlord => _landlordDestinations,
    AppRole.tenant => _tenantDestinations,
    AppRole.admin => _adminDestinations,
    AppRole.client => const <AppDestination>[],
  };
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
        border: Border(right: BorderSide(color: context.nyumba.outline)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                collapsed ? 19 : 18,
                20,
                collapsed ? 19 : 18,
                22,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
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
              padding: const EdgeInsets.fromLTRB(11, 0, 11, 14),
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
        label: widget.destination.label,
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
                        child: Text(widget.destination.label),
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
                child: Text(
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
      tooltip: 'Account menu',
      onSelected: (value) {
        if (value == 'profile') context.go('/settings');
        if (value == 'sign-out') onSignOut();
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'profile',
          child: ListTile(
            leading: Icon(Icons.manage_accounts_outlined),
            title: Text('Profile settings'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'sign-out',
          child: ListTile(
            leading: Icon(Icons.logout_rounded),
            title: Text('Sign out'),
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
                    Text(
                      session.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    Text(
                      session.role.name,
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
            child: Text(
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
                    (item) => item.label.toLowerCase().contains(query),
                  );
                  if (matches.isNotEmpty) {
                    context.go(matches.first.path);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('No workspace page matches "$value".'),
                      ),
                    );
                  }
                },
                decoration: const InputDecoration(
                  hintText: 'Search workspace',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
              ),
            ),
          const SizedBox(width: 14),
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => _showNotifications(context),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
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
        title: const NyumbaLogo(height: 38),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => _showNotifications(context),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'Account menu',
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
                  title: Text('Profile settings'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'sign-out',
                child: ListTile(
                  leading: Icon(Icons.logout_rounded),
                  title: Text('Sign out'),
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
              label: destination.label,
            ),
          if (overflow.isNotEmpty)
            const NavigationDestination(
              icon: Icon(Icons.more_horiz_rounded),
              selectedIcon: Icon(Icons.more_rounded),
              label: 'More',
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
    final initials = parts.isEmpty
        ? '?'
        : parts.take(2).map((part) => part[0]).join().toUpperCase();
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      child: Text(
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

Future<void> _showNotifications(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Notifications',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Icon(Icons.sync_rounded)),
              title: Text('Sync status is available in the workspace'),
              subtitle: Text(
                'Pending, rejected, and confirmed changes are shown locally.',
              ),
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                child: Icon(Icons.notifications_none_rounded),
              ),
              title: Text('No unread notifications'),
              subtitle: Text('New local alerts will appear here.'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    ),
  );
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
              child: Text(
                'More',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final destination in destinations)
              ListTile(
                leading: Icon(destination.icon),
                title: Text(destination.label),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(context);
                  context.go(destination.path);
                },
              ),
          ],
        ),
      ),
    ),
  );
}
