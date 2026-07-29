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
import {
  MAP_SECRETS,
  publicMapCoordinates,
  staticMapUrl,
  STATIC_MAP_CACHE_CONTROL,
} from './static-map';

const PUBLIC_LISTING_PAGE_SIZE = 500;
const PUBLIC_IMAGE_CONTENT_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
]);
/**
 * A shared cache stores a response under the headers it had *at fetch time*;
 * nothing this handler does on a later request can shorten a copy it already
 * handed out. An `s-maxage` longer than the browser lifetime was an invitation
 * to keep serving an unpublished or expired listing as a 200 for however much
 * longer that edge copy had left — up to the full hour this used to allow.
 * Matching `s-maxage` to `max-age` bounds a shared cache to the same window a
 * browser already accepts, so the worst case is "one more minute," not "up to
 * an hour," on every response this handler returns — including the sitemap
 * and the explore page, which read as stale-active-listing lists under the
 * same shared-cache lifetime for the same reason.
 */
export const PUBLIC_SEO_CACHE_CONTROL = 'public, max-age=60, s-maxage=60';

/**
 * A 404, 410, 405, or media error must not outlive the state change that
 * caused it in a shared cache. These aren't responses a CDN should ever
 * smooth over with staleness — unlike the happy path above, there is no
 * "close enough" render to serve while revalidating.
 */
const UNAVAILABLE_CACHE_CONTROL = 'no-store';

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

function markUnavailable(response: HeaderResponse): void {
  response.set({ 'Cache-Control': UNAVAILABLE_CACHE_CONTROL });
}

export async function activeListings(now: Date): Promise<PublicSeoListing[]> {
  const query = getFirestore()
    .collection(COLLECTIONS.publicListings)
    .where('status', '==', 'published')
    .where('expiresAt', '>', Timestamp.fromDate(now))
    .orderBy('expiresAt')
    // Match firestore.indexes.json exactly. Without the trailing order the
    // deployed three-field index cannot serve this query and /explore fails.
    .orderBy('publishedAt', 'desc');
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
    // Needed only by the /listing/{id}/map route. Absent in a deployment that
    // has not provisioned it, which that route treats as "no map" rather than
    // an error.
    secrets: MAP_SECRETS,
  },
  async (request, response) => {
    applyDocumentHeaders(response);
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      markUnavailable(response);
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
        markUnavailable(response);
        response
          .set('X-Robots-Tag', 'noindex, nofollow')
          .status(404)
          .send('Listing image not found.');
        return;
      }
      const data = snapshot.data() ?? {};
      if (!isActivePublicListing(data, now)) {
        markUnavailable(response);
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
        markUnavailable(response);
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
          markUnavailable(response);
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
        markUnavailable(response);
        response
          .set('X-Robots-Tag', 'noindex, nofollow')
          .status(404)
          .send('Listing image not found.');
      }
      return;
    }

    // The rendered location map. Served from this function rather than a
    // separate one so it inherits the existing `/listing/**` Hosting rewrite,
    // and so the public invariant is rechecked by the same code path that
    // guards every other public response.
    const mapMatch = /^\/listing\/([A-Za-z0-9_-]{8,128})\/map$/.exec(
      request.path,
    );
    if (mapMatch) {
      const listingId = mapMatch[1]!;
      const snapshot = await getFirestore()
        .collection(COLLECTIONS.publicListings)
        .doc(listingId)
        .get();
      const data = snapshot.exists ? snapshot.data() ?? {} : null;
      if (data === null || !isActivePublicListing(data, now)) {
        markUnavailable(response);
        response
          .set('X-Robots-Tag', 'noindex, nofollow')
          .status(data === null ? 404 : 410)
          .send('Listing map is not available.');
        return;
      }
      // Only ever the coarsened projection field. The canonical listing's
      // exact pin and the property's address are private and are not read
      // here at all.
      const centre = publicMapCoordinates(data.approximateLocation);
      const apiKey = process.env.MAPS_STATIC_API_KEY;
      if (!centre || !apiKey) {
        // A listing with no pin and a deployment with no key are the same
        // outcome for a visitor: there is no map. Neither is an error worth
        // caching, and neither should be indexed.
        markUnavailable(response);
        response
          .set('X-Robots-Tag', 'noindex, nofollow')
          .status(404)
          .send('Listing map is not available.');
        return;
      }
      try {
        const upstream = await fetch(staticMapUrl(centre, apiKey));
        const contentType = upstream.headers.get('content-type') ?? '';
        if (!upstream.ok || !contentType.startsWith('image/')) {
          throw new Error(`Static Maps responded ${upstream.status}.`);
        }
        response.set({
          'Cache-Control': STATIC_MAP_CACHE_CONTROL,
          'Content-Type': contentType,
        });
        if (request.method === 'HEAD') {
          response.status(200).end();
          return;
        }
        response
          .status(200)
          .send(Buffer.from(await upstream.arrayBuffer()));
      } catch (error) {
        // Diagnosable without being dangerous: the message distinguishes a
        // network failure from an auth, quota, or non-image response, while
        // the URL — which carries the API key — is deliberately never logged.
        console.error(
          `Static map render failed for ${listingId}:`,
          error instanceof Error ? error.message : error,
        );
        // Never cache a failed render: the next request should try again
        // rather than serve a hole for a day.
        markUnavailable(response);
        response
          .set('X-Robots-Tag', 'noindex, nofollow')
          .status(404)
          .send('Listing map is not available.');
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
        markUnavailable(response);
        response
          .set('X-Robots-Tag', 'noindex, nofollow')
          .type('html')
          .status(404)
          .send(renderUnavailablePage(404));
        return;
      }
      const data = snapshot.data() ?? {};
      if (!isActivePublicListing(data, now)) {
        markUnavailable(response);
        response
          .set('X-Robots-Tag', 'noindex, nofollow')
          .type('html')
          .status(410)
          .send(renderUnavailablePage(410));
        return;
      }
      const listing = toPublicSeoListing(listingId, data, now);
      if (!listing) {
        markUnavailable(response);
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

    markUnavailable(response);
    response
      .set('X-Robots-Tag', 'noindex, nofollow')
      .type('html')
      .status(404)
      .send(renderUnavailablePage(404));
  },
);
