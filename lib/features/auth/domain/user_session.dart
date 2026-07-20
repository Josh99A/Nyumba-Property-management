import '../../../core/localization/app_language.dart';

enum AppRole { superAdmin, admin, landlord, tenant, client }

extension AppRolePresentation on AppRole {
  String get label => switch (this) {
    AppRole.superAdmin => 'Super Admin',
    AppRole.admin => 'Admin',
    AppRole.landlord => 'Landlord',
    AppRole.tenant => 'Tenant',
    AppRole.client => 'Prospective Client',
  };
}

enum AccountStatus { active, pendingApproval, suspended }

enum LandlordSubscriptionStatus {
  notApplicable,
  pendingPayment,
  active,
  pastDue,
  canceled,
  expired,
  unavailable,
}

class UserSession {
  const UserSession({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.role,
    this.phone = '+256772000100',
    this.accountStatus = AccountStatus.active,
    this.subscriptionStatus = LandlordSubscriptionStatus.notApplicable,
    this.subscriptionTier,
    this.subscriptionRequestedTier,
    this.language,
    this.emailVerified = true,
    this.isAnonymous = false,
  });

  final String userId;
  final String displayName;
  final String email;
  final AppRole role;
  final String phone;
  final AccountStatus accountStatus;
  final LandlordSubscriptionStatus subscriptionStatus;
  final String? subscriptionTier;

  /// Tier this landlord asked to upgrade to (`subscription.requestUpgrade`);
  /// entitlements stay on [subscriptionTier] until staff confirm the payment.
  final String? subscriptionRequestedTier;

  final AppLanguage? language;
  final bool emailVerified;
  final bool isAnonymous;

  String get firstName {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return 'there';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  bool get hasConfirmedSubscription =>
      role != AppRole.landlord ||
      subscriptionStatus == LandlordSubscriptionStatus.active;

  /// Where this session's workspace lives, or null when the account has no
  /// workspace to return to (anonymous visitors and prospects, whose home is
  /// the public explore page itself).
  String? get workspacePath => switch (role) {
    AppRole.landlord => hasConfirmedSubscription ? '/dashboard' : '/subscription',
    AppRole.tenant => '/tenant',
    AppRole.superAdmin || AppRole.admin => '/admin',
    AppRole.client => null,
  };

  UserSession copyWith({String? displayName, String? email, String? phone}) =>
      UserSession(
        userId: userId,
        displayName: displayName ?? this.displayName,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        role: role,
        accountStatus: accountStatus,
        subscriptionStatus: subscriptionStatus,
        subscriptionTier: subscriptionTier,
        subscriptionRequestedTier: subscriptionRequestedTier,
        language: language,
        emailVerified: emailVerified,
        isAnonymous: isAnonymous,
      );

  UserSession withSubscription({
    required LandlordSubscriptionStatus status,
    required String? tier,
    String? requestedTier,
  }) => UserSession(
    userId: userId,
    displayName: displayName,
    email: email,
    phone: phone,
    role: role,
    accountStatus: accountStatus,
    subscriptionStatus: status,
    subscriptionTier: tier,
    subscriptionRequestedTier: requestedTier,
    language: language,
    emailVerified: emailVerified,
    isAnonymous: isAnonymous,
  );
}
