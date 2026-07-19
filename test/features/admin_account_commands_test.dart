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
  }) => PlatformAccount(
    uid: 'landlord-uid',
    displayName: 'Sandra Nakato',
    email: 'sandra@acaciahomes.ug',
    roleLabel: 'Landlord',
    status: PlatformAccountStatus.pendingApproval,
    joinedLabel: '12 Mar 2026',
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
}
