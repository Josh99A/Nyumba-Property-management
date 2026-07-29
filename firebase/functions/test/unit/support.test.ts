import { describe, expect, it } from 'vitest';
import { supportOpen, supportReply, supportUpdateStatus } from '../../src/commands/support';
import {
  SUPPORT_MAX_ATTACHMENTS,
  SUPPORT_MAX_OPEN_TICKETS,
} from '../../src/shared/config';

const validOpen = {
  subject: 'Payment not reconciling',
  category: 'billing',
  body: 'My tenant paid on the 3rd but the balance has not moved.',
  appVersion: '1.4.2+31',
  platform: 'android',
};

describe('support.open payload', () => {
  it('accepts a well-formed ticket and defaults attachments to none', () => {
    const parsed = supportOpen.payloadSchema.safeParse(validOpen);
    expect(parsed.success).toBe(true);
    expect(parsed.success && parsed.data.stagedAttachmentPaths).toEqual([]);
  });

  it('rejects an unknown category rather than filing it under other', () => {
    expect(
      supportOpen.payloadSchema.safeParse({ ...validOpen, category: 'urgent' }).success,
    ).toBe(false);
  });

  it('rejects a client-chosen priority', () => {
    // Priority is derived server-side. A payload field would be a field where
    // everyone picks urgent; `strictPayload` is what keeps it out.
    expect(
      supportOpen.payloadSchema.safeParse({ ...validOpen, priority: 'high' }).success,
    ).toBe(false);
  });

  it('rejects an empty subject or body', () => {
    expect(supportOpen.payloadSchema.safeParse({ ...validOpen, subject: '   ' }).success).toBe(false);
    expect(supportOpen.payloadSchema.safeParse({ ...validOpen, body: '' }).success).toBe(false);
  });

  it('accepts the attachment ceiling and rejects one more', () => {
    const staged = (count: number) =>
      Array.from({ length: count }, (_, index) => `uploads/landlord_1/shot-${index}.webp`);
    expect(
      supportOpen.payloadSchema.safeParse({
        ...validOpen,
        stagedAttachmentPaths: staged(SUPPORT_MAX_ATTACHMENTS),
      }).success,
    ).toBe(true);
    expect(
      supportOpen.payloadSchema.safeParse({
        ...validOpen,
        stagedAttachmentPaths: staged(SUPPORT_MAX_ATTACHMENTS + 1),
      }).success,
    ).toBe(false);
  });
});

describe('support.reply payload', () => {
  it('accepts a reply and rejects a blank one', () => {
    expect(supportReply.payloadSchema.safeParse({ body: 'Here it is.' }).success).toBe(true);
    expect(supportReply.payloadSchema.safeParse({ body: '   ' }).success).toBe(false);
  });

  it('caps a single reply at 2000 characters', () => {
    expect(supportReply.payloadSchema.safeParse({ body: 'a'.repeat(2_000) }).success).toBe(true);
    expect(supportReply.payloadSchema.safeParse({ body: 'a'.repeat(2_001) }).success).toBe(false);
  });
});

describe('support.updateStatus payload', () => {
  it('accepts every status a ticket can be moved to', () => {
    for (const status of ['in_progress', 'awaiting_landlord', 'resolved', 'closed']) {
      expect(supportUpdateStatus.payloadSchema.safeParse({ status }).success).toBe(true);
    }
  });

  it('refuses to move a ticket back to open', () => {
    // Nothing transitions back to `open`; a reopened ticket is `in_progress`,
    // which is what is actually true of it.
    expect(supportUpdateStatus.payloadSchema.safeParse({ status: 'open' }).success).toBe(false);
  });
});

describe('support command shapes', () => {
  it('creates on open and edits on reply, so replies carry a version', () => {
    // A reply without optimistic concurrency would let two devices append to the
    // same thread and lose one of the messages.
    expect(supportOpen.expectedVersionMode).toBe('create');
    expect(supportReply.expectedVersionMode).toBe('edit');
    expect(supportUpdateStatus.expectedVersionMode).toBe('edit');
  });

  it('keeps the open-ticket cap above one, so the cap can never mean "no support"', () => {
    expect(SUPPORT_MAX_OPEN_TICKETS).toBeGreaterThan(1);
  });
});
