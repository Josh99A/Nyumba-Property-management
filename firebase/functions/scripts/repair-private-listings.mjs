#!/usr/bin/env node
/**
 * Repairs private listing documents written before the server persisted the
 * client-required `propertyId` and `currency` fields.
 *
 * Valid listings are re-saved through `listing.saveDraft`, so the normal
 * validation, receipt, version bump, and audit trail all apply. A listing
 * whose unit no longer exists is only reported by default. Pass both
 * `--apply` and `--delete-orphans` after reviewing the dry run to retire those
 * records through the audited `listing.delete` command.
 *
 * Usage:
 *   node scripts/repair-private-listings.mjs --project <projectId>
 *   node scripts/repair-private-listings.mjs --project <projectId> --apply
 *   node scripts/repair-private-listings.mjs --project <projectId> --apply --delete-orphans
 *
 * Run `npm run build` first (imports the compiled router from lib/).
 * Requires Application Default Credentials with access to the target project.
 */
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { executeCommandCore } from '../lib/shared/router.js';

const args = process.argv.slice(2);
const projectFlag = args.indexOf('--project');
const projectId = projectFlag === -1 ? null : args[projectFlag + 1];
const apply = args.includes('--apply');
const deleteOrphans = args.includes('--delete-orphans');

if (!projectId || projectId.startsWith('--')) {
  console.error('Pass an explicit Firebase project: --project <projectId>');
  process.exit(1);
}
if (deleteOrphans && !apply) {
  console.error('--delete-orphans also requires --apply.');
  process.exit(1);
}

initializeApp({ projectId });
const db = getFirestore();

const commandClient = {
  // No date baked in: this string lands in the command envelope and the audit
  // trail, so a literal one would report the day the script was written on
  // every future run.
  installationId: 'ops_listing_repair',
  appVersion: 'repair-1',
  platform: 'web',
};

function commandActor(uid = 'ops_script_super_admin') {
  return {
    uid,
    email: null,
    platformAdmin: true,
    superAdmin: true,
    emailVerified: true,
    signInProvider: null,
  };
}

function uploaderUid(paths) {
  const match = Array.isArray(paths) && paths.length > 0
    ? /^uploads\/([^/]+)\//.exec(paths[0])
    : null;
  return match?.[1] ?? 'ops_script_super_admin';
}

function draftPayload(data) {
  const payload = {
    unitId: data.unitId,
    title: data.title,
    description: data.description,
    monthlyRentMinor: data.monthlyRentMinor,
    unitType: data.unitType,
    city: data.city,
    neighborhood: data.neighborhood,
    bedrooms: data.bedrooms,
    bathrooms: data.bathrooms,
    amenities: Array.isArray(data.amenities) ? data.amenities : [],
  };
  if (typeof data.district === 'string') payload.district = data.district;
  if (data.approximateLocation !== undefined) {
    payload.approximateLocation = data.approximateLocation;
  }
  if (Array.isArray(data.stagedImagePaths)) {
    payload.stagedImagePaths = data.stagedImagePaths;
  }
  return payload;
}

const listings = await db.collection('privateListings').get();
let repairable = 0;
let repaired = 0;
let orphans = 0;
let deleted = 0;

for (const listing of listings.docs) {
  const data = listing.data();
  if (
    typeof data.propertyId === 'string' &&
    data.propertyId.length > 0 &&
    typeof data.currency === 'string' &&
    data.currency.length > 0
  ) {
    continue;
  }

  const unit = typeof data.unitId === 'string'
    ? await db.collection('units').doc(data.unitId).get()
    : null;
  if (!unit?.exists) {
    orphans += 1;
    console.log(`ORPHAN privateListings/${listing.id} -> units/${data.unitId ?? '(missing)'}`);
    if (apply && deleteOrphans) {
      const response = await executeCommandCore(
        db,
        commandActor(),
        {
          commandId: `repair_delete_${listing.id}`,
          type: 'listing.delete',
          schemaVersion: 1,
          aggregateId: listing.id,
          expectedVersion: data.version,
          payload: { reasonCode: 'ADMIN_CORRECTION' },
          client: commandClient,
        },
      );
      if (response.status === 'rejected') {
        throw new Error(
          `listing.delete rejected for ${listing.id}: ${response.error?.code}`,
        );
      }
      deleted += 1;
    }
    continue;
  }

  repairable += 1;
  console.log(
    `REPAIR privateListings/${listing.id} from units/${data.unitId} `
      + `(version ${data.version})`,
  );
  if (!apply) continue;

  const response = await executeCommandCore(
    db,
    commandActor(uploaderUid(data.stagedImagePaths)),
    {
      commandId: `repair_shape_${listing.id}`,
      type: 'listing.saveDraft',
      schemaVersion: 1,
      aggregateId: listing.id,
      expectedVersion: data.version,
      payload: draftPayload(data),
      client: commandClient,
    },
  );
  if (response.status === 'rejected') {
    throw new Error(
      `listing.saveDraft rejected for ${listing.id}: ${response.error?.code}`,
    );
  }
  repaired += 1;
}

console.log(
  `${apply ? 'Applied' : 'Dry run'} on ${projectId}: `
    + `${repairable} repairable (${repaired} repaired), `
    + `${orphans} orphaned (${deleted} deleted).`,
);
