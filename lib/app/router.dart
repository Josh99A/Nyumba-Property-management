import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/presentation/admin_overview_screen.dart';
import '../features/admin/presentation/admin_access_operations_screen.dart';
import '../features/admin/presentation/admin_broadcast_screen.dart';
import '../features/admin/presentation/admin_portfolio_screen.dart';
import '../features/admin/presentation/admin_reports_screen.dart';
import '../features/admin/presentation/admin_subscriptions_screen.dart';
import '../features/admin/presentation/admin_support_screen.dart';
import '../features/admin/presentation/admin_users_screen.dart';
import '../features/auth/application/session_controller.dart';
import '../features/auth/domain/authorization_policy.dart';
import '../features/auth/domain/user_session.dart';
import '../features/auth/presentation/onboarding_screen.dart';
import '../features/auth/presentation/sign_in_screen.dart';
import '../features/auth/presentation/sign_up_screen.dart';
import '../features/dashboard/presentation/landlord_dashboard_screen.dart';
import '../features/documents/presentation/documents_screen.dart';
import '../features/finance/presentation/finance_screen.dart';
import '../features/maintenance/presentation/maintenance_screen.dart';
import '../features/marketplace/presentation/landlord_listings_screen.dart';
import '../features/marketplace/presentation/listing_detail_screen.dart';
import '../features/marketplace/presentation/public/listing_query.dart';
import '../features/marketplace/presentation/public_listings_screen.dart';
import '../features/marketplace/presentation/public_search_screen.dart';
import '../features/portfolio/presentation/properties_screen.dart';
import '../features/portfolio/presentation/property_detail_screen.dart';
import '../features/admin/presentation/admin_feedback_screen.dart';
import '../features/admin/presentation/admin_reviews_screen.dart';
import '../features/profile/presentation/profile_settings_screen.dart';
import '../features/reviews/presentation/landlord_reviews_screen.dart';
import '../features/reviews/presentation/tenant_reviews_screen.dart';
import '../features/staff/presentation/team_screen.dart';
import '../features/support/presentation/support_screen.dart';
import '../features/support/presentation/support_thread_screen.dart';
import '../features/subscriptions/presentation/landlord_subscription_screen.dart';
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
        redirectForLocation(ref.read(sessionControllerProvider), state.uri),
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
        path: '/sign-up',
        pageBuilder: (context, state) =>
            _transitionPage(state: state, child: const SignUpScreen()),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) =>
            _transitionPage(state: state, child: const OnboardingScreen()),
      ),
      GoRoute(
        path: '/subscription',
        pageBuilder: (context, state) => _transitionPage(
          state: state,
          child: const LandlordSubscriptionScreen(),
        ),
      ),
      GoRoute(
        path: '/explore',
        pageBuilder: (context, state) =>
            _transitionPage(state: state, child: const PublicListingsScreen()),
      ),
      GoRoute(
        path: '/search',
        pageBuilder: (context, state) => _transitionPage(
          state: state,
          // Parsed here rather than inside the screen so a linked, reloaded, or
          // back-navigated search restores exactly the filters it was shared
          // with.
          child: PublicSearchScreen(
            initialQuery: ListingQuery.fromQueryParameters(
              state.uri.queryParameters,
            ),
          ),
        ),
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
              child: LandlordListingsScreen(
                initialUnitId: state.uri.queryParameters['unitId'],
              ),
            ),
          ),
          GoRoute(
            path: '/documents',
            pageBuilder: (context, state) =>
                _transitionPage(state: state, child: const DocumentsScreen()),
          ),
          GoRoute(
            path: '/reviews',
            pageBuilder: (context, state) => _transitionPage(
              state: state,
              child: const LandlordReviewsScreen(),
            ),
          ),
          GoRoute(
            path: '/team',
            pageBuilder: (context, state) =>
                _transitionPage(state: state, child: const TeamScreen()),
          ),
          GoRoute(
            path: '/support',
            pageBuilder: (context, state) => _transitionPage(
              state: state,
              // `?compose=true` is what the contextual entry points link to, so
              // a landlord who tapped "Contact support" on a failed payment
              // lands in the composer rather than on a page they must act on
              // again. Parsed here so a reload or a back-navigation restores it.
              child: SupportScreen(
                openComposerOnLoad:
                    state.uri.queryParameters['compose'] == 'true',
              ),
            ),
            routes: [
              GoRoute(
                path: ':ticketId',
                pageBuilder: (context, state) => _transitionPage(
                  state: state,
                  child: SupportThreadScreen(
                    ticketId: state.pathParameters['ticketId']!,
                  ),
                ),
              ),
            ],
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
              GoRoute(
                path: 'reviews',
                pageBuilder: (context, state) => _transitionPage(
                  state: state,
                  child: const TenantReviewsScreen(),
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
                path: 'access',
                pageBuilder: (context, state) => _transitionPage(
                  state: state,
                  child: const AdminAccessOperationsScreen(),
                ),
              ),
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
              GoRoute(
                path: 'broadcast',
                pageBuilder: (context, state) => _transitionPage(
                  state: state,
                  child: const AdminBroadcastScreen(),
                ),
              ),
              GoRoute(
                path: 'portfolio',
                pageBuilder: (context, state) => _transitionPage(
                  state: state,
                  child: const AdminPortfolioScreen(),
                ),
              ),
              GoRoute(
                path: 'reviews',
                pageBuilder: (context, state) => _transitionPage(
                  state: state,
                  child: const AdminReviewsScreen(),
                ),
              ),
              GoRoute(
                path: 'feedback',
                pageBuilder: (context, state) => _transitionPage(
                  state: state,
                  child: const AdminFeedbackScreen(),
                ),
              ),
              GoRoute(
                path: 'support',
                pageBuilder: (context, state) => _transitionPage(
                  state: state,
                  child: const AdminSupportScreen(),
                ),
                routes: [
                  // The deep link the support alert email carries, so an agent
                  // opens the ticket they were told about rather than the top
                  // of the queue.
                  GoRoute(
                    path: ':ticketId',
                    pageBuilder: (context, state) => _transitionPage(
                      state: state,
                      child: AdminSupportScreen(
                        initialTicketId: state.pathParameters['ticketId'],
                      ),
                    ),
                  ),
                ],
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

@visibleForTesting
String? redirectForSession(UserSession? session, String path) {
  final publicPath =
      path == '/' ||
      path == '/sign-in' ||
      path == '/sign-up' ||
      path == '/explore' ||
      path == '/search' ||
      path.startsWith('/listing/');
  if (session == null) return publicPath ? null : '/sign-in';

  // A signed-in account without a workspace role (fresh landlord sign-up or a
  // tenant whose invitation has not been claimed yet) completes onboarding.
  final needsOnboarding =
      session.role == AppRole.client && !session.isAnonymous;
  final home =
      session.workspacePath ?? (needsOnboarding ? '/onboarding' : '/explore');
  if (path == '/sign-in' || path == '/sign-up') return home;
  if (path == '/onboarding') return needsOnboarding ? null : home;
  if (path == '/subscription') {
    // Landlords can always open their subscription: it is the payment gate
    // before activation and the self-service upgrade path afterwards.
    return session.role == AppRole.landlord ? null : home;
  }
  final supportPath = path == '/support' || path.startsWith('/support/');
  if (supportPath && session.role == AppRole.landlord) {
    // Cleared ahead of the subscription gate below, deliberately. That gate
    // sends an unconfirmed landlord to the payment screen, which would put
    // "my payment was not confirmed" behind the very screen they cannot get
    // past — a support channel that closes on the day it is needed. The
    // command behind it makes the same allowance for the same reason.
    return null;
  }
  if (publicPath) return null;
  if (session.role == AppRole.landlord && !session.hasConfirmedSubscription) {
    return '/subscription';
  }
  // A staff member cannot open the payment gate, so a lapsed owner workspace
  // sends them home rather than to the subscription screen.
  if (session.role == AppRole.staff && !session.hasConfirmedSubscription) {
    return home;
  }

  final adminPath = path == '/admin' || path.startsWith('/admin/');
  final portfolioResource = switch (path) {
    '/properties' => AppResource.property,
    _ when path.startsWith('/properties/') => AppResource.property,
    '/tenants' => AppResource.tenantRecord,
    '/finances' => AppResource.payment,
    '/maintenance' => AppResource.maintenanceRequest,
    '/listings' => AppResource.privateListing,
    '/documents' => AppResource.document,
    _ => null,
  };
  final portfolioAllowed = path == '/dashboard'
      ? switch (session.role) {
          AppRole.landlord ||
          AppRole.staff ||
          AppRole.admin ||
          AppRole.superAdmin => true,
          _ => false,
        }
      : portfolioResource != null &&
            AuthorizationPolicy.allowsSession(
              session,
              portfolioResource,
              CrudOperation.read,
            );
  // Managing the team (staff seats) is the owner's alone; staff never see it.
  final teamPath = path == '/team';
  // Reviews left for the landlord's tenants are workspace data, so staff read
  // and respond to them the same as any other portfolio resource.
  final reviewsPath = path == '/reviews';
  final allowed =
      path == '/settings' ||
      // Owner-only, matching the Firestore rule: a support thread routinely
      // names billing state and account access, and no staff capability covers
      // the owner's correspondence with Nyumba. Landlords already returned
      // above; this leaves the path closed to every other role.
      (supportPath && session.role == AppRole.landlord) ||
      (adminPath &&
          AuthorizationPolicy.allowsSession(
            session,
            AppResource.userAccount,
            CrudOperation.read,
          )) ||
      portfolioAllowed ||
      (teamPath && session.role == AppRole.landlord) ||
      (reviewsPath &&
          (session.role == AppRole.landlord ||
              session.role == AppRole.staff)) ||
      (session.role == AppRole.tenant &&
          (path == '/tenant' || path.startsWith('/tenant/')));
  return allowed ? null : home;
}

/// Preserves an authenticated deep link while the session is hydrating.
///
/// GoRouter evaluates redirects before Firebase has restored the user. The old
/// redirect replaced a private URL with `/sign-in`, then sent the restored
/// session to its generic home, so a refresh of a property or listing always
/// lost the page (and query parameters) the person was using.
@visibleForTesting
String? redirectForLocation(UserSession? session, Uri location) {
  final pathRedirect = redirectForSession(session, location.path);
  if (session == null) {
    if (pathRedirect != '/sign-in') return pathRedirect;
    return Uri(
      path: '/sign-in',
      queryParameters: <String, String>{'redirect': location.toString()},
    ).toString();
  }

  if (location.path == '/sign-in' || location.path == '/sign-up') {
    final target = _safeLocalRedirect(location.queryParameters['redirect']);
    if (target != null && redirectForSession(session, target.path) == null) {
      return target.toString();
    }
  }
  return pathRedirect;
}

Uri? _safeLocalRedirect(String? raw) {
  if (raw == null ||
      raw.isEmpty ||
      !raw.startsWith('/') ||
      raw.startsWith('//')) {
    return null;
  }
  final target = Uri.tryParse(raw);
  if (target == null ||
      target.hasScheme ||
      target.hasAuthority ||
      target.path == '/sign-in' ||
      target.path == '/sign-up') {
    return null;
  }
  return target;
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
              Text.localized(
                'We could not open this page',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text.localized(message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => context.go('/explore'),
                child: const Text.localized('Browse available homes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
