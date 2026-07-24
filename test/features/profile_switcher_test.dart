import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/router.dart';
import 'package:nyumba_property_management/features/auth/application/session_controller.dart';
import 'package:nyumba_property_management/features/auth/domain/user_session.dart';

const _landlordProfile = SessionProfile(
  role: AppRole.landlord,
  workspaceId: 'dual-1',
  subscriptionStatus: LandlordSubscriptionStatus.active,
  subscriptionTier: 'starter',
);
const _tenantProfile = SessionProfile(role: AppRole.tenant);

/// A landlord who also rents somewhere: two profiles, landlord active.
const _dualSession = UserSession(
  userId: 'dual-1',
  displayName: 'Dual Role',
  email: 'dual@nyumba.test',
  role: AppRole.landlord,
  subscriptionStatus: LandlordSubscriptionStatus.active,
  subscriptionTier: 'starter',
  workspaceId: 'dual-1',
  profiles: [_landlordProfile, _tenantProfile],
);

const _singleSession = UserSession(
  userId: 'solo-1',
  displayName: 'Solo Landlord',
  email: 'solo@nyumba.test',
  role: AppRole.landlord,
  subscriptionStatus: LandlordSubscriptionStatus.active,
  subscriptionTier: 'starter',
  profiles: [
    SessionProfile(
      role: AppRole.landlord,
      workspaceId: 'solo-1',
      subscriptionStatus: LandlordSubscriptionStatus.active,
      subscriptionTier: 'starter',
    ),
  ],
);

class _StubSessionController extends SessionController {
  _StubSessionController(this.session);

  final UserSession? session;

  @override
  UserSession? build() => session;
}

Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 50);
  for (var elapsed = Duration.zero; elapsed < total; elapsed += step) {
    await tester.pump(step);
  }
}

void main() {
  test('the redirect gates a multi-profile session by its active profile', () {
    // Landlord active: workspace open, tenant portal closed.
    expect(redirectForSession(_dualSession, '/dashboard'), isNull);
    expect(redirectForSession(_dualSession, '/tenant'), '/dashboard');

    // Tenant active: same account, opposite doors.
    final asTenant = _dualSession.withActiveProfile(_tenantProfile);
    expect(redirectForSession(asTenant, '/tenant'), isNull);
    expect(redirectForSession(asTenant, '/team'), '/tenant');
    expect(redirectForSession(asTenant, '/dashboard'), '/tenant');
  });

  testWidgets('the account menu offers the switcher only to multi-role users', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(
      overrides: [
        sessionControllerProvider.overrideWith(
          () => _StubSessionController(_singleSession),
        ),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider)..go('/settings');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await _pumpFor(tester, const Duration(seconds: 1));

    await tester.tap(find.byTooltip('Account menu'));
    await _pumpFor(tester, const Duration(milliseconds: 500));

    expect(find.text('Switch profile'), findsNothing);
    expect(find.text('Profile settings'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('switching to the tenant profile reopens the tenant portal', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(
      overrides: [
        sessionControllerProvider.overrideWith(
          () => _StubSessionController(_dualSession),
        ),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider)..go('/settings');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await _pumpFor(tester, const Duration(seconds: 1));

    await tester.tap(find.byTooltip('Account menu'));
    await _pumpFor(tester, const Duration(milliseconds: 500));

    expect(find.text('Switch profile'), findsOneWidget);
    expect(find.text('Landlord'), findsWidgets);
    expect(find.text('Tenant'), findsOneWidget);

    await tester.tap(find.text('Tenant'));
    await _pumpFor(tester, const Duration(seconds: 1));

    final session = container.read(sessionControllerProvider);
    expect(session?.role, AppRole.tenant);
    expect(session?.profiles, hasLength(2));
    expect(router.routeInformationProvider.value.uri.path, '/tenant');
    expect(tester.takeException(), isNull);
  });
}
