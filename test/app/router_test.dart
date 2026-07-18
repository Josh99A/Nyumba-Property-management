import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/router.dart';
import 'package:nyumba_property_management/features/auth/application/session_controller.dart';
import 'package:nyumba_property_management/features/auth/domain/user_session.dart';
import 'package:nyumba_property_management/features/marketplace/presentation/public_listings_screen.dart';
import 'package:nyumba_property_management/features/subscriptions/presentation/landlord_subscription_screen.dart';

class _PendingLandlordSessionController extends SessionController {
  @override
  UserSession? build() => const UserSession(
    userId: 'landlord-pending',
    displayName: 'Pending Landlord',
    email: 'pending@nyumba.test',
    role: AppRole.landlord,
    subscriptionStatus: LandlordSubscriptionStatus.pendingPayment,
    subscriptionTier: 'starter',
  );
}

class _StubSessionController extends SessionController {
  _StubSessionController(this.session);

  final UserSession? session;

  @override
  UserSession? build() => session;
}

void main() {
  test('landlord workspace stays locked until payment is confirmed', () {
    const pending = UserSession(
      userId: 'landlord-pending',
      displayName: 'Pending Landlord',
      email: 'pending@nyumba.test',
      role: AppRole.landlord,
      subscriptionStatus: LandlordSubscriptionStatus.pendingPayment,
      subscriptionTier: 'starter',
    );
    const active = UserSession(
      userId: 'landlord-active',
      displayName: 'Active Landlord',
      email: 'active@nyumba.test',
      role: AppRole.landlord,
      subscriptionStatus: LandlordSubscriptionStatus.active,
      subscriptionTier: 'starter',
    );

    expect(redirectForSession(pending, '/dashboard'), '/subscription');
    expect(redirectForSession(pending, '/properties'), '/subscription');
    expect(redirectForSession(pending, '/subscription'), isNull);
    expect(redirectForSession(active, '/dashboard'), isNull);
    expect(redirectForSession(active, '/subscription'), '/dashboard');
  });

  testWidgets('subscription gate renders at desktop and phone sizes', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final size in const [Size(1280, 900), Size(390, 844)]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionControllerProvider.overrideWith(
              _PendingLandlordSessionController.new,
            ),
          ],
          child: const MaterialApp(home: LandlordSubscriptionScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Choose your plan'), findsOneWidget);
      expect(find.text('Awaiting payment confirmation'), findsOneWidget);
      // The reserved starter tier shows as selected; the other tiers stay
      // choosable. Without Firebase the catalog is empty, so no capacity
      // number may appear anywhere.
      expect(find.text('Selected'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Choose plan'),
        findsNWidgets(3),
      );
      expect(find.textContaining('rental spaces'), findsNothing);
      expect(
        tester.takeException(),
        isNull,
        reason:
            'subscription gate should render at ${size.width}x${size.height}',
      );
    }
  });

  testWidgets('role changes refresh one stable router instance', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final router = container.read(routerProvider);
    router.go('/sign-in');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);

    container
        .read(sessionControllerProvider.notifier)
        .startDemo(AppRole.landlord);
    // The dashboard owns live local streams and entrance animations, so it is
    // intentionally not a permanently settled frame.
    await _pumpFor(tester, const Duration(seconds: 2));

    expect(container.read(routerProvider), same(router));
    expect(router.routeInformationProvider.value.uri.path, '/dashboard');
    expect(find.text('Your portfolio at a glance'), findsOneWidget);
  });

  testWidgets('tenant documents route lays out document cards', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final router = container.read(routerProvider);
    container
        .read(sessionControllerProvider.notifier)
        .startDemo(AppRole.tenant);
    router.go('/tenant/documents');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Documents'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'Request document'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Send request'));
    await tester.pumpAndSettle();

    expect(find.text('Rent clearance letter request'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('every actor may browse the public marketplace', () {
    // The explore catalogue and any listing detail are reachable by every
    // session, including an unpaid landlord whose workspace is otherwise
    // locked and a signed-out visitor.
    const roles = [
      null,
      UserSession(
        userId: 'unpaid-landlord',
        displayName: 'Unpaid Landlord',
        email: 'unpaid@nyumba.test',
        role: AppRole.landlord,
        subscriptionStatus: LandlordSubscriptionStatus.pendingPayment,
      ),
      UserSession(
        userId: 't',
        displayName: 'Tenant',
        email: 't@nyumba.test',
        role: AppRole.tenant,
      ),
      UserSession(
        userId: 'a',
        displayName: 'Admin',
        email: 'a@nyumba.test',
        role: AppRole.admin,
      ),
    ];
    for (final session in roles) {
      expect(
        redirectForSession(session, '/explore'),
        isNull,
        reason: '${session?.role.name ?? 'visitor'} should reach /explore',
      );
      expect(
        redirectForSession(session, '/listing/abc'),
        isNull,
        reason: '${session?.role.name ?? 'visitor'} should open a listing',
      );
    }
  });

  testWidgets('the workspace shell links every role to the explore page', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final role in const [
      AppRole.landlord,
      AppRole.tenant,
      AppRole.admin,
    ]) {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final router = container.read(routerProvider);
      container.read(sessionControllerProvider.notifier).startDemo(role);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      // The app opens on the public catalogue (initialLocation '/explore'),
      // which is reachable by every role; navigate into the workspace shell
      // via the neutral settings route (allowed for all roles, and free of the
      // dashboard's intrinsic-layout quirk) to confirm the shell links back
      // out. appDependenciesProvider never resolves under the test harness (no
      // path_provider), so pumpAndSettle would hang; bounded pumps suffice.
      router.go('/settings');
      await _pumpFor(tester, const Duration(seconds: 1));

      final explore = find.text('Explore homes');
      expect(
        explore,
        findsOneWidget,
        reason: '${role.name} shell should list the explore destination',
      );
      await tester.tap(explore);
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(router.routeInformationProvider.value.uri.path, '/explore');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the explore page routes signed-in actors back to a workspace', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // A signed-in actor sees a route home instead of a redundant sign-in
    // prompt; a visitor still gets the sign-in call to action.
    for (final (session, expectWorkspace) in [
      (null, false),
      (
        const UserSession(
          userId: 't',
          displayName: 'Tenant',
          email: 't@nyumba.test',
          role: AppRole.tenant,
          isDemo: true,
        ),
        true,
      ),
    ]) {
      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey(expectWorkspace),
          overrides: [
            sessionControllerProvider.overrideWith(
              () => _StubSessionController(session),
            ),
          ],
          child: const MaterialApp(home: PublicListingsScreen()),
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 1));

      expect(find.text('My workspace'), findsExactly(expectWorkspace ? 1 : 0));
      expect(find.text('Sign in'), findsExactly(expectWorkspace ? 0 : 1));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('tenant portal routes render at desktop and phone sizes', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    container
        .read(sessionControllerProvider.notifier)
        .startDemo(AppRole.tenant);
    final router = container.read(routerProvider);

    for (final size in const [Size(1280, 720), Size(390, 844)]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;

      for (final route in const [
        '/tenant',
        '/tenant/payments',
        '/tenant/maintenance',
        '/tenant/documents',
      ]) {
        router.go(route);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '$route should render at ${size.width}x${size.height}',
        );
      }
    }
  });

  testWidgets('landlord workspace routes render at desktop and phone sizes', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    container
        .read(sessionControllerProvider.notifier)
        .startDemo(AppRole.landlord);
    final router = container.read(routerProvider);

    for (final size in const [Size(1280, 720), Size(390, 844)]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;

      for (final route in const [
        '/dashboard',
        '/properties',
        '/tenants',
        '/finances',
        '/maintenance',
        '/listings',
        '/documents',
        '/settings',
      ]) {
        router.go(route);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '$route should render at ${size.width}x${size.height}',
        );
      }
    }
  });

  testWidgets('admin workspace routes render at desktop and phone sizes', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    container.read(sessionControllerProvider.notifier).startDemo(AppRole.admin);
    final router = container.read(routerProvider);

    for (final size in const [Size(1280, 720), Size(390, 844)]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;

      for (final route in const [
        '/admin',
        '/admin/access',
        '/admin/users',
        '/admin/subscriptions',
        '/admin/reports',
        '/dashboard',
        '/properties',
        '/tenants',
        '/finances',
        '/maintenance',
        '/listings',
        '/documents',
      ]) {
        router.go(route);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '$route should render at ${size.width}x${size.height}',
        );
      }
    }
  });

  testWidgets('the More sheet scrolls instead of overflowing on a phone', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    // Short phone: a staff session routes eight destinations through the
    // sheet, more rows than this height can show without scrolling.
    tester.view.physicalSize = const Size(360, 640);

    container.read(sessionControllerProvider.notifier).startDemo(AppRole.admin);
    final router = container.read(routerProvider);
    router.go('/admin');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: 'opening the sheet must not overflow',
    );

    // The deepest destination stays reachable by scrolling within the sheet.
    await tester.dragUntilVisible(
      find.text('Documents'),
      find.byType(ListView).last,
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Documents'), findsOneWidget);
  });

  testWidgets('super admin can open admin and portfolio workspaces', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(sessionControllerProvider.notifier)
        .startDemo(AppRole.superAdmin);
    final router = container.read(routerProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    for (final route in const [
      '/admin/access',
      '/admin/users',
      '/properties',
      '/finances',
    ]) {
      router.go(route);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(router.routeInformationProvider.value.uri.path, route);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('admin sees visible CRUD operations and protected roles', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);

    container.read(sessionControllerProvider.notifier).startDemo(AppRole.admin);
    final router = container.read(routerProvider)..go('/admin/access');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Access & operations'), findsWidgets);
    expect(find.text('Admin permissions'), findsOneWidget);
    expect(find.text('Super Admin accounts'), findsOneWidget);
    expect(find.text('No access'), findsWidgets);
    expect(find.text('Create'), findsWidgets);
    expect(find.text('Read'), findsWidgets);
    expect(find.text('Update'), findsWidgets);
    expect(find.text('Archive'), findsWidgets);
    expect(find.byKey(const ValueKey('access-property')), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Protected'));
    await tester.pump();
    expect(find.text('Super Admin accounts'), findsOneWidget);
    expect(find.byKey(const ValueKey('access-property')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('access operations screen remains usable on a phone', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    container
        .read(sessionControllerProvider.notifier)
        .startDemo(AppRole.superAdmin);
    final router = container.read(routerProvider)..go('/admin/access');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Access & operations'), findsWidgets);
    expect(find.text('Super Admin permissions'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('access-superAdminAccount')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

/// Pumps a fixed number of frames instead of settling, for screens whose
/// providers never resolve under the test harness (no path_provider) and so
/// would make `pumpAndSettle` hang.
Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 50);
  for (var elapsed = Duration.zero; elapsed < total; elapsed += step) {
    await tester.pump(step);
  }
}
