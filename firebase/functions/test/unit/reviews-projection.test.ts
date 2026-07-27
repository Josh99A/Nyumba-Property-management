import { Timestamp } from 'firebase-admin/firestore';
import { describe, expect, it } from 'vitest';
import {
  landlordReviewProjection,
  publicReviewProjection,
  tenantReviewProjection,
  type ReviewRecord,
} from '../../src/shared/projections';

/**
 * Pins the review read-model contract.
 *
 * Every earlier tenant projection in this codebase was written against a Dart
 * mapper that already existed and did not fit, and the result was a
 * FormatException on a screen far from the cause — which is why the tenant pull
 * was disabled entirely (see app_dependencies.dart). These field lists are the
 * Flutter client's, and `LandlordReviewMapper.fromJson` reads exactly them. If
 * this test and `test/features/landlord_review_mapper_test.dart` disagree, the
 * pull is broken in production and nothing here will say so.
 */
const CLIENT_FIELDS = [
  'id', 'version', 'overall', 'responsiveness', 'maintenance', 'listingAccuracy',
  'depositFairness', 'body', 'status', 'landlordResponse', 'respondedAt', 'stayMonths',
  'createdAt', 'updatedAt', 'landlordId', 'propertyName', 'unitLabel', 'reviewerLabel',
  'editableUntil', 'flagState', 'isDeleted',
].sort();

const now = Timestamp.fromMillis(1_700_000_000_000);

function review(overrides: Partial<ReviewRecord> = {}): ReviewRecord {
  return {
    id: 'lease-1',
    version: 3,
    landlordId: 'landlord-1',
    reviewerUid: 'tenant-1',
    propertyName: 'Kireka Heights',
    unitLabel: 'B4',
    overall: 4,
    dimensions: {
      responsiveness: 5,
      maintenance: 3,
      listingAccuracy: null,
      depositFairness: null,
    },
    body: 'Repairs were handled quickly.',
    status: 'published',
    flagState: 'none',
    landlordResponse: null,
    respondedAt: null,
    editableUntil: now,
    stayMonths: 14,
    createdAt: now,
    updatedAt: now,
    isDeleted: false,
    ...overrides,
  };
}

describe('review projections', () => {
  it('publishes exactly the fields the Dart mapper reads', () => {
    for (const projection of [
      tenantReviewProjection(review()),
      landlordReviewProjection(review()),
      publicReviewProjection(review(), 'token-abc'),
    ]) {
      // publicReviewProjection adds landlordToken on top of the shared shape.
      const keys = Object.keys(projection).filter((key) => key !== 'landlordToken').sort();
      expect(keys).toEqual(CLIENT_FIELDS);
    }
  });

  it('flattens dimension scores, preserving nulls for skipped questions', () => {
    const projected = tenantReviewProjection(review());
    expect(projected.responsiveness).toBe(5);
    expect(projected.maintenance).toBe(3);
    // Null rather than absent: JsonReader.optionalInt treats both as "no
    // answer", but a missing key would make an added dimension indistinguishable
    // from an old record and silently read as zero somewhere downstream.
    expect(projected.listingAccuracy).toBeNull();
    expect(projected.depositFairness).toBeNull();
  });

  it('never leaks the reviewer or the unit into the public copy', () => {
    const projected = publicReviewProjection(review(), 'token-abc');
    const serialized = JSON.stringify(projected);
    expect(serialized).not.toContain('tenant-1');
    expect(serialized).not.toContain('landlord-1');
    // A unit label on a four-unit property identifies the author outright.
    expect(projected.unitLabel).toBe('');
    expect(projected.reviewerLabel).toBe('Verified tenant');
    // The one piece of provenance a reader gets, and the one that matters.
    expect(projected.stayMonths).toBe(14);
  });

  it('substitutes the opaque token for the landlord id in the public copy', () => {
    // The client's mapper requires landlordId; the public mirror must satisfy it
    // without handing out the UID, so the token stands in for it.
    expect(publicReviewProjection(review(), 'token-abc').landlordId).toBe('token-abc');
  });

  it('tells the author their review was hidden and until when it is editable', () => {
    const hidden = tenantReviewProjection(review({ status: 'hidden' }));
    // A review that silently vanishes is worse than one that was refused.
    expect(hidden.status).toBe('hidden');
    expect(hidden.editableUntil).toBe(now);
  });

  it('does not hand the landlord an edit window over someone else\'s review', () => {
    expect(landlordReviewProjection(review()).editableUntil).toBeNull();
  });

  it('names the unit for the landlord, who can already tell whose lease it is', () => {
    // Anonymity here is toward the public only, and the composer says so.
    expect(landlordReviewProjection(review()).reviewerLabel).toBe('Tenant of B4');
  });
});
