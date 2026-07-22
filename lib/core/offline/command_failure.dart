import 'remote_sync_gateway.dart';

/// Plain-language text for a failed backend command.
///
/// Every mutation crosses the callable command boundary, which answers with a
/// stable domain error code (`docs/architecture/backend-command-contracts.md`).
/// Without this mapping those codes reach people as "Something went wrong",
/// which names nothing and tells them nothing to do — the most common failures
/// (a stale record, a plan limit, a not-yet-live payment rail) all have a real
/// next step, so each one says what it is and what to do about it.
///
/// Server `details.reason` is preferred where it exists: the backend already
/// distinguishes "this is already your plan" from "your subscription is not
/// active", and collapsing those into one message throws that away.
String describeCommandFailure(RemoteSyncException error) {
  final reason = error.reason;
  return switch (error.message) {
    'UNAUTHENTICATED' => 'Your session has expired. Sign in again to continue.',
    'APP_CHECK_REQUIRED' =>
      'Nyumba could not verify this device. Update the app and try again.',
    'PERMISSION_DENIED' =>
      'This account does not have permission to do that.',
    'ACCOUNT_NOT_APPROVED' =>
      'Your account is still awaiting review, so this action is not available '
          'yet.',
    'ACCOUNT_SUSPENDED' =>
      'This account is suspended. Contact Nyumba support to restore it.',
    'SUBSCRIPTION_INACTIVE' =>
      'Your subscription is not active yet, so this action is unavailable.',
    'ENTITLEMENT_MISSING' =>
      'Nyumba could not confirm your plan, so this action was not applied. '
          'Try again shortly, or contact support if it continues.',
    'UNIT_LIMIT_REACHED' =>
      'You have reached the limit your plan allows. Upgrade your plan to add '
          'more.',
    'SEAT_LIMIT_REACHED' =>
      'You have used every staff seat your plan allows. Upgrade your plan to '
          'add more team members.',
    'CUSTOM_ROLES_UNAVAILABLE' =>
      'Custom staff permissions are a Premium feature. Upgrade your plan to '
          'tailor what each team member can do.',
    'PAYMENT_PROVIDER_UNAVAILABLE' =>
      'Electronic payments are not available yet. Pay Nyumba directly and an '
          'administrator will confirm it.',
    'PAYMENT_PENDING' =>
      'This payment is still being confirmed. You will see it here as soon as '
          'it clears.',
    'NOT_FOUND' =>
      'Nyumba could not find that record. It may have been removed — reload '
          'and try again.',
    'ALREADY_EXISTS' => 'That record already exists.',
    'VERSION_CONFLICT' =>
      'Someone else changed this while you were working on it. Reload to see '
          'the latest version, then try again.',
    'IDEMPOTENCY_KEY_REUSED' =>
      'This action was already sent with different details. Reload and try '
          'again.',
    'RATE_LIMITED' =>
      'Too many attempts. Wait a moment before trying again.',
    'REQUIRES_ONLINE' =>
      'This action needs an internet connection. Reconnect and try again.',
    'VALIDATION_FAILED' => _describeValidation(reason, error.rejectedFields),
    'INTERNAL_RETRYABLE' =>
      'Nyumba could not complete that just now. Please try again.',
    'unavailable' || 'network-request-failed' =>
      'Nyumba cannot reach the server. Check your connection and try again.',
    'deadline-exceeded' => 'The server took too long to respond. Try again.',
    _ => 'Nyumba could not complete that action. Please try again.',
  };
}

/// `VALIDATION_FAILED` is the server's catch-all, so its `reason` carries the
/// real explanation. An unrecognised reason still beats silence: it names the
/// field or rule the backend rejected.
String _describeValidation(String? reason, List<String> fields) {
  if (reason == null && fields.isNotEmpty) {
    return 'Nyumba did not accept these details: ${fields.join(', ')}. Check '
        'them and try again — if they look right, reload the app to get the '
        'latest version.';
  }
  return _describeValidationReason(reason);
}

String _describeValidationReason(String? reason) => switch (reason) {
  'subscriptionAlreadyActive' => 'That plan is already active on this account.',
  'subscriptionNotActive' =>
    'Your subscription is not active yet, so it cannot be upgraded. Complete '
        'your first payment first.',
  'tierUnchanged' => 'That is already your current plan. Choose a different '
      'one to change plans.',
  'accountSuspended' =>
    'This account is suspended, so payment cannot activate it. It must be '
        'reinstated first.',
  'landlordAccountMissing' =>
    'This account has no landlord record yet, so it cannot be activated.',
  'accountApprovalStatusInvalid' =>
    'This account is not in a state that can be activated.',
  'invalidApprovalTransition' =>
    'This account is no longer in that state. Reload to see its current '
        'status.',
  'alreadyArchived' => 'This account is already archived.',
  'notArchived' => 'Archive this account before doing that.',
  'roleUnchanged' => 'That is already this account\'s role.',
  'amountExceedsBalance' =>
    'That amount is more than the outstanding balance.',
  'leaseNotActive' => 'That tenancy is not active.',
  'noFieldsToUpdate' => 'Change at least one detail before saving.',
  'yearlyPriceExceedsMonthlyTimesTwelve' =>
    'The yearly price cannot cost more than twelve monthly payments.',
  'unknownCommandType' =>
    'This version of the app is out of date. Reload to get the latest '
        'version.',
  // A payload the server refused. Almost always a client that is behind the
  // deployed backend, so say the one thing that actually fixes it.
  'envelopeInvalid' || 'envelopeTooLarge' || 'envelopeNotAnObject' =>
    'Nyumba could not accept that request. Reload the app and try again.',
  null => 'Some of those details were not accepted. Check them and try again.',
  _ => 'Nyumba did not accept that request ($reason). Reload and try again.',
};
