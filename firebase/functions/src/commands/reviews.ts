import { Timestamp, type Firestore, type Transaction } from 'firebase-admin/firestore';
import { z } from 'zod';
import { requirePlatformAdmin } from '../shared/actor';
import { bumpVersion, newAggregate, requireAbsent, requireAggregate } from '../shared/aggregates';
import { landlordPublicToken } from '../shared/canonical';
import {
  COLLECTIONS,
  LANDLORD_PORTAL_SECTIONS,
  TENANT_PORTAL_SECTIONS,
} from '../shared/collections';
import {
  REVIEW_EDIT_WINDOW_DAYS,
  REVIEW_MIN_TENANCY_DAYS,
  REVIEW_POST_TENANCY_WINDOW_DAYS,
} from '../shared/config';
import { DomainError } from '../shared/errors';
import { createJob, longText, strictPayload, type CommandHandler } from '../shared/handlers';
import {
  landlordReviewProjection,
  publicReviewProjection,
  tenantReviewProjection,
  type ReviewRecord,
} from '../shared/projections';
import {
  applyReview,
  emptyDimensionScores,
  ratingDocument,
  readTotals,
  REVIEW_DIMENSIONS,
  type DimensionScores,
  type RatingTotals,
} from '../shared/ratings';

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Tenant reviews of a landlord.
 *
 * The aggregate ID is deliberately the **lease ID**. That single choice carries
 * most of this file's integrity guarantees:
 *
 *  - One review per tenancy, enforced by document existence rather than by a
 *    duplicate query (contrast `applicationSubmit`, which fetches ten documents
 *    and filters in code).
 *  - Idempotent outbox replays: `requireAbsent` absorbs the retry.
 *  - Eligibility is provable from the ID alone — the lease it names either
 *    belongs to this tenant or the command fails.
 *
 * A tenant holding two leases from one landlord may review twice, which is
 * correct: those are two tenancies with two separate experiences.
 */
const dimensionScore = z.number().int().min(1).max(5).optional();

const submitSchema = strictPayload({
  overall: z.number().int().min(1).max(5),
  responsiveness: dimensionScore,
  maintenance: dimensionScore,
  listingAccuracy: dimensionScore,
  depositFairness: dimensionScore,
  body: longText.optional(),
});

type SubmitPayload = z.infer<typeof submitSchema>;

function dimensionsFrom(payload: Partial<SubmitPayload>): DimensionScores {
  const scores = emptyDimensionScores();
  for (const dimension of REVIEW_DIMENSIONS) {
    const value = payload[dimension];
    if (typeof value === 'number') scores[dimension] = value;
  }
  return scores;
}

/** Only a published review moves the average. */
function countsTowardRating(status: string): boolean {
  return status === 'published';
}

interface LeaseFacts {
  landlordId: string;
  unitId: string;
  activatedAt: Timestamp;
  endedAt: Timestamp | null;
  status: string;
}

/**
 * Loads the lease named by the aggregate ID and proves this actor may review it.
 *
 * `landlordId` is taken from the lease and never from the payload — a client
 * that could name its own subject could review a landlord it never rented from,
 * which is the one attack that would make the whole corpus worthless.
 */
function requireReviewableLease(
  data: Record<string, unknown> | undefined,
  actorUid: string,
  now: Timestamp,
): LeaseFacts {
  if (!data || data.isDeleted === true) throw new DomainError('NOT_FOUND');
  if (data.tenantUserUid !== actorUid) throw new DomainError('PERMISSION_DENIED');
  const activatedAt = data.activatedAt;
  if (!(activatedAt instanceof Timestamp)) {
    throw new DomainError('VALIDATION_FAILED', { reason: 'tenancyNeverStarted' });
  }
  const status = String(data.status ?? '');
  const endedAt = data.endedAt instanceof Timestamp ? data.endedAt : null;

  if (status === 'ended' || endedAt !== null) {
    // A finished tenancy is reviewable at any tenure — a stay cut short after
    // three weeks is often the most informative review there is, and
    // `stayMonths` tells readers how long it lasted. What it is not is
    // reviewable forever: past the window the landlord has no realistic chance
    // to answer and the reader has no idea whether it still describes them.
    const deadline = (endedAt ?? activatedAt).toMillis()
      + REVIEW_POST_TENANCY_WINDOW_DAYS * DAY_MS;
    if (now.toMillis() > deadline) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'reviewWindowClosed' });
    }
  } else if (status === 'active' || status === 'noticeGiven') {
    // Still living there: require real tenure first. Week-one reviews are
    // written mid-dispute, before anything about the landlord's actual conduct
    // over a tenancy can be known.
    if (now.toMillis() - activatedAt.toMillis() < REVIEW_MIN_TENANCY_DAYS * DAY_MS) {
      throw new DomainError('VALIDATION_FAILED', {
        reason: 'tenancyTooNew',
        eligibleAt: activatedAt.toMillis() + REVIEW_MIN_TENANCY_DAYS * DAY_MS,
      });
    }
  } else {
    throw new DomainError('VALIDATION_FAILED', { reason: 'tenancyNotReviewable' });
  }

  return {
    landlordId: String(data.landlordId ?? ''),
    unitId: String(data.unitId ?? ''),
    activatedAt,
    endedAt,
    status,
  };
}

