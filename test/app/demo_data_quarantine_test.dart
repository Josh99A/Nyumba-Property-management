import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/bootstrap/app_dependencies.dart';
import 'package:nyumba_property_management/features/auth/domain/user_session.dart';

UserSession _session({
  required AppRole role,
  bool isDemo = false,
  bool isAnonymous = false,
}) => UserSession(
  userId: 'user-1',
  displayName: 'Joshua Mugisha',
  email: 'joshua@example.ug',
  role: role,
  isDemo: isDemo,
  isAnonymous: isAnonymous,
);

void main() {
  group('demo data quarantine', () {
    test('every real role is refused seeded data', () {
      for (final role in AppRole.values) {
        expect(
          seedsDemoData(_session(role: role)),
          isFalse,
          reason:
              '$role is a real account and must never see invented records.',
        );
      }
    });

    test('an anonymous visitor browses the real catalogue', () {
      expect(
        seedsDemoData(null),
        isFalse,
        reason: 'Public browsing reads publicListings, not fixtures.',
      );
      expect(
        seedsDemoData(_session(role: AppRole.client, isAnonymous: true)),
        isFalse,
      );
    });

    test('only an explicitly chosen demo role is seeded', () {
      for (final role in AppRole.values) {
        expect(seedsDemoData(_session(role: role, isDemo: true)), isTrue);
      }
    });

    test('seeding never keys off Firebase being unavailable', () {
      // main() swallows Firebase initialisation failures on purpose so the
      // offline workspace still opens. If seeding were gated on "no Firebase"
      // instead of "is demo", a startup hiccup would silently hand a real
      // landlord a portfolio of invented properties. seedsDemoData takes only
      // the session, so that mistake cannot be reintroduced by accident.
      expect(seedsDemoData(_session(role: AppRole.landlord)), isFalse);
      expect(
        seedsDemoData(_session(role: AppRole.landlord, isDemo: true)),
        isTrue,
      );
    });
  });
}
