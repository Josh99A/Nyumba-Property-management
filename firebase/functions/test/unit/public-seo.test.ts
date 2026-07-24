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

describe('public SEO rendering', () => {
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
