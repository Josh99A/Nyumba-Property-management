# Subscription tiers and entitlements

This document is the normative tier structure for Nyumba subscriptions. It
resolves the tier *shape*; monetary prices, billing intervals, trials, and
transaction fees remain **TBD** and belong in versioned server-owned
configuration (see [firebase-data-and-security.md](firebase-data-and-security.md)).

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
(`scripts/confirm-subscription.mjs`), a verified provider webhook once billing
integration exists. In-app checkout stays unavailable and fails closed rather
than simulating payment.

The admin subscriptions screen presents this structure with illustrative UGX
prices clearly labelled as drafts. The client may render plan and entitlement
state, but enforcement (unit counting, publishing entitlement, billing state)
is exclusively server-side, per
[backend-command-contracts.md](backend-command-contracts.md).

Benchmarks consulted: DoorLoop, TenantCloud, and Buildium keep core rent,
tenant, lease, and maintenance tools in entry tiers; automation and team
features in mid tiers; and APIs, custom permissions, audit tooling, and
premium support in higher tiers.
