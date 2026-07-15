import { createHash } from 'node:crypto';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { COLLECTIONS } from '../shared/collections';
import { MAX_DOCUMENT_BYTES, MAX_IMAGE_BYTES, MAX_LISTING_PHOTOS } from '../shared/config';

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
  const db = getFirestore();
  const documentRef = db.collection(COLLECTIONS.documents).doc(documentId);
  const documentSnap = await documentRef.get();
  if (!documentSnap.exists) return;
  const declared = documentSnap.data()!;
  if (declared.state !== 'pending') return;

  // The staged object must match what the command declared: content type and
  // size within the finalized limits, and the client-computed SHA-256. A
  // mismatch is deterministic, so mark the document rejected instead of
  // burning the job's retry budget.
  const bucket = getStorage().bucket();
  const source = bucket.file(sourcePath);
  const [metadata] = await source.getMetadata();
  const size = Number(metadata.size);
  const limit = declared.contentType === 'application/pdf' ? MAX_DOCUMENT_BYTES : MAX_IMAGE_BYTES;
  let rejectionReason: string | null = null;
  if (metadata.contentType !== declared.contentType) {
    rejectionReason = 'contentTypeMismatch';
  } else if (!Number.isFinite(size) || size !== Number(declared.byteSize) || size > limit) {
    rejectionReason = 'byteSizeMismatch';
  } else {
    const [contents] = await source.download();
    const sha256 = createHash('sha256').update(contents).digest('hex');
    if (sha256 !== declared.sha256) rejectionReason = 'checksumMismatch';
  }
  if (rejectionReason) {
    await documentRef.update({
      state: 'rejected',
      rejectionReason,
      updatedAt: Timestamp.now(),
    });
    return;
  }

  const destination = `private/landlords/${landlordId}/documents/${documentId}/${fileName(sourcePath)}`;
  await source.copy(bucket.file(destination));
  await documentRef.update({
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
