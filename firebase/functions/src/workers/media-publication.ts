import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { COLLECTIONS } from '../shared/collections';
import { MAX_IMAGE_BYTES, MAX_LISTING_PHOTOS } from '../shared/config';

const imageContentTypes = new Set(['image/jpeg', 'image/png', 'image/webp']);

function fileName(path: string): string {
  return path.split('/').pop()?.replace(/[^A-Za-z0-9._-]/g, '_') || 'image';
}

export async function publishListingMedia(payload: Record<string, unknown>): Promise<void> {
  const listingId = String(payload.listingId);
  const staged = Array.isArray(payload.stagedImagePaths)
    ? payload.stagedImagePaths.filter((value): value is string => typeof value === 'string')
    : [];
  if (staged.length > MAX_LISTING_PHOTOS) throw new Error('Listing photo limit exceeded.');
  const bucket = getStorage().bucket();
  const publicPaths: string[] = [];
  for (const [index, sourcePath] of staged.entries()) {
    const source = bucket.file(sourcePath);
    const [metadata] = await source.getMetadata();
    const size = Number(metadata.size);
    if (!imageContentTypes.has(metadata.contentType ?? '') || !Number.isFinite(size) || size > MAX_IMAGE_BYTES) {
      throw new Error('Staged listing image failed validation.');
    }
    const destination = `public/listings/${listingId}/${index}_${fileName(sourcePath)}`;
    await source.copy(bucket.file(destination));
    publicPaths.push(destination);
  }
  const now = Timestamp.now();
  await getFirestore().runTransaction(async (tx) => {
    const privateRef = getFirestore().collection(COLLECTIONS.privateListings).doc(listingId);
    const publicRef = getFirestore().collection(COLLECTIONS.publicListings).doc(listingId);
    const [privateSnap, publicSnap] = await Promise.all([tx.get(privateRef), tx.get(publicRef)]);
    if (!privateSnap.exists || !publicSnap.exists || publicSnap.data()?.status !== 'published') return;
    tx.update(privateRef, { mediaState: 'published', publicImagePaths: publicPaths, updatedAt: now });
    tx.update(publicRef, { imagePaths: publicPaths, updatedAt: now });
  });
}

export async function cleanupListingMedia(payload: Record<string, unknown>): Promise<void> {
  const prefix = `public/listings/${String(payload.listingId)}/`;
  await getStorage().bucket().deleteFiles({ prefix, force: true });
}

export async function movePrivateDocument(payload: Record<string, unknown>): Promise<void> {
  const documentId = String(payload.documentId);
  const landlordId = String(payload.landlordId);
  const sourcePath = String(payload.sourcePath);
  const bucket = getStorage().bucket();
  const destination = `private/landlords/${landlordId}/documents/${documentId}/${fileName(sourcePath)}`;
  await bucket.file(sourcePath).copy(bucket.file(destination));
  await getFirestore().collection(COLLECTIONS.documents).doc(documentId).update({
    state: 'available',
    privatePath: destination,
    updatedAt: Timestamp.now(),
  });
}

export async function purgeDocument(payload: Record<string, unknown>): Promise<void> {
  const documentId = String(payload.documentId);
  const ref = getFirestore().collection(COLLECTIONS.documents).doc(documentId);
  const snapshot = await ref.get();
  if (!snapshot.exists || snapshot.data()?.isDeleted !== true) return;
  const privatePath = snapshot.data()?.privatePath;
  if (typeof privatePath === 'string') await getStorage().bucket().file(privatePath).delete({ ignoreNotFound: true });
  await ref.delete();
}
