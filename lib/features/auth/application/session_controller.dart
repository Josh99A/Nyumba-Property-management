import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/user_session.dart';

final sessionControllerProvider =
    NotifierProvider<SessionController, UserSession?>(SessionController.new);

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
    if (generation != _generation) return;
    final data = userDocument?.data() ?? const <String, dynamic>{};
    final platformAdmin = token.claims?['platformAdmin'] == true;
    state = UserSession(
      userId: user.uid,
      displayName:
          data['displayName']?.toString() ??
          user.displayName ??
          (user.isAnonymous ? 'Prospective tenant' : 'Nyumba user'),
      email: data['email']?.toString() ?? user.email ?? '',
      phone: data['phone']?.toString() ?? user.phoneNumber ?? '',
      role: platformAdmin
          ? AppRole.admin
          : _roleFromServer(data['role']?.toString(), user.isAnonymous),
      accountStatus: _statusFromServer(data['status']?.toString()),
      emailVerified: user.emailVerified,
      isAnonymous: user.isAnonymous,
    );
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
