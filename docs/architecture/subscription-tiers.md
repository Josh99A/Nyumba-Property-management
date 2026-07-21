# Subscription tiers and entitlements

This document is the normative tier structure for Nyumba subscriptions. It
resolves the tier *shape* and the launch pricing; trials and transaction fees
remain **TBD**. Prices, limits, and feature availability live in versioned
server-owned configuration (see
[firebase-data-and-security.md](firebase-data-and-security.md)) — this
document records the decisions, the catalog serves them.

## Pricing (decided 2026-07-20)

| Billing | Starter | Pro | Premium | Enterprise |
|---|---:|---:|---:|---:|
| Monthly (UGX) | 50,000 | 100,000 | 200,000 | 300,000 |
| Yearly (UGX) | 500,000 | 1,000,000 | 2,000,000 | 3,000,000 |

Yearly billing is priced at ten months (two months free, shown to landlords
as a ~17% saving). Prices are stored on `planCatalog/{tier}` in UGX minor
units (`monthlyPriceMinor`, `yearlyPriceMinor`) and are seeded by
`firebase/functions/scripts/seed-entitlements.mjs`. Super admins change them at
runtime through the audited `plan.update` command (admin Subscriptions
screen); the client never hard-codes a price, and the saving percentage is
derived from the two stored prices rather than stored itself.

## Feature availability ("coming soon" greying)

Each catalog entry carries a `features` list — `{id, label, implemented}` —
covering the tier's incremental benefits. Benefits with `implemented: false`
are sold on the roadmap and MUST stay visible but greyed out with a "coming
soon" marker wherever plans are rendered, so nobody pays for a promise they
did not see. When a feature ships, a super admin flips its flag via
`plan.update` (no deploy needed). Operational promises delivered by people
(support tiers, onboarding, SLA) count as implemented.

## Self-service upgrades

An active landlord upgrades from inside the app: the subscription screen
offers every higher tier as an "Upgrade" action. Tapping it asks **how they
will pay** before anything is recorded, and the chosen method decides how the
upgrade is confirmed:

- **Cash** → `subscription.requestUpgrade` records `requestedTier` +
  `billingChannel: cash` + `upgradeState: awaiting_admin`. The request appears
  in the admin payment-confirmation queue, and `subscription.confirmPayment`
  applies the new tier against a verified reference once the cash is received.
- **Mobile money / card** → the electronic path. A real aggregator collects
  the money and its signed webhook calls the same `confirmPayment` transition
  to auto-activate the upgrade with **no admin in the loop**. This path
  **fails closed** (`PAYMENT_PROVIDER_UNAVAILABLE`) until an aggregator is
  configured in `backendConfig/subscriptionBilling.enabled`, so the app never
  activates a plan against money that never moved. Until then the app tells
  the landlord electronic checkout is coming soon and to pay cash.

In every case `requestUpgrade` records only intent — the paid plan, its
entitlements, and the workspace stay exactly as paid for until the matching
confirmation runs. Downgrades remain a support conversation (the
downgrade-safety rules below still govern them).

**Wiring an aggregator later:** register a `PaymentProviderAdapter`
(`workers/payment-provider.ts`), set `backendConfig/subscriptionBilling.enabled`,
and add the signed webhook that calls `subscription.confirmPayment` for the
subscription owner. No client change is needed — the electronic path already
routes through `requestUpgrade` and stops failing closed the moment billing is
enabled.

When a landlord hits a plan wall the app prompts the upgrade path instead of
failing silently: adding a rental space at the unit limit and publishing a
listing at the active-listing limit both raise an upgrade prompt that names
the limit and links to the subscription screen. Prompts fire only on a
server-confirmed entitlement — an unknown or unavailable plan never blocks
locally; the backend stays the judge.

## Platform broadcasts

Super admins can send platform announcements (incidents, maintenance windows,
commercial notices) through the `platform.broadcast` command: to everyone, a
role group (landlords/tenants/clients), every account on one subscription
tier, or a single account. Delivery is a durable backend job that writes each
recipient's notification inbox, sends a push nudge, and emails a courtesy
copy. Broadcast records live in server-owned `platformBroadcasts` documents,
readable by platform staff for the history panel on the admin Announcements
screen.

## Who subscribes

Subscriptions apply to **landlords and property managers** only. Tenant and
prospective-client access is free and must remain free: tenants always keep
their portal (balances, payments, documents, maintenance requests), and
anonymous prospects always keep public listing browsing, contact, and
applications.

## Tier matrix

