import { HttpsError, type FunctionsErrorCode } from 'firebase-functions/v2/https';

/**
 * Stable domain error codes from docs/architecture/backend-command-contracts.md.
 * Clients branch on these, never on transport status codes.
 */
export const DOMAIN_ERROR_CODES = [
  'UNAUTHENTICATED',
  'APP_CHECK_REQUIRED',
  'PERMISSION_DENIED',
  'ACCOUNT_NOT_APPROVED',
  'ACCOUNT_SUSPENDED',
  'SUBSCRIPTION_INACTIVE',
  'ENTITLEMENT_MISSING',
  'UNIT_LIMIT_REACHED',
  'VALIDATION_FAILED',
  'NOT_FOUND',
  'ALREADY_EXISTS',
  'VERSION_CONFLICT',
  'IDEMPOTENCY_KEY_REUSED',
  'RATE_LIMITED',
  'REQUIRES_ONLINE',
  'PAYMENT_PROVIDER_UNAVAILABLE',
  'PAYMENT_PENDING',
  'INTERNAL_RETRYABLE',
] as const;

export type DomainErrorCode = (typeof DOMAIN_ERROR_CODES)[number];

const MESSAGE_KEYS: Record<DomainErrorCode, string> = {
  UNAUTHENTICATED: 'auth.required',
  APP_CHECK_REQUIRED: 'auth.appCheckRequired',
  PERMISSION_DENIED: 'auth.permissionDenied',
  ACCOUNT_NOT_APPROVED: 'account.notApproved',
  ACCOUNT_SUSPENDED: 'account.suspended',
  SUBSCRIPTION_INACTIVE: 'subscription.inactive',
  ENTITLEMENT_MISSING: 'subscription.entitlementMissing',
  UNIT_LIMIT_REACHED: 'subscription.unitLimitReached',
  VALIDATION_FAILED: 'validation.failed',
  NOT_FOUND: 'resource.notFound',
  ALREADY_EXISTS: 'resource.alreadyExists',
  VERSION_CONFLICT: 'sync.versionConflict',
  IDEMPOTENCY_KEY_REUSED: 'sync.idempotencyKeyReused',
  RATE_LIMITED: 'request.rateLimited',
  REQUIRES_ONLINE: 'request.requiresOnline',
  PAYMENT_PROVIDER_UNAVAILABLE: 'payment.providerUnavailable',
  PAYMENT_PENDING: 'payment.pending',
  INTERNAL_RETRYABLE: 'request.internalRetryable',
};

/**
 * Deterministic rejections produce the same answer for every retry of the
 * same command, so the router persists them as `rejected` receipts. Every
 * other code is transient or transport-level and must never be persisted.
 */
const DETERMINISTIC_CODES: ReadonlySet<DomainErrorCode> = new Set([
  'PERMISSION_DENIED',
  'ACCOUNT_NOT_APPROVED',
  'ACCOUNT_SUSPENDED',
  'SUBSCRIPTION_INACTIVE',
  'ENTITLEMENT_MISSING',
  'UNIT_LIMIT_REACHED',
  'VALIDATION_FAILED',
  'NOT_FOUND',
  'ALREADY_EXISTS',
  'VERSION_CONFLICT',
]);

const HTTPS_CODES: Record<DomainErrorCode, FunctionsErrorCode> = {
  UNAUTHENTICATED: 'unauthenticated',
  APP_CHECK_REQUIRED: 'unauthenticated',
  PERMISSION_DENIED: 'permission-denied',
  ACCOUNT_NOT_APPROVED: 'permission-denied',
  ACCOUNT_SUSPENDED: 'permission-denied',
  SUBSCRIPTION_INACTIVE: 'permission-denied',
  ENTITLEMENT_MISSING: 'permission-denied',
  UNIT_LIMIT_REACHED: 'resource-exhausted',
  VALIDATION_FAILED: 'invalid-argument',
  NOT_FOUND: 'not-found',
  ALREADY_EXISTS: 'already-exists',
  VERSION_CONFLICT: 'failed-precondition',
  IDEMPOTENCY_KEY_REUSED: 'failed-precondition',
  RATE_LIMITED: 'resource-exhausted',
  REQUIRES_ONLINE: 'failed-precondition',
  PAYMENT_PROVIDER_UNAVAILABLE: 'unavailable',
  PAYMENT_PENDING: 'failed-precondition',
  INTERNAL_RETRYABLE: 'internal',
};

/** Details must only carry safe remediation data, never another user's record. */
export type SafeDetails = Record<string, string | number | boolean | string[]>;

export class DomainError extends Error {
  readonly code: DomainErrorCode;
  readonly messageKey: string;
  readonly details: SafeDetails;

  constructor(code: DomainErrorCode, details: SafeDetails = {}) {
    super(`${code}: ${MESSAGE_KEYS[code]}`);
    this.name = 'DomainError';
    this.code = code;
    this.messageKey = MESSAGE_KEYS[code];
    this.details = details;
  }

  get deterministic(): boolean {
    return DETERMINISTIC_CODES.has(this.code);
  }

  toSafeError(): { code: DomainErrorCode; messageKey: string; details: SafeDetails } {
    return { code: this.code, messageKey: this.messageKey, details: this.details };
  }

  toHttpsError(): HttpsError {
    return new HttpsError(HTTPS_CODES[this.code], this.messageKey, this.toSafeError());
  }
}
