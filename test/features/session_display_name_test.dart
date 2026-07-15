import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/features/auth/application/session_controller.dart';

void main() {
  group('firstFilled', () {
    test('falls through a blank profile value to the auth profile', () {
      // The regression that rendered the account avatar as "?": the
      // onUserCreated trigger stores '' before updateDisplayName runs, and ''
      // is not null, so a plain ?? chain kept it and hid the real name.
      expect(firstFilled('', 'Joshua Mugisha'), 'Joshua Mugisha');
      expect(firstFilled('   ', 'Joshua Mugisha'), 'Joshua Mugisha');
      expect(firstFilled(null, 'Joshua Mugisha'), 'Joshua Mugisha');
    });

    test('prefers the stored profile value when it has text', () {
      expect(firstFilled('Stored Name', 'Auth Name'), 'Stored Name');
    });

    test('trims surrounding whitespace', () {
      expect(firstFilled('  Joshua Mugisha  ', null), 'Joshua Mugisha');
      expect(firstFilled(null, '  Joshua Mugisha  '), 'Joshua Mugisha');
    });

    test('returns null when neither source has text', () {
      expect(firstFilled(null, null), isNull);
      expect(firstFilled('', ''), isNull);
      expect(firstFilled('  ', '  '), isNull);
    });
  });
}
