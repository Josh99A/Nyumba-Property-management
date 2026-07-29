import { describe, expect, it } from 'vitest';
import {
  isActivePublicListing,
  listingMediaPath,
  publicListingImagePaths,
  renderExplorePage,
  renderListingPage,
  renderSitemap,
  toPublicSeoListing,
  type PublicSeoListing,
} from '../../src/http/public-seo';

const now = new Date('2026-07-24T08:00:00.000Z');

function projection(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    id: 'listing_1234',
    status: 'published',
    isDeleted: false,
    title: 'Two-bedroom apartment',
    description: 'A bright home near shops and public transport.',
    monthlyRentMinor: 150_000_000,
    currency: 'UGX',
    unitType: 'apartment',
    city: 'Kampala',
    neighborhood: 'Kololo',
    district: 'Kampala',
    bedrooms: 2,
    bathrooms: 1,
    amenities: ['Parking', 'Security'],
    imagePaths: [
      'public/listings/listing_1234/0_living-room.png',
      'public/listings/listing_1234/1_kitchen.png',
      'public/listings/listing_1234/2_bedroom.png',
    ],
    publishedAt: new Date('2026-07-20T08:00:00.000Z'),
    updatedAt: new Date('2026-07-23T08:00:00.000Z'),
    expiresAt: new Date('2026-08-20T08:00:00.000Z'),
    ...overrides,
  };
}

function listing(overrides: Partial<PublicSeoListing> = {}): PublicSeoListing {
  return {
    id: 'listing_1234',
    title: 'Two-bedroom apartment',
    description: 'A bright home near shops and public transport.',
    monthlyRentMinor: 150_000_000,
    currency: 'UGX',
    unitType: 'apartment',
    city: 'Kampala',
    neighborhood: 'Kololo',
    district: 'Kampala',
    bedrooms: 2,
    bathrooms: 1,
    amenities: ['Parking', 'Security'],
    imageCount: 3,
    publishedAt: new Date('2026-07-20T08:00:00.000Z'),
    updatedAt: new Date('2026-07-23T08:00:00.000Z'),
    expiresAt: new Date('2026-08-20T08:00:00.000Z'),
    ...overrides,
  };
}

describe('public SEO projection', () => {
  it('accepts only active public listing documents', () => {
    expect(isActivePublicListing(projection(), now)).toBe(true);
    expect(
      isActivePublicListing(projection({ status: 'unpublished' }), now),
    ).toBe(false);
    expect(
      isActivePublicListing(
        projection({ expiresAt: new Date('2026-07-24T07:59:59.000Z') }),
        now,
      ),
    ).toBe(false);
    expect(isActivePublicListing(projection({ isDeleted: true }), now)).toBe(
      false,
    );
  });

  it('allowlists fields and ignores private projection additions', () => {
    const result = toPublicSeoListing(
      'listing_1234',
      projection({
        landlordId: 'private_landlord',
        contactEmail: 'private@example.com',
        exactAddress: 'Private address',
      }),
      now,
    );

    expect(result).not.toBeNull();
    expect(result).not.toHaveProperty('landlordId');
    expect(result).not.toHaveProperty('contactEmail');
    expect(result).not.toHaveProperty('exactAddress');
    expect(result).not.toHaveProperty('imagePaths');
    expect(result?.imageCount).toBe(3);
  });

  it('accepts only server-published image paths owned by the listing', () => {
    const paths = publicListingImagePaths('listing_1234', [
      'public/listings/listing_1234/0_living-room.png',
      'public/listings/another_listing/1_private.png',
      'uploads/private/image.png',
      'public/listings/listing_1234/../private.png',
    ]);

    expect(paths).toEqual([
      'public/listings/listing_1234/0_living-room.png',
    ]);
    expect(listingMediaPath('listing_1234', 0)).toBe(
      '/listing/listing_1234/media/0',
    );
  });

  it('exposes no more than five listing photos', () => {
    const paths = publicListingImagePaths(
      'listing_1234',
      Array.from(
        { length: 6 },
        (_, index) => `public/listings/listing_1234/${index}_photo.png`,
      ),
    );

    expect(paths).toHaveLength(5);
    expect(paths.at(-1)).toBe(
      'public/listings/listing_1234/4_photo.png',
    );
  });

  it('carries the coarsened map pin and nothing more precise', () => {
    const result = toPublicSeoListing(
      'listing_1234',
      projection({
        approximateLocation: { lat: 0.357, lng: 32.612 },
        // What the canonical listing and its property hold. Neither may ever
        // reach the public projection, whatever else changes around them.
        exactLocation: { lat: 0.3571234, lng: 32.6129876 },
        addressLine: 'Plot 14, Acacia Avenue',
      }),
      now,
    );

    expect(result?.approximateLocation).toEqual({ lat: 0.357, lng: 32.612 });
    expect(result).not.toHaveProperty('exactLocation');
    expect(result).not.toHaveProperty('addressLine');
  });

  it('drops a map pin that is missing, partial, or out of range', () => {
    const pin = (approximateLocation: unknown) =>
      toPublicSeoListing(
        'listing_1234',
        projection({ approximateLocation }),
        now,
      )?.approximateLocation;

    // `listingPublish` writes an explicit null when no pin was set, so this is
    // the ordinary case for most listings rather than an edge case.
    expect(pin(null)).toBeUndefined();
    expect(pin({ lat: 0.357 })).toBeUndefined();
    expect(pin({ lat: '0.357', lng: '32.612' })).toBeUndefined();
    expect(pin({ lat: 91, lng: 32.612 })).toBeUndefined();
    expect(pin({ lat: 0.357, lng: 181 })).toBeUndefined();
    expect(pin({ lat: Number.NaN, lng: 32.612 })).toBeUndefined();
  });

  it('rejects malformed and unrecognized currency codes', () => {
    expect(
      toPublicSeoListing(
        'listing_1234',
        projection({ currency: 'ugx' }),
        now,
      ),
    ).toBeNull();
    expect(
      toPublicSeoListing(
        'listing_1234',
        projection({ currency: 'ZZZ' }),
        now,
      ),
    ).toBeNull();
    expect(toPublicSeoListing('listing_1234', projection(), now)?.currency).toBe(
      'UGX',
    );
  });
});

