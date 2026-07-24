import { APP_ORIGIN, MAX_LISTING_PHOTOS } from '../shared/config';

export interface PublicSeoListing {
  id: string;
  title: string;
  description: string;
  monthlyRentMinor: number;
  currency: string;
  unitType: string;
  city: string;
  neighborhood: string;
  district?: string;
  bedrooms?: number;
  bathrooms?: number;
  amenities: string[];
  imageCount: number;
  publishedAt?: Date;
  updatedAt?: Date;
  expiresAt: Date;
}

interface PageOptions {
  title: string;
  description: string;
  canonicalPath: string;
  body: string;
  structuredData?: unknown;
  robots?: 'index, follow' | 'noindex, nofollow';
  socialImagePath?: string;
}

const DEFAULT_DESCRIPTION =
  'Browse verified available rental homes in Uganda and contact landlords through Nyumba.';
const SUPPORTED_CURRENCIES = new Set(Intl.supportedValuesOf('currency'));

function stringValue(value: unknown, maximumLength: number): string | null {
  if (typeof value !== 'string') return null;
  const normalized = value.trim();
  if (normalized.length === 0 || normalized.length > maximumLength) return null;
  return normalized;
}

function optionalString(value: unknown, maximumLength: number): string | undefined {
  return stringValue(value, maximumLength) ?? undefined;
}

function currencyValue(value: unknown): string | null {
  const currency = stringValue(value, 3);
  return currency !== null
    && /^[A-Z]{3}$/.test(currency)
    && SUPPORTED_CURRENCIES.has(currency)
    ? currency
    : null;
}

function nonNegativeInteger(value: unknown): number | undefined {
  return typeof value === 'number' && Number.isInteger(value) && value >= 0
    ? value
    : undefined;
}

function dateValue(value: unknown): Date | null {
  if (value instanceof Date && Number.isFinite(value.getTime())) return value;
  if (
    typeof value === 'object'
    && value !== null
    && 'toDate' in value
    && typeof (value as { toDate?: unknown }).toDate === 'function'
  ) {
    const date = (value as { toDate: () => unknown }).toDate();
    return date instanceof Date && Number.isFinite(date.getTime()) ? date : null;
  }
  if (typeof value === 'string') {
    const date = new Date(value);
    return Number.isFinite(date.getTime()) ? date : null;
  }
  return null;
}

function stringList(value: unknown, maximumItems: number): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((entry) => stringValue(entry, 100))
    .filter((entry): entry is string => entry !== null)
    .slice(0, maximumItems);
}

export function publicListingImagePaths(
  documentId: string,
  value: unknown,
): string[] {
  if (!Array.isArray(value)) return [];
  const prefix = `public/listings/${documentId}/`;
  return value
    .filter((entry): entry is string => {
      if (typeof entry !== 'string' || !entry.startsWith(prefix)) return false;
      const fileName = entry.slice(prefix.length);
      return /^[A-Za-z0-9][A-Za-z0-9._-]{0,255}$/.test(fileName)
        && !fileName.includes('..');
    })
    .slice(0, MAX_LISTING_PHOTOS);
}

/**
 * Rechecks the public-read invariant even though the HTTP Function uses the
 * Admin SDK and therefore bypasses Firestore Rules.
 */
export function isActivePublicListing(
  data: Record<string, unknown>,
  now: Date,
): boolean {
  const expiresAt = dateValue(data.expiresAt);
  return data.status === 'published'
    && data.isDeleted !== true
    && expiresAt !== null
    && expiresAt.getTime() > now.getTime();
}

/**
 * Maps only the documented public projection fields. Extra Firestore fields
 * are ignored so an accidental private-field addition can never reach HTML.
 */
