import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show immutable, kIsWeb, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/push_registration.dart';
import '../../../core/offline/firebase_remote_sync_gateway.dart';
import '../domain/auth_failure.dart';
import '../domain/user_session.dart';

final sessionControllerProvider =
    NotifierProvider<SessionController, UserSession?>(SessionController.new);

/// Progress of the session resolution that runs on the auth-state listener.
///
/// A form cannot `await` that work: it starts when Firebase reports a new user,
/// not when the button is pressed, so a sign-in that is accepted by Google but
/// then fails to resolve a profile has no `catch` to land in. This is how the
/// button knows to keep spinning and how such a failure reaches the user.
@immutable
class SessionResolution {
  const SessionResolution({
    this.isResolving = false,
    this.error,
    this.welcome,
    this.sequence = 0,
  });

  final bool isResolving;
  final String? error;

  /// First name to greet once an explicitly requested session lands.
  final String? welcome;

  /// Distinguishes repeats: two identical failures in a row are two events,
  /// and `ref.listen` would otherwise ignore the second.
  final int sequence;
}

final sessionResolutionProvider =
    NotifierProvider<SessionResolutionController, SessionResolution>(
      SessionResolutionController.new,
    );

class SessionResolutionController extends Notifier<SessionResolution> {
  @override
  SessionResolution build() => const SessionResolution();

  void publish(SessionResolution resolution) => state = resolution;
}

/// How long a brand-new account waits for its profile document to appear.
///
/// `onUserCreated` is an asynchronous background trigger, so the document does
/// not exist at the moment the auth state flips; a cold start pushes the write
/// seconds past the client's first read. Giving up immediately strands a
/// first-time user on the sign-in screen with a valid credential and no
/// session.
const _profileWaitBudget = Duration(seconds: 20);

/// Returns the first value that carries actual text, treating blanks as absent.
///
/// The `onUserCreated` trigger runs the instant an account exists, which for an
/// email/password sign-up is *before* `updateDisplayName`, so the profile
/// document can hold an empty name. A plain `??` chain keeps that empty string
/// (it is not null) and hides the real name Auth holds, leaving the account
/// avatar with no initials, so blanks must fall through to the next source.
@visibleForTesting
String? firstFilled(Object? preferred, String? fallback) {
  final candidate = preferred?.toString().trim();
  if (candidate != null && candidate.isNotEmpty) return candidate;
  final alternative = fallback?.trim();
  if (alternative != null && alternative.isNotEmpty) return alternative;
  return null;
}

/// Lightweight command channel for auth-time flows (onboarding, invite
/// claims). Separate from the per-workspace sync gateway because these
/// commands run before any workspace exists.
final authCommandGatewayProvider = FutureProvider<FirebaseRemoteSyncGateway>(
  (ref) => FirebaseRemoteSyncGateway.create(),
);

class SessionController extends Notifier<UserSession?> {
  StreamSubscription<User?>? _authSubscription;
  var _generation = 0;
  var _noticeSequence = 0;

