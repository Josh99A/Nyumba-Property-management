import type { AuthData } from 'firebase-functions/v2/tasks';
import { DomainError } from './errors';

/**
 * The verified actor. Everything here comes from the decoded Firebase Auth
 * token; nothing is ever read from the command payload.
 */
export interface Actor {
  uid: string;
  /** Token email; only trustworthy for linking when emailVerified is true. */
  email: string | null;
  platformAdmin: boolean;
  superAdmin: boolean;
  emailVerified: boolean;
  signInProvider: string | null;
}

export function actorFromAuth(auth: AuthData | undefined): Actor {
  if (!auth?.uid) throw new DomainError('UNAUTHENTICATED');
  const token = auth.token;
  return {
    uid: auth.uid,
    email: typeof token.email === 'string' ? token.email : null,
    platformAdmin: token.platformAdmin === true,
    superAdmin: token.superAdmin === true,
    emailVerified: token.email_verified === true,
    signInProvider: token.firebase?.sign_in_provider ?? null,
  };
}

export function requirePlatformAdmin(actor: Actor): void {
  if (!actor.platformAdmin && !actor.superAdmin) {
    throw new DomainError('PERMISSION_DENIED');
  }
}

export function requireSuperAdmin(actor: Actor): void {
  if (!actor.superAdmin) throw new DomainError('PERMISSION_DENIED');
}
