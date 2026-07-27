import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => {
  const documentGet = vi.fn();
  const query = {
    get: vi.fn(),
    limit: vi.fn(),
    orderBy: vi.fn(),
    startAfter: vi.fn(),
  };
  query.limit.mockReturnValue(query);
  query.orderBy.mockReturnValue(query);
  query.startAfter.mockReturnValue(query);

  const collection = {
    doc: vi.fn(() => ({ get: documentGet })),
    orderBy: vi.fn(() => query),
    where: vi.fn(),
  };
  collection.where.mockReturnValue(collection);

  const download = vi.fn();
  const getMetadata = vi.fn();
  const file = vi.fn(() => ({ download, getMetadata }));

  return {
    collection,
    documentGet,
    download,
    file,
    firestore: { collection: vi.fn(() => collection) },
    getMetadata,
    query,
    storage: { bucket: vi.fn(() => ({ file })) },
  };
});

vi.mock('firebase-admin/firestore', () => ({
  getFirestore: () => mocks.firestore,
  Timestamp: { fromDate: (date: Date) => date },
}));

vi.mock('firebase-functions/v2/https', () => ({
  onRequest: vi.fn((_options, handler) => handler),
}));

vi.mock('firebase-admin/storage', () => ({
  getStorage: () => mocks.storage,
}));

import {
  activeListings,
  applyDocumentHeaders,
  PUBLIC_SEO_CACHE_CONTROL,
  publicSeo,
} from '../../src/http/public-seo-handler';

const now = new Date('2026-07-24T08:00:00.000Z');

function document(index: number) {
  return {
    id: `listing_${String(index).padStart(4, '0')}`,
    data: () => ({
      status: 'published',
      isDeleted: false,
      title: `Listing ${index}`,
      description: 'A public listing description.',
      monthlyRentMinor: 150_000_000,
      currency: 'UGX',
      unitType: 'apartment',
      city: 'Kampala',
      neighborhood: 'Kololo',
      expiresAt: new Date('2026-08-20T08:00:00.000Z'),
    }),
  };
}

describe('public SEO handler', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.query.limit.mockReturnValue(mocks.query);
    mocks.query.orderBy.mockReturnValue(mocks.query);
    mocks.query.startAfter.mockReturnValue(mocks.query);
    mocks.collection.where.mockReturnValue(mocks.collection);
  });

  it('paginates active listings beyond the first 500 documents', async () => {
    const firstPage = Array.from({ length: 500 }, (_, index) => document(index));
    const secondPage = [document(500)];
    mocks.query.get
      .mockResolvedValueOnce({ docs: firstPage })
      .mockResolvedValueOnce({ docs: secondPage });

    const listings = await activeListings(now);

    expect(listings).toHaveLength(501);
    expect(mocks.collection.orderBy).toHaveBeenCalledWith('expiresAt');
    expect(mocks.query.orderBy).toHaveBeenCalledWith('publishedAt', 'desc');
    expect(mocks.query.get).toHaveBeenCalledTimes(2);
    expect(mocks.query.startAfter).toHaveBeenNthCalledWith(1, firstPage[499]);
  });

  it('sets short-lived browser and shared-cache headers', () => {
    const response = { set: vi.fn() };

    applyDocumentHeaders(response);

    expect(response.set).toHaveBeenCalledWith(
      expect.objectContaining({
        'Cache-Control': PUBLIC_SEO_CACHE_CONTROL,
        'Referrer-Policy': 'strict-origin-when-cross-origin',
        'X-Content-Type-Options': 'nosniff',
      }),
    );
    expect(PUBLIC_SEO_CACHE_CONTROL).toBe('public, max-age=60, s-maxage=60');
  });

  it('marks 404, 410, and media-error responses as not cacheable', async () => {
    function response() {
      const res = {
        end: vi.fn(),
        redirect: vi.fn(),
        send: vi.fn(),
        set: vi.fn(),
        status: vi.fn(),
        type: vi.fn(),
      };
      res.set.mockReturnValue(res);
      res.status.mockReturnValue(res);
      res.type.mockReturnValue(res);
      return res;
    }

    async function call(
      res: ReturnType<typeof response>,
      request: { method: string; path: string },
    ) {
      await (publicSeo as unknown as (
        request: { method: string; path: string },
        response: ReturnType<typeof response>,
      ) => Promise<void>)(request, res);
    }

    // A listing that does not exist at all.
    mocks.documentGet.mockResolvedValue({ exists: false });
    const missing = response();
    await call(missing, { method: 'GET', path: '/listing/listing_9999' });
    expect(missing.set).toHaveBeenCalledWith({ 'Cache-Control': 'no-store' });
    expect(missing.status).toHaveBeenCalledWith(404);

    // A listing that has since expired.
    mocks.documentGet.mockResolvedValue({
      exists: true,
      data: () => ({
        ...document(0).data(),
        expiresAt: new Date('2020-01-01T00:00:00.000Z'),
      }),
    });
    const expired = response();
    await call(expired, { method: 'GET', path: '/listing/listing_0000' });
    expect(expired.set).toHaveBeenCalledWith({ 'Cache-Control': 'no-store' });
    expect(expired.status).toHaveBeenCalledWith(410);

    // An unsupported method.
    const badMethod = response();
    await call(badMethod, { method: 'POST', path: '/explore' });
    expect(badMethod.set).toHaveBeenCalledWith({ 'Cache-Control': 'no-store' });
    expect(badMethod.status).toHaveBeenCalledWith(405);

    // An active listing whose stored image metadata cannot be read.
    mocks.documentGet.mockResolvedValue({
      exists: true,
      data: () => ({
        ...document(0).data(),
        imagePaths: ['public/listings/listing_0000/0_living-room.png'],
      }),
    });
    mocks.getMetadata.mockRejectedValue(new Error('object not found'));
    const mediaError = response();
    await call(mediaError, { method: 'GET', path: '/listing/listing_0000/media/0' });
    expect(mediaError.set).toHaveBeenCalledWith({ 'Cache-Control': 'no-store' });
    expect(mediaError.status).toHaveBeenCalledWith(404);
  });

  it('serves validated active-listing media without exposing its storage path', async () => {
    mocks.documentGet.mockResolvedValue({
      exists: true,
      data: () => ({
        ...document(0).data(),
        imagePaths: ['public/listings/listing_0000/0_living-room.png'],
      }),
    });
    mocks.getMetadata.mockResolvedValue([
      { contentType: 'image/png', size: '5' },
    ]);
    mocks.download.mockResolvedValue([Buffer.from('image')]);
    const response = {
      end: vi.fn(),
      redirect: vi.fn(),
      send: vi.fn(),
      set: vi.fn(),
      status: vi.fn(),
      type: vi.fn(),
    };
    response.set.mockReturnValue(response);
    response.status.mockReturnValue(response);
    response.type.mockReturnValue(response);

    await (publicSeo as unknown as (
      request: { method: string; path: string },
      response: typeof response,
    ) => Promise<void>)(
      { method: 'GET', path: '/listing/listing_0000/media/0' },
      response,
    );

    expect(mocks.file).toHaveBeenCalledWith(
      'public/listings/listing_0000/0_living-room.png',
    );
    expect(response.set).toHaveBeenCalledWith({
      'Content-Length': '5',
      'Content-Type': 'image/png',
    });
    expect(response.status).toHaveBeenCalledWith(200);
    expect(response.send).toHaveBeenCalledWith(Buffer.from('image'));
  });
});
