import { Timestamp } from 'firebase-admin/firestore';
import sharp from 'sharp';
import { describe, expect, it } from 'vitest';
import {
  optimisePublicListingImage,
  publicListingMediaPatch,
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
      updatedAt,
      version: 8,
    });
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
        { status: 'published', version: 8, imagePaths: paths },
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
