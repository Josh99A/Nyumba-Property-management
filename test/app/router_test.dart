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
}
