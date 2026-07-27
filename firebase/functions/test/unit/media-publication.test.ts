import { Timestamp } from 'firebase-admin/firestore';
import sharp from 'sharp';
import { describe, expect, it } from 'vitest';
import {
  deliveryObjectPath,
  optimisePublicListingImage,
  publicListingMediaPatch,
  renderImageVariants,
} from '../../src/workers/media-publication';

describe('public listing media projection', () => {
  it('keeps cover-first order and advances the projection version', () => {
    const paths = [
      'public/listings/listing_1234/0_primary.webp',
      'public/listings/listing_1234/1_kitchen.webp',
      'public/listings/listing_1234/2_bedroom.webp',
    ];
    const listing = { status: 'published', version: 7, imagePaths: [] };
    const updatedAt = Timestamp.fromMillis(1_721_771_200_000);

    expect(publicListingMediaPatch(listing, paths, updatedAt)).toEqual({
      imagePaths: paths,
      imageThumbPaths: [],
      updatedAt,
      version: 8,
    });
  });

  it('projects thumbnails alongside the full copies', () => {
    const paths = ['public/listings/listing_1234/0-abc123-full.webp'];
    const thumbs = ['public/listings/listing_1234/0-abc123-thumb.webp'];
    const updatedAt = Timestamp.fromMillis(1_721_771_200_000);

    expect(
      publicListingMediaPatch(
        { status: 'published', version: 3, imagePaths: [] },
        paths,
        updatedAt,
        thumbs,
      ),
    ).toEqual({
      imagePaths: paths,
      imageThumbPaths: thumbs,
      updatedAt,
      version: 4,
    });
  });

  it('fills in thumbnails for a projection that only has full copies', () => {
    const paths = ['public/listings/listing_1234/0-abc123-full.webp'];
    const thumbs = ['public/listings/listing_1234/0-abc123-thumb.webp'];

    // A listing published before thumbnails existed carries matching
    // `imagePaths` already; treating that as a completed retry would leave it
    // permanently without a thumbnail.
    expect(
      publicListingMediaPatch(
        { status: 'published', version: 9, imagePaths: paths },
        paths,
        Timestamp.fromMillis(1_721_771_200_000),
        thumbs,
      ),
    ).not.toBeNull();
  });

  it('fails closed when the projection has no valid version', () => {
    expect(() =>
      publicListingMediaPatch(
        { status: 'published' },
        ['public/listings/listing_1234/0_primary.webp'],
        Timestamp.fromMillis(1_721_771_200_000),
      ),
    ).toThrow('valid projection version');
  });

  it('is a no-op when an at-least-once retry already projected the paths', () => {
    const paths = [
      'public/listings/listing_1234/0_primary.webp',
      'public/listings/listing_1234/1_kitchen.webp',
    ];

    expect(
      publicListingMediaPatch(
        { status: 'published', version: 8, imagePaths: paths, imageThumbPaths: [] },
        paths,
        Timestamp.fromMillis(1_721_771_200_000),
      ),
    ).toBeNull();
  });

  it('auto-orients and bounds the WebP public delivery copy', async () => {
    const width = 3_000;
    const height = 2_000;
    const orientation = 6;
    const source = await sharp({
      create: {
        width,
        height,
        channels: 3,
        background: { r: 95, g: 143, b: 107 },
      },
    }).jpeg().withMetadata({ orientation }).toBuffer();

    const output = await optimisePublicListingImage(source);
    const metadata = await sharp(output).metadata();

    expect(metadata.format).toBe('webp');
    expect(metadata.width).toBe(960);
    expect(metadata.height).toBe(1_440);
    expect(metadata.orientation).toBeUndefined();
    expect(output.byteLength).toBeLessThan(source.byteLength);
  });
});

describe('delivery variants', () => {
  async function sourcePhoto(): Promise<Buffer> {
    return sharp({
      create: {
        width: 3_000,
        height: 2_000,
        channels: 3,
        background: { r: 95, g: 143, b: 107 },
      },
    }).jpeg().toBuffer();
  }

  it('renders a grid-sized thumbnail far smaller than the detail copy', async () => {
    const variants = await renderImageVariants(await sourcePhoto());
    const thumb = await sharp(variants.thumb).metadata();
    const full = await sharp(variants.full).metadata();

    expect(thumb.format).toBe('webp');
    expect(thumb.width).toBe(640);
    expect(full.width).toBe(1_920);
    expect(variants.thumb.byteLength).toBeLessThan(variants.full.byteLength);
  });

  it('gives both variants of one photo the same content digest', async () => {
    const source = await sourcePhoto();
    const first = await renderImageVariants(source);
    const second = await renderImageVariants(source);

    expect(first.digest).toBe(second.digest);
    expect(first.digest).toHaveLength(16);
  });

  it('names a changed photo differently so caches are never poisoned', async () => {
    const original = await renderImageVariants(await sourcePhoto());
    const replacement = await renderImageVariants(
      await sharp({
        create: {
          width: 3_000,
          height: 2_000,
          channels: 3,
          background: { r: 10, g: 20, b: 30 },
        },
      }).jpeg().toBuffer(),
    );

    expect(replacement.digest).not.toBe(original.digest);
    expect(
      deliveryObjectPath('public/listings/listing_1/', 0, replacement.digest, 'full'),
    ).not.toBe(
      deliveryObjectPath('public/listings/listing_1/', 0, original.digest, 'full'),
    );
  });

  it('builds a cover-first, variant-tagged object path', () => {
    expect(deliveryObjectPath('public/listings/listing_1/', 2, 'deadbeefdeadbeef', 'thumb'))
      .toBe('public/listings/listing_1/2-deadbeefdeadbeef-thumb.webp');
  });
});