| Capability | Starter | Pro | Premium | Enterprise |
|---|---:|---:|---:|---:|
| Suggested unit limit | 10 | 50 | 200 | Custom, 200+ |
| Landlord/staff accounts | 1 | 3 | 10 | Custom |
| Active public listings | 3 | 25 | All vacant units | Custom |
| Properties, units, tenants and leases | Included | Included | Included | Included |
| Rent ledger, invoices and receipts | Basic | Automated | Advanced | Custom |
| Maintenance management | Basic requests | Assignment and tracking | Vendors and workflows | Custom workflows |
| Reports | Basic dashboard | Operational reports | Advanced/custom reports | Cross-portfolio analytics |
| Communication | Individual notices | Bulk notices and reminders | Automated communication | Custom channels |
| Roles and permissions | Owner only | Standard staff roles | Custom roles | Organization-wide roles |
| Integrations | None | Selected integrations | API and webhooks | Custom integrations |
| Support | Email/help centre | Priority support | Priority onboarding | Dedicated manager and SLA |

## Tier contents

### Starter — individual landlords and small portfolios

- Property and unit management
- Tenant profiles and lease records
- Rent balances and payment recording
- Basic invoice and receipt generation
- Maintenance request tracking
- Notices and document printing
- Basic dashboard and reports
- Up to three public advertisements
- Offline access and synchronization
- Data export
- One landlord account

### Pro — growing landlords and small property-management teams

Everything in Starter, plus:

- Recurring rent invoices
- Payment and overdue-rent reminders
- Configurable late-fee policies
- Application and prospective-client management
- Lease-expiry and renewal reminders
- Bulk tenant notices
- Document templates
- Staff accounts with standard permissions
- More public advertisements
- Operational and financial reports
- Priority support

### Premium — professional property managers with larger portfolios

Everything in Pro, plus:

- Workflow automation
- Advanced dashboards and custom reports
- Multiple portfolios and property groups
- Vendor and work-order management
- Inspection records
- Bulk unit, tenant, and payment operations
- Custom fields
- API and webhook access
- Accounting or payment-provider integrations
- Searchable/exportable audit history
- Custom staff roles and permissions
- Priority onboarding and support
- Advertising for every eligible vacant unit

### Enterprise — agencies, institutions, and large companies

Everything in Premium, plus:

- Custom unit and user limits
- Multiple branches or organizations
- Enterprise SSO
- Advanced organization-level permissions
- Dedicated onboarding and data migration
- Custom integrations and API limits
- Data warehouse or scheduled report exports
- Configurable audit-log retention
- Contract billing and negotiated transaction fees
- Dedicated account manager
- Guaranteed support response times and SLA
- Optional branded portals and custom domain

## Rules that hold across every tier

1. **Never paywalled:** security, tenant access, data export, offline
   reliability, and server-side audit logging. Higher tiers may add longer
   audit retention and advanced audit search, but the underlying logging and
   a baseline export always exist.
2. **Server-owned entitlements:** unit limits and feature entitlements are
   versioned server-owned configuration (`planCatalog`, `entitlementsVersion`),
   never hard-coded in Flutter or security rules. An unknown or missing plan
   grants no unit-creation or publishing entitlement (fail closed).
3. **Downgrade safety:** a downgrade never deletes units and never blocks
   tenants. The account receives a grace period, keeps read access to all
   existing data, and is only prevented from creating additional units or
   publishing new listings until it is within its new limit. Existing
   published listings beyond the limit stop renewing rather than being
   removed abruptly.

## Client presentation

After landlord onboarding, the client routes the account to the subscription
screen and keeps every landlord workspace route locked until the server-owned
subscription status is `active`. The screen renders plan names and capacity
limits from the public `planCatalog` documents (seeded by
`scripts/seed-entitlements.mjs`), never from values baked into Flutter, and
lets the landlord change their intended tier via `subscription.selectPlan`
while unpaid. A local plan choice, an initiated checkout, or an accepted
asynchronous command is never payment confirmation. New accounts start as
`pending_payment`; activation happens only through the audited
`subscription.confirmPayment` command — platform staff today
(`firebase/functions/scripts/confirm-subscription.mjs`), a verified provider webhook once billing
integration exists. Confirming payment also approves a still-pending landlord
account in the same transaction, so one confirmed payment activates the
account and opens the workspace (a suspended account rejects instead —
reinstatement is a separate, deliberate act). In-app checkout stays
unavailable and fails closed rather than simulating payment.

The admin subscriptions screen renders the same server-owned catalog —
prices, limits, and roadmap counts — and offers super admins the `plan.update`
editor. The client may render plan and entitlement state, but enforcement
(unit counting, publishing entitlement, billing state) is exclusively
server-side, per
[backend-command-contracts.md](backend-command-contracts.md).

Benchmarks consulted: DoorLoop, TenantCloud, and Buildium keep core rent,
tenant, lease, and maintenance tools in entry tiers; automation and team
features in mid tiers; and APIs, custom permissions, audit tooling, and
premium support in higher tiers.