export function toPublicSeoListing(
  documentId: string,
  data: Record<string, unknown>,
  now: Date,
): PublicSeoListing | null {
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(documentId)) return null;
  if (!isActivePublicListing(data, now)) return null;

  const title = stringValue(data.title, 200);
  const description = stringValue(data.description, 5_000);
  const unitType = stringValue(data.unitType, 100);
  const city = stringValue(data.city, 100);
  const neighborhood = stringValue(data.neighborhood, 100);
  const currency = currencyValue(data.currency);
  const expiresAt = dateValue(data.expiresAt);
  const monthlyRentMinor = data.monthlyRentMinor;
  if (
    title === null
    || description === null
    || unitType === null
    || city === null
    || neighborhood === null
    || currency === null
    || expiresAt === null
    || typeof monthlyRentMinor !== 'number'
    || !Number.isSafeInteger(monthlyRentMinor)
    || monthlyRentMinor <= 0
  ) {
    return null;
  }

  const district = optionalString(data.district, 100);
  const bedrooms = nonNegativeInteger(data.bedrooms);
  const bathrooms = nonNegativeInteger(data.bathrooms);
  const publishedAt = dateValue(data.publishedAt) ?? undefined;
  const updatedAt = dateValue(data.updatedAt) ?? undefined;
  const imageCount = publicListingImagePaths(documentId, data.imagePaths).length;
  return {
    id: documentId,
    title,
    description,
    monthlyRentMinor,
    currency,
    unitType,
    city,
    neighborhood,
    ...(district ? { district } : {}),
    ...(bedrooms !== undefined ? { bedrooms } : {}),
    ...(bathrooms !== undefined ? { bathrooms } : {}),
    amenities: stringList(data.amenities, 50),
    imageCount,
    ...(publishedAt ? { publishedAt } : {}),
    ...(updatedAt ? { updatedAt } : {}),
    expiresAt,
  };
}

export function listingPath(listingId: string): string {
  return `/listing/${encodeURIComponent(listingId)}`;
}

export function listingMediaPath(listingId: string, index: number): string {
  return `${listingPath(listingId)}/media/${index}`;
}

function absoluteUrl(path: string): string {
  return new URL(path, APP_ORIGIN).href;
}

