import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/user_session.dart';

final sessionControllerProvider =
    NotifierProvider<SessionController, UserSession?>(SessionController.new);

class SessionController extends Notifier<UserSession?> {
  @override
  UserSession? build() => null;

  void startDemo(AppRole role) {
    state = switch (role) {
      AppRole.landlord => const UserSession(
        userId: 'demo-landlord-001',
        displayName: 'Joshua Mwangi',
        email: 'joshua@demo.nyumba.co.ke',
        role: AppRole.landlord,
      ),
      AppRole.tenant => const UserSession(
        userId: 'demo-tenant-001',
        displayName: 'Amina Kamau',
        email: 'amina@demo.nyumba.co.ke',
        role: AppRole.tenant,
      ),
      AppRole.admin => const UserSession(
        userId: 'demo-admin-001',
        displayName: 'Nyumba Admin',
        email: 'admin@demo.nyumba.co.ke',
        role: AppRole.admin,
      ),
    };
  }

  Future<void> signIn({required String email, required String password}) async {
    // FirebaseAuth is composed at the data boundary once project options exist.
    // The local demo intentionally exercises the same role-aware presentation.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    state = UserSession(
      userId: 'demo-landlord-001',
      displayName: 'Joshua Mwangi',
      email: email.trim(),
      role: AppRole.landlord,
    );
  }

  void signOut() => state = null;
}
