/// What the server currently allows this landlord to do.
///
/// Every field here is read from server-owned documents (`subscriptions/{uid}`
/// and `planCatalog/{tier}`). Nothing on this object may be defaulted, guessed,
/// or computed on the device: the whole point is that the client shows what the
/// server will actually enforce, so a landlord is never told they have room for
/// a unit the server is about to refuse.
final class LandlordEntitlement {
  const LandlordEntitlement({
    required this.tier,
    required this.displayName,
    required this.status,
    required this.unitLimit,
    required this.activeListingLimit,
  });

  /// Plan identifier, e.g. `starter`.
  final String tier;

  /// Human-readable plan name from the catalog, e.g. `Starter`.
  final String displayName;

  /// Subscription status. Workspace entitlements are exposed only for `active`.
  final String status;

  final int unitLimit;
  final int activeListingLimit;
}

/// The landlord's plan, or why it could not be established.
///
/// A missing subscription or an unknown tier is deliberately not collapsed into
/// a default plan. The backend fails closed on exactly these cases
/// (`ENTITLEMENT_MISSING`), so the UI has to be able to say "we don't know"
/// rather than invent a limit the server never agreed to.
sealed class EntitlementState {
  const EntitlementState();
}

final class EntitlementKnown extends EntitlementState {
  const EntitlementKnown(this.entitlement);
  final LandlordEntitlement entitlement;
}

/// No subscription document, no catalog entry for the tier, or a malformed one.
final class EntitlementUnavailable extends EntitlementState {
  const EntitlementUnavailable(this.reason);

  /// Short, user-facing explanation. Not an error code.
  final String reason;
}

/// This session has no plan to show: non-landlord roles, or no configured
/// Firebase project.
final class EntitlementNotApplicable extends EntitlementState {
  const EntitlementNotApplicable();
}
