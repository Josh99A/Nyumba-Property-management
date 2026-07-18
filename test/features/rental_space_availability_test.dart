import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/bootstrap/app_dependencies.dart';
import 'package:nyumba_property_management/app/theme/nyumba_theme.dart';
import 'package:nyumba_property_management/features/dashboard/presentation/widgets/rental_space_availability.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit.dart';
import 'package:nyumba_property_management/features/tenants/application/tenancy_providers.dart';
import 'package:nyumba_property_management/features/tenants/domain/tenancy.dart';

void main() {
  testWidgets('unresolved listing state keeps availability controls loading', (
    tester,
  ) async {
    final listings = StreamController<List<Listing>>();
    addTearDown(listings.close);

    await _pumpPanel(tester, listings: listings.stream);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(DropdownButton<UnitStatus>), findsNothing);
    expect(find.text('No listing'), findsNothing);
  });

  testWidgets('listing errors render an explicit availability error', (
    tester,
  ) async {
    await _pumpPanel(
      tester,
      listings: Stream<List<Listing>>.error(StateError('listing read failed')),
    );

    expect(
      find.text('Rental space availability could not be loaded. Try again.'),
      findsOneWidget,
    );
    expect(find.byType(DropdownButton<UnitStatus>), findsNothing);
    expect(find.text('No listing'), findsNothing);
  });
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required Stream<List<Listing>> listings,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        portfolioPropertiesProvider.overrideWith(
          (ref) => Stream.value(const <Property>[]),
        ),
        portfolioUnitsProvider.overrideWith(
          (ref) => Stream.value(const <Unit>[]),
        ),
        landlordListingsProvider.overrideWith((ref) => listings),
        tenanciesProvider.overrideWith(
          (ref) => Stream.value(const <Tenancy>[]),
        ),
      ],
      child: MaterialApp(
        theme: NyumbaTheme.light,
        home: const Scaffold(body: RentalSpaceAvailabilityPanel()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}
