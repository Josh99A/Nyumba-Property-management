import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { onRequest } from 'firebase-functions/v2/https';
import { COLLECTIONS } from '../shared/collections';
import {
  APP_ORIGIN,
  MAX_IMAGE_BYTES,
  MAX_LISTING_PHOTOS,
  REGION,
} from '../shared/config';
import {
  isActivePublicListing,
  publicListingImagePaths,
  renderExplorePage,
  renderListingPage,
  renderSitemap,
  renderUnavailablePage,
  toPublicSeoListing,
  type PublicSeoListing,
} from './public-seo';

const PUBLIC_LISTING_PAGE_SIZE = 500;
const PUBLIC_IMAGE_CONTENT_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
]);
export const PUBLIC_SEO_CACHE_CONTROL = 'public, max-age=60, s-maxage=300';

interface HeaderResponse {
  set(headers: Record<string, string>): unknown;
}

export function applyDocumentHeaders(
  response: HeaderResponse,
): void {
  response.set({
    'Cache-Control': PUBLIC_SEO_CACHE_CONTROL,
    'Content-Language': 'en',
    'Referrer-Policy': 'strict-origin-when-cross-origin',
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'SAMEORIGIN',
  });
}

export async function activeListings(now: Date): Promise<PublicSeoListing[]> {
  const query = getFirestore()
    .collection(COLLECTIONS.publicListings)
    .where('status', '==', 'published')
    .where('expiresAt', '>', Timestamp.fromDate(now))
    .orderBy('expiresAt');
  const listings: PublicSeoListing[] = [];
  let cursor;

  while (true) {
    const snapshot = await (cursor === undefined
      ? query
      : query.startAfter(cursor))
      .limit(PUBLIC_LISTING_PAGE_SIZE)
      .get();
    listings.push(
      ...snapshot.docs
        .map((document) => toPublicSeoListing(document.id, document.data(), now))
        .filter((listing): listing is PublicSeoListing => listing !== null),
    );
    if (snapshot.docs.length < PUBLIC_LISTING_PAGE_SIZE) break;
    cursor = snapshot.docs.at(-1);
  }

  return listings;
}

export const publicSeo = onRequest(
  {
    region: REGION,
    timeoutSeconds: 30,
    memory: '256MiB',
    cors: false,
  },
  async (request, response) => {
    applyDocumentHeaders(response);
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      response.set('Allow', 'GET, HEAD').status(405).send('Method not allowed.');
      return;
    }

    if (request.path === '/') {
      response.redirect(308, `${APP_ORIGIN}/explore`);
      return;
    }

    const now = new Date();
    if (request.path === '/explore') {
      const listings = await activeListings(now);
      response.type('html').status(200).send(renderExplorePage(listings));
      return;
    }

    if (request.path === '/sitemap.xml') {
      const listings = await activeListings(now);
      response
        .type('application/xml')
        .status(200)
        .send(renderSitemap(listings));
      return;
    }

    const mediaMatch = /^\/listing\/([A-Za-z0-9_-]{8,128})\/media\/(\d{1,2})$/.exec(
      request.path,
    );
    if (mediaMatch) {
      const listingId = mediaMatch[1]!;
      const imageIndex = Number(mediaMatch[2]);
      const snapshot = await getFirestore()
        .collection(COLLECTIONS.publicListings)
        .doc(listingId)
        .get();
      if (!snapshot.exists) {
        response
          .set('X-Robots-Tag', 'noindex, nofollow')
          .status(404)
          .send('Listing image not found.');
        return;
      }
      const data = snapshot.data() ?? {};
      if (!isActivePublicListing(data, now)) {
        response
          .set('X-Robots-Tag', 'noindex, nofollow')
          .status(410)
          .send('Listing image is no longer available.');
        return;
      }
      const imagePaths = publicListingImagePaths(listingId, data.imagePaths);
      const imagePath = Number.isInteger(imageIndex)
        && imageIndex >= 0
        && imageIndex < MAX_LISTING_PHOTOS
        ? imagePaths[imageIndex]
        : undefined;
      if (!imagePath) {
        response
          .set('X-Robots-Tag', 'noindex, nofollow')
          .status(404)
          .send('Listing image not found.');
        return;
      }
      try {
        const file = getStorage().bucket().file(imagePath);
        const [metadata] = await file.getMetadata();
        const contentType = metadata.contentType ?? '';
        const byteSize = Number(metadata.size);
        if (
          !PUBLIC_IMAGE_CONTENT_TYPES.has(contentType)
          || !Number.isFinite(byteSize)
          || byteSize <= 0
          || byteSize > MAX_IMAGE_BYTES
        ) {
          response
            .set('X-Robots-Tag', 'noindex, nofollow')
            .status(404)
            .send('Listing image not found.');
          return;
        }
        response.set({
          'Content-Length': String(byteSize),
          'Content-Type': contentType,
        });
        if (request.method === 'HEAD') {
          response.status(200).end();
          return;
        }
        const [image] = await file.download();
        response.status(200).send(image);
      } catch {
        response
          .set('X-Robots-Tag', 'noindex, nofollow')
          .status(404)
          .send('Listing image not found.');
      }
      return;
    }

    const listingMatch = /^\/listing\/([A-Za-z0-9_-]{8,128})$/.exec(
      request.path,
    );
    if (listingMatch) {
      const listingId = listingMatch[1]!;
      const snapshot = await getFirestore()
        .collection(COLLECTIONS.publicListings)
        .doc(listingId)
        .get();
      if (!snapshot.exists) {
        response
          .set('X-Robots-Tag', 'noindex, nofollow')
          .type('html')
          .status(404)
          .send(renderUnavailablePage(404));
        return;
      }
      const data = snapshot.data() ?? {};
      if (!isActivePublicListing(data, now)) {
        response
          .set('X-Robots-Tag', 'noindex, nofollow')
          .type('html')
          .status(410)
          .send(renderUnavailablePage(410));
        return;
      }
      const listing = toPublicSeoListing(listingId, data, now);
      if (!listing) {
        response
          .set('X-Robots-Tag', 'noindex, nofollow')
          .type('html')
          .status(404)
          .send(renderUnavailablePage(404));
        return;
      }
      response.type('html').status(200).send(renderListingPage(listing));
      return;
    }

    response
      .set('X-Robots-Tag', 'noindex, nofollow')
      .type('html')
      .status(404)
      .send(renderUnavailablePage(404));
  },
);