/** Whole months lived in the unit, floored at one. */
function stayMonthsOf(lease: LeaseFacts, now: Timestamp): number {
  const until = lease.endedAt ?? now;
  const months = (until.toMillis() - lease.activatedAt.toMillis()) / (30.44 * DAY_MS);
  return Math.max(1, Math.round(months));
}

/**
 * Writes one review to every surface that must reflect it.
 *
 * The public mirror is *deleted* rather than downgraded when a review stops
 * being published. A withdrawn or moderated review that lingers publicly with a
 * status field nobody filters on is the failure mode this avoids.
 */
function fanOutReview(
  tx: Transaction,
  db: Firestore,
  review: ReviewRecord,
  landlordToken: string,
): void {
  tx.set(db.collection(COLLECTIONS.landlordReviews).doc(review.id), review);
  tx.set(
    db.collection(COLLECTIONS.tenantPortals).doc(review.reviewerUid)
      .collection(TENANT_PORTAL_SECTIONS.reviews).doc(review.id),
    tenantReviewProjection(review),
  );
  tx.set(
    db.collection(COLLECTIONS.landlordPortals).doc(review.landlordId)
      .collection(LANDLORD_PORTAL_SECTIONS.reviews).doc(review.id),
    landlordReviewProjection(review),
  );
  const publicRef = db.collection(COLLECTIONS.publicReviews).doc(review.id);
  if (review.status === 'published') {
    tx.set(publicRef, publicReviewProjection(review, landlordToken));
  } else {
    tx.delete(publicRef);
  }
}

/**
 * Rewrites both rating aggregates and schedules the listing badge refresh.
 *
 * Badges are *not* stamped here. A landlord's live listing count is unbounded,
 * so writing them inside this transaction would make a single review's cost
 * scale with the size of the landlord's portfolio and eventually blow the
 * transaction's write limit. A badge may lag a few seconds; a failed review
 * submission may not.
 */
function writeRatings(
  tx: Transaction,
  db: Firestore,
  landlordId: string,
  landlordToken: string,
  totals: RatingTotals,
  previous: Record<string, unknown> | undefined,
  now: Timestamp,
  jobId: string,
): void {
  const privateDoc = ratingDocument(landlordId, totals, now, previous?.createdAt);
  tx.set(db.collection(COLLECTIONS.landlordRatings).doc(landlordId), privateDoc);
  tx.set(db.collection(COLLECTIONS.publicLandlordRatings).doc(landlordToken), {
    ...ratingDocument(landlordToken, totals, now, previous?.createdAt),
    landlordToken,
  });
  createJob(tx, db, jobId, 'refreshLandlordRatingBadges', { landlordId }, now);
}

/** Reads the current totals for a landlord alongside the document they came from. */
async function loadRatings(
  tx: Transaction,
  db: Firestore,
  landlordId: string,
): Promise<{ totals: RatingTotals; previous: Record<string, unknown> | undefined }> {
  const snapshot = await tx.get(db.collection(COLLECTIONS.landlordRatings).doc(landlordId));
  const previous = snapshot.data();
  return { totals: readTotals(previous), previous };
}

function loadReview(
  snapshot: FirebaseFirestore.DocumentSnapshot,
  expectedVersion: number | undefined,
): ReviewRecord {
  return requireAggregate<ReviewRecord>(snapshot, expectedVersion);
}

