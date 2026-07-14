import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/presentation/admin_overview_screen.dart';
import '../features/admin/presentation/admin_reports_screen.dart';
import '../features/admin/presentation/admin_subscriptions_screen.dart';
import '../features/admin/presentation/admin_users_screen.dart';
import '../features/auth/application/session_controller.dart';
import '../features/auth/domain/user_session.dart';
import '../features/auth/presentation/sign_in_screen.dart';
import '../features/dashboard/presentation/landlord_dashboard_screen.dart';
import '../features/documents/presentation/documents_screen.dart';
import '../features/finance/presentation/finance_screen.dart';
import '../features/maintenance/presentation/maintenance_screen.dart';
import '../features/marketplace/presentation/landlord_listings_screen.dart';
import '../features/marketplace/presentation/listing_detail_screen.dart';
import '../features/marketplace/presentation/public_listings_screen.dart';
import '../features/portfolio/presentation/properties_screen.dart';
import '../features/portfolio/presentation/property_detail_screen.dart';
import '../features/profile/presentation/profile_settings_screen.dart';
import '../features/tenant_portal/presentation/tenant_documents_screen.dart';
import '../features/tenant_portal/presentation/tenant_home_screen.dart';
import '../features/tenant_portal/presentation/tenant_maintenance_screen.dart';
import '../features/tenant_portal/presentation/tenant_payments_screen.dart';
import '../features/tenants/presentation/tenants_screen.dart';
import 'navigation/nyumba_app_shell.dart';

/// Calm fade-and-rise transition shared by every route. Falls back to an
/// immediate swap when the platform requests reduced motion.
CustomTransitionPage<void> _transitionPage({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        return child;
      }
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, .015),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier();
  ref.listen<UserSession?>(sessionControllerProvider, (_, _) {
    refreshNotifier.refresh();
  });
  ref.onDispose(refreshNotifier.dispose);

  final router = GoRouter(
    initialLocation: '/explore',
    debugLogDiagnostics: false,
    refreshListenable: refreshNotifier,
    redirect: (context, state) =>
        _redirect(ref.read(sessionControllerProvider), state.uri.path),
    errorBuilder: (context, state) => _RouteNotFoundScreen(
      message: state.error?.toString() ?? 'Page not found',
    ),
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/explore'),
      GoRoute(
        path: '/sign-in',
        pageBuilder: (context, state) =>
            _transitionPage(state: state, child: const SignInScreen()),
      ),
      GoRoute(
        path: '/explore',
        pageBuilder: (context, state) =>
            _transitionPage(state: state, child: const PublicListingsScreen()),
      ),
      GoRoute(
        path: '/listing/:listingId',
        pageBuilder: (context, state) => _transitionPage(
          state: state,
          child: ListingDetailScreen(
            listingId: state.pathParameters['listingId']!,
          ),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => NyumbaAppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (context, state) => _transitionPage(
              state: state,
              child: const LandlordDashboardScreen(),
            ),
          ),
          GoRoute(
            path: '/properties',
            pageBuilder: (context, state) =>
                _transitionPage(state: state, child: const PropertiesScreen()),
            routes: [
              GoRoute(
                path: 'new',
                pageBuilder: (context, state) => _transitionPage(
                  state: state,
                  child: const PropertiesScreen(openCreateOnLoad: true),
                ),
              ),
              GoRoute(
                path: ':propertyId',
                pageBuilder: (context, state) => _transitionPage(
                  state: state,
                  child: PropertyDetailScreen(
                    propertyId: state.pathParameters['propertyId']!,
                    openAddUnitOnLoad:
                        state.uri.queryParameters['addUnit'] == 'true',
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/tenants',
            pageBuilder: (context, state) =>
                _transitionPage(state: state, child: const TenantsScreen()),
          ),
          GoRoute(
            path: '/finances',
            pageBuilder: (context, state) =>
                _transitionPage(state: state, child: const FinanceScreen()),
          ),
          GoRoute(
            path: '/maintenance',
            pageBuilder: (context, state) =>
                _transitionPage(state: state, child: const MaintenanceScreen()),
          ),
          GoRoute(
            path: '/listings',
            pageBuilder: (context, state) => _transitionPage(
              state: state,
              child: const LandlordListingsScreen(),
            ),
          ),
          GoRoute(
            path: '/documents',
            pageBuilder: (context, state) =>
                _transitionPage(state: state, child: const DocumentsScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => _transitionPage(
              state: state,
              child: const ProfileSettingsScreen(),
            ),
          ),
          GoRoute(
            path: '/tenant',
            pageBuilder: (context, state) =>
                _transitionPage(state: state, child: const TenantHomeScreen()),
            routes: [
              GoRoute(
                path: 'payments',
                pageBuilder: (context, state) => _transitionPage(
                  state: state,
                  child: const TenantPaymentsScreen(),
                ),
              ),
              GoRoute(
                path: 'maintenance',
                pageBuilder: (context, state) => _transitionPage(
                  state: state,
                  child: const TenantMaintenanceScreen(),
                ),
              ),
              GoRoute(
                path: 'documents',
                pageBuilder: (context, state) => _transitionPage(
                  state: state,
                  child: const TenantDocumentsScreen(),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/admin',
            pageBuilder: (context, state) => _transitionPage(
              state: state,
              child: const AdminOverviewScreen(),
            ),
            routes: [
              GoRoute(
                path: 'users',
                pageBuilder: (context, state) => _transitionPage(
                  state: state,
                  child: const AdminUsersScreen(),
                ),
              ),
              GoRoute(
                path: 'subscriptions',
                pageBuilder: (context, state) => _transitionPage(
                  state: state,
                  child: const AdminSubscriptionsScreen(),
                ),
              ),
              GoRoute(
                path: 'reports',
                pageBuilder: (context, state) => _transitionPage(
                  state: state,
                  child: const AdminReportsScreen(),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

String? _redirect(UserSession? session, String path) {
  final publicPath =
      path == '/' ||
      path == '/sign-in' ||
      path == '/explore' ||
      path.startsWith('/listing/');
  if (session == null) return publicPath ? null : '/sign-in';

  final home = switch (session.role) {
    AppRole.landlord => '/dashboard',
    AppRole.tenant => '/tenant',
    AppRole.admin => '/admin',
  };
  if (path == '/sign-in') return home;
  if (publicPath) return null;

  final allowed = switch (session.role) {
    AppRole.landlord =>
      path == '/settings' ||
          path == '/dashboard' ||
          path == '/properties' ||
          path.startsWith('/properties/') ||
          path == '/tenants' ||
          path == '/finances' ||
          path == '/maintenance' ||
          path == '/listings' ||
          path == '/documents',
    AppRole.tenant =>
      path == '/settings' || path == '/tenant' || path.startsWith('/tenant/'),
    AppRole.admin =>
      path == '/settings' || path == '/admin' || path.startsWith('/admin/'),
  };
  return allowed ? null : home;
}

class _RouteNotFoundScreen extends StatelessWidget {
  const _RouteNotFoundScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_off_outlined, size: 54),
              const SizedBox(height: 16),
              Text(
                'We could not open this page',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => context.go('/explore'),
                child: const Text('Browse available homes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
