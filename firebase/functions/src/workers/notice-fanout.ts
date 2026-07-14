import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { COLLECTIONS, TENANT_PORTAL_SECTIONS } from '../shared/collections';

export async function fanoutNotice(payload: Record<string, unknown>): Promise<void> {
  const db = getFirestore();
  const noticeId = String(payload.noticeId);
  const landlordId = String(payload.landlordId);
  const noticeRef = db.collection(COLLECTIONS.notices).doc(noticeId);
  const [noticeSnap, leases] = await Promise.all([
    noticeRef.get(),
    db.collection(COLLECTIONS.leases)
      .where('landlordId', '==', landlordId)
      .where('status', '==', 'active')
      .get(),
  ]);
  if (!noticeSnap.exists) return;
  const notice = noticeSnap.data()!;
  const tenantUids = new Set<string>();
  for (const lease of leases.docs) {
    const uid = lease.data().tenantUserUid;
    if (typeof uid === 'string') tenantUids.add(uid);
  }
  for (const uid of tenantUids) {
    const dedupeRef = db.collection(COLLECTIONS.backendJobDedupe).doc(`${noticeId}_${uid}`);
    await db.runTransaction(async (tx) => {
      const prior = await tx.get(dedupeRef);
      if (prior.exists) return;
      tx.create(dedupeRef, { key: `${noticeId}:${uid}`, createdAt: Timestamp.now() });
      tx.set(db.collection(COLLECTIONS.tenantPortals).doc(uid).collection(TENANT_PORTAL_SECTIONS.notices).doc(noticeId), notice);
    });
  }
  await noticeRef.update({ publishState: 'published', publishedAt: Timestamp.now(), updatedAt: Timestamp.now() });
}
