import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/offline/firebase_remote_sync_gateway.dart';
import '../domain/user_session.dart';

final sessionControllerProvider =
    NotifierProvider<SessionController, UserSession?>(SessionController.new);

/// Lightweight command channel for auth-time flows (onboarding, invite
/// claims). Separate from the per-workspace sync gateway because these
/// commands run before any workspace exists.
final authCommandGatewayProvider = FutureProvider<FirebaseRemoteSyncGateway>(
  (ref) => FirebaseRemoteSyncGateway.create(),
);

class SessionController extends Notifier<UserSession?> {
  StreamSubscription<User?>? _authSubscription;
  var _generation = 0;

  @override
  UserSession? build() {
    ref.onDispose(() {
      _generation++;
      unawaited(_authSubscription?.cancel());
    });
    if (Firebase.apps.isEmpty) return null;
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      final generation = ++_generation;
      if (user == null) {
        state = null;
        return;
      }
      unawaited(_loadVerifiedSession(user, generation));
    });
    return null;
  }

  void startDemo(AppRole role) {
    state = switch (role) {
      AppRole.landlord => const UserSession(
        userId: 'demo-landlord-001',
        displayName: 'Joshua Mugisha',
        email: 'joshua@demo.nyumba.ug',
        role: AppRole.landlord,
        isDemo: true,
      ),
      AppRole.tenant => const UserSession(
        userId: 'demo-tenant-001',
        displayName: 'Brian Okello',
        email: 'brian@demo.nyumba.ug',
        role: AppRole.tenant,
        isDemo: true,
      ),
      AppRole.admin => const UserSession(
        userId: 'demo-admin-001',
        displayName: 'Nyumba Admin',
        email: 'admin@demo.nyumba.ug',
        role: AppRole.admin,
        isDemo: true,
      ),
      AppRole.client => const UserSession(
        userId: 'demo-client-001',
        displayName: 'Prospective tenant',
        email: '',
        role: AppRole.client,
        isDemo: true,
        isAnonymous: true,
      ),
    };
  }

  Future<void> signIn({required String email, required String password}) async {
    _requireFirebase();
    final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
      state = null;
      throw StateError(
        'Verify your email before continuing. A new verification email was sent.',
      );
    }
  }

  Future<void> signInAnonymously() async {
    _requireFirebase();
    await FirebaseAuth.instance.signInAnonymously();
  }

  /// Google accounts arrive email-verified, so the session loads immediately
  /// through the auth-state listener.
  Future<void> signInWithGoogle() async {
    _requireFirebase();
    final provider = GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});
    if (kIsWeb) {
      await FirebaseAuth.instance.signInWithPopup(provider);
    } else {
      await FirebaseAuth.instance.signInWithProvider(provider);
    }
  }

  /// Creates an email/password account destined for landlord onboarding. The
  /// session stays signed out until the verification link is used; onboarding
  /// itself runs from the onboarding screen on the first verified sign-in.
  Future<void> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    _requireFirebase();
    final credential = await FirebaseAuth.instance
        .createUserWithEmailAndPassword(email: email.trim(), password: password);
    await credential.user?.updateDisplayName(displayName.trim());
    await credential.user?.sendEmailVerification();
  }

  /// Promotes the verified signed-in user to a landlord (pending approval)
  /// through the server-authoritative landlord.onboard command.
  Future<void> completeLandlordOnboarding({
    required String phone,
    String? businessName,
  }) async {
    _requireFirebase();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('Sign in before setting up a landlord workspace.');
    }
    final gateway = await ref.read(authCommandGatewayProvider.future);
    await gateway.sendCommand(
      type: 'landlord.onboard',
      aggregateId: user.uid,
      expectedVersion: 0,
      payload: <String, Object?>{
        'phone': phone,
        if (businessName != null && businessName.trim().isNotEmpty)
          'businessName': businessName.trim(),
      },
    );
    await refreshSession();
  }

  /// Links any pending tenant invitations addressed to this verified email.
  /// Returns how many tenant records were linked; the session reloads when the
  /// role changes to tenant.
  Future<int> claimTenantInvites() async {
    _requireFirebase();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return 0;
    final gateway = await ref.read(authCommandGatewayProvider.future);
    final response = await gateway.sendCommand(type: 'tenant.claimInvite');
    final result = response['result'];
    final linked = result is Map
        ? (result['linkedRecords'] as num?)?.toInt() ?? 0
        : 0;
    if (linked > 0) await refreshSession();
    return linked;
  }

  /// Re-resolves the session from the server (fresh claims, users document,
  /// and landlord approval state).
  Future<void> refreshSession() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await _loadVerifiedSession(user, ++_generation);
  }

  Future<void> sendPasswordResetEmail(String email) async {
    _requireFirebase();
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> sendEmailVerification() async {
    _requireFirebase();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    await user.sendEmailVerification();
  }

  Future<void> _loadVerifiedSession(User user, int generation) async {
    if (!user.isAnonymous) {
      await user.getIdToken(true);
      await user.reload();
      user = FirebaseAuth.instance.currentUser ?? user;
      if (!user.emailVerified) {
        if (generation == _generation) state = null;
        return;
      }
    }
    final token = await user.getIdTokenResult(true);
    DocumentSnapshot<Map<String, dynamic>>? userDocument;
    if (!user.isAnonymous) {
      userDocument = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server));
      if (!userDocument.exists) {
        if (generation == _generation) state = null;
        return;
      }
    }
    final data = userDocument?.data() ?? const <String, dynamic>{};
    final platformAdmin = token.claims?['platformAdmin'] == true;
    final role = platformAdmin
        ? AppRole.admin
        : _roleFromServer(data['role']?.toString(), user.isAnonymous);
    var accountStatus = _statusFromServer(data['status']?.toString());
    if (role == AppRole.landlord) {
      // Approval lives on the server-owned landlord account, not the user
      // document, so suspension or pending review applies on next load.
      final account = await FirebaseFirestore.instance
          .collection('landlordAccounts')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server));
      accountStatus = switch (account.data()?['approvalStatus']?.toString()) {
        'pending' => AccountStatus.pendingApproval,
        'suspended' => AccountStatus.suspended,
        _ => accountStatus,
      };
    }
    if (generation != _generation) return;
    state = UserSession(
      userId: user.uid,
      displayName:
          data['displayName']?.toString() ??
          user.displayName ??
          (user.isAnonymous ? 'Prospective tenant' : 'Nyumba user'),
      email: data['email']?.toString() ?? user.email ?? '',
      phone: data['phone']?.toString() ?? user.phoneNumber ?? '',
      role: role,
      accountStatus: accountStatus,
      emailVerified: user.emailVerified,
      isAnonymous: user.isAnonymous,
    );
    if (role == AppRole.client && !user.isAnonymous) {
      // An invited tenant signs in as a plain account; linking happens
      // server-side against the verified email and upgrades the role.
      unawaited(_autoClaimInvites(generation));
    }
  }

  Future<void> _autoClaimInvites(int generation) async {
    try {
      if (generation != _generation) return;
      await claimTenantInvites();
    } on Object {
      // Best-effort: offline or backend-unavailable claims retry on the next
      // sign-in, and the onboarding screen exposes a manual retry.
    }
  }

  void updateProfile({
    required String displayName,
    required String email,
    required String phone,
  }) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      displayName: displayName,
      email: email,
      phone: phone,
    );
  }

  Future<void> signOut() async {
    final current = state;
    state = null;
    _generation++;
    if (current?.isDemo == true || Firebase.apps.isEmpty) return;
    await FirebaseAuth.instance.signOut();
  }

  static AppRole _roleFromServer(String? role, bool anonymous) {
    if (anonymous) return AppRole.client;
    return switch (role) {
      'landlord' => AppRole.landlord,
      'tenant' => AppRole.tenant,
      'client' => AppRole.client,
      _ => AppRole.client,
    };
  }

  static AccountStatus _statusFromServer(String? status) => switch (status) {
    'pending' || 'pendingApproval' => AccountStatus.pendingApproval,
    'suspended' => AccountStatus.suspended,
    _ => AccountStatus.active,
  };

  static void _requireFirebase() {
    if (Firebase.apps.isEmpty) {
      throw StateError(
        'Firebase is not configured. Choose an explicit demo role to continue locally.',
      );
    }
  }
}
