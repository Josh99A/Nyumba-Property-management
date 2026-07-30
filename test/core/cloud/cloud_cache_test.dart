import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/cloud/cloud_cache.dart';
import 'package:nyumba_property_management/core/domain/clock.dart';

/// A clock the test moves by hand, so expiry is asserted rather than waited on.
final class _MutableClock implements Clock {
  _MutableClock(this._value);

  DateTime _value;

  void advance(Duration by) => _value = _value.add(by);

  @override
  DateTime now() => _value.toUtc();
}

void main() {
  final start = DateTime.utc(2026, 7, 29, 9);

  const environment = 'nyumba-property-management';
  const landlord = CachePartition(
    environment: environment,
    userId: 'uid-landlord',
    role: 'landlord',
  );
  const otherLandlord = CachePartition(
    environment: environment,
    userId: 'uid-other',
    role: 'landlord',
  );
  const sameUserAsAdmin = CachePartition(
    environment: environment,
    userId: 'uid-landlord',
    role: 'admin',
  );
  const public = CachePartition.public(environment: environment);

  group('partitioning', () {
    test('one account cannot read another account\'s entry', () {
      final cache = CloudCache(clock: _MutableClock(start));
      cache.write(landlord, 'property', ['kololo'], retrievedAt: start);

      expect(cache.read<List<String>>(otherLandlord, 'property'), isNull);
      expect(cache.read<List<String>>(landlord, 'property')?.value, ['kololo']);
    });

    test('the same person in another role gets a separate partition', () {
      final cache = CloudCache(clock: _MutableClock(start));
      cache.write(landlord, 'property', ['kololo'], retrievedAt: start);

      // An admin session must not inherit the landlord session's workspace
      // reads just because it is the same human being.
      expect(cache.read<List<String>>(sameUserAsAdmin, 'property'), isNull);
    });

    test('a different Firebase project never shares entries', () {
      final cache = CloudCache(clock: _MutableClock(start));
      cache.write(landlord, 'property', ['kololo'], retrievedAt: start);

      const staging = CachePartition(
        environment: 'nyumba-staging',
        userId: 'uid-landlord',
        role: 'landlord',
      );
      expect(cache.read<List<String>>(staging, 'property'), isNull);
    });
  });

  group('expiry and versioning', () {
    test('an entry past its time to live is a miss', () {
      final clock = _MutableClock(start);
      final cache = CloudCache(clock: clock);
      cache.write(landlord, 'property', ['kololo'], retrievedAt: start);

      clock.advance(const Duration(minutes: 4));
      expect(cache.read<List<String>>(landlord, 'property'), isNotNull);

      clock.advance(const Duration(minutes: 2));
      expect(cache.read<List<String>>(landlord, 'property'), isNull);
    });

    test('a caller may impose a shorter time to live than the default', () {
      final clock = _MutableClock(start);
      final cache = CloudCache(clock: clock);
      cache.write(landlord, 'plan', ['premium'], retrievedAt: start);

      clock.advance(const Duration(seconds: 90));
      expect(
        cache.read<List<String>>(
          landlord,
          'plan',
          timeToLive: const Duration(seconds: 30),
        ),
        isNull,
      );
    });

    test('storedAt reports when the server produced the value', () {
      final clock = _MutableClock(start);
      final cache = CloudCache(clock: clock);
      final producedAt = start.subtract(const Duration(seconds: 20));
      cache.write(landlord, 'property', ['kololo'], retrievedAt: producedAt);

      // "Last updated" must describe the data, not the cache write, or every
      // stale record would claim to be seconds old.
      expect(
        cache.read<List<String>>(landlord, 'property')?.storedAt,
        producedAt,
      );
    });

    test('a key reused for a different shape is dropped, not miscast', () {
      final cache = CloudCache(clock: _MutableClock(start));
      cache.write(landlord, 'property', ['kololo'], retrievedAt: start);

      expect(cache.read<List<int>>(landlord, 'property'), isNull);
    });
  });

  group('size limit', () {
    test('evicts least recently used entries beyond the cap', () {
      final cache = CloudCache(clock: _MutableClock(start), maximumEntries: 3);
      for (final key in ['a', 'b', 'c']) {
        cache.write(landlord, key, [key], retrievedAt: start);
      }
      // Touch 'a' so 'b' becomes the least recently used.
      cache.read<List<String>>(landlord, 'a');
      cache.write(landlord, 'd', ['d'], retrievedAt: start);

      expect(cache.length, 3);
      expect(cache.read<List<String>>(landlord, 'b'), isNull);
      expect(cache.read<List<String>>(landlord, 'a'), isNotNull);
      expect(cache.read<List<String>>(landlord, 'd'), isNotNull);
    });
  });

  group('invalidation', () {
    test('a prefix invalidation clears a whole aggregate family', () {
      final cache = CloudCache(clock: _MutableClock(start));
      cache.write(landlord, 'unit', ['a'], retrievedAt: start);
      cache.write(landlord, 'unit:property-1', ['a'], retrievedAt: start);
      cache.write(landlord, 'property', ['p'], retrievedAt: start);

      cache.invalidatePrefix(landlord, 'unit');

      expect(cache.read<List<String>>(landlord, 'unit'), isNull);
      expect(cache.read<List<String>>(landlord, 'unit:property-1'), isNull);
      expect(cache.read<List<String>>(landlord, 'property'), isNotNull);
    });
  });

  group('sign-out and account switching', () {
    test('clearProtected drops account data and keeps public data', () {
      final cache = CloudCache(clock: _MutableClock(start));
      cache.write(landlord, 'property', ['kololo'], retrievedAt: start);
      cache.write(public, 'public_listing', ['advert'], retrievedAt: start);

      cache.clearProtected();

      expect(cache.read<List<String>>(landlord, 'property'), isNull);
      expect(cache.read<List<String>>(public, 'public_listing'), isNotNull);
    });

    test('a second account on the same device sees nothing from the first', () {
      final cache = CloudCache(clock: _MutableClock(start));
      cache.write(landlord, 'property', ['kololo'], retrievedAt: start);

      // Sign-out.
      cache.clearProtected();
      // Next account signs in on the same browser.
      expect(cache.read<List<String>>(otherLandlord, 'property'), isNull);
      // And the original account's own entry is gone too, so a re-sign-in
      // re-reads from the server rather than resurrecting a stale workspace.
      expect(cache.read<List<String>>(landlord, 'property'), isNull);
    });

    test('a public partition is never treated as protected', () {
      expect(public.isProtected, isFalse);
      expect(landlord.isProtected, isTrue);
    });
  });
}
