import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/router.dart';
import 'package:nyumba_property_management/features/auth/application/session_controller.dart';
import 'package:nyumba_property_management/features/auth/domain/user_session.dart';

void main() {
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
    await tester.pumpAndSettle();

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

    for (final route in const ['/admin/users', '/properties', '/finances']) {
      router.go(route);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(router.routeInformationProvider.value.uri.path, route);
      expect(tester.takeException(), isNull);
    }
  });
}