export const reviewSubmit: CommandHandler<SubmitPayload> = {
  payloadSchema: submitSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'create',
  async apply({ tx, db, actor, cmd, now }) {
    const leaseId = cmd.aggregateId!;
    const reviewRef = db.collection(COLLECTIONS.landlordReviews).doc(leaseId);
    const [reviewSnap, leaseSnap] = await Promise.all([
      tx.get(reviewRef),
      tx.get(db.collection(COLLECTIONS.leases).doc(leaseId)),
    ]);
    requireAbsent(reviewSnap);
    const lease = requireReviewableLease(leaseSnap.data(), actor.uid, now);

    // Labels for the landlord's copy. Sequential because the property is only
    // reachable through the unit, and both must be read before the first write.
    const unitSnap = await tx.get(db.collection(COLLECTIONS.units).doc(lease.unitId));
    const unit = unitSnap.data() ?? {};
    const propertyId = typeof unit.propertyId === 'string' ? unit.propertyId : null;
    const propertySnap = propertyId
      ? await tx.get(db.collection(COLLECTIONS.properties).doc(propertyId))
      : null;
    const { totals, previous } = await loadRatings(tx, db, lease.landlordId);

    const dimensions = dimensionsFrom(cmd.payload);
    const review: ReviewRecord = {
      ...newAggregate(leaseId, now),
      landlordId: lease.landlordId,
      reviewerUid: actor.uid,
      propertyName: String(propertySnap?.data()?.name ?? 'Property'),
      unitLabel: String(unit.label ?? 'Unit'),
      overall: cmd.payload.overall,
      dimensions,
      body: cmd.payload.body ?? null,
      status: 'published',
      flagState: 'none',
      landlordResponse: null,
      respondedAt: null,
      editableUntil: Timestamp.fromMillis(now.toMillis() + REVIEW_EDIT_WINDOW_DAYS * DAY_MS),
      stayMonths: stayMonthsOf(lease, now),
    };

    const landlordToken = landlordPublicToken(lease.landlordId);
    fanOutReview(tx, db, review, landlordToken);
    writeRatings(
      tx, db, lease.landlordId, landlordToken,
      applyReview(totals, review.overall, dimensions, 1),
      previous, now, `${cmd.commandId}_badges`,
    );
    createJob(tx, db, `${cmd.commandId}_notify`, 'notifyLandlordReview', { reviewId: leaseId }, now);

    return {
      status: 'applied',
      aggregateId: leaseId,
      serverVersion: 1,
      changedFields: ['overall', 'body', 'status'],
    };
  },
};

export const reviewUpdate: CommandHandler<SubmitPayload> = {
  payloadSchema: submitSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const reviewRef = db.collection(COLLECTIONS.landlordReviews).doc(cmd.aggregateId!);
    const reviewSnap = await tx.get(reviewRef);
    const current = loadReview(reviewSnap, cmd.expectedVersion);
    if (current.reviewerUid !== actor.uid) throw new DomainError('PERMISSION_DENIED');
    if (current.status !== 'published') {
      throw new DomainError('VALIDATION_FAILED', { reason: 'reviewNotEditable' });
    }
    if (current.editableUntil instanceof Timestamp
      && now.toMillis() > current.editableUntil.toMillis()) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'editWindowClosed' });
    }
    const { totals, previous } = await loadRatings(tx, db, current.landlordId);

    const dimensions = dimensionsFrom(cmd.payload);
    const next: ReviewRecord = {
      ...current,
      overall: cmd.payload.overall,
      dimensions,
      body: cmd.payload.body ?? null,
      ...bumpVersion(current, now),
    };
    const landlordToken = landlordPublicToken(current.landlordId);
    fanOutReview(tx, db, next, landlordToken);
    // Invert the old contribution before adding the new one; totals are kept
    // precisely so an edit is arithmetic rather than a full recount.
    const rebased = applyReview(
      applyReview(totals, current.overall, current.dimensions, -1),
      next.overall, dimensions, 1,
    );
    writeRatings(
      tx, db, current.landlordId, landlordToken, rebased, previous, now,
      `${cmd.commandId}_badges`,
    );

    return {
      status: 'applied',
      aggregateId: cmd.aggregateId!,
      serverVersion: next.version,
      changedFields: ['overall', 'body'],
    };
  },
};