function escapeHtml(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function escapeXml(value: string): string {
  return escapeHtml(value);
}

function jsonForScript(value: unknown): string {
  return JSON.stringify(value)
    .replaceAll('&', '\\u0026')
    .replaceAll('<', '\\u003c')
    .replaceAll('>', '\\u003e')
    .replaceAll('\u2028', '\\u2028')
    .replaceAll('\u2029', '\\u2029');
}

function plainText(value: string): string {
  return value.replace(/\s+/g, ' ').trim();
}

function metaDescription(value: string): string {
  const text = plainText(value);
  if (text.length <= 160) return text;
  return `${text.slice(0, 157).trimEnd()}…`;
}

function displayUnitType(value: string): string {
  return value
    .replaceAll('_', ' ')
    .replace(/\b\w/g, (character) => character.toUpperCase());
}

function locationFor(listing: PublicSeoListing): string {
  const locations = [
    listing.neighborhood,
    ...(listing.district && listing.district !== listing.neighborhood
      ? [listing.district]
      : []),
    ...(listing.city !== listing.district ? [listing.city] : []),
  ];
  return locations.join(', ');
}

function formattedRent(listing: PublicSeoListing): string {
  return new Intl.NumberFormat('en-UG', {
    style: 'currency',
    currency: listing.currency,
    currencyDisplay: 'code',
    maximumFractionDigits: 0,
  }).format(listing.monthlyRentMinor / 100);
}

function schemaType(unitType: string): 'Apartment' | 'House' | 'Accommodation' {
  if (unitType === 'apartment' || unitType === 'bedsitter' || unitType === 'room') {
    return 'Apartment';
  }
  if (unitType === 'house') return 'House';
  return 'Accommodation';
}

const arrowIcon = `<svg aria-hidden="true" viewBox="0 0 24 24" fill="none">
  <path d="M5 12h14m-6-6 6 6-6 6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
</svg>`;
const homeIcon = `<svg aria-hidden="true" viewBox="0 0 24 24" fill="none">
  <path d="m4 10 8-6 8 6v9a1 1 0 0 1-1 1h-5v-6h-4v6H5a1 1 0 0 1-1-1v-9Z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/>
</svg>`;
const bedIcon = `<svg aria-hidden="true" viewBox="0 0 24 24" fill="none">
  <path d="M4 18v-7m16 7v-5a2 2 0 0 0-2-2H9a3 3 0 0 0-3 3v1m0-4V8h5a2 2 0 0 1 2 2v1M4 15h16" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>
</svg>`;
const bathIcon = `<svg aria-hidden="true" viewBox="0 0 24 24" fill="none">
  <path d="M4 13h16v2a4 4 0 0 1-4 4H8a4 4 0 0 1-4-4v-2Zm2 0V7a3 3 0 0 1 5.7-1.3M7 19v2m10-2v2" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>
</svg>`;

function page({
  title,
  description,
  canonicalPath,
  body,
  structuredData,
  robots = 'index, follow',
  socialImagePath = '/icons/Icon-512.png',
}: PageOptions): string {
  const canonical = absoluteUrl(canonicalPath);
  const socialImage = absoluteUrl(socialImagePath);
  const safeTitle = escapeHtml(title);
  const safeDescription = escapeHtml(metaDescription(description));
  const structuredDataElement = structuredData === undefined
    ? ''
    : `<script type="application/ld+json">${jsonForScript(structuredData)}</script>`;
  const shouldBootFlutter = robots === 'index, follow';
  const flutterBoot = shouldBootFlutter
    ? `
  <script>
    window.addEventListener('flutter-first-frame', function () {
      var seoContent = document.getElementById('seo-content');
      if (seoContent) seoContent.remove();
    });
  </script>
  <script src="/flutter_bootstrap.js" async></script>`
    : '';

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="theme-color" content="#123A6F">
  <meta name="robots" content="${robots}">
  <meta name="description" content="${safeDescription}">
  <title>${safeTitle}</title>
  <link rel="canonical" href="${escapeHtml(canonical)}">
  <link rel="icon" type="image/png" href="/favicon.png">
  <link rel="apple-touch-icon" href="/icons/Icon-192.png">
  <link rel="manifest" href="/manifest.json">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Nyumba">
  <meta property="og:title" content="${safeTitle}">
  <meta property="og:description" content="${safeDescription}">
  <meta property="og:url" content="${escapeHtml(canonical)}">
  <meta property="og:image" content="${escapeHtml(socialImage)}">
  <meta name="twitter:card" content="${socialImagePath === '/icons/Icon-512.png' ? 'summary' : 'summary_large_image'}">
  <meta name="twitter:title" content="${safeTitle}">
  <meta name="twitter:description" content="${safeDescription}">
  <meta name="twitter:image" content="${escapeHtml(socialImage)}">
  ${structuredDataElement}
  <style>
    :root { color-scheme:light; --navy:#123A6F; --navy-deep:#0b284d; --sage:#5F8F6B; --sage-soft:#eaf2ec; --gold:#C98B2E; --ivory:#F7F4ED; --ink:#172033; --muted:#667085; --line:#e2e7ec; --white:#fff; --shadow:0 22px 55px rgba(18,58,111,.1); }
    * { box-sizing: border-box; }
    html { scroll-behavior:smooth; }
    body { margin:0; color:var(--ink); background:var(--white); font:16px/1.6 ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; -webkit-font-smoothing:antialiased; }
    img { display:block; width:100%; }
    a { color:var(--navy); }
    a:focus-visible { outline:3px solid rgba(201,139,46,.55); outline-offset:4px; border-radius:4px; }
    .seo-header { background:rgba(255,255,255,.96); border-bottom:1px solid var(--line); }
    .seo-nav { max-width:1240px; margin:auto; padding:20px 28px; display:flex; align-items:center; justify-content:space-between; gap:24px; }
    .seo-brand { color:var(--navy); font-size:1.55rem; font-weight:850; letter-spacing:-.04em; text-decoration:none; }
    .seo-nav-links { display:flex; gap:28px; align-items:center; }
    .seo-nav-links a { color:var(--ink); font-size:.94rem; font-weight:700; text-decoration:none; }
    .seo-nav-links a:hover { color:var(--navy); }
    .seo-hero { background:var(--ivory); }
    .seo-hero-inner { max-width:1440px; min-height:510px; margin:auto; display:grid; grid-template-columns:1fr 1fr; }
    .seo-hero-copy { display:flex; flex-direction:column; justify-content:center; padding:72px clamp(32px,6vw,96px); color:var(--white); background:var(--navy); }
    .seo-hero h1 { max-width:620px; margin:0 0 24px; font-size:clamp(2.8rem,5vw,5rem); font-weight:780; letter-spacing:-.055em; line-height:.98; }
    .seo-hero p { max-width:540px; margin:0; color:#dce7f4; font-size:clamp(1rem,1.3vw,1.2rem); }
    .seo-hero-media { min-height:400px; overflow:hidden; background:#dce3df; }
    .seo-hero-media img { height:100%; object-fit:cover; }
    .seo-main { max-width:1240px; margin:auto; padding:72px 28px 88px; }
    .seo-results-head { display:flex; align-items:end; justify-content:space-between; gap:24px; margin-bottom:28px; }
    .seo-results-head h2 { margin:0; color:var(--navy); font-size:clamp(1.7rem,3vw,2.5rem); line-height:1.1; letter-spacing:-.035em; }
    .seo-results-head p { margin:0; color:var(--muted); }
    .seo-grid { display:grid; gap:24px; margin:0; padding:0; list-style:none; }
    .seo-card { display:grid; grid-template-columns:minmax(300px,42%) 1fr; min-height:330px; overflow:hidden; background:var(--white); border:1px solid var(--line); border-radius:24px; box-shadow:var(--shadow); }
    .seo-card-media { min-height:300px; overflow:hidden; background:linear-gradient(145deg,#e5ebe6,#cad8cf); }
    .seo-card-media img { height:100%; object-fit:cover; transition:transform .45s ease; }
    .seo-card:hover .seo-card-media img { transform:scale(1.025); }
    .seo-card-placeholder,.seo-gallery-placeholder { height:100%; min-height:inherit; display:grid; place-items:center; padding:28px; color:#4d6254; background:linear-gradient(145deg,#edf2ee,#d7e2da); text-align:center; font-weight:750; }
    .seo-card-body { display:flex; flex-direction:column; justify-content:center; padding:clamp(28px,5vw,56px); }
    .seo-card-title-row { display:flex; align-items:flex-start; justify-content:space-between; gap:28px; }
    .seo-card a { color:var(--navy); text-decoration:none; }
    .seo-card h2 { margin:7px 0 10px; font-size:clamp(1.55rem,3vw,2.35rem); letter-spacing:-.035em; line-height:1.08; }
    .seo-card-arrow { flex:0 0 auto; width:46px; height:46px; display:grid; place-items:center; border:1px solid var(--line); border-radius:50%; color:var(--navy); }
    .seo-card-arrow svg,.seo-cta svg,.seo-facts svg { width:20px; height:20px; }
    .seo-kicker { margin:0; color:var(--sage); font-weight:800; text-transform:uppercase; letter-spacing:.11em; font-size:.75rem; }
    .seo-location { margin:0; color:var(--muted); }
    .seo-price { margin:22px 0 0; color:var(--navy); font-size:1.2rem; font-weight:850; }
    .seo-summary { max-width:660px; margin:14px 0 0; color:#465366; }
    .seo-empty { max-width:720px; padding:56px; border-radius:24px; background:var(--ivory); }
    .seo-empty h2 { color:var(--navy); }
    .seo-listing-main { max-width:1320px; margin:auto; padding:36px 28px 96px; }
    .seo-breadcrumbs { margin:0 0 28px; color:var(--muted); font-size:.9rem; }
    .seo-breadcrumbs a { font-weight:700; text-decoration:none; }
    .seo-listing-layout { display:grid; grid-template-columns:minmax(0,1.2fr) minmax(340px,.8fr); align-items:start; gap:clamp(38px,5vw,72px); }
    .seo-gallery { display:grid; grid-template-columns:1.6fr 1fr; grid-template-rows:repeat(2,minmax(220px,1fr)); gap:14px; min-height:610px; }
    .seo-gallery-item { margin:0; overflow:hidden; border-radius:20px; background:#e1e8e2; }
    .seo-gallery-item:first-child { grid-row:1 / 3; }
    .seo-gallery-item img { height:100%; object-fit:cover; }
    .seo-gallery.is-single { display:block; min-height:610px; }
    .seo-gallery.is-single .seo-gallery-item { height:610px; }
    .seo-gallery.is-double { grid-template-columns:1.45fr 1fr; grid-template-rows:1fr; }
    .seo-gallery.is-double .seo-gallery-item:first-child { grid-row:auto; }
    .seo-listing-details { padding-top:8px; }
    .seo-listing-details h1 { margin:10px 0 12px; color:var(--navy); font-size:clamp(2.35rem,4vw,4.25rem); font-weight:780; letter-spacing:-.055em; line-height:1.01; }
    .seo-listing-details .seo-price { margin-top:28px; font-size:1.55rem; }
    .seo-facts { display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:10px; margin:30px 0 0; padding:0; list-style:none; }
    .seo-facts li { min-height:88px; display:flex; flex-direction:column; align-items:flex-start; justify-content:center; gap:8px; padding:14px; border:1px solid var(--line); border-radius:16px; color:#445164; font-size:.9rem; }
    .seo-facts svg { color:var(--sage); }
    .seo-copy { margin:0; color:#465366; white-space:pre-line; }
    .seo-section { margin-top:34px; padding-top:30px; border-top:1px solid var(--line); }
    .seo-section h2 { margin:0 0 14px; color:var(--navy); font-size:1.25rem; }
    .seo-chips { display:flex; flex-wrap:wrap; gap:10px; margin:0; padding:0; list-style:none; }
    .seo-chip { border-radius:999px; background:var(--sage-soft); padding:8px 13px; color:#365540; font-size:.9rem; font-weight:700; }
    .seo-cta { width:100%; display:flex; align-items:center; justify-content:space-between; gap:16px; margin-top:34px; padding:17px 20px; border-radius:14px; color:var(--white); background:var(--navy); box-shadow:0 12px 30px rgba(18,58,111,.2); text-decoration:none; font-weight:800; transition:transform .2s ease,background .2s ease; }
    .seo-cta:hover { transform:translateY(-2px); background:var(--navy-deep); }
    .seo-footer { border-top:1px solid var(--line); padding:30px 24px; background:var(--ivory); text-align:center; color:var(--muted); font-size:.9rem; }
    @media (max-width:900px) {
      .seo-hero-inner { min-height:auto; grid-template-columns:1fr; }
      .seo-hero-copy { min-height:430px; }
      .seo-hero-media { height:430px; }
      .seo-card { grid-template-columns:1fr; }
      .seo-card-media { height:360px; }
      .seo-listing-layout { grid-template-columns:1fr; }
      .seo-listing-details { max-width:720px; }
    }
    @media (max-width:600px) {
      .seo-nav { padding:17px 18px; }
      .seo-nav-links { gap:15px; }
      .seo-nav-links a { font-size:.82rem; }
      .seo-brand { font-size:1.35rem; }
      .seo-hero-copy { min-height:390px; padding:58px 22px; }
      .seo-hero h1 { font-size:clamp(2.75rem,14vw,4rem); }
      .seo-hero-media { height:300px; min-height:300px; }
      .seo-main,.seo-listing-main { padding-left:18px; padding-right:18px; }
      .seo-main { padding-top:52px; padding-bottom:64px; }
      .seo-results-head { align-items:flex-start; flex-direction:column; }
      .seo-card { border-radius:18px; }
      .seo-card-media { height:250px; min-height:250px; }
      .seo-card-body { padding:28px 22px 30px; }
      .seo-card-arrow { width:40px; height:40px; }
      .seo-gallery { min-height:460px; grid-template-columns:1fr 1fr; grid-template-rows:300px 150px; gap:9px; }
      .seo-gallery-item { border-radius:13px; }
      .seo-gallery-item:first-child { grid-column:1 / 3; grid-row:auto; }
      .seo-gallery.is-single,.seo-gallery.is-single .seo-gallery-item { min-height:360px; height:360px; }
      .seo-gallery.is-double { min-height:250px; grid-template-columns:1fr 1fr; grid-template-rows:250px; }
      .seo-gallery.is-double .seo-gallery-item:first-child { grid-column:auto; }
      .seo-listing-details h1 { font-size:clamp(2.35rem,12vw,3.5rem); }
      .seo-facts { grid-template-columns:repeat(2,minmax(0,1fr)); }
    }
    @media (prefers-reduced-motion:reduce) { html { scroll-behavior:auto; } .seo-card-media img,.seo-cta { transition:none; } }
  </style>
</head>
<body>
  <div id="seo-content">
    <header class="seo-header">
      <nav class="seo-nav" aria-label="Primary">
        <a class="seo-brand" href="/explore">Nyumba</a>
        <span class="seo-nav-links">
          <a href="/explore">Available homes</a>
          <a href="/sign-in" rel="nofollow">Sign in</a>
        </span>
      </nav>
    </header>
    ${body}
    <footer class="seo-footer">Nyumba Property Management · Uganda</footer>
  </div>
  ${flutterBoot}
</body>
</html>`;
}

export function renderExplorePage(listings: PublicSeoListing[]): string {
  const cards = listings.length === 0
    ? `<main class="seo-main"><section class="seo-empty"><h2>No homes are listed right now</h2><p>Landlords add new rental spaces regularly — check back soon.</p></section></main>`
    : `<main class="seo-main">
        <div class="seo-results-head">
          <h2>${listings.length} available ${listings.length === 1 ? 'home' : 'homes'}</h2>
        </div>
        <ul class="seo-grid">
          ${listings.map((listing) => `<li>
            <article class="seo-card">
              <a class="seo-card-media" href="${listingPath(listing.id)}" aria-label="View ${escapeHtml(listing.title)}">
                ${listing.imageCount > 0
                  ? `<img src="${listingMediaPath(listing.id, 0)}" alt="${escapeHtml(listing.title)}" loading="lazy">`
                  : '<span class="seo-card-placeholder">Listing photos coming soon</span>'}
              </a>
              <div class="seo-card-body">
                <p class="seo-kicker">${escapeHtml(displayUnitType(listing.unitType))}</p>
                <div class="seo-card-title-row">
                  <h2><a href="${listingPath(listing.id)}">${escapeHtml(listing.title)}</a></h2>
                  <a class="seo-card-arrow" href="${listingPath(listing.id)}" aria-label="View ${escapeHtml(listing.title)}">${arrowIcon}</a>
                </div>
                <p class="seo-location">${escapeHtml(locationFor(listing))}</p>
                <p class="seo-price">${escapeHtml(formattedRent(listing))} / month</p>
                <p class="seo-summary">${escapeHtml(metaDescription(listing.description))}</p>
              </div>
            </article>
          </li>`).join('')}
        </ul>
      </main>`;
  const itemList = listings.map((listing, index) => ({
    '@type': 'ListItem',
    position: index + 1,
    url: absoluteUrl(listingPath(listing.id)),
    name: listing.title,
  }));
  return page({
    title: 'Rental Homes in Uganda | Nyumba',
    description: DEFAULT_DESCRIPTION,
    canonicalPath: '/explore',
    socialImagePath:
      '/assets/assets/listings/generated-modern-apartment-exterior.png',
    body: `<section class="seo-hero"><div class="seo-hero-inner">
        <div class="seo-hero-copy">
          <h1>Find a place that feels like home.</h1>
          <p>Browse verified available rental spaces and contact landlords directly.</p>
        </div>
        <div class="seo-hero-media">
          <img src="/assets/assets/listings/generated-modern-apartment-exterior.png" alt="">
        </div>
      </div></section>${cards}`,
    structuredData: {
      '@context': 'https://schema.org',
      '@graph': [
        {
          '@type': 'WebSite',
          '@id': `${APP_ORIGIN}/#website`,
          url: APP_ORIGIN,
          name: 'Nyumba',
          inLanguage: 'en',
        },
        {
          '@type': 'CollectionPage',
          '@id': `${APP_ORIGIN}/explore#page`,
          url: `${APP_ORIGIN}/explore`,
          name: 'Rental Homes in Uganda',
          description: DEFAULT_DESCRIPTION,
          isPartOf: { '@id': `${APP_ORIGIN}/#website` },
          mainEntity: {
            '@type': 'ItemList',
            numberOfItems: listings.length,
            itemListElement: itemList,
          },
        },
      ],
    },
  });
}

export function renderListingPage(listing: PublicSeoListing): string {
  const path = listingPath(listing.id);
  const location = locationFor(listing);
  const type = displayUnitType(listing.unitType);
  const titleIncludesNeighborhood = listing.title
    .toLocaleLowerCase('en')
    .includes(listing.neighborhood.toLocaleLowerCase('en'));
  const pageTitle = titleIncludesNeighborhood
    ? `${listing.title} | Nyumba`
    : `${listing.title} in ${listing.neighborhood} | Nyumba`;
  const facts = [
    ...(listing.bedrooms !== undefined
      ? [{
        icon: bedIcon,
        label: `${listing.bedrooms} bedroom${listing.bedrooms === 1 ? '' : 's'}`,
      }]
      : []),
    ...(listing.bathrooms !== undefined
      ? [{
        icon: bathIcon,
        label: `${listing.bathrooms} bathroom${listing.bathrooms === 1 ? '' : 's'}`,
      }]
      : []),
    { icon: homeIcon, label: type },
  ];
  const galleryCount = Math.min(listing.imageCount, 3);
  const galleryClass = galleryCount <= 1
    ? 'is-single'
    : galleryCount === 2
      ? 'is-double'
      : '';
  const gallery = galleryCount === 0
    ? `<div class="seo-gallery is-single">
        <div class="seo-gallery-item seo-gallery-placeholder">Listing photos coming soon</div>
      </div>`
    : `<div class="seo-gallery ${galleryClass}">
        ${Array.from({ length: galleryCount }, (_, index) => `
          <figure class="seo-gallery-item">
            <img src="${listingMediaPath(listing.id, index)}" alt="${escapeHtml(listing.title)} — photo ${index + 1}" ${index === 0 ? 'fetchpriority="high"' : 'loading="lazy"'}>
          </figure>`).join('')}
      </div>`;
  const amenities = listing.amenities.length === 0
    ? ''
    : `<section class="seo-section"><h2>Amenities</h2><ul class="seo-chips">${listing.amenities
      .map((amenity) => `<li class="seo-chip">${escapeHtml(amenity)}</li>`)
      .join('')}</ul></section>`;

  return page({
    title: pageTitle,
    description: `${type} for rent in ${location}. ${listing.description}`,
    canonicalPath: path,
    ...(listing.imageCount > 0
      ? { socialImagePath: listingMediaPath(listing.id, 0) }
      : {}),
    body: `<main class="seo-listing-main">
      <nav class="seo-breadcrumbs" aria-label="Breadcrumb"><a href="/explore">Available homes</a> / ${escapeHtml(listing.title)}</nav>
      <div class="seo-listing-layout">
        ${gallery}
        <article class="seo-listing-details">
          <p class="seo-kicker">${escapeHtml(type)} for rent</p>
          <h1>${escapeHtml(listing.title)}</h1>
          <p class="seo-location">${escapeHtml(location)}</p>
          <p class="seo-price">${escapeHtml(formattedRent(listing))} / month</p>
          <ul class="seo-facts">${facts.map((fact) => `<li>${fact.icon}<span>${escapeHtml(fact.label)}</span></li>`).join('')}</ul>
          <section class="seo-section"><h2>About this home</h2><p class="seo-copy">${escapeHtml(listing.description)}</p></section>
          ${amenities}
          <a class="seo-cta" href="${path}#contact"><span>Contact landlord</span>${arrowIcon}</a>
        </article>
      </div>
    </main>`,
    structuredData: {
      '@context': 'https://schema.org',
      '@graph': [
        {
          '@type': 'BreadcrumbList',
          itemListElement: [
            {
              '@type': 'ListItem',
              position: 1,
              name: 'Available homes',
              item: `${APP_ORIGIN}/explore`,
            },
            {
              '@type': 'ListItem',
              position: 2,
              name: listing.title,
              item: absoluteUrl(path),
            },
          ],
        },
        {
          '@type': 'Offer',
          url: absoluteUrl(path),
          price: listing.monthlyRentMinor / 100,
          priceCurrency: listing.currency,
          availability: 'https://schema.org/InStock',
          businessFunction: 'http://purl.org/goodrelations/v1#LeaseOut',
          priceSpecification: {
            '@type': 'UnitPriceSpecification',
            price: listing.monthlyRentMinor / 100,
            priceCurrency: listing.currency,
            unitText: 'MONTH',
          },
          itemOffered: {
            '@type': schemaType(listing.unitType),
            name: listing.title,
            description: listing.description,
            ...(listing.imageCount > 0
              ? {
                image: Array.from(
                  { length: listing.imageCount },
                  (_, index) => absoluteUrl(listingMediaPath(listing.id, index)),
                ),
              }
              : {}),
            ...(listing.bedrooms !== undefined
              ? { numberOfBedrooms: listing.bedrooms }
              : {}),
            ...(listing.bathrooms !== undefined
              ? { numberOfBathroomsTotal: listing.bathrooms }
              : {}),
            address: {
              '@type': 'PostalAddress',
              addressCountry: 'UG',
              addressLocality: listing.city,
              addressRegion: listing.district ?? listing.neighborhood,
            },
            amenityFeature: listing.amenities.map((amenity) => ({
              '@type': 'LocationFeatureSpecification',
              name: amenity,
              value: true,
            })),
          },
        },
      ],
    },
  });
}

export function renderUnavailablePage(status: 404 | 410): string {
  const missing = status === 404;
  return page({
    title: `${missing ? 'Listing not found' : 'Listing no longer available'} | Nyumba`,
    description: 'Browse currently available rental homes on Nyumba.',
    canonicalPath: '/explore',
    robots: 'noindex, nofollow',
    body: `<main class="seo-main">
      <h1>${missing ? 'Listing not found' : 'This listing is no longer available'}</h1>
      <p>Browse currently available rental homes on Nyumba.</p>
      <a class="seo-cta" href="/explore">Browse available homes</a>
    </main>`,
  });
}

export function renderSitemap(listings: PublicSeoListing[]): string {
  const urls = [
    {
      location: `${APP_ORIGIN}/explore`,
      lastModified: listings
        .map((listing) => listing.updatedAt ?? listing.publishedAt)
        .filter((date): date is Date => date !== undefined)
        .sort((left, right) => right.getTime() - left.getTime())[0],
    },
    ...listings.map((listing) => ({
      location: absoluteUrl(listingPath(listing.id)),
      lastModified: listing.updatedAt ?? listing.publishedAt,
    })),
  ];
  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls.map(({ location, lastModified }) => `  <url>
    <loc>${escapeXml(location)}</loc>${lastModified ? `
    <lastmod>${lastModified.toISOString()}</lastmod>` : ''}
  </url>`).join('\n')}
</urlset>
`;
}
