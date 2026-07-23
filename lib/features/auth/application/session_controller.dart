import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        defaultTargetPlatform,
        immutable,
        kIsWeb,
        visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/notifications/push_registration.dart';
import '../../../core/localization/app_language.dart';
import '../../../core/localization/app_localizations_adapter.dart';
import '../../../core/localization/command_failure_localizations.dart';
import '../../../core/localization/device_language_store.dart';
import '../../../core/offline/firebase_remote_sync_gateway.dart';
import '../../staff/domain/staff_permission.dart';
import '../data/active_profile_store.dart';
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

/// Picks which of an account's profiles opens first: the device's remembered
/// choice when it still exists, otherwise the highest-privilege profile. The
/// priority mirrors what the old single-role cascade produced, so accounts
/// that only ever had one hat resolve exactly as before.
@visibleForTesting
SessionProfile selectActiveProfile(
  List<SessionProfile> profiles,
  String? persistedKey,
) {
  if (persistedKey != null) {
    for (final profile in profiles) {
      if (profile.key == persistedKey) return profile;
    }
  }
  const priority = [
    AppRole.superAdmin,
    AppRole.admin,
    AppRole.landlord,
    AppRole.staff,
    AppRole.tenant,
    AppRole.client,
  ];
  for (final role in priority) {
    for (final profile in profiles) {
      if (profile.role == role) return profile;
    }
  }
  return profiles.first;
}

/// Resolves listener-owned failures through the best language known while the
/// session is still opening. Unlike form failures, these have no widget
/// context or caller that can localize them before publishing the notice.
@visibleForTesting
String describeLocalizedSessionFailure(Object error, AppLanguage language) {
  final copy = appLocalizationsFor(language);
  return describeAuthFailure(
    error,
    commandFailureLocalizer: (failure) => localizeCommandFailure(copy, failure),
  );
}

class SessionController extends Notifier<UserSession?> {
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _subscriptionStateSubscription;

  /// Keeps push registration current across FCM token rotations for the
  /// lifetime of one authenticated session; cancelled whenever that session
  /// ends so a rotated token is never registered against a signed-out user.
  StreamSubscription<String>? _tokenRotationSubscription;
  var _generation = 0;
  var _noticeSequence = 0;
  AppLanguage? _lastKnownLanguage;

  /// Set by an explicit sign-in so the arriving session can be greeted. A
  /// session restored on page load reaches the same code path, and must not
  /// announce a welcome the user never asked for.
  var _announceArrival = false;

