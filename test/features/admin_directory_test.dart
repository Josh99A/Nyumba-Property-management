import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/features/admin/data/firestore_admin_directory.dart';
import 'package:nyumba_property_management/features/admin/domain/platform_account.dart';

void main() {
  group('FirestoreAdminDirectory.combineAccounts', () {
    test('joins users with landlord standing and subscription state', () {
      final accounts = FirestoreAdminDirectory.combineAccounts(
        users: {
          'uid-landlord': {
            'displayName': 'Sandra Nakato',
            'email': 'sandra@acaciahomes.ug',
            'role': 'landlord',
            'status': 'active',
            'createdAt': DateTime.utc(2026, 3, 12),
          },
          'uid-tenant': {
            'displayName': 'Brian Okello',
            'email': 'brian@example.com',
            'role': 'tenant',
            'status': 'active',
            'createdAt': DateTime.utc(2026, 5, 1),
          },
        },
        landlordAccounts: {
          'uid-landlord': {
            'approvalStatus': 'pending',
            'version': 4,
            'businessName': 'Acacia Homes',
          },
        },
        subscriptions: {
          'uid-landlord': {
            'tier': 'starter',
            'status': 'pending_payment',
            'version': 2,
          },
        },
      );

      expect(accounts, hasLength(2));
      final landlord = accounts.singleWhere((a) => a.uid == 'uid-landlord');
      expect(landlord.roleLabel, 'Landlord');
      expect(landlord.status, PlatformAccountStatus.pendingApproval);
      expect(landlord.landlordAccountVersion, 4);
      expect(landlord.businessName, 'Acacia Homes');
      expect(landlord.subscriptionTier, 'starter');
      expect(
        landlord.subscriptionStatus,
        PlatformSubscriptionStatus.pendingPayment,
      );
      expect(landlord.subscriptionVersion, 2);

      final tenant = accounts.singleWhere((a) => a.uid == 'uid-tenant');
      expect(tenant.status, PlatformAccountStatus.active);
      expect(tenant.landlordAccountVersion, isNull);
      expect(tenant.subscriptionStatus, PlatformSubscriptionStatus.none);
    });

    test(
      'landlord standing comes from the landlord aggregate, not users.status',
      () {
        final accounts = FirestoreAdminDirectory.combineAccounts(
          users: {
            'uid-1': {
              'displayName': 'Sam Walusimbi',
              'email': 'sam@kilima.ug',
              'role': 'landlord',
              // The users document still says active; the aggregate that
              // actually gates access says suspended.
              'status': 'active',
            },
          },
          landlordAccounts: {
            'uid-1': {'approvalStatus': 'suspended', 'version': 9},
          },
          subscriptions: const {},
        );
        expect(accounts.single.status, PlatformAccountStatus.suspended);
      },
    );

    test('falls back to the email when a display name never arrived', () {
      final accounts = FirestoreAdminDirectory.combineAccounts(
        users: {
          'uid-1': {
            'displayName': null,
            'email': 'noname@example.com',
            'role': 'client',
          },
        },
        landlordAccounts: const {},
        subscriptions: const {},
      );
      expect(accounts.single.displayName, 'noname@example.com');
      expect(accounts.single.roleLabel, 'Client');
      expect(accounts.single.joinedLabel, 'Unknown');
    });

    test('excludes soft-deleted accounts and sorts by name', () {
      final accounts = FirestoreAdminDirectory.combineAccounts(
        users: {
          'uid-z': {'displayName': 'Zainab', 'role': 'client'},
          'uid-a': {'displayName': 'amina', 'role': 'client'},
          'uid-gone': {
            'displayName': 'Deleted Person',
            'role': 'client',
            'isDeleted': true,
          },
        },
        landlordAccounts: const {},
        subscriptions: const {},
      );
      expect(accounts.map((a) => a.displayName), ['amina', 'Zainab']);
    });

    test('orphaned profiles of a re-registered email collapse to the '
        'newest account', () {
      // Deleting an Auth account leaves its users document behind, and a
      // re-registration mints a new UID. Auth allows one live account per
      // email, so only the newest document can be live.
      final accounts = FirestoreAdminDirectory.combineAccounts(
        users: {
          'uid-old-client': {
            'displayName': null,
            'email': 'M.Sadat13@gmail.com',
            'role': 'client',
            'createdAt': DateTime.utc(2026, 7, 10),
          },
          'uid-old-landlord': {
            'displayName': 'D&T Computech',
            'email': 'm.sadat13@gmail.com',
            'role': 'landlord',
            'createdAt': DateTime.utc(2026, 7, 12),
          },
          'uid-live': {
            'displayName': 'D&T Computech',
            'email': 'm.sadat13@gmail.com',
            'role': 'landlord',
            'createdAt': DateTime.utc(2026, 7, 16),
          },
          'uid-other': {
            'displayName': 'Someone Else',
            'email': 'other@example.com',
            'role': 'client',
          },
        },
        landlordAccounts: {
          'uid-live': {'approvalStatus': 'pending', 'version': 1},
        },
        subscriptions: const {},
      );

      expect(accounts, hasLength(2));
      final survivor = accounts.singleWhere(
        (a) => a.email.toLowerCase() == 'm.sadat13@gmail.com',
      );
      expect(survivor.uid, 'uid-live');
      expect(survivor.status, PlatformAccountStatus.pendingApproval);
    });

    test('suspension on the users document applies to non-landlords', () {
      final accounts = FirestoreAdminDirectory.combineAccounts(
        users: {
          'uid-1': {
            'displayName': 'Kevin Odongo',
            'role': 'tenant',
            'status': 'suspended',
          },
        },
        landlordAccounts: const {},
        subscriptions: const {},
      );
      expect(accounts.single.status, PlatformAccountStatus.suspended);
    });
  });
}