  /// Set by an explicit sign-in so the arriving session can be greeted. A
  /// session restored on page load reaches the same code path, and must not
  /// announce a welcome the user never asked for.
  var _announceArrival = false;

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
      AppRole.superAdmin => const UserSession(
        userId: 'demo-super-admin-001',
        displayName: 'Nyumba Super Admin',
        email: 'superadmin@demo.nyumba.ug',
        role: AppRole.superAdmin,
        isDemo: true,
      ),
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
    _announceArrival = true;
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        // The credential is good but the address is unproven, so nothing may
        // open. Signing out keeps Firebase from holding a half-session that the
        // listener would re-resolve to null on every rebuild.
        await FirebaseAuth.instance.signOut();
        state = null;
        throw EmailNotVerifiedException(user.email ?? email.trim());
      }
    } on Object {
      // No session will arrive, so the pending greeting must not outlive this
      // attempt and land on someone else's sign-in.
      _announceArrival = false;
      rethrow;
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
    _announceArrival = true;
    final provider = GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});
    try {
      if (kIsWeb) {
        await FirebaseAuth.instance.signInWithPopup(provider);
      } else {
        await FirebaseAuth.instance.signInWithProvider(provider);
      }
    } on Object {
      _announceArrival = false;
      rethrow;
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
        .createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
    await credential.user?.updateDisplayName(displayName.trim());
    await credential.user?.sendEmailVerification();
    // createUser signs the new account in, but an unverified address may not
    // open a workspace. Sign out so the app holds no half-session while the
    // user goes to their inbox.
    await FirebaseAuth.instance.signOut();
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
    _publish(const SessionResolution(isResolving: true), generation);
    try {
      final welcome = await _resolveSession(user, generation);
      _publish(
        SessionResolution(
          welcome: welcome,
          sequence: welcome == null ? 0 : ++_noticeSequence,
        ),
        generation,
      );
      _registerForPush(generation);
    } on Object catch (error) {
      // Nothing else can report this: the listener has no caller to throw to,
      // and a silent return here is what leaves a signed-in user staring at the
      // sign-in screen.
      if (generation != _generation) return;
      state = null;
      _publish(
        SessionResolution(
          error: describeAuthFailure(error),
          sequence: ++_noticeSequence,
        ),
        generation,
      );
    }
  }

  void _publish(SessionResolution resolution, int generation) {
    if (generation != _generation) return;
    ref.read(sessionResolutionProvider.notifier).publish(resolution);
  }

  /// Registers this device for push once a real session exists.
  ///
  /// Deliberately not awaited: the permission prompt is the OS's, and a user
  /// who ignores it would otherwise hold up the session resolving. Demo and
  /// anonymous sessions are skipped — there is no server-side user document to
  /// hang a token on, and asking a browsing prospect for notification
  /// permission before they have an account is the prompt everyone blocks.
  void _registerForPush(int generation) {
    final session = state;
    if (generation != _generation) return;
    if (session == null || session.isDemo || session.isAnonymous) return;
    unawaited(
      registerForPush(
        gateway: () => ref.read(authCommandGatewayProvider.future),
      ),
    );
  }

  /// Returns the first name to greet, or null when nothing should be
  /// announced (a restored session, or a load that another generation owns).
  Future<String?> _resolveSession(User user, int generation) async {
    if (!user.isAnonymous) {
      await user.getIdToken(true);
      await user.reload();
      user = FirebaseAuth.instance.currentUser ?? user;
      if (!user.emailVerified) {
        if (generation == _generation) state = null;
        return null;
      }
    }
    final token = await user.getIdTokenResult(true);
    DocumentSnapshot<Map<String, dynamic>>? userDocument;
    if (!user.isAnonymous) {
      userDocument = await _awaitUserProfile(user.uid, generation);
      if (userDocument == null) return null;
    }
    final data = userDocument?.data() ?? const <String, dynamic>{};
    final superAdmin = token.claims?['superAdmin'] == true;
    final platformAdmin = token.claims?['platformAdmin'] == true;
    final role = superAdmin
        ? AppRole.superAdmin
        : platformAdmin
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
    if (generation != _generation) return null;
    final session = UserSession(
      userId: user.uid,
      displayName:
          firstFilled(data['displayName'], user.displayName) ??
          (user.isAnonymous ? 'Prospective tenant' : 'Nyumba user'),
      email: firstFilled(data['email'], user.email) ?? '',
      phone: firstFilled(data['phone'], user.phoneNumber) ?? '',
      role: role,
      accountStatus: accountStatus,
      emailVerified: user.emailVerified,
      isAnonymous: user.isAnonymous,
    );
    state = session;
    if (role == AppRole.client && !user.isAnonymous) {
      // An invited tenant signs in as a plain account; linking happens
      // server-side against the verified email and upgrades the role.
      unawaited(_autoClaimInvites(generation));
    }
    if (!_announceArrival) return null;
    _announceArrival = false;
    return session.firstName;
  }

  /// Reads the profile document, waiting out the gap between the account
  /// existing and [_profileWaitBudget] elapsing.
  ///
  /// Returns null when a newer generation has taken over. Throws when the
  /// budget runs out, so the caller reports a real failure instead of leaving
  /// the user signed in with no session.
  Future<DocumentSnapshot<Map<String, dynamic>>?> _awaitUserProfile(
    String uid,
    int generation,
  ) async {
    final reference = FirebaseFirestore.instance.collection('users').doc(uid);
    final deadline = DateTime.now().add(_profileWaitBudget);
    var backoff = const Duration(milliseconds: 250);
    while (true) {
      if (generation != _generation) return null;
      final snapshot = await reference.get(
        const GetOptions(source: Source.server),
      );
      if (snapshot.exists) return snapshot;
      if (!DateTime.now().isBefore(deadline)) {
        throw StateError(
          'Your account is still being set up. Give it a moment, then sign in '
          'again.',
        );
      }
      await Future<void>.delayed(backoff);
      backoff = backoff * 2;
      if (backoff > const Duration(seconds: 2)) {
        backoff = const Duration(seconds: 2);
      }
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
    _announceArrival = false;
    ref
        .read(sessionResolutionProvider.notifier)
        .publish(const SessionResolution());
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
