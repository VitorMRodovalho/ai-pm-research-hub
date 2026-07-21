/**
 * Contract: #1424 — the send-notification-email EF (notification/digest lane) must
 * stop blowing the shared Resend 100/day quota on Saturday digest bursts.
 *
 * Two structural guarantees are locked here (both source-pattern, always run —
 * the EF has no DB fixture harness; the Deno EF Check job type-checks it):
 *
 *   Fase A — coalesce by recipient: the run groups pending transactional_immediate
 *   notifications by recipient_id and sends ONE email per person listing the N
 *   simple notifications (was 1 email PER ROW — volunteer_agreement_signed hit
 *   7.3 emails/pessoa). Rich JSON digests + onboarding-prep + governance types
 *   still render individually (they carry dedicated blocks).
 *
 *   Fase B — shared daily cap: before sending, the run counts the day's real
 *   sends across ALL lanes from email_webhook_events (event_type='email.sent')
 *   and stops at a safe headroom (DAILY_SEND_CAP < 100). Excess rows keep
 *   email_sent_at NULL and drain on the next 5-minute cron run or the next day.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const EF = readFileSync(
  resolve(ROOT, 'supabase/functions/send-notification-email/index.ts'),
  'utf8',
);

test('#1424 Fase B: DAILY_SEND_CAP declared with safe headroom under the Resend 100/day quota', () => {
  const m = EF.match(/const\s+DAILY_SEND_CAP\s*=\s*(\d+)/);
  assert.ok(m, 'EF must declare const DAILY_SEND_CAP.');
  const cap = Number(m[1]);
  assert.ok(cap > 0 && cap < 100,
    `DAILY_SEND_CAP must leave headroom under 100 (got ${cap}).`);
});

test('#1424 Fase B: cap counts the day\'s real sends from email_webhook_events (shared cross-lane truth)', () => {
  assert.ok(/email_webhook_events/.test(EF),
    'EF must read email_webhook_events to count the day\'s sends.');
  assert.ok(/event_type['"]?\s*,\s*['"]email\.sent['"]/.test(EF),
    'EF must filter email_webhook_events to event_type = \'email.sent\'.');
  assert.ok(/DAILY_SEND_CAP\s*-\s*sentToday/.test(EF),
    'EF must compute the remaining budget as DAILY_SEND_CAP - sentToday.');
});

test('#1424 Fase B: run defers once the daily budget is exhausted (does not blast past the cap)', () => {
  assert.ok(/sent\s*>=\s*dailyBudget/.test(EF),
    'EF must stop sending once sent >= dailyBudget.');
  assert.ok(/deferred/.test(EF),
    'EF must track deferred rows (left email_sent_at NULL for the next run).');
});

test('#1424 Fase B: transactional/operational mail wins the remaining budget over digests', () => {
  assert.ok(/LOW_PRIORITY_TYPES/.test(EF),
    'EF must define LOW_PRIORITY_TYPES so digests yield to urgent mail when the budget is tight.');
  assert.ok(/\.sort\(/.test(EF) && /Urgent/.test(EF),
    'EF must order recipients so urgent (non-low-priority) mail is served first.');
});

test('#1424 Fase A: run groups pending notifications by recipient (coalesce), not 1-email-per-row', () => {
  assert.ok(/const\s+groups\s*=\s*new\s+Map/.test(EF),
    'EF must build a per-recipient group Map.');
  assert.ok(/recipient_id/.test(EF),
    'EF must group by recipient_id.');
  // The old 1-per-row anti-pattern iterated notifications and sent inside the loop.
  assert.ok(/orderedRecipients/.test(EF),
    'EF must iterate recipients (coalesced), not raw notification rows, when sending.');
});

test('#1424 Fase A: a coalesced multi-notification email is built and covers all rows in one send', () => {
  assert.ok(/function\s+buildCoalescedHtml\s*\(/.test(EF),
    'EF must declare buildCoalescedHtml for the multi-notification list email.');
  assert.ok(/coalesced-notification\//.test(EF),
    'EF must use a coalesced Idempotency-Key for the grouped email.');
  // Every row the email covered is marked sent in one batch update.
  assert.ok(/\.update\(\{\s*email_sent_at[\s\S]{0,60}\}\)\s*\.in\(\s*['"]id['"]\s*,/.test(EF),
    'EF must mark ALL covered rows sent via .in(\'id\', ids) after a successful send.');
});

test('#1424 Fase A: rich digests + onboarding-prep + governance still render individually', () => {
  assert.ok(/ALWAYS_INDIVIDUAL_TYPES/.test(EF),
    'EF must define ALWAYS_INDIVIDUAL_TYPES (types excluded from coalescing).');
  assert.ok(/RICH_DIGEST_TYPES/.test(EF),
    'EF must define RICH_DIGEST_TYPES so weekly digests keep their dedicated rich rendering.');
  assert.ok(/WEEKLY_MEMBER_DIGEST_TYPE/.test(EF) && /WEEKLY_TRIBE_DIGEST_LEADER_TYPE/.test(EF),
    'Both rich weekly digest types must be excluded from coalescing.');
});

test('#1424 Fase A: fetch window is wide enough to coalesce a recipient burst in one run', () => {
  const m = EF.match(/\.limit\((\d+)\)/);
  assert.ok(m, 'EF must cap the pending fetch with .limit(N).');
  assert.ok(Number(m[1]) >= 100,
    `fetch limit must be >= 100 so a recipient's same-event burst lands in one run (got ${m[1]}).`);
});

test('#1424 regression: suppress_all opt-out + candidate-facing operational bypass preserved', () => {
  // Guards ADR-0022 W2 Leaf 6 survives the coalescing refactor.
  assert.ok(/OPERATIONAL_CANDIDATE_FACING\.has\(notif\.type\)/.test(EF),
    'EF must still compute isOperationalCandidateFacing per notification.');
  assert.ok(/suppress_all['"]?\s*&&\s*!isOperationalCandidateFacing/.test(EF),
    'EF suppress_all skip must still require !isOperationalCandidateFacing.');
});
