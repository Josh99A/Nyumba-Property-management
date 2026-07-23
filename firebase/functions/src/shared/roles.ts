/**
 * The additive `users.{roles}` array. The scalar `role` field stays the
 * client-facing primary and is never used for authorization; the array exists
 * so one account can hold several ordinary roles at once (a tenant who
 * onboards as a landlord keeps 'tenant') and so broadcast fanout can target
 * every role a person holds rather than only the primary one.
 */

export type OrdinaryRole = 'client' | 'tenant' | 'landlord';

const ORDINARY_ROLES: ReadonlySet<string> = new Set(['client', 'tenant', 'landlord']);

/**
 * Merges [added] into an account's role set. Seeds from the existing array
 * when present, else from the legacy scalar; 'client' is a placeholder that
 * drops out as soon as a real role exists. Unknown strings are discarded, not
 * trusted. Returns a sorted, de-duplicated array so repeated writes are
 * byte-identical.
 */
export function mergeRoles(
  existingRoles: unknown,
  existingScalar: unknown,
  added: OrdinaryRole,
): OrdinaryRole[] {
  const roles = new Set<OrdinaryRole>();
  if (Array.isArray(existingRoles)) {
    for (const entry of existingRoles) {
      if (typeof entry === 'string' && ORDINARY_ROLES.has(entry)) {
        roles.add(entry as OrdinaryRole);
      }
    }
  } else if (typeof existingScalar === 'string' && ORDINARY_ROLES.has(existingScalar)) {
    roles.add(existingScalar as OrdinaryRole);
  }
  roles.add(added);
  if (roles.size > 1) roles.delete('client');
  return [...roles].sort();
}
