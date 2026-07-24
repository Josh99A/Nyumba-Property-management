import { APP_ORIGIN } from '../shared/config';

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
}

const DEFAULT_DESCRIPTION =
  'Browse verified available rental homes in Uganda and contact landlords through Nyumba.';

function stringValue(value: unknown, maximumLength: number): string | null {
  if (typeof value !== 'string') return null;
  const normalized = value.trim();
  if (normalized.length === 0 || normalized.length > maximumLength) return null;
  return normalized;
}

function optionalString(value: unknown, maximumLength: number): string | undefined {
  return stringValue(value, maximumLength) ?? undefined;
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
  const currency = stringValue(data.currency, 3);
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
    ...(publishedAt ? { publishedAt } : {}),
    ...(updatedAt ? { updatedAt } : {}),
    expiresAt,
  };
}

export function listingPath(listingId: string): string {
  return `/listing/${encodeURIComponent(listingId)}`;
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

function page({
  title,
  description,
  canonicalPath,
  body,
  structuredData,
  robots = 'index, follow',
}: PageOptions): string {
  const canonical = absoluteUrl(canonicalPath);
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
  <meta property="og:image" content="${APP_ORIGIN}/icons/Icon-512.png">
  <meta name="twitter:card" content="summary">
  <meta name="twitter:title" content="${safeTitle}">
  <meta name="twitter:description" content="${safeDescription}">
  <meta name="twitter:image" content="${APP_ORIGIN}/icons/Icon-512.png">
  ${structuredDataElement}
  <style>
    :root { color-scheme: light; --navy:#123A6F; --sage:#5F8F6B; --gold:#C98B2E; --ivory:#F7F4ED; --ink:#172033; }
    * { box-sizing: border-box; }
    body { margin:0; color:var(--ink); background:var(--ivory); font:16px/1.55 system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; }
    a { color:var(--navy); }
    .seo-header { background:#fff; border-bottom:1px solid #dde4ea; }
    .seo-nav { max-width:1180px; margin:auto; padding:18px 24px; display:flex; align-items:center; justify-content:space-between; gap:20px; }
    .seo-brand { color:var(--navy); font-size:1.45rem; font-weight:800; text-decoration:none; }
    .seo-nav-links { display:flex; gap:18px; align-items:center; }
    .seo-nav-links a { font-weight:650; text-decoration:none; }
    .seo-hero { color:#fff; background:linear-gradient(135deg,var(--navy),#0b284d); }
    .seo-hero-inner,.seo-main { max-width:1180px; margin:auto; padding:48px 24px; }
    .seo-hero h1 { max-width:780px; margin:0 0 12px; font-size:clamp(2.1rem,5vw,3.7rem); line-height:1.05; }
    .seo-hero p { max-width:760px; margin:0; color:#dce7f4; font-size:1.1rem; }
    .seo-main h1 { color:var(--navy); font-size:clamp(2rem,4vw,3.25rem); line-height:1.12; margin:12px 0; }
    .seo-breadcrumbs { margin:0 0 18px; color:#526072; font-size:.92rem; }
    .seo-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(250px,1fr)); gap:20px; padding:0; list-style:none; }
    .seo-card { height:100%; background:#fff; border:1px solid #dde4ea; border-radius:16px; padding:22px; box-shadow:0 8px 24px rgba(18,58,111,.06); }
    .seo-card a { color:var(--navy); text-decoration:none; }
    .seo-card h2 { margin:0 0 9px; font-size:1.25rem; }
    .seo-kicker { color:var(--sage); font-weight:750; text-transform:uppercase; letter-spacing:.07em; font-size:.78rem; }
    .seo-location { color:#526072; }
    .seo-price { color:var(--navy); font-size:1.18rem; font-weight:800; }
    .seo-facts { display:flex; flex-wrap:wrap; gap:10px; margin:18px 0; padding:0; list-style:none; }
    .seo-facts li,.seo-chip { border-radius:999px; background:#eaf2ec; padding:7px 11px; font-size:.92rem; }
    .seo-copy { max-width:760px; white-space:pre-line; }
    .seo-section { margin-top:32px; }
    .seo-section h2 { color:var(--navy); }
    .seo-chips { display:flex; flex-wrap:wrap; gap:10px; padding:0; list-style:none; }
    .seo-cta { display:inline-block; margin-top:24px; padding:12px 18px; border-radius:10px; color:#fff; background:var(--navy); text-decoration:none; font-weight:750; }
    .seo-footer { border-top:1px solid #dde4ea; padding:24px; text-align:center; color:#526072; }
    @media (max-width:560px) { .seo-nav,.seo-hero-inner,.seo-main { padding-left:18px; padding-right:18px; } .seo-nav-links { gap:11px; font-size:.9rem; } }
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
    ? `<section class="seo-main"><h2>No homes are listed right now</h2><p>Landlords add new rental spaces regularly — check back soon.</p></section>`
    : `<main class="seo-main">
        <h2>${listings.length} available ${listings.length === 1 ? 'home' : 'homes'}</h2>
        <ul class="seo-grid">
          ${listings.map((listing) => `<li>
            <article class="seo-card">
              <p class="seo-kicker">${escapeHtml(displayUnitType(listing.unitType))}</p>
              <h2><a href="${listingPath(listing.id)}">${escapeHtml(listing.title)}</a></h2>
              <p class="seo-location">${escapeHtml(locationFor(listing))}</p>
              <p class="seo-price">${escapeHtml(formattedRent(listing))} / month</p>
              <p>${escapeHtml(metaDescription(listing.description))}</p>
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
    body: `<section class="seo-hero"><div class="seo-hero-inner">
        <h1>Find a place that feels like home.</h1>
        <p>Browse verified available rental spaces and contact landlords directly.</p>
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
      ? [`${listing.bedrooms} bedroom${listing.bedrooms === 1 ? '' : 's'}`]
      : []),
    ...(listing.bathrooms !== undefined
      ? [`${listing.bathrooms} bathroom${listing.bathrooms === 1 ? '' : 's'}`]
      : []),
    type,
  ];
  const amenities = listing.amenities.length === 0
    ? ''
    : `<section class="seo-section"><h2>Amenities</h2><ul class="seo-chips">${listing.amenities
      .map((amenity) => `<li class="seo-chip">${escapeHtml(amenity)}</li>`)
      .join('')}</ul></section>`;

  return page({
    title: pageTitle,
    description: `${type} for rent in ${location}. ${listing.description}`,
    canonicalPath: path,
    body: `<main class="seo-main">
      <nav class="seo-breadcrumbs" aria-label="Breadcrumb"><a href="/explore">Available homes</a> / ${escapeHtml(listing.title)}</nav>
      <p class="seo-kicker">${escapeHtml(type)} for rent</p>
      <h1>${escapeHtml(listing.title)}</h1>
      <p class="seo-location">${escapeHtml(location)}</p>
      <p class="seo-price">${escapeHtml(formattedRent(listing))} / month</p>
      <ul class="seo-facts">${facts.map((fact) => `<li>${escapeHtml(fact)}</li>`).join('')}</ul>
      <section class="seo-section"><h2>About this home</h2><p class="seo-copy">${escapeHtml(listing.description)}</p></section>
      ${amenities}
      <a class="seo-cta" href="${path}#contact">Contact landlord</a>
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
