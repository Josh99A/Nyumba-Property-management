import { Timestamp } from 'firebase-admin/firestore';
import { describe, expect, it } from 'vitest';
import { publicListingMediaPatch } from '../../src/workers/media-publication';

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
});