  @override
  UserSession? build() {
    ref.onDispose(() {
      _generation++;
      unawaited(_authSubscription?.cancel());
      _cancelSubscriptionStateWatch();
      _cancelTokenRotationWatch();
    });
    if (Firebase.apps.isEmpty) return null;
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      final generation = ++_generation;
      // Whatever session the rotation watcher was serving has ended.
      _cancelTokenRotationWatch();
      _cancelSubscriptionStateWatch();
      if (user == null) {
        state = null;
        return;
      }
      unawaited(_loadVerifiedSession(user, generation));
    });
    return null;
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
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider()
          ..setCustomParameters({'prompt': 'select_account'});
        await FirebaseAuth.instance.signInWithPopup(provider);
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        // Native Credential Manager flow. The provider-redirect flow bounces
        // through <project>.firebaseapp.com in a Custom Tab and dies with
        // "missing initial state" whenever the browser partitions or clears
        // sessionStorage mid-redirect; the native flow never leaves the app.
        await _signInWithGoogleNatively();
      } else {
        final provider = GoogleAuthProvider()
          ..setCustomParameters({'prompt': 'select_account'});
        await FirebaseAuth.instance.signInWithProvider(provider);
      }
    } on Object {
      _announceArrival = false;
      rethrow;
    }
  }

  /// Completed once per process; `authenticate` may not run before it.
  static Future<void>? _googleSignInReady;

  Future<void> _signInWithGoogleNatively() async {
    final signIn = GoogleSignIn.instance;
    try {
      // The Android plugin reads the web OAuth client from the app's
      // google-services.json, so no environment-specific ID lives in Dart.
      await (_googleSignInReady ??= signIn.initialize());
    } on Object {
      // A failed initialize must not poison every later attempt.
      _googleSignInReady = null;
      rethrow;
    }
    try {
      final account = await signIn.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw StateError('Google did not return a sign-in token. Try again.');
      }
      await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
    } on GoogleSignInException catch (error) {
      // Re-express plugin failures in the vocabulary the auth layer already
      // understands: dismissing the account sheet is a decision, not a fault.
      if (error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted) {
        throw FirebaseAuthException(code: 'user-cancelled');
      }
      throw StateError(
        'Google sign-in is unavailable on this device right now. '
        'Use your email and password, or try again later.',
      );
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
      _watchLandlordSubscription(generation);
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
      final language =
          state?.language ??
          _lastKnownLanguage ??
          await const SecureDeviceLanguageStore().read() ??
          AppLanguage.english;
      if (generation != _generation) return;
      state = null;
      _publish(
        SessionResolution(
          error: describeLocalizedSessionFailure(error, language),
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
  /// who ignores it would otherwise hold up the session resolving. Anonymous
  /// sessions are skipped — there is no server-side user document to hang a
  /// token on, and asking a browsing prospect for notification permission
  /// before they have an account is the prompt everyone blocks.
  void _registerForPush(int generation) {
    final session = state;
    if (generation != _generation) return;
    if (session == null || session.isAnonymous) return;
    unawaited(
      registerForPush(
        gateway: () => ref.read(authCommandGatewayProvider.future),
      ),
    );
    // FCM can rotate the token mid-session; re-register each rotation for as
    // long as this authenticated session lasts.
    _cancelTokenRotationWatch();
    _tokenRotationSubscription = watchTokenRotation(
      gateway: () => ref.read(authCommandGatewayProvider.future),
    );
  }

  void _cancelTokenRotationWatch() {
    unawaited(_tokenRotationSubscription?.cancel());
    _tokenRotationSubscription = null;
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
    if (data['locale'] is String) {
      _lastKnownLanguage = AppLanguage.fromCode(data['locale'] as String);
    }
    final superAdmin = token.claims?['superAdmin'] == true;
    final platformAdmin = token.claims?['platformAdmin'] == true;
    final accountStatus = _statusFromServer(data['status']?.toString());
    final serverRoles = _serverRoles(data);

    // One account can wear several hats at once (an admin who owns a landlord
    // workspace, a landlord renting elsewhere as a tenant, a tenant who is
    // staff in another workspace). Collect every profile the server state
    // supports; exactly one becomes active below.
    final profiles = <SessionProfile>[];
    if (!user.isAnonymous) {
      if (superAdmin || platformAdmin) {
        profiles.add(
          SessionProfile(
            role: superAdmin ? AppRole.superAdmin : AppRole.admin,
            accountStatus: accountStatus,
          ),
        );
      }
      if (serverRoles.contains('landlord')) {
        final workspace = await _loadWorkspaceState(user.uid, accountStatus);
        profiles.add(
          SessionProfile(
            role: AppRole.landlord,
            workspaceId: user.uid,
            accountStatus: workspace.accountStatus,
            subscriptionStatus: workspace.subscriptionStatus,
            subscriptionTier: workspace.tier,
            subscriptionRequestedTier: workspace.requestedTier,
          ),
        );
      }
      // The membership doc is the source of truth (users/{uid}.role is left
      // untouched so a person can be both); staff inherit the owner's approval
      // and subscription gating because they act in the owner's space.
      final membership = await _resolveStaffMembership(user.uid, generation);
      if (generation != _generation) return null;
      if (membership != null) {
        final workspace = await _loadWorkspaceState(
          membership.landlordId,
          accountStatus,
        );
        profiles.add(
          SessionProfile(
            role: AppRole.staff,
            workspaceId: membership.landlordId,
            permissions: membership.permissions,
            accountStatus: workspace.accountStatus,
            subscriptionStatus: workspace.subscriptionStatus,
            subscriptionTier: workspace.tier,
            subscriptionRequestedTier: workspace.requestedTier,
          ),
        );
      }
      // The role fields answer tenant-ness for everyone whose invite claim
      // could promote the scalar. Landlords and admins keep their primary
      // scalar on claim, so for them (pre-`roles`-array accounts) fall back to
      // probing the uid-keyed portal projection directly.
      final tenantMasked =
          profiles.isNotEmpty && !serverRoles.contains('tenant');
      if (serverRoles.contains('tenant') ||
          (tenantMasked && await _hasTenantLeases(user.uid))) {
        profiles.add(
          SessionProfile(role: AppRole.tenant, accountStatus: accountStatus),
        );
      }
    }
    if (profiles.isEmpty) {
      profiles.add(
        SessionProfile(role: AppRole.client, accountStatus: accountStatus),
      );
    }

    if (generation != _generation) return null;
    final persistedKey = user.isAnonymous
        ? null
        : await const SecureActiveProfileStore().read(user.uid);
    if (generation != _generation) return null;
    final active = selectActiveProfile(profiles, persistedKey);
    final session = UserSession(
      userId: user.uid,
      displayName:
          firstFilled(data['displayName'], user.displayName) ??
          (user.isAnonymous ? 'Prospective tenant' : 'Nyumba user'),
      email: firstFilled(data['email'], user.email) ?? '',
      phone: firstFilled(data['phone'], user.phoneNumber) ?? '',
      role: active.role,
      accountStatus: active.accountStatus,
      subscriptionStatus: active.subscriptionStatus,
      subscriptionTier: active.subscriptionTier,
      subscriptionRequestedTier: active.subscriptionRequestedTier,
      language: data['locale'] is String
          ? AppLanguage.fromCode(data['locale'] as String)
          : null,
      emailVerified: user.emailVerified,
      isAnonymous: user.isAnonymous,
      workspaceId: active.workspaceId,
      permissions: active.permissions,
      profiles: profiles,
      isWorkspaceOwner: active.role == AppRole.landlord,
    );
    state = session;
    final onlyClient =
        profiles.length == 1 && profiles.single.role == AppRole.client;
    if (onlyClient && !user.isAnonymous) {
      // An invited tenant signs in as a plain account; linking happens
      // server-side against the verified email and upgrades the role.
      unawaited(_autoClaimInvites(generation));
    }
    if (!_announceArrival) return null;
    _announceArrival = false;
    return session.firstName;
  }

  /// Reopens this session as [profile] — one of the hats collected at
  /// resolution. The scalar fields swap to the profile's snapshot; every
  /// watcher of the session (router redirect, dependency bootstrap with its
  /// per-role offline workspace) rebuilds from there. Pending outbox writes in
  /// the closing workspace stay quarantined on disk and flush the next time
  /// that profile is active.
  void switchProfile(SessionProfile profile) {
    final session = state;
    if (session == null || profile.key == session.activeProfile.key) return;
    state = session.withActiveProfile(profile);
    // Re-aim the subscription watch at the new profile's workspace (or stop
    // it, for roles without one).
    _watchLandlordSubscription(_generation);
    unawaited(
      const SecureActiveProfileStore().write(session.userId, profile.key),
    );
  }

  /// Reads a workspace's server-owned approval and subscription state — the
  /// owner's own for a landlord profile, the owner's for a staff profile.
  Future<
    ({
      AccountStatus accountStatus,
      LandlordSubscriptionStatus subscriptionStatus,
      String? tier,
      String? requestedTier,
    })
  >
  _loadWorkspaceState(String workspaceUid, AccountStatus fallbackStatus) async {
    final account = await FirebaseFirestore.instance
        .collection('landlordAccounts')
        .doc(workspaceUid)
        .get(const GetOptions(source: Source.server));
    final accountStatus = switch (account.data()?['approvalStatus']?.toString()) {
      'pending' => AccountStatus.pendingApproval,
      'suspended' => AccountStatus.suspended,
      _ => fallbackStatus,
    };
    final subscription = await FirebaseFirestore.instance
        .collection('subscriptions')
        .doc(workspaceUid)
        .get(const GetOptions(source: Source.server));
    final subscriptionData = subscription.data();
    final rawTier = subscriptionData?['tier'];
    final rawRequestedTier = subscriptionData?['requestedTier'];
    return (
      accountStatus: accountStatus,
      subscriptionStatus: _subscriptionStatusFromServer(
        subscriptionData?['status']?.toString(),
      ),
      tier: rawTier is String && rawTier.trim().isNotEmpty
          ? rawTier.trim()
          : null,
      requestedTier:
          rawRequestedTier is String && rawRequestedTier.trim().isNotEmpty
          ? rawRequestedTier.trim()
          : null,
    );
  }

  /// Whether any lease projection exists under this uid's tenant portal.
  /// Best-effort: an unreachable server reads as "no", and the probe reruns
  /// on the next resolution.
  Future<bool> _hasTenantLeases(String uid) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('tenantPortals')
          .doc(uid)
          .collection('leases')
          .limit(1)
          .get(const GetOptions(source: Source.server));
      return snapshot.docs.isNotEmpty;
    } on Object {
      return false;
    }
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
      final linkedTenant = await claimTenantInvites();
      // A tenant claim reloads the session as a tenant; only look for a staff
      // membership while this is still a plain client account.
      if (linkedTenant == 0 && generation == _generation) {
        await claimStaffInvites();
      }
    } on Object {
      // Best-effort: offline or backend-unavailable claims retry on the next
      // sign-in, and the onboarding screen exposes a manual retry.
    }
  }

  /// Finds an active staff membership for [uid] and the workspace it grants
  /// access to. Returns null when there is none, or when the lookup cannot
  /// reach the server — the account then resolves as a plain client and
  /// re-resolves on the next sign-in.
  Future<({String landlordId, Set<StaffPermission> permissions})?>
  _resolveStaffMembership(String uid, int generation) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('staffMemberships')
          .where('memberUid', isEqualTo: uid)
          .where('active', isEqualTo: true)
          .limit(2)
          .get(const GetOptions(source: Source.server));
      if (generation != _generation) return null;
      if (snapshot.docs.length != 1) return null;
      final data = snapshot.docs.single.data();
      if (data['landlordId'] is String) {
        return (
          landlordId: data['landlordId'] as String,
          permissions: StaffPermission.parse(data['permissions']),
        );
      }
    } on Object {
      // Offline or unavailable: fall back to the plain client role.
    }
    return null;
  }

  /// Links any pending staff invitations addressed to this verified email.
  /// Returns how many memberships were linked; the session reloads as a staff
  /// member when the first one links.
  Future<int> claimStaffInvites() async {
    _requireFirebase();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return 0;
    final gateway = await ref.read(authCommandGatewayProvider.future);
    final response = await gateway.sendCommand(type: 'staff.claimInvite');
    final result = response['result'];
    final linked = result is Map
        ? (result['linkedMemberships'] as num?)?.toInt() ?? 0
        : 0;
    if (linked > 0) await refreshSession();
    return linked;
  }

  void _watchLandlordSubscription(int generation) {
    _cancelSubscriptionStateWatch();
    final session = state;
    if (session == null ||
        (session.role != AppRole.landlord && session.role != AppRole.staff) ||
        Firebase.apps.isEmpty) {
      return;
    }
    // Staff watch the owner's subscription: a lapse must lock their access too.
    _subscriptionStateSubscription = FirebaseFirestore.instance
        .collection('subscriptions')
        .doc(session.effectiveWorkspaceId)
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) {
            if (generation != _generation) return;
            // Subscription activation is server-authoritative. A cached
            // `active` value must never unlock the workspace while offline or
            // before Firestore has confirmed it against the backend.
            if (snapshot.metadata.isFromCache) return;
            final current = state;
            if (current == null || current.userId != session.userId) return;
            final data = snapshot.data();
            final rawTier = data?['tier'];
            final tier = rawTier is String && rawTier.trim().isNotEmpty
                ? rawTier.trim()
                : null;
            final rawRequestedTier = data?['requestedTier'];
            state = current.withSubscription(
              status: _subscriptionStatusFromServer(
                data?['status']?.toString(),
              ),
              tier: tier,
              requestedTier:
                  rawRequestedTier is String &&
                      rawRequestedTier.trim().isNotEmpty
                  ? rawRequestedTier.trim()
                  : null,
            );
          },
          onError: (_) {
            if (generation != _generation) return;
            final current = state;
            if (current == null || current.userId != session.userId) return;
            state = current.withSubscription(
              status: LandlordSubscriptionStatus.unavailable,
              tier: current.subscriptionTier,
              requestedTier: current.subscriptionRequestedTier,
            );
          },
        );
  }

  void _cancelSubscriptionStateWatch() {
    unawaited(_subscriptionStateSubscription?.cancel());
    _subscriptionStateSubscription = null;
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
    final hasRealFirebaseSession = current != null && Firebase.apps.isNotEmpty;
    final shouldUnregisterFromPush =
        hasRealFirebaseSession && !current.isAnonymous;
    if (hasRealFirebaseSession) _cancelTokenRotationWatch();

    // Clear private local/session state before any network cleanup. Push token
    // revocation is best-effort and must never leave the Firebase Auth session
    // signed in when it fails.
    state = null;
    _generation++;
    _announceArrival = false;
    _cancelSubscriptionStateWatch();
    ref
        .read(sessionResolutionProvider.notifier)
        .publish(const SessionResolution());
    if (!hasRealFirebaseSession) return;
    try {
      if (shouldUnregisterFromPush) {
        await unregisterFromPush(
          gateway: () => ref.read(authCommandGatewayProvider.future),
        );
      }
    } finally {
      await FirebaseAuth.instance.signOut();
    }
  }

  /// Every role the server records for this account: the legacy scalar plus
  /// the additive `roles` array (which survives promotions the scalar loses,
  /// e.g. a tenant who onboards as a landlord).
  static Set<String> _serverRoles(Map<String, dynamic> data) {
    final roles = <String>{};
    if (data['role'] is String) roles.add(data['role'] as String);
    final list = data['roles'];
    if (list is List) {
      for (final entry in list) {
        if (entry is String) roles.add(entry);
      }
    }
    return roles;
  }

  static AccountStatus _statusFromServer(String? status) => switch (status) {
    'pending' || 'pendingApproval' => AccountStatus.pendingApproval,
    'suspended' => AccountStatus.suspended,
    _ => AccountStatus.active,
  };

  static LandlordSubscriptionStatus _subscriptionStatusFromServer(
    String? status,
  ) => switch (status) {
    'active' => LandlordSubscriptionStatus.active,
    'pending_payment' ||
    'trialing' => LandlordSubscriptionStatus.pendingPayment,
    'past_due' => LandlordSubscriptionStatus.pastDue,
    'canceled' => LandlordSubscriptionStatus.canceled,
    'expired' => LandlordSubscriptionStatus.expired,
    _ => LandlordSubscriptionStatus.unavailable,
  };

  static void _requireFirebase() {
    if (Firebase.apps.isEmpty) {
      throw StateError(
        'Firebase is not configured. Sign-in is unavailable until the app is '
        'connected to a Nyumba project.',
      );
    }
  }
}
