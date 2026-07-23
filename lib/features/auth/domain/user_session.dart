import '../../../core/localization/app_language.dart';
import '../../staff/domain/staff_permission.dart';

enum AppRole { superAdmin, admin, landlord, staff, tenant, client }

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

/// One hat a signed-in person can wear. An account may hold several at once
/// (an admin who owns a landlord workspace, a landlord who rents elsewhere as
/// a tenant); exactly one profile is active per [UserSession], and the
/// session's scalar fields always mirror the active one so role-branching
/// call sites never need to know about the others.
class SessionProfile {
  const SessionProfile({
    required this.role,
    this.workspaceId,
    this.permissions = const {},
    this.accountStatus = AccountStatus.active,
    this.subscriptionStatus = LandlordSubscriptionStatus.notApplicable,
    this.subscriptionTier,
    this.subscriptionRequestedTier,
  });

  final AppRole role;

  /// The landlord workspace this profile acts in: own uid for a landlord,
  /// the owner's uid for a staff member, null for workspace-less roles.
  final String? workspaceId;

  final Set<StaffPermission> permissions;
  final AccountStatus accountStatus;
  final LandlordSubscriptionStatus subscriptionStatus;
  final String? subscriptionTier;
  final String? subscriptionRequestedTier;

  /// Stable identity used for persistence and equality: distinct staff
  /// workspaces yield distinct keys, everything else is identified by role.
  String get key => workspaceId == null ? role.name : '${role.name}:$workspaceId';

  SessionProfile withSubscription({
    required LandlordSubscriptionStatus status,
    required String? tier,
    String? requestedTier,
  }) => SessionProfile(
    role: role,
    workspaceId: workspaceId,
    permissions: permissions,
    accountStatus: accountStatus,
    subscriptionStatus: status,
    subscriptionTier: tier,
    subscriptionRequestedTier: requestedTier,
  );
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
    this.workspaceId,
    this.permissions = const {},
    this.profiles = const [],
    bool? isWorkspaceOwner,
  }) : isWorkspaceOwner = isWorkspaceOwner ?? role == AppRole.landlord;

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

  /// The landlord workspace this session acts in. For an owner (landlord) this
  /// equals [userId]; for a staff member it is the owner's uid, learned from
  /// their membership. Null for roles with no landlord workspace.
  final String? workspaceId;

  /// Capabilities a staff member was granted. An owner implicitly holds all of
  /// them (see [can]); other roles hold none.
  final Set<StaffPermission> permissions;

  /// Every hat this account can wear. Empty for sessions built before the
  /// resolver collected profiles (and in most tests); [activeProfile] then
  /// synthesizes the single profile from the scalar fields.
  final List<SessionProfile> profiles;

  /// Whether this session owns its workspace (a landlord) rather than being a
  /// staff member within someone else's.
  final bool isWorkspaceOwner;

  /// The profile the scalar fields mirror.
  SessionProfile get activeProfile {
    for (final profile in profiles) {
      if (profile.role == role && profile.workspaceId == workspaceId) {
        return profile;
      }
    }
    return SessionProfile(
      role: role,
      workspaceId: workspaceId,
      permissions: permissions,
      accountStatus: accountStatus,
      subscriptionStatus: subscriptionStatus,
      subscriptionTier: subscriptionTier,
      subscriptionRequestedTier: subscriptionRequestedTier,
    );
  }

  bool get hasMultipleProfiles => profiles.length > 1;

  /// A copy of this session acting as [profile]: the scalar fields swap to the
  /// profile's snapshot while identity, language and the profile set carry
  /// over. The caller owns rebuilding whatever hangs off the session.
  UserSession withActiveProfile(SessionProfile profile) => UserSession(
    userId: userId,
    displayName: displayName,
    email: email,
    phone: phone,
    role: profile.role,
    accountStatus: profile.accountStatus,
    subscriptionStatus: profile.subscriptionStatus,
    subscriptionTier: profile.subscriptionTier,
    subscriptionRequestedTier: profile.subscriptionRequestedTier,
    language: language,
    emailVerified: emailVerified,
    isAnonymous: isAnonymous,
    workspaceId: profile.workspaceId,
    permissions: profile.permissions,
    profiles: profiles,
    isWorkspaceOwner: profile.role == AppRole.landlord,
  );

  String get firstName {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return 'there';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  /// A workspace member (owner or staff) needs the owner's subscription to be
  /// active; staff inherit that gating because they act in the owner's space.
  bool get hasConfirmedSubscription =>
      (role != AppRole.landlord && role != AppRole.staff) ||
      subscriptionStatus == LandlordSubscriptionStatus.active;

  /// The workspace to scope landlord reads/commands to: the owner's uid for a
  /// staff member, otherwise this account's own uid.
  String get effectiveWorkspaceId => workspaceId ?? userId;

  /// Whether this session may perform [permission]. An owner holds every
  /// capability; a staff member holds only those granted on their membership.
  bool can(StaffPermission permission) =>
      role == AppRole.landlord ||
      (role == AppRole.staff && permissions.contains(permission));

  /// Where this session's workspace lives, or null when the account has no
  /// workspace to return to (anonymous visitors and prospects, whose home is
  /// the public explore page itself).
  String? get workspacePath => switch (role) {
    AppRole.landlord =>
      hasConfirmedSubscription ? '/dashboard' : '/subscription',
    // Staff cannot open the payment gate, so a lapsed workspace falls back to
    // the public explore page rather than the subscription screen.
    AppRole.staff => hasConfirmedSubscription ? '/dashboard' : null,
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
        workspaceId: workspaceId,
        permissions: permissions,
        profiles: profiles,
        isWorkspaceOwner: isWorkspaceOwner,
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
    workspaceId: workspaceId,
    permissions: permissions,
    // The active entry must track the new subscription state too, or switching
    // away and back would resurrect the stale snapshot.
    profiles: [
      for (final profile in profiles)
        if (profile.role == role && profile.workspaceId == workspaceId)
          profile.withSubscription(
            status: status,
            tier: tier,
            requestedTier: requestedTier,
          )
        else
          profile,
    ],
    isWorkspaceOwner: isWorkspaceOwner,
  );
}
