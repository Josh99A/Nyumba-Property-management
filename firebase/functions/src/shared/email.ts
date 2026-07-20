import { defineSecret } from 'firebase-functions/params';
import { CURRENCY } from './config';

/**
 * Resend API key. Lives in Secret Manager, never in the repository: functions
 * that send email declare it in their `secrets` list and the runtime injects
 * it as an environment variable. Rotating the key is
 * `firebase functions:secrets:set RESEND_API_KEY` plus a redeploy.
 */
export const RESEND_API_KEY = defineSecret('RESEND_API_KEY');

/** Every function whose code path can reach sendEmail must declare these. */
export const EMAIL_SECRETS = [RESEND_API_KEY];

/** The verified Resend sending domain — also where email links land. */
export const APP_ORIGIN = 'https://nyumba.online';

const FROM = 'Nyumba <notifications@nyumba.online>';

export interface OutboundEmail {
  to: string;
  subject: string;
  /** Body paragraphs/blocks already rendered by buildEmailHtml. */
  html: string;
  /**
   * Stable per business event (e.g. `receipt_<receiptId>`). Resend deduplicates
   * on it for 24 hours, which covers the backend job retry window: a worker
   * that crashed after the API accepted the send cannot email the person twice.
   */
  idempotencyKey: string;
}

/**
 * Sends one transactional email through Resend.
 *
 * Throws on transport failures and rate limits so the durable backend job
 * retries with its existing backoff. Rejections the API marks permanent (a
 * malformed address, a validation error) return without throwing: retrying
 * them would only burn attempts on an outcome that cannot change, and email
 * is a courtesy channel — the in-app record it points at already exists.
 */
export async function sendEmail(email: OutboundEmail): Promise<void> {
  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey) {
    throw new Error('RESEND_API_KEY is not configured for this function.');
  }
  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
      'Idempotency-Key': email.idempotencyKey,
    },
    body: JSON.stringify({
      from: FROM,
      to: [email.to],
      subject: email.subject,
      html: email.html,
    }),
  });
  if (response.ok) return;
  const detail = (await response.text().catch(() => '')).slice(0, 300);
  if (response.status === 429 || response.status >= 500) {
    throw new Error(`Resend transient failure (${response.status}): ${detail}`);
  }
  console.error(
    `Resend permanently rejected email ${email.idempotencyKey} (${response.status}): ${detail}`,
  );
}

/** UGX has no minor unit in practice, but amounts are stored in minor units. */
export function formatEmailMoney(amountMinor: number): string {
  const major = amountMinor / 100;
  return `${CURRENCY} ${major.toLocaleString('en-UG', {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  })}`;
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

export interface EmailRow {
  label: string;
  value: string;
}

export interface EmailContent {
  /** Greeting name; the greeting is omitted when absent. */
  recipientName?: string | null;
  heading: string;
  paragraphs: string[];
  /** Label/value facts (amounts, references) rendered as a table. */
  rows?: EmailRow[];
  /** Call-to-action button; links must stay on APP_ORIGIN. */
  cta?: { label: string; url: string };
}

/**
 * Renders the single branded layout every Nyumba email uses. Inline styles
 * only — email clients strip stylesheets — in the Midnight Navy / Terracotta
 * Gold palette the receipt PDF already established.
 */
export function buildEmailHtml(content: EmailContent): string {
  const greeting = content.recipientName
    ? `<p style="margin:0 0 16px">Hello ${escapeHtml(content.recipientName)},</p>`
    : '';
  const paragraphs = content.paragraphs
    .map((text) => `<p style="margin:0 0 16px">${escapeHtml(text)}</p>`)
    .join('');
  const rows = content.rows?.length
    ? `<table role="presentation" style="border-collapse:collapse;margin:0 0 16px">${content.rows
      .map(
        (row) =>
          `<tr><td style="padding:4px 24px 4px 0;color:#5F6B7A">${escapeHtml(row.label)}</td>`
          + `<td style="padding:4px 0;color:#101828;font-weight:600">${escapeHtml(row.value)}</td></tr>`,
      )
      .join('')}</table>`
    : '';
  const cta = content.cta
    ? `<p style="margin:24px 0"><a href="${escapeHtml(content.cta.url)}" `
      + 'style="background:#123A6F;color:#FFFFFF;text-decoration:none;padding:12px 24px;'
      + `border-radius:8px;display:inline-block;font-weight:600">${escapeHtml(content.cta.label)}</a></p>`
    : '';
  return (
    '<div style="background:#F4F6F8;padding:24px 12px;font-family:Segoe UI,Helvetica,Arial,sans-serif">'
    + '<div style="max-width:560px;margin:0 auto;background:#FFFFFF;border-radius:12px;overflow:hidden">'
    + '<div style="background:#123A6F;padding:20px 32px">'
    + '<span style="color:#FFFFFF;font-size:22px;font-weight:700">Nyumba</span>'
    + '<span style="color:#C98B2E;font-size:13px;display:block;margin-top:2px">Property management</span>'
    + '</div>'
    + `<div style="padding:32px;color:#101828;font-size:15px;line-height:1.6">`
    + `<h1 style="margin:0 0 16px;font-size:19px;color:#123A6F">${escapeHtml(content.heading)}</h1>`
    + greeting
    + paragraphs
    + rows
    + cta
    + '</div>'
    + '<div style="padding:16px 32px 24px;color:#5F6B7A;font-size:12px;border-top:1px solid #E4E7EC">'
    + `Sent by Nyumba · <a href="${APP_ORIGIN}" style="color:#123A6F">nyumba.online</a>. `
    + 'This is a service message about your Nyumba account or tenancy.'
    + '</div>'
    + '</div>'
    + '</div>'
  );
}
