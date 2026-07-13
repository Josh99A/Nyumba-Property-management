import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/nyumba_colors.dart';
import '../../core/presentation/nyumba_logo.dart';
import '../../core/presentation/responsive.dart';
import '../../features/auth/application/session_controller.dart';
import '../../features/auth/domain/user_session.dart';

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
      backgroundColor: NyumbaColors.softIvory,
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
                _DesktopTopBar(session: session),
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
    return Container(
      width: collapsed ? 84 : 232,
      decoration: const BoxDecoration(
        color: NyumbaColors.surface,
        border: Border(right: BorderSide(color: NyumbaColors.outline)),
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
                  final selected = _isSelected(currentPath, destination.path);
                  return Tooltip(
                    message: collapsed ? destination.label : '',
                    child: Material(
                      color: selected
                          ? NyumbaColors.midnightNavy
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      child: InkWell(
                        onTap: () => context.go(destination.path),
                        borderRadius: BorderRadius.circular(9),
                        child: SizedBox(
                          height: 48,
                          child: Row(
                            mainAxisAlignment: collapsed
                                ? MainAxisAlignment.center
                                : MainAxisAlignment.start,
                            children: [
                              if (!collapsed) const SizedBox(width: 14),
                              Icon(
                                selected
                                    ? destination.selectedIcon
                                    : destination.icon,
                                size: 21,
                                color: selected
                                    ? Colors.white
                                    : NyumbaColors.mutedInk,
                              ),
                              if (!collapsed) ...[
                                const SizedBox(width: 13),
                                Expanded(
                                  child: Text(
                                    destination.label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: selected
                                              ? Colors.white
                                              : NyumbaColors.ink,
                                        ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: NyumbaColors.sageTint,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: const Color(0xFFCDE4D2)),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: collapsed ? 0 : 12,
                    vertical: 11,
                  ),
                  child: Row(
                    mainAxisAlignment: collapsed
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.check_circle_outline_rounded,
                        color: NyumbaColors.sageDark,
                        size: 19,
                      ),
                      if (!collapsed) ...[
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'Synced just now',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
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
        if (value == 'sign-out') onSignOut();
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'profile', child: Text('Profile settings')),
        PopupMenuItem(value: 'sign-out', child: Text('Sign out')),
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
  const _DesktopTopBar({required this.session});

  final UserSession session;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 30),
      decoration: const BoxDecoration(
        color: NyumbaColors.surface,
        border: Border(bottom: BorderSide(color: NyumbaColors.outline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Good morning, ${session.firstName}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (MediaQuery.sizeOf(context).width >= 1040)
            SizedBox(
              width: 300,
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search properties, tenants…',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Searching for “${value.trim()}”'),
                      ),
                    );
                  }
                },
              ),
            ),
          const SizedBox(width: 14),
          Badge(
            label: const Text('3'),
            child: IconButton(
              tooltip: 'Notifications',
              onPressed: () => _showNotifications(context),
              icon: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          const SizedBox(width: 12),
          _Avatar(session: session),
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
      backgroundColor: NyumbaColors.softIvory,
      appBar: AppBar(
        toolbarHeight: 68,
        backgroundColor: NyumbaColors.surface,
        titleSpacing: 16,
        title: const NyumbaLogo(height: 38),
        actions: [
          Badge(
            label: const Text('3'),
            child: IconButton(
              tooltip: 'Notifications',
              onPressed: () => _showNotifications(context),
              icon: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Account menu',
            onSelected: (value) {
              if (value == 'sign-out') {
                ref.read(sessionControllerProvider.notifier).signOut();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'profile', child: Text('Profile settings')),
              PopupMenuItem(value: 'sign-out', child: Text('Sign out')),
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
    final parts = session.displayName.trim().split(RegExp(r'\s+'));
    final initials = parts.take(2).map((part) => part[0]).join().toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: NyumbaColors.midnightNavy,
      foregroundColor: Colors.white,
      child: Text(
        initials,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: Colors.white),
      ),
    );
  }
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

void _showNotifications(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notifications',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Icon(Icons.payments_outlined)),
              title: Text('Rent received from Brian Otieno'),
              subtitle: Text('KES 45,000 · 20 minutes ago'),
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Icon(Icons.build_outlined)),
              title: Text('New maintenance request'),
              subtitle: Text('Leaking tap in kitchen · 1 hour ago'),
            ),
          ],
        ),
      ),
    ),
  );
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
