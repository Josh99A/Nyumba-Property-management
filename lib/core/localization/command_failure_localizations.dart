import '../offline/command_failure.dart';
import 'generated/app_localizations.dart';

/// Resolves a command failure descriptor through generated localized copy.
String localizeCommandFailure(
  AppLocalizations copy,
  CommandFailureDescriptor failure,
) => switch (failure.code) {
  CommandFailureCode.unauthenticated => copy.legacy_bd9b9bf7438f,
  CommandFailureCode.appCheckRequired => copy.legacy_3a6e632ad56d,
  CommandFailureCode.permissionDenied => copy.legacy_0486dbaa769f,
  CommandFailureCode.accountNotApproved => copy.legacy_bdbcbdd54088,
  CommandFailureCode.accountSuspended => copy.legacy_e2a1b305ffbd,
  CommandFailureCode.subscriptionInactive => copy.legacy_f6bf142ea0c0,
  CommandFailureCode.entitlementMissing => copy.legacy_fc164894a18a,
  CommandFailureCode.unitLimitReached => copy.legacy_427eb1e9b92d,
  CommandFailureCode.seatLimitReached => copy.legacy_c34019924764,
  CommandFailureCode.customRolesUnavailable => copy.legacy_87a2131e6d61,
  CommandFailureCode.paymentProviderUnavailable => copy.legacy_b292aea5f50e,
  CommandFailureCode.paymentPending => copy.legacy_6e7e677ba3d3,
  CommandFailureCode.notFound => copy.legacy_5f40e5d243c5,
  CommandFailureCode.alreadyExists => copy.legacy_865689190ea5,
  CommandFailureCode.versionConflict => copy.legacy_2dc6de513de7,
  CommandFailureCode.idempotencyKeyReused => copy.legacy_977b7fe2ba26,
  CommandFailureCode.rateLimited => copy.legacy_4610306154c0,
  CommandFailureCode.requiresOnline => copy.legacy_34a370bb8f26,
  CommandFailureCode.validationFields => copy.legacy_553f76c2b4de(
    failure.rejectedFields.join(', '),
  ),
  CommandFailureCode.subscriptionAlreadyActive => copy.legacy_e3d4879fe8e6,
  CommandFailureCode.subscriptionNotActive => copy.legacy_5856f45a39ca,
  CommandFailureCode.tierUnchanged => copy.legacy_ab87caef66c3,
  CommandFailureCode.paymentCannotActivateSuspendedAccount =>
    copy.legacy_b7224264cf97,
  CommandFailureCode.landlordAccountMissing => copy.legacy_98c1804b4d45,
  CommandFailureCode.accountApprovalStatusInvalid => copy.legacy_0d1dfd3592f9,
  CommandFailureCode.invalidApprovalTransition => copy.legacy_208b9378be87,
  CommandFailureCode.alreadyArchived => copy.legacy_8927961a2446,
  CommandFailureCode.notArchived => copy.legacy_59138b8999c6,
  CommandFailureCode.roleUnchanged => copy.legacy_dad068aa555b,
  CommandFailureCode.amountExceedsBalance => copy.legacy_26124c0ce6a9,
  CommandFailureCode.leaseNotActive => copy.legacy_b85cb4bf091b,
  CommandFailureCode.noFieldsToUpdate => copy.legacy_4134f7a8316a,
  CommandFailureCode.yearlyPriceExceedsMonthlyTimesTwelve =>
    copy.legacy_ad65b6dfeb97,
  CommandFailureCode.unknownCommandType => copy.legacy_e9b3d6e695b4,
  CommandFailureCode.envelopeInvalid => copy.legacy_f810bcddd7ed,
  CommandFailureCode.validationGeneric => copy.legacy_eacb633c809b,
  CommandFailureCode.validationRejected => copy.legacy_8032d3a419ad,
  CommandFailureCode.internalRetryable => copy.legacy_8dd971279a6c,
  CommandFailureCode.networkUnavailable => copy.legacy_b791dbf9cc55,
  CommandFailureCode.deadlineExceeded => copy.legacy_06fafad86a95,
  CommandFailureCode.unknown => copy.legacy_3852e291776f,
};
