import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/features/staff/application/staff_providers.dart';
import 'package:nyumba_property_management/features/staff/domain/staff_repository.dart';
import 'package:nyumba_property_management/features/staff/domain/staff_permission.dart';
import 'package:nyumba_property_management/features/staff/presentation/team_screen.dart';

void main() {
  testWidgets('a plan without staff seats shows the upgrade prompt', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffPlanProvider.overrideWith(
            (ref) => Stream.value(
              const StaffPlan(seatLimit: 0, customRoles: false),
            ),
          ),
          staffInvitesProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MaterialApp(home: TeamScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add your team on a higher plan'), findsOneWidget);
    expect(find.text('See plans'), findsOneWidget);
    // No seats means no way to invite.
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('an active seat lists the teammate and offers an invite', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffPlanProvider.overrideWith(
            (ref) => Stream.value(
              const StaffPlan(seatLimit: 3, customRoles: true),
            ),
          ),
          staffInvitesProvider.overrideWith(
            (ref) => Stream.value(const [
              StaffInvite(
                id: 'staffinv_1',
                email: 'agent@nyumba.test',
                displayName: 'Agent Ada',
                permissions: {StaffPermission.manageProperties},
                state: StaffInviteState.accepted,
                version: 2,
                linked: true,
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: TeamScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Agent Ada'), findsOneWidget);
    expect(find.text('agent@nyumba.test'), findsOneWidget);
    expect(find.text('1 of 3 seats used'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Properties and units'), findsOneWidget);
    // Custom-role plans expose per-person permission editing.
    expect(find.text('Change access'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });
}
