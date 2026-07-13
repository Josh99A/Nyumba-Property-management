enum AppRole { admin, landlord, tenant }

enum AccountStatus { active, pendingApproval, suspended }

class UserSession {
  const UserSession({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.role,
    this.accountStatus = AccountStatus.active,
  });

  final String userId;
  final String displayName;
  final String email;
  final AppRole role;
  final AccountStatus accountStatus;

  String get firstName {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return 'there';
    return trimmed.split(RegExp(r'\s+')).first;
  }
}
