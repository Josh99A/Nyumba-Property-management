import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { onRequest } from 'firebase-functions/v2/https';
import { COLLECTIONS } from '../shared/collections';
import { APP_ORIGIN, REGION } from '../shared/config';
import {
  isActivePublicListing,
  renderExplorePage,
  renderListingPage,
  renderSitemap,
  renderUnavailablePage,
  toPublicSeoListing,
  type PublicSeoListing,
} from './public-seo';

const MAX_SITEMAP_LISTINGS = 500;

interface HeaderResponse {
  set(headers: Record<string, string>): unknown;
}

function applyDocumentHeaders(
  response: HeaderResponse,
): void {
  response.set({
    'Cache-Control': 'no-store',
    'Content-Language': 'en',
    'Referrer-Policy': 'strict-origin-when-cross-origin',
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'SAMEORIGIN',
  });
}

async function activeListings(now: Date): Promise<PublicSeoListing[]> {
  const snapshot = await getFirestore()
    .collection(COLLECTIONS.publicListings)
    .where('status', '==', 'published')
    .where('expiresAt', '>', Timestamp.fromDate(now))
    .orderBy('expiresAt')
    .limit(MAX_SITEMAP_LISTINGS)
    .get();
  return snapshot.docs
    .map((document) => toPublicSeoListing(document.id, document.data(), now))
    .filter((listing): listing is PublicSeoListing => listing !== null);
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
