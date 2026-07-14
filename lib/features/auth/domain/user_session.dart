enum AppRole { admin, landlord, tenant }

enum AccountStatus { active, pendingApproval, suspended }

class UserSession {
  const UserSession({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.role,
    this.phone = '+256772000100',
    this.accountStatus = AccountStatus.active,
  });

  final String userId;
  final String displayName;
  final String email;
  final AppRole role;
  final String phone;
  final AccountStatus accountStatus;

  String get firstName {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return 'there';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  UserSession copyWith({String? displayName, String? email, String? phone}) =>
      UserSession(
        userId: userId,
        displayName: displayName ?? this.displayName,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        role: role,
        accountStatus: accountStatus,
      );
}
