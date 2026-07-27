import { createHash } from 'node:crypto';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import sharp from 'sharp';
import { COLLECTIONS } from '../shared/collections';
import {
  MAX_DOCUMENT_BYTES,
  MAX_IMAGE_BYTES,
  MAX_LISTING_PHOTOS,
  MAX_PROPERTY_PHOTOS,
  MAX_PUBLIC_LISTING_IMAGE_HEIGHT,
  MAX_PUBLIC_LISTING_IMAGE_WIDTH,
  MEDIA_FULL_SUFFIX,
  MEDIA_IMMUTABLE_CACHE_CONTROL,
  MEDIA_THUMB_IMAGE_HEIGHT,
  MEDIA_THUMB_IMAGE_WIDTH,
  MEDIA_THUMB_SUFFIX,
} from '../shared/config';

const imageContentTypes = new Set(['image/jpeg', 'image/png', 'image/webp']);

/** The two delivery copies produced from one source photo. */
export interface RenderedImageVariants {
  readonly digest: string;
  readonly full: Buffer;
  readonly thumb: Buffer;
}

/** Short content digest naming a delivery object. */
export function imageDigest(source: Buffer): string {
  return createHash('sha256').update(source).digest('hex').slice(0, 16);
}

/**
 * Names a delivery object after its content.
 *
 * The digest — not the index — carries the identity, so re-publishing an
 * unchanged photo lands on the same path (a free cache hit) and republishing a
 * changed one lands on a new path instead of poisoning caches holding the old
 * bytes. The index stays in the name only to keep cover-first ordering legible
 * when browsing the bucket.
 */
export function deliveryObjectPath(
  prefix: string,
  index: number,
  digest: string,
  variant: string,
): string {
  return `${prefix}${index}-${digest}-${variant}.webp`;
}

function fileName(path: string): string {
  return path.split('/').pop()?.replace(/[^A-Za-z0-9._-]/g, '_') || 'image';
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === 'string')
    : [];
}

function sameOrder(left: readonly string[], right: readonly string[]): boolean {
  return left.length === right.length
    && left.every((value, index) => value === right[index]);
}

export function publicListingMediaPatch(
  publicListing: Record<string, unknown>,
  imagePaths: readonly string[],
  updatedAt: Timestamp,
  thumbPaths: readonly string[] = [],
): Record<string, unknown> | null {
  const currentVersion = Number(publicListing.version);
  if (!Number.isInteger(currentVersion) || currentVersion < 1) {
    throw new Error('Published listing media requires a valid projection version.');
  }
  const currentPaths = stringArray(publicListing.imagePaths);
  const currentThumbs = stringArray(publicListing.imageThumbPaths);
  // Both arrays must match before this is a no-op retry: a projection carrying
  // the full copies but no thumbnails is exactly the state an older publication
  // left behind, and it still needs the thumbnail field filled in.
  if (sameOrder(currentPaths, imagePaths) && sameOrder(currentThumbs, thumbPaths)) {
    return null;
  }
  return {
    imagePaths: [...imagePaths],
    imageThumbPaths: [...thumbPaths],
    updatedAt,
    version: currentVersion + 1,
  };
}

/**
 * Produces the public delivery copy rather than exposing the upload verbatim.
 * Auto-orientation fixes phone-camera EXIF rotation, resizing bounds decode
 * and transfer cost, WebP keeps photographs compact, and Sharp strips source
 * metadata by default (including camera/location metadata).
 */
export async function optimisePublicListingImage(
  source: Buffer,
  width: number = MAX_PUBLIC_LISTING_IMAGE_WIDTH,
  height: number = MAX_PUBLIC_LISTING_IMAGE_HEIGHT,
): Promise<Buffer> {
  const output = await sharp(source)
    .rotate()
    .resize({
      width,
      height,
      fit: 'inside',
      withoutEnlargement: true,
    })
    .webp({ quality: 82, effort: 4, smartSubsample: true })
    .toBuffer();
  if (output.length <= 0 || output.length > MAX_IMAGE_BYTES) {
    throw new Error('Optimized listing image failed validation.');
  }
  return output;
}

/**
 * Renders both delivery copies from one source, digesting the source rather
 * than either output so the two variants of a photo always share an identity.
 */
export async function renderImageVariants(
  source: Buffer,
): Promise<RenderedImageVariants> {
  const [full, thumb] = await Promise.all([
    optimisePublicListingImage(source),
    optimisePublicListingImage(
      source,
      MEDIA_THUMB_IMAGE_WIDTH,
      MEDIA_THUMB_IMAGE_HEIGHT,
    ),
  ]);
  return { digest: imageDigest(source), full, thumb };
}

/** Reads a staged upload, rejecting anything outside the declared limits. */
async function downloadStagedImage(sourcePath: string): Promise<Buffer> {
  const source = getStorage().bucket().file(sourcePath);
  const [metadata] = await source.getMetadata();
  const size = Number(metadata.size);
  if (
    !imageContentTypes.has(metadata.contentType ?? '')
    || !Number.isFinite(size)
    || size <= 0
    || size > MAX_IMAGE_BYTES
  ) {
    throw new Error('Staged image failed validation.');
  }
  const [contents] = await source.download();
  return contents;
}

interface DeliveredMedia {
  readonly imagePaths: string[];
  readonly thumbPaths: string[];
}

/**
 * Writes both delivery copies of every staged photo under [prefix] and removes
 * any object left there by a previous publication.
 *
 * Sweeping is what keeps content-addressed naming from leaking storage: a
 * changed photo writes a new digest, so without this the superseded objects
 * would accumulate under the listing forever.
 */
