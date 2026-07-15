import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { COLLECTIONS, TENANT_PORTAL_SECTIONS } from '../shared/collections';
import { tenantNoticeProjection } from '../shared/projections';

/**
 * Resolves a notice's audience to tenant UIDs and writes their portal
 * projections idempotently. Delivery honors the notice's audience scope:
 * `all_active_tenants`, one `property`, or one `lease`.
 */
export async function fanoutNotice(payload: Record<string, unknown>): Promise<void> {
  const db = getFirestore();
  const noticeId = String(payload.noticeId);
  const landlordId = String(payload.landlordId);
  const noticeRef = db.collection(COLLECTIONS.notices).doc(noticeId);
  const noticeSnap = await noticeRef.get();
  if (!noticeSnap.exists) return;
  const raw = noticeSnap.data()!;
  // Tenants receive the published shape even though the canonical document is
  // only marked published after the fanout completes.
  const notice: Record<string, unknown> = {
    ...raw,
    publishState: 'published',
    publishedAt: raw.publishedAt ?? Timestamp.now(),
  };
  const audience = String(notice.audience ?? 'all_active_tenants');
  const audienceId = typeof notice.audienceId === 'string' ? notice.audienceId : null;

  let leasesQuery = db
    .collection(COLLECTIONS.leases)
    .where('landlordId', '==', landlordId)
    .where('status', '==', 'active');
  if (audience === 'lease') {
    if (!audienceId) return;
    leasesQuery = leasesQuery.where('id', '==', audienceId);
  } else if (audience === 'property') {
    if (!audienceId) return;
    const units = await db
      .collection(COLLECTIONS.units)
      .where('landlordId', '==', landlordId)
      .where('propertyId', '==', audienceId)
      .get();
    const unitIds = units.docs.map((unit) => unit.id);
    if (unitIds.length === 0) return;
    // Firestore 'in' filters accept at most 30 values; fan out per chunk.
    const tenantUids = new Set<string>();
    for (let start = 0; start < unitIds.length; start += 30) {
      const chunk = unitIds.slice(start, start + 30);
      const leases = await leasesQuery.where('unitId', 'in', chunk).get();
      for (const lease of leases.docs) {
        const uid = lease.data().tenantUserUid;
        if (typeof uid === 'string') tenantUids.add(uid);
      }
    }
    await deliver(noticeId, notice, tenantUids);
    await markPublished(noticeRef);
    return;
  }

  const leases = await leasesQuery.get();
  const tenantUids = new Set<string>();
  for (const lease of leases.docs) {
    const uid = lease.data().tenantUserUid;
    if (typeof uid === 'string') tenantUids.add(uid);
  }
  await deliver(noticeId, notice, tenantUids);
  await markPublished(noticeRef);
}

async function deliver(
  noticeId: string,
  notice: Record<string, unknown>,
  tenantUids: ReadonlySet<string>,
): Promise<void> {
  const db = getFirestore();
  for (const uid of tenantUids) {
    const dedupeRef = db.collection(COLLECTIONS.backendJobDedupe).doc(`${noticeId}_${uid}`);
    await db.runTransaction(async (tx) => {
      const prior = await tx.get(dedupeRef);
      if (prior.exists) return;
      tx.create(dedupeRef, { key: `${noticeId}:${uid}`, createdAt: Timestamp.now() });
      tx.set(
        db
          .collection(COLLECTIONS.tenantPortals)
          .doc(uid)
          .collection(TENANT_PORTAL_SECTIONS.notices)
          .doc(noticeId),
        tenantNoticeProjection(notice),
      );
    });
  }
}

async function markPublished(
  noticeRef: FirebaseFirestore.DocumentReference,
): Promise<void> {
  await noticeRef.update({
    publishState: 'published',
    publishedAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
  });
}
