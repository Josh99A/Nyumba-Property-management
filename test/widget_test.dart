import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/theme/nyumba_theme.dart';
import 'package:nyumba_property_management/features/auth/presentation/sign_in_screen.dart';

void main() {
  testWidgets('sign-in surface exposes role demos and client browsing', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: NyumbaTheme.light,
          home: const SignInScreen(),
        ),
      ),
    );

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Landlord'), findsOneWidget);
    expect(find.text('Tenant'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Browse available homes'), findsWidgets);
  });
}