/**
 * The parsed JSON-LD block, so structured-data assertions test what a crawler
 * actually consumes rather than a substring that happens to appear in the HTML.
 */
function structuredData(html: string): Record<string, unknown> {
  const match = html.match(
    /<script type="application\/ld\+json">([\s\S]*?)<\/script>/,
  );
  expect(match).not.toBeNull();
  return JSON.parse(match![1]) as Record<string, unknown>;
}

function itemOffered(html: string): Record<string, unknown> {
  const graph = structuredData(html)['@graph'] as Array<Record<string, unknown>>;
  const offer = graph.find((node) => node['@type'] === 'Offer');
  expect(offer).toBeDefined();
  return offer!.itemOffered as Record<string, unknown>;
}

describe('public SEO rendering', () => {
  it('describes the listing location with the coarsened coordinates', () => {
    const html = renderListingPage(
      listing({ approximateLocation: { lat: 0.357, lng: 32.612 } }),
    );

    expect(itemOffered(html).geo).toEqual({
      '@type': 'GeoCoordinates',
      latitude: 0.357,
      longitude: 32.612,
    });
    // The page shows a neighbourhood, never a street address, and the
    // structured data must not claim otherwise.
    expect(itemOffered(html).address).toMatchObject({
      '@type': 'PostalAddress',
      addressCountry: 'UG',
      addressLocality: 'Kampala',
    });
    expect(html).not.toContain('streetAddress');
  });

  it('renders a crawlable location section with a first-party map', () => {
    const html = renderListingPage(
      listing({ approximateLocation: { lat: 0.357, lng: 32.612 } }),
    );

    expect(html).toContain('<h2>Where you will live</h2>');
    // A first-party path, so the Static Maps key never reaches the page and
    // the image re-checks the public invariant itself.
    expect(html).toContain('src="/listing/listing_1234/map"');
    expect(html).not.toContain('maps.googleapis.com');
    expect(html).not.toContain('key=');
    // Works with JavaScript disabled, which is the whole point of this page.
    expect(html).toContain(
      'href="https://www.google.com/maps/dir/?api=1&amp;destination=0.357%2C32.612"',
    );
    expect(html).toContain('Get directions');
    // Reserved space, so the copy below never jumps when the map arrives.
    expect(html).toContain('width="640" height="320"');
  });

  it('omits the location section when no pin was set', () => {
    const html = renderListingPage(listing());

    expect(html).not.toContain('Where you will live');
    expect(html).not.toContain('/map');
    expect(html).not.toContain('Get directions');
  });

  it('omits the geo node entirely when no pin was set', () => {
    const html = renderListingPage(listing());

    expect(itemOffered(html)).not.toHaveProperty('geo');
    expect(html).not.toContain('GeoCoordinates');
  });

  it('renders canonical listing metadata and escapes user-authored markup', () => {
    const html = renderListingPage(
      listing({
        title: 'Home </title><script>alert(1)</script>',
        description: 'Safe description </script><script>alert(2)</script>',
      }),
    );

    expect(html).toContain(
      '<link rel="canonical" href="https://nyumba.online/listing/listing_1234">',
    );
    expect(html).toContain('<meta name="robots" content="index, follow">');
    expect(html).toContain('application/ld+json');
    expect(html).toContain('&lt;script&gt;alert(1)&lt;/script&gt;');
    expect(html).not.toContain('</script><script>alert');
    expect(html).toContain('\\u003c/script\\u003e');
  });

  it('does not duplicate a neighborhood already present in the title', () => {
    const html = renderListingPage(
      listing({ title: 'Garden apartment in Kololo' }),
    );

    expect(html).toContain(
      '<title>Garden apartment in Kololo | Nyumba</title>',
    );
    expect(html).not.toContain('in Kololo in Kololo');
  });

  it('renders crawlable listing links on the explore page', () => {
    const html = renderExplorePage([listing()]);

    expect(html).toContain('<title>Rental Homes in Uganda | Nyumba</title>');
    expect(html).toContain('href="/listing/listing_1234"');
    expect(html).toContain('src="/listing/listing_1234/media/0"');
    expect(html).toContain('Two-bedroom apartment');
    expect(html).toContain('UGX\u00a01,500,000 / month');
    expect(html).not.toContain('public/listings/');
  });

  it('renders a responsive listing gallery without exposing storage paths', () => {
    const html = renderListingPage(listing());

    expect(html).toContain('class="seo-gallery ');
    expect(html).toContain('src="/listing/listing_1234/media/0"');
    expect(html).toContain('src="/listing/listing_1234/media/2"');
    expect(html).toContain('summary_large_image');
    expect(html).not.toContain('public/listings/');
  });

  it('generates canonical sitemap URLs with accurate last-modified values', () => {
    const xml = renderSitemap([listing()]);

    expect(xml).toContain('<loc>https://nyumba.online/explore</loc>');
    expect(xml).toContain(
      '<loc>https://nyumba.online/listing/listing_1234</loc>',
    );
    expect(xml).toContain('<lastmod>2026-07-23T08:00:00.000Z</lastmod>');
  });
});
