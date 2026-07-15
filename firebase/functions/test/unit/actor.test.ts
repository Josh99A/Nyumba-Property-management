import { describe, expect, it } from 'vitest';
import { actorFromAuth, requirePlatformAdmin, requireSuperAdmin } from '../../src/shared/actor';

function authWithClaims(claims: Record<string, unknown>) {
  return {
    uid: 'user_123456',
    token: {
      ...claims,
      firebase: { sign_in_provider: 'password' },
    },
  } as Parameters<typeof actorFromAuth>[0];
}

describe('administrator claims', () => {
  it('keeps admin and super-admin identities distinct', () => {
    const admin = actorFromAuth(authWithClaims({ platformAdmin: true }));
    const superAdmin = actorFromAuth(authWithClaims({ superAdmin: true }));

    expect(admin).toMatchObject({ platformAdmin: true, superAdmin: false });
    expect(superAdmin).toMatchObject({ platformAdmin: false, superAdmin: true });
    expect(() => requirePlatformAdmin(admin)).not.toThrow();
    expect(() => requirePlatformAdmin(superAdmin)).not.toThrow();
    expect(() => requireSuperAdmin(admin)).toThrow();
    expect(() => requireSuperAdmin(superAdmin)).not.toThrow();
  });
});
