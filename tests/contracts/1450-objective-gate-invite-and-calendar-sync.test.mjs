/**
 * Contract: #1450 — the interview-scheduling invite (and the raw-calendar backdoor that
 * materializes an interview) MUST be gated on the objective phase being complete
 * (objective_score_avg IS NOT NULL), the same canonical signal schedule_interview /
 * issue_interview_booking_token already enforce (P0003).
 *
 * Regression: VEP candidates advanced to interview scheduling BEFORE the objective phase.
 *   - notify_selection_cutoff_approved sent the raw booking URL selected by STATUS only
 *     (screening / interview_pending) on the manual/bulk dispatch path.
 *   - sync_calendar_booking_to_interview created a selection_interviews row + promoted
 *     submitted / interview_pending → interview_scheduled with NO objective gate (observed
 *     live: a researcher self-booked with objective_score_avg IS NULL).
 *
 * Fix (migration 20260805000469): both functions refuse when objective_score_avg IS NULL —
 * the invite RAISEs P0003 GATE_NO_SCORE; the webhook logs arm116.calendar_booking_premature
 * and returns a warning instead of creating the interview.
 *
 * Static test (always run) + forward-defense (no later migration drops either gate).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const FIX = '20260805000469_1450_objective_gate_invite_and_calendar_sync.sql';
const FIX_FILE = resolve(MIGRATIONS_DIR, FIX);

// Extract a CREATE OR REPLACE FUNCTION public.<name> ... $function$ ... $function$ block.
function fnBlock(body, name) {
  const re = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.${name}\\s*\\([\\s\\S]*?\\$function\\$[\\s\\S]*?\\$function\\$`,
    'i',
  );
  return body.match(re)?.[0] || '';
}

test('1450: fix migration exists', () => {
  assert.ok(existsSync(FIX_FILE), `migration must exist at ${FIX_FILE}`);
});

test('1450: notify_selection_cutoff_approved gates the invite on objective_score_avg', () => {
  const block = fnBlock(readFileSync(FIX_FILE, 'utf8'), 'notify_selection_cutoff_approved');
  assert.ok(block, 'notify_selection_cutoff_approved CREATE OR REPLACE block must be present');
  // The gate: refuse when the objective score has not been computed.
  assert.match(block, /objective_score_avg\s+IS\s+NULL/i,
    'must test objective_score_avg IS NULL');
  assert.match(block, /GATE_NO_SCORE/i, 'must raise the canonical GATE_NO_SCORE error');
  assert.match(block, /P0003/i, 'must use the P0003 errcode (parity with schedule_interview)');
  // The gate must sit AFTER the already_sent idempotency return (so a prior legitimate
  // send is still reported idempotently) and BEFORE the booking-URL resolution / dispatch.
  const idemIdx = block.search(/already_sent/i);
  const gateIdx = block.search(/objective_score_avg\s+IS\s+NULL/i);
  const dispatchIdx = block.search(/campaign_send_one_off/i);
  assert.ok(idemIdx >= 0 && gateIdx > idemIdx,
    'objective gate must come AFTER the already_sent idempotency return');
  assert.ok(dispatchIdx > gateIdx,
    'objective gate must come BEFORE the campaign_send_one_off dispatch');
});

test('1450: sync_calendar_booking_to_interview gates the raw-calendar backdoor', () => {
  const block = fnBlock(readFileSync(FIX_FILE, 'utf8'), 'sync_calendar_booking_to_interview');
  assert.ok(block, 'sync_calendar_booking_to_interview CREATE OR REPLACE block must be present');
  assert.match(block, /objective_score_avg\s+IS\s+NULL/i,
    'must test objective_score_avg IS NULL');
  assert.match(block, /arm116\.calendar_booking_premature/i,
    'must log the premature-booking audit action');
  // The gate must sit BEFORE the interview INSERT so a scoreless booking never materializes.
  const gateIdx = block.search(/objective_score_avg\s+IS\s+NULL/i);
  const insertIdx = block.search(/INSERT\s+INTO\s+public\.selection_interviews/i);
  const existingIdx = block.search(/v_existing_id\s+IS\s+NOT\s+NULL/i);
  assert.ok(gateIdx >= 0 && insertIdx > gateIdx,
    'objective gate must come BEFORE the selection_interviews INSERT');
  // ...and AFTER the existing-event idempotency branch, so a reschedule of an
  // already-created interview is never blocked.
  assert.ok(existingIdx >= 0 && gateIdx > existingIdx,
    'objective gate must come AFTER the existing-interview idempotency branch');
});

function subsequentMigrations() {
  const all = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort();
  const idx = all.indexOf(FIX);
  assert.ok(idx >= 0, 'fix migration must be in the registry');
  return all.slice(idx + 1).map((f) => ({ name: f, body: readFileSync(resolve(MIGRATIONS_DIR, f), 'utf8') }));
}

test('1450: no later migration drops either objective gate', () => {
  const offenders = [];
  for (const m of subsequentMigrations()) {
    const notify = fnBlock(m.body, 'notify_selection_cutoff_approved');
    if (notify && !/objective_score_avg\s+IS\s+NULL/i.test(notify)) {
      offenders.push(`${m.name} (notify_selection_cutoff_approved lost the objective gate)`);
    }
    const sync = fnBlock(m.body, 'sync_calendar_booking_to_interview');
    if (sync && !/objective_score_avg\s+IS\s+NULL/i.test(sync)) {
      offenders.push(`${m.name} (sync_calendar_booking_to_interview lost the objective gate)`);
    }
  }
  assert.equal(offenders.length, 0,
    `both invite paths must keep the objective_score_avg gate. Offenders: ${offenders.join(', ')}`);
});