export const reviewWithdraw: CommandHandler<Record<string, never>> = {
  payloadSchema: strictPayload({}),
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const reviewSnap = await tx.get(
      db.collection(COLLECTIONS.landlordReviews).doc(cmd.aggregateId!),
    );
    const current = loadReview(reviewSnap, cmd.expectedVersion);
    if (current.reviewerUid !== actor.uid) throw new DomainError('PERMISSION_DENIED');
    if (current.status === 'withdrawn') {
      throw new DomainError('VALIDATION_FAILED', { reason: 'reviewAlreadyWithdrawn' });
    }
    const { totals, previous } = await loadRatings(tx, db, current.landlordId);
    const next: ReviewRecord = { ...current, status: 'withdrawn', ...bumpVersion(current, now) };
    const landlordToken = landlordPublicToken(current.landlordId);
    fanOutReview(tx, db, next, landlordToken);
    writeRatings(
      tx, db, current.landlordId, landlordToken,
      countsTowardRating(current.status)
        ? applyReview(totals, current.overall, current.dimensions, -1)
        : totals,
      previous, now, `${cmd.commandId}_badges`,
    );
    return {
      status: 'applied',
      aggregateId: cmd.aggregateId!,
      serverVersion: next.version,
      changedFields: ['status'],
    };
  },
};

const respondSchema = strictPayload({ response: longText });

/**
 * The reviewed landlord's public reply.
 *
 * The highest-value feature in the system for landlord buy-in, and the one that
 * defuses most disputes: a landlord who can answer a bad review in public has
 * far less reason to demand it be taken down. Editable indefinitely — a stale
 * reply the landlord cannot correct helps nobody, and unlike the review it
 * carries no anonymity to protect.
 */
export const reviewRespond: CommandHandler<z.infer<typeof respondSchema>> = {
  payloadSchema: respondSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const reviewSnap = await tx.get(
      db.collection(COLLECTIONS.landlordReviews).doc(cmd.aggregateId!),
    );
    const current = loadReview(reviewSnap, cmd.expectedVersion);
    if (current.landlordId !== actor.uid) throw new DomainError('PERMISSION_DENIED');
    if (current.status !== 'published') {
      throw new DomainError('VALIDATION_FAILED', { reason: 'reviewNotPublished' });
    }
    const next: ReviewRecord = {
      ...current,
      landlordResponse: cmd.payload.response,
      respondedAt: now,
      ...bumpVersion(current, now),
    };
    fanOutReview(tx, db, next, landlordPublicToken(current.landlordId));
    createJob(
      tx, db, `${cmd.commandId}_notify`, 'notifyTenantReviewResponse',
      { reviewId: cmd.aggregateId! }, now,
    );
    return {
      status: 'applied',
      aggregateId: cmd.aggregateId!,
      serverVersion: next.version,
      changedFields: ['landlordResponse', 'respondedAt'],
    };
  },
};

const flagSchema = strictPayload({
  reasonCode: z.enum(['inaccurate', 'abusive', 'notMyTenant', 'personalData', 'spam']),
  note: longText.optional(),
});

/**
 * Raises a review for admin adjudication **without hiding it**.
 *
 * This is the single most important rule in the moderation design. If flagging
 * hid the review, every negative review would be flagged within a day and the
 * ratings would show nothing but the reviews landlords were happy with — a
 * system worse than having none, because it would look trustworthy. The review
 * stays up while a human decides.
 */
export const reviewFlag: CommandHandler<z.infer<typeof flagSchema>> = {
  payloadSchema: flagSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const reviewSnap = await tx.get(
      db.collection(COLLECTIONS.landlordReviews).doc(cmd.aggregateId!),
    );
    const current = loadReview(reviewSnap, cmd.expectedVersion);
    if (current.landlordId !== actor.uid) throw new DomainError('PERMISSION_DENIED');
    if (current.flagState === 'pending') {
      throw new DomainError('ALREADY_EXISTS', { reason: 'reviewAlreadyFlagged' });
    }
    const next: ReviewRecord = {
      ...current,
      flagState: 'pending',
      flagReasonCode: cmd.payload.reasonCode,
      flagNote: cmd.payload.note ?? null,
      flaggedAt: now,
      ...bumpVersion(current, now),
    };
    fanOutReview(tx, db, next, landlordPublicToken(current.landlordId));
    return {
      status: 'applied',
      aggregateId: cmd.aggregateId!,
      serverVersion: next.version,
      changedFields: ['flagState'],
    };
  },
};

