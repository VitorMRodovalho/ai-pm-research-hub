/**
 * Contract: #472 correction #1 (re-scoped) — sync_calendar_booking_to_interview
 * matching robustness + the updated_at 42703 bug.
 *
 * Approach A (a Google-Calendar PULL EF) is infeasible (no Calendar scope; DwD
 * blocked by ADR-0064), so corr-1 hardens the existing booking-sync RPC:
 *   1) updated_at 42703 fix — the idempotent re-fire branch wrote
 *      `UPDATE selection_interviews SET ... updated_at = now()`, but
 *      selection_interviews has NO updated_at column → every re-fire threw
 *      42703 undefined_column. Removed.
 *   2) robust invitee matching — was PRIMARY-email only; now also matches when
 *      the calendar guest email and the application email PROVABLY belong to the
 *      SAME member (member_emails bridge) — zero cross-candidate risk, direct
 *      primary match always preferred.
 *
 * NOTE: the LIVE booking ingress is src/pages/api/calendar-webhook.ts; this RPC
 * is the older issue-#116 surface. Mirroring the matching into the webhook (TS)
 * is the production-effect follow-up.
 *
 * Cross-ref: issue #472 (B1); ADR-0073; migration 20260516920000 (prior body).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000091_472_corr1_calendar_booking_match_and_updated_at.sql');
const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
// strip line comments so assertions match real SQL, not documentation that
// intentionally mentions the old anti-pattern.
const mig = migRaw.replace(/^\s*--.*$/gm, '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

function fnBody(src, name) {
  const re = new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\b[\\s\\S]*?\\$function\\$([\\s\\S]*?)\\$function\\$`, 'i');
  const m = src.match(re);
  return m ? m[1] : null;
}

// ── STATIC ──────────────────────────────────────────────────────────────────
test('472-c1 static: migration 20260805000091 exists', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000091 present');
});

test('472-c1 static: updated_at REMOVED from the selection_interviews idempotent UPDATE (42703 fix)', () => {
  const body = fnBody(mig, 'sync_calendar_booking_to_interview');
  assert.ok(body, 'sync_calendar_booking_to_interview defined');
  // the interviews re-fire UPDATE must set ONLY scheduled_at
  assert.match(body, /UPDATE public\.selection_interviews\s+SET scheduled_at = v_scheduled_at\s+WHERE id = v_existing_id/,
    'idempotent UPDATE sets only scheduled_at');
  // forward defense: the exact pre-fix bug shape must NOT reappear
  assert.ok(
    !/UPDATE public\.selection_interviews\s+SET[^;]*updated_at/i.test(body),
    'REGRESSION: selection_interviews UPDATE writes updated_at again (#472 corr.1 — column does not exist → 42703)'
  );
});

test('472-c1 static: robust matching — primary OR same-member alternate (member_emails bridge)', () => {
  const body = fnBody(mig, 'sync_calendar_booking_to_interview');
  // resolves guest -> member
  assert.match(body, /SELECT me\.member_id INTO v_guest_member_id[\s\S]*?FROM public\.member_emails me\s+WHERE me\.email = v_guest_email::citext/,
    'resolves guest email to a member via member_emails');
  // primary match retained
  assert.match(body, /LOWER\(TRIM\(a\.email\)\) = v_guest_email/, 'direct primary-email match retained');
  // alternate bridge: same member_id on both sides
  assert.match(body, /v_guest_member_id IS NOT NULL\s*\n?\s*AND EXISTS \(\s*\n?\s*SELECT 1 FROM public\.member_emails me2\s+WHERE me2\.member_id = v_guest_member_id/,
    'alternate match requires the application email to belong to the SAME member (no cross-candidate risk)');
  // primary match preferred, then most-recently-opened cycle (avoids wrong-cycle
  // attachment when a returning member has apps in >1 open/active cycle), then newest app
  assert.match(body, /ORDER BY \(LOWER\(TRIM\(a\.email\)\) = v_guest_email\) DESC, c\.open_date DESC NULLS LAST, a\.created_at DESC/,
    'tie-break: primary match > most-recent open cycle > newest application');
});

test('472-c1 static: matched_by audit + secret gate + status promotion preserved', () => {
  const body = fnBody(mig, 'sync_calendar_booking_to_interview');
  assert.match(body, /v_matched_by text := 'primary'/, 'matched_by defaults to primary');
  assert.match(body, /v_matched_by := 'alternate'/, 'flags alternate match for the audit trail');
  assert.match(body, /'matched_by', v_matched_by/, 'matched_by surfaced in audit + return payload');
  // unchanged guards
  assert.match(body, /v_provided_secret <> v_expected_secret THEN\s*\n?\s*RETURN jsonb_build_object\('error','invalid secret'\)/, 'secret gate preserved');
  assert.match(body, /v_app\.status IN \('submitted','in_review','interview_pending'\)/, 'status-promotion guard preserved');
  assert.match(body, /'arm116\.calendar_booking_unmatched'/, 'unmatched audit preserved');
  assert.match(body, /'arm116\.calendar_booking_synced'/, 'synced audit preserved');
});

test('472-c1 static: NOTIFY pgrst reload', () => {
  assert.match(migRaw, /NOTIFY pgrst, 'reload schema'/);
});

// ── BEHAVIOURAL (DB-gated) ────────────────────────────────────────────────────
test('472-c1 behavioural: RPC is callable and the secret gate rejects a bad secret (read-only)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('sync_calendar_booking_to_interview', {
    p_payload: {
      secret: 'definitely-not-the-secret',
      guest_email: 'nobody@example.invalid',
      scheduled_at: '2026-06-02T12:00:00Z',
      calendar_event_id: 'contract-test-bad-secret',
    },
  });
  assert.ifError(error);
  assert.equal(data?.error, 'invalid secret', 'bad secret is rejected before any write');
});

// NOTE: live body == migration file is enforced by the global Phase-C
// rpc-body-drift gate (tests/contracts/...), so no per-function live-body
// re-check is needed here — the static asserts above lock the SQL shape.
