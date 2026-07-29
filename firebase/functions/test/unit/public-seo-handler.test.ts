import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

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
import { STATIC_MAP_CACHE_CONTROL } from '../../src/http/static-map';

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

  describe('the listing location map', () => {
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

    function call(res: ReturnType<typeof response>, path: string, method = 'GET') {
      return (publicSeo as unknown as (
        request: { method: string; path: string },
        response: ReturnType<typeof response>,
      ) => Promise<void>)({ method, path }, res);
    }

    const pinned = () => ({
      exists: true,
      data: () => ({
        ...document(0).data(),
        approximateLocation: { lat: 0.357, lng: 32.612 },
      }),
    });

    beforeEach(() => {
      process.env.MAPS_STATIC_API_KEY = 'test-key';
    });

    // One place, so a test that throws mid-way cannot leak a stubbed fetch or
    // a deleted key into the next one.
    afterEach(() => {
      delete process.env.MAPS_STATIC_API_KEY;
    });

    it('renders the coarsened pin and caches it hard', async () => {
      mocks.documentGet.mockResolvedValue(pinned());
      const fetchMock = vi.fn().mockResolvedValue({
        ok: true,
        headers: { get: () => 'image/png' },
        arrayBuffer: async () => new TextEncoder().encode('png').buffer,
      });
      vi.stubGlobal('fetch', fetchMock);
      const res = response();

      await call(res, '/listing/listing_0000/map');

      // The long lifetime is what makes this affordable: the URL is
      // deterministic per listing, so the CDN collapses all traffic into
      // roughly one upstream call per listing per day.
      expect(res.set).toHaveBeenCalledWith(
        expect.objectContaining({ 'Cache-Control': STATIC_MAP_CACHE_CONTROL }),
      );
      expect(res.status).toHaveBeenCalledWith(200);

      const requested = String(fetchMock.mock.calls[0]![0]);
      expect(requested).toContain('center=0.357%2C32.612');
      // A circle, never a marker: a pin on a coarsened point still reads as
      // "this house".
      expect(requested).toContain('path=');
      expect(requested).not.toContain('markers=');
    });

    it('never reads anything more precise than the public projection', async () => {
      mocks.documentGet.mockResolvedValue({
        exists: true,
        data: () => ({
          ...document(0).data(),
          approximateLocation: { lat: 0.357, lng: 32.612 },
          exactLocation: { lat: 0.3571234, lng: 32.6129876 },
          addressLine: 'Plot 14, Acacia Avenue',
        }),
      });
      const fetchMock = vi.fn().mockResolvedValue({
        ok: true,
        headers: { get: () => 'image/png' },
        arrayBuffer: async () => new TextEncoder().encode('png').buffer,
      });
      vi.stubGlobal('fetch', fetchMock);
      const res = response();

      await call(res, '/listing/listing_0000/map');

      const requested = String(fetchMock.mock.calls[0]![0]);
      expect(requested).not.toContain('0.3571234');
      expect(requested).not.toContain('Acacia');
      expect(mocks.firestore.collection).toHaveBeenCalledWith('publicListings');
    });

    it('rechecks the public invariant on every request', async () => {
      mocks.documentGet.mockResolvedValue({ exists: false });
      const missing = response();
      await call(missing, '/listing/listing_9999/map');
      expect(missing.status).toHaveBeenCalledWith(404);
      expect(missing.set).toHaveBeenCalledWith({ 'Cache-Control': 'no-store' });

      mocks.documentGet.mockResolvedValue({
        exists: true,
        data: () => ({
          ...pinned().data(),
          expiresAt: new Date('2020-01-01T00:00:00.000Z'),
        }),
      });
      const expired = response();
      await call(expired, '/listing/listing_0000/map');
      expect(expired.status).toHaveBeenCalledWith(410);
      expect(expired.set).toHaveBeenCalledWith(
        'X-Robots-Tag',
        'noindex, nofollow',
      );
    });

    it('treats an unpinned listing and an unkeyed deployment alike', async () => {
      mocks.documentGet.mockResolvedValue({
        exists: true,
        data: () => document(0).data(),
      });
      const unpinned = response();
      await call(unpinned, '/listing/listing_0000/map');
      expect(unpinned.status).toHaveBeenCalledWith(404);

      // Every deployment is in this state until the key is provisioned, and a
      // visitor should simply see no map rather than a broken one.
      delete process.env.MAPS_STATIC_API_KEY;
      mocks.documentGet.mockResolvedValue(pinned());
      const unkeyed = response();
      await call(unkeyed, '/listing/listing_0000/map');
      expect(unkeyed.status).toHaveBeenCalledWith(404);
      expect(unkeyed.set).toHaveBeenCalledWith({ 'Cache-Control': 'no-store' });
    });

    it('does not cache a failed upstream render', async () => {
      mocks.documentGet.mockResolvedValue(pinned());
      vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
        ok: false,
        status: 502,
        headers: { get: () => 'text/plain' },
        arrayBuffer: async () => new ArrayBuffer(0),
      }));
      const res = response();

      await call(res, '/listing/listing_0000/map');

      expect(res.status).toHaveBeenCalledWith(404);
      expect(res.set).toHaveBeenCalledWith({ 'Cache-Control': 'no-store' });
    });
  });
});