const moderateSchema = strictPayload({
  decision: z.enum(['publish', 'hide', 'remove']),
  note: longText.optional(),
});

/**
 * Platform adjudication of a flagged or reported review.
 *
 * `expectedVersionMode: 'none'` on purpose: an admin acts from a server-read
 * queue, not from an offline mirror, and a moderation decision that fails on a
 * stale version leaves harmful content up while someone reloads a page.
 * The router writes the audit record for every command, so the decision is
 * already append-only without this handler doing anything extra.
 */
export const reviewModerate: CommandHandler<z.infer<typeof moderateSchema>> = {
  payloadSchema: moderateSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'none',
  async apply({ tx, db, actor, cmd, now }) {
    requirePlatformAdmin(actor);
    const reviewSnap = await tx.get(
      db.collection(COLLECTIONS.landlordReviews).doc(cmd.aggregateId!),
    );
    const current = requireAggregate<ReviewRecord>(reviewSnap, undefined, { allowDeleted: true });
    const status = cmd.payload.decision === 'publish'
      ? 'published'
      : cmd.payload.decision === 'hide' ? 'hidden' : 'removed';
    const { totals, previous } = await loadRatings(tx, db, current.landlordId);

    const next: ReviewRecord = {
      ...current,
      status,
      flagState: cmd.payload.decision === 'publish' ? 'dismissed' : 'upheld',
      moderationNote: cmd.payload.note ?? null,
      moderatedAt: now,
      moderatedBy: actor.uid,
      ...bumpVersion(current, now),
    };
    const landlordToken = landlordPublicToken(current.landlordId);
    fanOutReview(tx, db, next, landlordToken);

    const wasCounted = countsTowardRating(current.status);
    const isCounted = countsTowardRating(status);
    let rebased = totals;
    if (wasCounted && !isCounted) {
      rebased = applyReview(totals, current.overall, current.dimensions, -1);
    } else if (!wasCounted && isCounted) {
      rebased = applyReview(totals, current.overall, current.dimensions, 1);
    }
    writeRatings(
      tx, db, current.landlordId, landlordToken, rebased, previous, now,
      `${cmd.commandId}_badges`,
    );

    return {
      status: 'applied',
      aggregateId: cmd.aggregateId!,
      serverVersion: next.version,
      changedFields: ['status', 'flagState'],
      reasonCode: cmd.payload.decision,
    };
  },
};

const reportSchema = strictPayload({
  reasonCode: z.enum(['inaccurate', 'abusive', 'notMyTenant', 'personalData', 'spam']),
  note: longText.optional(),
});

/**
 * A reader reporting a public review.
 *
 * Routes into the same queue as a landlord flag and, likewise, does not hide
 * anything. Rate-limited by actor so the report button cannot itself become the
 * takedown mechanism it exists to replace.
 */
export const reviewReport: CommandHandler<z.infer<typeof reportSchema>> = {
  payloadSchema: reportSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'none',
  async apply({ tx, db, actor, cmd, now }) {
    const reviewRef = db.collection(COLLECTIONS.landlordReviews).doc(cmd.aggregateId!);
    const cutoff = Timestamp.fromMillis(now.toMillis() - DAY_MS);
    const [reviewSnap, recent] = await Promise.all([
      tx.get(reviewRef),
      tx.get(
        db.collection(COLLECTIONS.landlordReviews)
          .where('lastReportedBy', '==', actor.uid)
          .where('lastReportedAt', '>=', cutoff)
          .limit(6),
      ),
    ]);
    const current = requireAggregate<ReviewRecord>(reviewSnap, undefined);
    if (recent.size >= 5) throw new DomainError('RATE_LIMITED', { retryAfterSeconds: 86400 });
    if (current.reviewerUid === actor.uid) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'cannotReportOwnReview' });
    }
    const next: ReviewRecord = {
      ...current,
      flagState: current.flagState === 'none' ? 'pending' : current.flagState,
      reportCount: (typeof current.reportCount === 'number' ? current.reportCount : 0) + 1,
      lastReportedBy: actor.uid,
      lastReportedAt: now,
      ...bumpVersion(current, now),
    };
    fanOutReview(tx, db, next, landlordPublicToken(current.landlordId));
    return {
      status: 'applied',
      aggregateId: cmd.aggregateId!,
      serverVersion: next.version,
      changedFields: ['flagState', 'reportCount'],
    };
  },
};