async function deliverImages(
  stagedPaths: readonly string[],
  prefix: string,
): Promise<DeliveredMedia> {
  const bucket = getStorage().bucket();
  const imagePaths: string[] = [];
  const thumbPaths: string[] = [];

  for (const [index, sourcePath] of stagedPaths.entries()) {
    const uploaded = await downloadStagedImage(sourcePath);
    const variants = await renderImageVariants(uploaded);
    const fullPath = deliveryObjectPath(prefix, index, variants.digest, MEDIA_FULL_SUFFIX);
    const thumbPath = deliveryObjectPath(prefix, index, variants.digest, MEDIA_THUMB_SUFFIX);
    await Promise.all([
      bucket.file(fullPath).save(variants.full, {
        resumable: false,
        metadata: {
          contentType: 'image/webp',
          cacheControl: MEDIA_IMMUTABLE_CACHE_CONTROL,
        },
      }),
      bucket.file(thumbPath).save(variants.thumb, {
        resumable: false,
        metadata: {
          contentType: 'image/webp',
          cacheControl: MEDIA_IMMUTABLE_CACHE_CONTROL,
        },
      }),
    ]);
    imagePaths.push(fullPath);
    thumbPaths.push(thumbPath);
  }

  const keep = new Set([...imagePaths, ...thumbPaths]);
  const [existing] = await bucket.getFiles({ prefix });
  await Promise.all(
    existing
      .filter((file) => !keep.has(file.name))
      .map((file) => file.delete({ ignoreNotFound: true })),
  );

  return { imagePaths, thumbPaths };
}

export async function publishListingMedia(payload: Record<string, unknown>): Promise<void> {
  const listingId = String(payload.listingId);
  const staged = stringArray(payload.stagedImagePaths);
  if (staged.length > MAX_LISTING_PHOTOS) throw new Error('Listing photo limit exceeded.');

  const delivered = await deliverImages(staged, `public/listings/${listingId}/`);
  const now = Timestamp.now();
  await getFirestore().runTransaction(async (tx) => {
    const privateRef = getFirestore().collection(COLLECTIONS.privateListings).doc(listingId);
    const publicRef = getFirestore().collection(COLLECTIONS.publicListings).doc(listingId);
    const [privateSnap, publicSnap] = await Promise.all([tx.get(privateRef), tx.get(publicRef)]);
    if (!privateSnap.exists || !publicSnap.exists || publicSnap.data()?.status !== 'published') return;
    tx.update(privateRef, {
      mediaState: 'published',
      publicImagePaths: delivered.imagePaths,
      publicImageThumbPaths: delivered.thumbPaths,
      updatedAt: now,
    });
    const publicPatch = publicListingMediaPatch(
      publicSnap.data()!,
      delivered.imagePaths,
      now,
      delivered.thumbPaths,
    );
    if (publicPatch) tx.update(publicRef, publicPatch);
  });
}

/**
 * Gives property photos the delivery pipeline listings already had.
 *
 * Property photos previously stayed exactly as the landlord uploaded them, in
 * the staging prefix, at full capture resolution — so a portfolio grid of
 * 300px tiles fetched 1920px originals. These land under the landlord's own
 * private prefix, which the storage rules already scope to the owner and
 * platform admins, so the delivery copies inherit the same access as the
 * originals.
 */
export async function publishPropertyMedia(payload: Record<string, unknown>): Promise<void> {
  const propertyId = String(payload.propertyId);
  const landlordId = String(payload.landlordId);
  const staged = stringArray(payload.stagedImagePaths);
  if (staged.length > MAX_PROPERTY_PHOTOS) throw new Error('Property photo limit exceeded.');

  const delivered = await deliverImages(
    staged,
    `private/landlords/${landlordId}/properties/${propertyId}/`,
  );
  const now = Timestamp.now();
  const ref = getFirestore().collection(COLLECTIONS.properties).doc(propertyId);
  await getFirestore().runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    if (!snapshot.exists) return;
    const current = snapshot.data()!;
    // The staged list this job was created from must still be the property's
    // current one. A newer edit has already enqueued its own job; letting this
    // one land would resurrect the photos the landlord just replaced.
    if (!sameOrder(stringArray(current.stagedImagePaths), staged)) return;
    if (
      sameOrder(stringArray(current.imagePaths), delivered.imagePaths)
      && sameOrder(stringArray(current.imageThumbPaths), delivered.thumbPaths)
    ) {
      return;
    }
    tx.update(ref, {
      imagePaths: delivered.imagePaths,
      imageThumbPaths: delivered.thumbPaths,
      mediaState: 'published',
      updatedAt: now,
      version: Number(current.version ?? 0) + 1,
    });
  });
}

/** Removes every delivery copy of a property's photos. */
export async function cleanupPropertyMedia(payload: Record<string, unknown>): Promise<void> {
  const prefix = `private/landlords/${String(payload.landlordId)}/properties/${String(payload.propertyId)}/`;
  await getStorage().bucket().deleteFiles({ prefix, force: true });
}

export async function cleanupListingMedia(payload: Record<string, unknown>): Promise<void> {
  const prefix = `public/listings/${String(payload.listingId)}/`;
  await getStorage().bucket().deleteFiles({ prefix, force: true });
}

/**
 * Deletes an explicit list of storage objects, for records whose photos never
 * reached a server-owned prefix — a property keeps its staged uploads under
 * `uploads/{uid}/...`, so there is nothing to sweep by prefix. Missing objects
 * are not an error: the purge that enqueued this is the last word either way.
 */
export async function purgeStorageObjects(payload: Record<string, unknown>): Promise<void> {
  const paths = Array.isArray(payload.paths)
    ? payload.paths.filter((value): value is string => typeof value === 'string' && value.length > 0)
    : [];
  const bucket = getStorage().bucket();
  for (const path of paths) {
    await bucket.file(path).delete({ ignoreNotFound: true });
  }
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
