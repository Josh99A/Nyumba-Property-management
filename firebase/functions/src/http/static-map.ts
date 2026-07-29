import { defineSecret } from 'firebase-functions/params';
import { MAPS_PUBLIC_PRIVACY_RADIUS_METRES } from '../shared/config';

/**
 * Google Maps Static API key. Lives in Secret Manager, never in the repository
 * and never in a page: a key placed in an `<img src>` is a key handed to the
 * internet, and an unrestricted maps key on a public marketplace is a way to
 * lose real money to a stranger. Rotating it is
 * `firebase functions:secrets:set MAPS_STATIC_API_KEY` plus a redeploy.
 *
 * This is the *server* key of the four (see
 * docs/architecture/maps-and-location-plan.md). It is deliberately distinct
 * from the referrer-restricted web key and the two mobile SDK keys.
 */
export const MAPS_STATIC_API_KEY = defineSecret('MAPS_STATIC_API_KEY');

export const MAP_SECRETS = [MAPS_STATIC_API_KEY];

/**
 * How long a rendered map may be cached.
 *
 * This used to be `max-age=86400, s-maxage=604800`, justified on the grounds
 * that the image is a function of an already-coarsened coordinate and so
 * cannot leak newer information. That reasoning was about the wrong risk. A
 * shared cache stores a response under the headers it had *at fetch time*, so
 * a week-long `s-maxage` meant an edge copy kept serving a listing's location
 * for up to seven days after it was unpublished, deleted, or expired — the one
 * thing `isActivePublicListing` exists to prevent, undone by a header.
 *
 * `PUBLIC_SEO_CACHE_CONTROL` already settled this exact question for every
 * other public response, and matching `s-maxage` to `max-age` is the rule that
 * came out of it. This now follows it. Five minutes rather than the documents'
 * sixty seconds because a coarsened circle is meaningfully less sensitive than
 * the advert's own copy and contact details, and because the map is the only
 * response here with an upstream per-request cost.
 *
 * The consequence is real and accepted: the CDN no longer collapses a
 * listing's traffic into roughly one Google call a day. If the Static Maps
 * bill becomes material, the fix is to cache the rendered PNG server-side by
 * coordinate — which a delisting can actually invalidate — and never to widen
 * this window again.
 */
export const STATIC_MAP_CACHE_CONTROL = 'public, max-age=300, s-maxage=300';

/** Rendered size in CSS pixels; `scale=2` doubles the delivered pixels. */
const MAP_WIDTH = 640;
const MAP_HEIGHT = 320;

export interface MapCoordinates {
  lat: number;
  lng: number;
}

/**
 * Reads the coarsened public pin, or null when the listing has none.
 *
 * Re-validated rather than trusted: this value crosses into a URL sent to a
 * third party, so a malformed pair must become "no map" instead of a
 * request built from whatever the document happened to contain.
 */
export function publicMapCoordinates(value: unknown): MapCoordinates | null {
  if (typeof value !== 'object' || value === null) return null;
  const { lat, lng } = value as { lat?: unknown; lng?: unknown };
  if (typeof lat !== 'number' || typeof lng !== 'number') return null;
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  return { lat, lng };
}

/**
 * The Static Maps request for a public listing.
 *
 * Renders a **circle, not a marker**. The published coordinate is already
 * coarsened to roughly 110 m, but a pin dropped on a coarsened point still
 * reads to a viewer as "this house". A translucent circle wider than the
 * coarsening is what keeps an approximate location approximate, and it is the
 * only thing standing between this image and an address.
 *
 * Google's Static API has no circle primitive, so the circle is drawn as an
 * encoded path polygon approximating one at the requested radius.
 */
export function staticMapUrl(
  centre: MapCoordinates,
  apiKey: string,
  { radiusMetres = MAPS_PUBLIC_PRIVACY_RADIUS_METRES } = {},
): string {
  const parameters = new URLSearchParams({
    center: `${centre.lat},${centre.lng}`,
    zoom: '14',
    size: `${MAP_WIDTH}x${MAP_HEIGHT}`,
    scale: '2',
    maptype: 'roadmap',
    format: 'png',
    language: 'en',
    region: 'UG',
    key: apiKey,
  });
  parameters.append(
    'path',
    `color:0x123A6FCC|weight:2|fillcolor:0x123A6F33|${circlePath(centre, radiusMetres)}`,
  );
  return `https://maps.googleapis.com/maps/api/staticmap?${parameters.toString()}`;
}

const EARTH_RADIUS_METRES = 6_378_137;

/** A closed ring of points approximating a circle of [radiusMetres]. */
function circlePath(centre: MapCoordinates, radiusMetres: number): string {
  const points: string[] = [];
  const steps = 36;
  const latitudeDelta = (radiusMetres / EARTH_RADIUS_METRES) * (180 / Math.PI);
  // Longitude degrees shrink toward the poles, so the radius has to be scaled
  // by the cosine of the latitude or the "circle" renders as an ellipse.
  const longitudeDelta = latitudeDelta / Math.cos((centre.lat * Math.PI) / 180);
  for (let step = 0; step <= steps; step++) {
    const angle = (step / steps) * 2 * Math.PI;
    const lat = centre.lat + latitudeDelta * Math.sin(angle);
    const lng = centre.lng + longitudeDelta * Math.cos(angle);
    points.push(`${lat.toFixed(6)},${lng.toFixed(6)}`);
  }
  return points.join('|');
}

/** The public path a rendered listing map is served from. */
export function listingMapPath(listingId: string): string {
  return `/listing/${listingId}/map`;
}
