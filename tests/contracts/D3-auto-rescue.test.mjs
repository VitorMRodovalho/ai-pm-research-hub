/**
 * Contract: ÉPICO D — D3 auto-rescue de candidato convidado-preso ("fecha o loop").
 * SPEC: docs/specs/SPEC_D3_AUTO_RESCUE_UNBOOKED.md. Migration: 20260805000219.
 *
 * Adds the action layer the detector (#781, mig 208) only NOTIFIED about: a
 * candidate parked in interview_pending whose last invite aged past the booking
 * grace, with no future slot, is automatically RE-INVITED (cap=1), then escalated
 * to the GP. unbooked + no-show unified (anchored on the LAST invite, not the
 * age of the problem).
 *
 * Components (mig 219):
 *   1. selection_applications.interview_auto_rescue_count int NOT NULL DEFAULT 0 (cap=1).
 *   2. RPC selection_rescue_unbooked_invite(uuid) — SECDEF cron-aware, atomic, guards
 *      open cycle / interview_pending (P0024) / cap (P0025).
 *   3. Cron _selection_unbooked_rescue_cron() — SECDEF service-role-only, NOT scheduled
 *      (go-live gated on legal R1 copy + R5 booking-provider DPA).
 *   4. Detector fix: bucket B anchors on cutoff (no longer notifies an already-reinvited no-show).
 *   5. Invariant AI_unbooked_rescue_cap_respected (35 -> 36), baseline 0.
 *
 * Council: data-architect GO-w-changes (open-cycle guard; cutoff IS NOT NULL explicit;
 * bucket B anchor) + legal-counsel GO-w-changes (LGPD Art. 7º II). DB assertions are
 * read-only / early-RAISE guard probes — they NEVER call the RPC on a valid app (it
 * sends a real email), and do NOT pin volatile prod cohort counts.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');
const MIG = read('supabase/migrations/20260805000219_d3_auto_rescue_unbooked.sql');

// Slice the RPC body, anchored on CREATE FUNCTION (NOT on ROLLBACK comments that name a DROP).
const RPC = (() => {
  const m = MIG.match(/CREATE OR REPLACE FUNCTION public\.selection_rescue_unbooked_invite[\s\S]*?AS \$\$([\s\S]*?)\$\$;/);
  return m ? m[1] : '';
})();
const CRON = (() => {
  const m = MIG.match(/CREATE OR REPLACE FUNCTION public\._selection_unbooked_rescue_cron[\s\S]*?\$func\$([\s\S]*?)\$func\$;/);
  return m ? m[1] : '';
})();

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── Offline: migration shape ───────────────────────────────────────────────────
test('migration file exists', () => {
  assert.ok(MIG, 'migration 20260805000219 exists');
});

test('block 1 — adds interview_auto_rescue_count int NOT NULL DEFAULT 0 (cap=1, idempotent)', () => {
  assert.match(MIG, /ADD COLUMN IF NOT EXISTS interview_auto_rescue_count int NOT NULL DEFAULT 0/);
  assert.match(MIG, /COMMENT ON COLUMN public\.selection_applications\.interview_auto_rescue_count/);
});

test('block 2 — RPC is SECDEF / search_path empty / jsonb / cron-aware (ADR-0028)', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.selection_rescue_unbooked_invite\(p_application_id uuid\)/);
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.selection_rescue_unbooked_invite\(p_application_id uuid\)[\s\S]*?SECURITY DEFINER[\s\S]*?SET search_path = ''/);
  assert.match(MIG, /RETURNS jsonb/);
  // cron-aware gate verbatim from selection_rescue_stuck_interview (mig 104).
  assert.match(RPC, /current_setting\('request\.jwt\.claims', true\) IS NULL OR auth\.role\(\) = 'service_role'/);
  assert.match(RPC, /v_is_cron := true/);
});

test('block 2 — RPC authority ladder (manage_member OR committee lead) on the manual path', () => {
  assert.match(RPC, /IF NOT v_is_cron THEN/);
  assert.match(RPC, /can_by_member\(v_caller\.id, 'manage_member'::text\)/);
  assert.match(RPC, /FROM public\.selection_committee/);
  assert.match(RPC, /role = 'lead'/);
});

test('block 2 — RPC guards: open cycle, interview_pending (P0024), cap (P0025)', () => {
  assert.match(RPC, /v_cycle\.status <> 'open'/);
  assert.match(RPC, /Rescue only valid for open cycle/);
  assert.match(RPC, /v_app\.status <> 'interview_pending'/);
  assert.match(RPC, /USING ERRCODE = 'P0024'/);
  assert.match(RPC, /v_app\.interview_auto_rescue_count >= 1/);
  assert.match(RPC, /USING ERRCODE = 'P0025'/);
});

test('block 2 — RPC increments count + clears cutoff, then re-dispatches notify ATOMICALLY (not in EXCEPTION)', () => {
  assert.match(RPC, /interview_auto_rescue_count = interview_auto_rescue_count \+ 1/);
  assert.match(RPC, /cutoff_approved_email_sent_at = NULL/);
  assert.match(RPC, /v_notify := public\.notify_selection_cutoff_approved\(p_application_id\)/);
  // notify must NOT be wrapped in a BEGIN/EXCEPTION (atomic: a notify RAISE rolls the rescue back).
  const notifyIdx = RPC.indexOf('notify_selection_cutoff_approved(p_application_id)');
  const before = RPC.slice(0, notifyIdx);
  // the only EXCEPTION in the RPC body must be absent (the RPC has no per-statement catch).
  assert.ok(!/EXCEPTION\s+WHEN/.test(RPC), 'RPC body must not catch exceptions (atomic re-dispatch)');
  assert.ok(notifyIdx > 0 && before.length > 0);
});

test('block 2 — audit row carries legal basis + trigger_type + dispatch_source (legal-counsel R4)', () => {
  assert.match(RPC, /'selection\.unbooked_invite_rescued'/);
  assert.match(RPC, /LGPD Art\. 7º II — procedimento preliminar de seleção voluntária/);
  assert.match(RPC, /'auto_rescue_never_booked'/);
  assert.match(RPC, /'auto_rescue_noshow'/);
  assert.match(RPC, /'dispatch_source', CASE WHEN v_is_cron THEN 'cron' ELSE 'manual' END/);
});

test('block 2 — grant model mirrors selection_rescue_stuck_interview (REVOKE PUBLIC+anon; GRANT authenticated+service_role)', () => {
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.selection_rescue_unbooked_invite\(uuid\) FROM PUBLIC, anon;/);
  assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\.selection_rescue_unbooked_invite\(uuid\) TO authenticated, service_role;/);
});

test('block 3 — cron is SECDEF service-role-only, predicate anchors on cutoff + cap + no future slot', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\._selection_unbooked_rescue_cron\(\)/);
  assert.match(CRON, /a\.status = 'interview_pending'/);
  assert.match(CRON, /c\.status = 'open'/);
  assert.match(CRON, /a\.cutoff_approved_email_sent_at IS NOT NULL/);     // data-architect blocker 2
  assert.match(CRON, /a\.cutoff_approved_email_sent_at < now\(\) - v_grace/);
  assert.match(CRON, /a\.interview_auto_rescue_count < 1/);               // cap
  assert.match(CRON, /a\.interview_reschedule_requested_at IS NULL/);
  assert.match(CRON, /si\.status IN \('scheduled', 'rescheduled'\)/);
  assert.match(CRON, /si\.scheduled_at > now\(\)/);
  assert.match(CRON, /LIMIT 20/);
  assert.match(CRON, /PERFORM public\.selection_rescue_unbooked_invite\(v_app\.app_id\)/);
  // service-role-only grant + anon explicitly revoked (Supabase: REVOKE FROM PUBLIC does NOT drop anon).
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\._selection_unbooked_rescue_cron\(\) FROM PUBLIC, anon, authenticated;/);
  assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\._selection_unbooked_rescue_cron\(\) TO service_role;/);
});

test('block 3 — cron is NOT scheduled (go-live gated on legal R1 + R5)', () => {
  // No cron.schedule for this job in the migration (the only allowed mention is the COMMENT/follow-up note).
  assert.ok(!/SELECT cron\.schedule\(\s*'selection-unbooked-rescue-daily'/.test(MIG),
    'cron.schedule for selection-unbooked-rescue-daily must NOT be present (go-live gated)');
  assert.ok(!/PERFORM cron\.schedule\(\s*'selection-unbooked-rescue-daily'/.test(MIG),
    'PERFORM cron.schedule for the job must NOT be present');
  assert.match(MIG, /GO-LIVE GATED/);
});

test('block 4 — detector bucket B gains the cutoff anchor (no re-notify of already-reinvited no-show)', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.detect_stuck_selection_funnel/);
  assert.match(MIG, /AND a\.cutoff_approved_email_sent_at < now\(\) - v_booking_grace/);
});

test('block 5 — invariant AI_unbooked_rescue_cap_respected appended (medium severity, baseline 0)', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.check_schema_invariants\(\)/);
  assert.match(MIG, /'AI_unbooked_rescue_cap_respected'::text/);
  assert.match(MIG, /WHERE interview_auto_rescue_count > 1/);
  assert.match(MIG, /'medium'::text/);
});

// ── DB-gated: read-only / early-RAISE guard probes (no email fired) ──────────────
const sb = dbGated ? createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } }) : null;

test('DB: column interview_auto_rescue_count exists, NOT NULL, default 0', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb.rpc('check_schema_invariants');
  assert.ok(!error, error?.message);
  // The AI invariant is present and clean (cap respected across the live table).
  const ai = data.find(r => r.invariant_name === 'AI_unbooked_rescue_cap_respected');
  assert.ok(ai, 'AI_unbooked_rescue_cap_respected present');
  assert.equal(ai.severity, 'medium');
  assert.equal(ai.violation_count, 0, 'cap=1 respected (baseline 0)');
});

test('DB: invariant total is 38, 0 violations', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb.rpc('check_schema_invariants');
  assert.ok(!error, error?.message);
  // #785 PR-2 (mig 232) added AJ_confidential_visibility_gate_present → 37; #333 (mig 259) added AK_voice_biometric_consent_enforcement → 38.
  assert.equal(data.length, 38, `expected 38 invariants, got ${data.length}`);
  const offenders = data.filter(x => x.violation_count > 0).map(x => `${x.invariant_name}=${x.violation_count}`);
  assert.equal(offenders.length, 0, `unexpected violations: ${offenders.join(', ')}`);
});
