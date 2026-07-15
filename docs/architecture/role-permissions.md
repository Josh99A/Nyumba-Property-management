# Role and permission policy

This is the normative application RBAC matrix. `C`, `R`, `U`, and `D` mean
create, read, update, and archive/tombstone respectively. A permission never
bypasses ownership, relationship, account-state, entitlement, validation,
payment-provider, retention, or audit requirements. Canonical writes continue
to use explicit callable commands; there is no generic administrative database
write endpoint.

| Resource | Super admin | Admin | Landlord | Tenant | Client |
| --- | --- | --- | --- | --- | --- |
| Super-admin accounts | CRUD | - | - | - | - |
| Admin accounts | CRUD | R | - | - | - |
| User accounts | CRUD | CRUD | - | - | - |
| Own profile | CRUD | CRUD | RU | RU | CRUD |
| Landlord account/approval | CRUD | CRUD | R | - | - |
| Subscriptions/plans | CRUD | CRUD | RU request only | - | - |
| Properties/units | CRUD | CRUD | CRUD, owned | safe projection R | - |
| Tenant records | CRUD | CRUD | CRUD, owned | - | - |
| Leases | CRUD | CRUD | CRU, owned | own projection R | - |
| Invoices | CRUD | CRUD | CR, owned | own projection R | - |
| Payments | controlled CRUD | controlled CRUD | CRU, owned | CR, own | - |
| Receipts | controlled CRUD | controlled CRUD | R, owned | R, own | - |
| Maintenance | CRUD | CRUD | CRU, owned | CRU, own | - |
| Notices/documents | CRUD | CRUD | CRUD, owned | delivered/shared R | - |
| Private listings | CRUD | CRUD | CRUD, owned | - | - |
| Public listings | CRUD | CRUD | R plus publish commands | R | R |
| Applications | CRUD | CRUD | RU for owned listings | CR when also applying | CRU, own |
| Contact requests | CRUD | CRUD | RU for owned listings | CR when also enquiring | CR, own |
| Reports | CRUD | CRUD | CR, owned | - | - |
| Audit logs | R | R | - | - | - |
| Platform security/backend operations | controlled CRUD | configuration RU | - | - | - |

## Privileged-role rules

- `superAdmin: true` and `platformAdmin: true` are separate server-issued
  custom claims. If both are present, `superAdmin` wins.
- An Admin cannot create, promote, suspend, demote, or delete an Admin or Super
  Admin account. A Super Admin may manage privileged accounts other than their
  own active session.
- Both roles may read the canonical operational collections needed for their
  work. Neither may directly write canonical Firestore or Storage records.
- Audit logs remain append-only. Backend jobs/provider payloads are not exposed
  directly; safe operational commands and projections are used instead.
- Electronic payment confirmation, subscription activation, and receipt
  issuance remain provider/server authoritative for every role.
- Financial deletion means an audited reversal/correction plus retention, never
  erasing protected history.

The Flutter mirror of this matrix is
`lib/features/auth/domain/authorization_policy.dart`. Firebase Rules and each
callable handler must still enforce the relevant server-side subset.
