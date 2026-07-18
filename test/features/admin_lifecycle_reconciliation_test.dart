import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/features/admin/domain/platform_account.dart';
import 'package:nyumba_property_management/features/admin/presentation/admin_users_screen.dart';

void main() {
  const deleted = PendingLifecycleAction(
    target: PendingLifecycleTarget.deleted,
    expectedVersion: 2,
  );
  const restored = PendingLifecycleAction(
    target: PendingLifecycleTarget.active,
    expectedVersion: 2,
  );

  test('loading and error snapshots do not reconcile pending actions', () {
    const pending = <String, PendingLifecycleAction>{'account-1': deleted};

    expect(
      resolvedPendingLifecycleActionIds(
        accountsValue: const AsyncLoading<List<PlatformAccount>>(),
        pendingActions: pending,
      ),
      isEmpty,
    );
    expect(
      resolvedPendingLifecycleActionIds(
        accountsValue: AsyncError<List<PlatformAccount>>(
          StateError('directory unavailable'),
          StackTrace.empty,
        ),
        pendingActions: pending,
      ),
      isEmpty,
    );
  });

  test('an authoritative empty snapshot confirms deletion', () {
    expect(
      resolvedPendingLifecycleActionIds(
        accountsValue: const AsyncData<List<PlatformAccount>>([]),
        pendingActions: const <String, PendingLifecycleAction>{
          'account-1': deleted,
        },
      ),
      {'account-1'},
    );
  });

  test('restoration requires the exact active status and expected version', () {
    for (final status in const [
      PlatformAccountStatus.pendingApproval,
      PlatformAccountStatus.suspended,
    ]) {
      expect(
        resolvedPendingLifecycleActionIds(
          accountsValue: AsyncData<List<PlatformAccount>>([
            _account(status: status, version: 2),
          ]),
          pendingActions: const <String, PendingLifecycleAction>{
            'account-1': restored,
          },
        ),
        isEmpty,
      );
    }

    expect(
      resolvedPendingLifecycleActionIds(
        accountsValue: AsyncData<List<PlatformAccount>>([
          _account(status: PlatformAccountStatus.active, version: 1),
        ]),
        pendingActions: const <String, PendingLifecycleAction>{
          'account-1': restored,
        },
      ),
      isEmpty,
    );
    expect(
      resolvedPendingLifecycleActionIds(
        accountsValue: AsyncData<List<PlatformAccount>>([
          _account(status: PlatformAccountStatus.active, version: 2),
        ]),
        pendingActions: const <String, PendingLifecycleAction>{
          'account-1': restored,
        },
      ),
      {'account-1'},
    );
  });
}

PlatformAccount _account({
  required PlatformAccountStatus status,
  required int version,
}) => PlatformAccount(
  uid: 'account-1',
  displayName: 'Test Account',
  email: 'account@nyumba.test',
  roleLabel: 'Landlord',
  status: status,
  joinedLabel: '1 Jan 2026',
  userVersion: version,
);
