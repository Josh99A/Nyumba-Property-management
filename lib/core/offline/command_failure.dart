import 'remote_sync_gateway.dart';

/// Stable presentation-independent failure identities returned by the command
/// boundary. Presentation code resolves these through the active locale.
enum CommandFailureCode {
  unauthenticated,
  appCheckRequired,
  permissionDenied,
  accountNotApproved,
  accountSuspended,
  subscriptionInactive,
  entitlementMissing,
  unitLimitReached,
  seatLimitReached,
  customRolesUnavailable,
  paymentProviderUnavailable,
  paymentPending,
  notFound,
  alreadyExists,
  versionConflict,
  idempotencyKeyReused,
  rateLimited,
  requiresOnline,
  validationFields,
  subscriptionAlreadyActive,
  subscriptionNotActive,
  tierUnchanged,
  paymentCannotActivateSuspendedAccount,
  landlordAccountMissing,
  accountApprovalStatusInvalid,
  invalidApprovalTransition,
  alreadyArchived,
  notArchived,
  roleUnchanged,
  amountExceedsBalance,
  leaseNotActive,
  noFieldsToUpdate,
  yearlyPriceExceedsMonthlyTimesTwelve,
  unknownCommandType,
  envelopeInvalid,
  validationGeneric,
  validationRejected,
  internalRetryable,
  networkUnavailable,
  deadlineExceeded,
  unknown,
}

final class CommandFailureDescriptor {
  const CommandFailureDescriptor(this.code, {this.rejectedFields = const []});

  final CommandFailureCode code;
  final List<String> rejectedFields;
}

typedef CommandFailureLocalizer = String Function(
  CommandFailureDescriptor failure,
);

/// Converts a remote failure into a stable descriptor without embedding
/// English presentation copy in the offline/application boundary.
CommandFailureDescriptor describeCommandFailure(RemoteSyncException error) {
  final code = switch (error.message) {
    'UNAUTHENTICATED' => CommandFailureCode.unauthenticated,
    'APP_CHECK_REQUIRED' => CommandFailureCode.appCheckRequired,
    'PERMISSION_DENIED' => CommandFailureCode.permissionDenied,
    'ACCOUNT_NOT_APPROVED' => CommandFailureCode.accountNotApproved,
    'ACCOUNT_SUSPENDED' => CommandFailureCode.accountSuspended,
    'SUBSCRIPTION_INACTIVE' => CommandFailureCode.subscriptionInactive,
    'ENTITLEMENT_MISSING' => CommandFailureCode.entitlementMissing,
    'UNIT_LIMIT_REACHED' => CommandFailureCode.unitLimitReached,
    'SEAT_LIMIT_REACHED' => CommandFailureCode.seatLimitReached,
    'CUSTOM_ROLES_UNAVAILABLE' => CommandFailureCode.customRolesUnavailable,
    'PAYMENT_PROVIDER_UNAVAILABLE' =>
      CommandFailureCode.paymentProviderUnavailable,
    'PAYMENT_PENDING' => CommandFailureCode.paymentPending,
    'NOT_FOUND' => CommandFailureCode.notFound,
    'ALREADY_EXISTS' => CommandFailureCode.alreadyExists,
    'VERSION_CONFLICT' => CommandFailureCode.versionConflict,
    'IDEMPOTENCY_KEY_REUSED' => CommandFailureCode.idempotencyKeyReused,
    'RATE_LIMITED' => CommandFailureCode.rateLimited,
    'REQUIRES_ONLINE' => CommandFailureCode.requiresOnline,
    'VALIDATION_FAILED' => _validationCode(error.reason, error.rejectedFields),
    'INTERNAL_RETRYABLE' => CommandFailureCode.internalRetryable,
    'unavailable' || 'network-request-failed' =>
      CommandFailureCode.networkUnavailable,
    'deadline-exceeded' => CommandFailureCode.deadlineExceeded,
    _ => CommandFailureCode.unknown,
  };
  return CommandFailureDescriptor(
    code,
    rejectedFields: code == CommandFailureCode.validationFields
        ? List.unmodifiable(error.rejectedFields)
        : const [],
  );
}

CommandFailureCode _validationCode(String? reason, List<String> fields) {
  if (reason == null && fields.isNotEmpty) {
    return CommandFailureCode.validationFields;
  }
  return switch (reason) {
    'subscriptionAlreadyActive' =>
      CommandFailureCode.subscriptionAlreadyActive,
    'subscriptionNotActive' => CommandFailureCode.subscriptionNotActive,
    'tierUnchanged' => CommandFailureCode.tierUnchanged,
    'accountSuspended' =>
      CommandFailureCode.paymentCannotActivateSuspendedAccount,
    'landlordAccountMissing' => CommandFailureCode.landlordAccountMissing,
    'accountApprovalStatusInvalid' =>
      CommandFailureCode.accountApprovalStatusInvalid,
    'invalidApprovalTransition' =>
      CommandFailureCode.invalidApprovalTransition,
    'alreadyArchived' => CommandFailureCode.alreadyArchived,
    'notArchived' => CommandFailureCode.notArchived,
    'roleUnchanged' => CommandFailureCode.roleUnchanged,
    'amountExceedsBalance' => CommandFailureCode.amountExceedsBalance,
    'leaseNotActive' => CommandFailureCode.leaseNotActive,
    'noFieldsToUpdate' => CommandFailureCode.noFieldsToUpdate,
    'yearlyPriceExceedsMonthlyTimesTwelve' =>
      CommandFailureCode.yearlyPriceExceedsMonthlyTimesTwelve,
    'unknownCommandType' => CommandFailureCode.unknownCommandType,
    'envelopeInvalid' || 'envelopeTooLarge' || 'envelopeNotAnObject' =>
      CommandFailureCode.envelopeInvalid,
    null => CommandFailureCode.validationGeneric,
    // An unrecognised backend token must not be interpolated into user-facing
    // copy. It remains a stable generic rejection descriptor instead.
    _ => CommandFailureCode.validationRejected,
  };
}
