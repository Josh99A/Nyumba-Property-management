import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/offline/firebase_remote_sync_gateway.dart';
import 'package:nyumba_property_management/features/admin/application/admin_directory_providers.dart';
import 'package:nyumba_property_management/features/admin/domain/platform_account.dart';
import 'package:nyumba_property_management/features/auth/application/session_controller.dart';
import 'package:nyumba_property_management/features/auth/domain/user_session.dart';

/// Session stub that never touches Firebase.
class _FixedSessionController extends SessionController {
  _FixedSessionController(this._session);

  final UserSession? _session;

  @override
  UserSession? build() => _session;
}

void main() {
  const admin = UserSession(
    userId: 'admin-uid',
    displayName: 'Nyumba Admin',
    email: 'admin@nyumba.ug',
    role: AppRole.admin,
  );

  PlatformAccount landlord({
    int? accountVersion = 3,
    int? subscriptionVersion = 2,
    // `user.*` commands version against the profile document, not the
    // landlord aggregate the approval transitions use.
    int? userVersion = 5,
  }) => PlatformAccount(
    uid: 'landlord-uid',
    displayName: 'Sandra Nakato',
    email: 'sandra@acaciahomes.ug',
    roleLabel: 'Landlord',
    status: PlatformAccountStatus.pendingApproval,
    joinedLabel: '12 Mar 2026',
    userVersion: userVersion,
    landlordAccountVersion: accountVersion,
    subscriptionTier: 'starter',
    subscriptionStatus: PlatformSubscriptionStatus.pendingPayment,
    subscriptionVersion: subscriptionVersion,
  );

  (ProviderContainer, List<Map<String, Object?>>) harness({
    UserSession? session = admin,
  }) {
    final sent = <Map<String, Object?>>[];
    final gateway = FirebaseRemoteSyncGateway(
      installationId: 'test-install',
      appVersion: '1.0.0',
      platform: 'test',
      invoke: (envelope) async {
        sent.add(envelope);
        return <String, Object?>{
          'status': 'applied',
          'serverVersion': 99,
          'serverUpdatedAt': DateTime.utc(2026, 7, 17).toIso8601String(),
        };
      },
    );
    final container = ProviderContainer(
      overrides: [
        sessionControllerProvider.overrideWith(
          () => _FixedSessionController(session),
        ),
        authCommandGatewayProvider.overrideWith((ref) => Future.value(gateway)),
      ],
    );
    addTearDown(container.dispose);
    return (container, sent);
  }

  test('approve sends the audited landlord.approve command', () async {
    final (container, sent) = harness();
    await container
        .read(adminAccountCommandsProvider)
        .approveLandlord(account: landlord(), reasonCode: 'IDENTITY_VERIFIED');

    final envelope = sent.single;
    expect(envelope['type'], 'landlord.approve');
    expect(envelope['aggregateId'], 'landlord-uid');
    expect(envelope['expectedVersion'], 3);
    expect(envelope['payload'], {'reasonCode': 'IDENTITY_VERIFIED'});
    expect(envelope['commandId'], isNotEmpty);
  });

  test(
    'payment confirmation carries the reference the server audits',
    () async {
      final (container, sent) = harness();
      await container
          .read(adminAccountCommandsProvider)
          .confirmSubscriptionPayment(
            account: landlord(),
            reference: ' MTN-12345 ',
          );

      final envelope = sent.single;
      expect(envelope['type'], 'subscription.confirmPayment');
      expect(envelope['aggregateId'], 'landlord-uid');
      expect(envelope['expectedVersion'], 2);
      expect(envelope['payload'], {'reference': 'MTN-12345'});
    },
  );

  test('a blank payment reference is refused before it reaches the server', () {
    final (container, sent) = harness();
    expect(
      () => container
          .read(adminAccountCommandsProvider)
          .confirmSubscriptionPayment(account: landlord(), reference: '   '),
      throwsStateError,
    );
    expect(sent, isEmpty);
  });

  test('an account without a landlord aggregate cannot be transitioned', () {
    final (container, sent) = harness();
    expect(
      () => container
          .read(adminAccountCommandsProvider)
          .suspendLandlord(
            account: landlord(accountVersion: null),
            reasonCode: 'POLICY_VIOLATION',
          ),
      throwsStateError,
    );
    expect(sent, isEmpty);
  });

  test('admins cannot act on their own account', () {
    final (container, sent) = harness();
    final self = PlatformAccount(
      uid: 'admin-uid',
      displayName: 'Nyumba Admin',
      email: 'admin@nyumba.ug',
      roleLabel: 'Landlord',
      status: PlatformAccountStatus.active,
      joinedLabel: '1 Jan 2026',
      landlordAccountVersion: 1,
    );
    expect(
      () => container
          .read(adminAccountCommandsProvider)
          .suspendLandlord(account: self, reasonCode: 'ADMIN_CORRECTION'),
      throwsStateError,
    );
    expect(sent, isEmpty);
  });

  // Archiving is reversible, so it moved to the ordinary admin claim alongside
  // the server gate. Only the permanent delete stayed behind super admin.
  test('an ordinary admin may archive and restore an account', () async {
    final (container, sent) = harness();
    await container
        .read(adminAccountCommandsProvider)
        .archiveUser(account: landlord(), reasonCode: 'POLICY_VIOLATION');
    await container
        .read(adminAccountCommandsProvider)
        .restoreUser(account: landlord(), reasonCode: 'APPEAL_APPROVED');

    expect(
      sent.map((envelope) => envelope['type']),
      ['user.archive', 'user.restore'],
    );
  });

  test('an ordinary admin cannot permanently delete an account', () {
    final (container, sent) = harness();
    expect(
      () => container
          .read(adminAccountCommandsProvider)
          .deleteUser(account: landlord(), reasonCode: 'USER_REQUESTED'),
      throwsStateError,
    );
    expect(sent, isEmpty);
  });

  group('portfolio purges', () {
    const superAdmin = UserSession(
      userId: 'super-uid',
      displayName: 'Nyumba Super Admin',
      email: 'super@nyumba.ug',
      role: AppRole.superAdmin,
    );

    test('a super admin purge carries the aggregate version and reason', () async {
      final (container, sent) = harness(session: superAdmin);
      await container
          .read(adminPurgeCommandsProvider)
          .deleteProperty(
            propertyId: 'property-1',
            expectedVersion: 4,
            reasonCode: 'DATA_RETENTION',
          );

      final envelope = sent.single;
      expect(envelope['type'], 'property.delete');
      expect(envelope['aggregateId'], 'property-1');
      expect(envelope['expectedVersion'], 4);
      expect(envelope['payload'], {'reasonCode': 'DATA_RETENTION'});
    });

    test('every purge maps to its own command', () async {
      final (container, sent) = harness(session: superAdmin);
      final commands = container.read(adminPurgeCommandsProvider);
      await commands.deleteUnit(
        unitId: 'unit-1',
        expectedVersion: 2,
        reasonCode: 'ADMIN_CORRECTION',
      );
      await commands.deleteListing(
        listingId: 'listing-1',
        expectedVersion: 1,
        reasonCode: 'POLICY_VIOLATION',
      );
      await commands.purgeDocument(
        documentId: 'document-1',
        expectedVersion: 3,
        reasonCode: 'USER_REQUESTED',
      );

      expect(sent.map((envelope) => envelope['type']), [
        'unit.delete',
        'listing.delete',
        'document.purge',
      ]);
    });

    test('an ordinary admin cannot purge anything', () {
      final (container, sent) = harness();
      expect(
        () => container
            .read(adminPurgeCommandsProvider)
            .deleteProperty(
              propertyId: 'property-1',
              expectedVersion: 4,
              reasonCode: 'DATA_RETENTION',
            ),
        throwsStateError,
      );
      expect(sent, isEmpty);
    });

    test('a reason the server would reject never leaves the device', () {
      final (container, sent) = harness(session: superAdmin);
      expect(
        () => container
            .read(adminPurgeCommandsProvider)
            .deleteUnit(
              unitId: 'unit-1',
              expectedVersion: 2,
              reasonCode: 'BECAUSE_I_SAID_SO',
            ),
        throwsStateError,
      );
      expect(sent, isEmpty);
    });
  });
}
