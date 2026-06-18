/**
 * Contract: ÉPICO D — D7 process_pending_vep_offer_reminders (candidate-facing PUSH:
 * lembra candidatos approved+OfferExtended a aceitar a oferta no volunteer.pmi.org).
 * #766 follow-up, PR DB-first. SPEC: docs/specs/SPEC_D7_VEP_OFFER_REMINDER.md.
 * Migration: 20260805000209.
 *
 * Pattern: p92 process_pending_reschedule_nudges (RPC/cron/template) + p157
 * trg_vep_acceptance_on_active (transition trigger on vep_status_raw). Single-fire
 * per application (vep_offer_reminder_sent_at); grace anchored on vep_offer_extended_at
 * stamped by a BEFORE trigger (re-offer resets the flag). No schema invariant.
 *
 * Council: data-architect GO-with-changes (BEFORE INSERT OR UPDATE trigger, WHEN on
 * NEW only + TG_OP/OLD body guard, search_path '', re-offer flag reset, grace 7d) +
 * legal-counsel GO-with-changes (Art.7 II procedimento preliminar; controller id +
 * finality + opt-out in template). 0 blockers.
 *
 * DB assertions are READ-ONLY and do NOT invoke the RPC (it sends real candidate
 * emails — single-fire, no dry-run param) nor pin the volatile prod cohort count.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');
const MIG = read('supabase/migrations/20260805000209_d7_vep_offer_accept_reminder.sql');

// Slice the RPC body, anchored on CREATE FUNCTION (NOT on ROLLBACK comments that
// name a DROP) — sediment: comment-naming a function breaks naive slicing.
const FN = (() => {
  const m = MIG.match(/CREATE OR REPLACE FUNCTION public\.process_pending_vep_offer_reminders[\s\S]*?\$func\$([\s\S]*?)\$func\$/);
  return m ? m[1] : '';
})();
const TRG = (() => {
  const m = MIG.match(/CREATE OR REPLACE FUNCTION public\._stamp_vep_offer_extended[\s\S]*?\$func\$([\s\S]*?)\$func\$/);
  return m ? m[1] : '';
})();

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── Offline: migration shape ───────────────────────────────────────────────────
test('migration exists; RPC is SECURITY DEFINER + search_path empty + RETURNS jsonb', () => {
  assert.ok(MIG, 'migration 20260805000209 exists');
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.process_pending_vep_offer_reminders\(\)/);
  assert.match(MIG, /SECURITY DEFINER/);
  assert.match(MIG, /SET search_path TO ''/);
  assert.match(MIG, /RETURNS jsonb/);
});

test('adds the 2 columns (offer anchor + single-fire flag)', () => {
  assert.match(MIG, /ADD COLUMN IF NOT EXISTS vep_offer_extended_at\s+timestamptz/);
  assert.match(MIG, /ADD COLUMN IF NOT EXISTS vep_offer_reminder_sent_at\s+timestamptz/);
});

test('stamp trigger: BEFORE INSERT OR UPDATE OF vep_status_raw, WHEN NEW=OfferExtended only', () => {
  // INSERT OR UPDATE (worker can INSERT a row already in OfferExtended — script-mapper.ts).
  assert.match(MIG, /BEFORE INSERT OR UPDATE OF vep_status_raw ON public\.selection_applications/);
  // WHEN references NEW only (Postgres forbids OLD in WHEN of an INSERT-bearing trigger).
  assert.match(MIG, /WHEN \(NEW\.vep_status_raw = 'OfferExtended'\)/);
  // The genuine-transition guard lives in the body via TG_OP/OLD.
  assert.match(TRG, /TG_OP = 'INSERT' OR OLD\.vep_status_raw IS DISTINCT FROM 'OfferExtended'/);
  assert.match(TRG, /NEW\.vep_offer_extended_at := now\(\)/);
});

test('re-offer resets the single-fire flag inside the trigger (Option A)', () => {
  assert.match(TRG, /NEW\.vep_offer_reminder_sent_at := NULL/);
});

test('backfill anchors existing OfferExtended rows on COALESCE(cutoff_email, created_at) — NOT reconciled_at', () => {
  assert.match(MIG, /SET vep_offer_extended_at = COALESCE\(cutoff_approved_email_sent_at, created_at\)/);
  // two independent predicate checks (newline-insensitive — survives reformatting)
  assert.match(MIG, /WHERE vep_status_raw = 'OfferExtended'/);
  assert.match(MIG, /AND vep_offer_extended_at IS NULL/);
  // reconciled_at is administrative — must not appear in the backfill SET expression
  // (it may appear in an explanatory comment, so scope the negative check to the COALESCE).
  const backfillCoalesce = (MIG.match(/SET vep_offer_extended_at = COALESCE\([^)]*\)/) || [''])[0];
  assert.ok(!/vep_reconciled_at/.test(backfillCoalesce), 'reconciled_at must not anchor the offer age');
});

test('seeds offer_accept_grace = 7 days as category=sla, idempotent', () => {
  assert.match(MIG, /'offer_accept_grace',\s*'7 days',\s*'sla'/);
  assert.match(MIG, /ON CONFLICT \(policy_key\) DO NOTHING/);
});

test('RPC reads the grace from sla_policies with a fallback literal (J4 config-driven)', () => {
  assert.match(FN, /policy_key = 'offer_accept_grace'/);
  assert.match(FN, /v_grace := COALESCE\(v_grace, interval '7 days'\)/);
});

test('cohort gate: approved + OfferExtended + single-fire NULL + stamped + past grace + open cycle + has email', () => {
  assert.match(FN, /a\.status = 'approved'/);
  assert.match(FN, /a\.vep_status_raw = 'OfferExtended'/);
  assert.match(FN, /a\.vep_offer_reminder_sent_at IS NULL/);
  assert.match(FN, /a\.vep_offer_extended_at IS NOT NULL/);
  assert.match(FN, /a\.vep_offer_extended_at < now\(\) - v_grace/);
  assert.match(FN, /c\.status = 'open'/);
  assert.match(FN, /a\.email IS NOT NULL/);
});

test('sends via campaign_send_one_off with the D7 template + minimized vars (first_name only)', () => {
  assert.match(FN, /public\.campaign_send_one_off\(/);
  assert.match(FN, /p_template_slug := 'vep_offer_accept_reminder'/);
  assert.match(FN, /p_variables := jsonb_build_object\('first_name', v_first_name\)/);
  // stamp AFTER send, per-row BEGIN/EXCEPTION (single-fire idempotency)
  assert.match(FN, /SET vep_offer_reminder_sent_at = now\(\)/);
});

test('auth: cron bypass + real user requires manage_member (p92 pattern → rpc-v4-auth satisfied)', () => {
  assert.match(FN, /auth\.role\(\) NOT IN \('service_role'\)/);
  assert.match(FN, /can_by_member\(\s*\(SELECT id FROM public\.members WHERE auth_id = auth\.uid\(\)\),\s*'manage_member'\s*\)/);
});

test('grants: REVOKE PUBLIC/anon/authenticated, GRANT authenticated + service_role', () => {
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.process_pending_vep_offer_reminders\(\) FROM public, anon, authenticated/);
  assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\.process_pending_vep_offer_reminders\(\) TO authenticated, service_role/);
});

test('cron registered daily 17:00 UTC, idempotent unschedule, invokes the RPC + NOTIFY', () => {
  assert.match(MIG, /cron\.unschedule\('nudge-vep-offer-accept-daily'\)/);
  assert.match(MIG, /'nudge-vep-offer-accept-daily',\s*'0 17 \* \* \*'/);
  assert.match(MIG, /SELECT public\.process_pending_vep_offer_reminders\(\)/);
  assert.match(MIG, /NOTIFY pgrst, 'reload schema'/);
});

test('NO schema invariant added (ephemeral notification pipeline)', () => {
  assert.ok(!/check_schema_invariants/.test(MIG), 'migration must not modify the invariant function');
});

test('template is trilingual with controller-id + finality + explicit opt-out (legal-counsel A/B/C)', () => {
  assert.match(MIG, /'vep_offer_accept_reminder'/);
  // 3 langs present in subject
  for (const lang of ['pt', 'en', 'es']) assert.match(MIG, new RegExp(`'${lang}',`));
  // (A) controller identification footer
  assert.match(MIG, /capítulo voluntário do PMI/);
  // (B) finality sentence
  assert.match(MIG, /sua candidatura ao Núcleo IA foi aprovada e há uma ação pendente/i);
  // (C) opt-out with explicit effect (application closed)
  assert.match(MIG, /Sua candidatura será encerrada/);
  // VEP step-by-step + spam note
  assert.match(MIG, /volunteer\.pmi\.org/);
  assert.match(MIG, /Accept Position/);
  assert.match(MIG, /donotreply@pmi\.org/);
});

test('grounding: no hardcoded cohort numbers as facts in the RPC body', () => {
  // Day-diffs are computed via EXTRACT; the only integer literals allowed are the grace
  // fallback (7) and the 86400 epoch divisor.
  assert.ok(!/\b(48|63|22|49|64|3)\b/.test(FN.replace(/86400/g, '')), 'no live cohort numbers hardcoded');
});

// ── DB-gated: live shape, READ-ONLY (does NOT invoke the RPC → no emails sent) ──
test('DB: both new columns are live on selection_applications', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // probe by selecting the columns (errors if missing)
  const { error } = await sb.from('selection_applications')
    .select('id, vep_offer_extended_at, vep_offer_reminder_sent_at').limit(1);
  assert.ok(!error, error?.message);
});

test('DB: offer_accept_grace live = 7 days', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.from('sla_policies').select('value_interval').eq('policy_key', 'offer_accept_grace').single();
  assert.ok(!error, error?.message);
  assert.equal(data.value_interval, '7 days');
});

test('DB: template live with all 3 languages in subject + body', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.from('campaign_templates')
    .select('subject, body_html, category').eq('slug', 'vep_offer_accept_reminder').single();
  assert.ok(!error, error?.message);
  assert.equal(data.category, 'operational');
  for (const lang of ['pt', 'en', 'es']) {
    assert.ok(data.subject[lang], `subject has ${lang}`);
    assert.ok(data.body_html[lang], `body_html has ${lang}`);
  }
});

test('DB: read-only cohort replication — every qualifying row is approved+OfferExtended (gate sanity, no send, no count pin)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // Mirror the RPC WHERE without invoking it. Pull candidates, assert each matches the
  // status/vep_status gate. Do NOT pin the count (volatile prod cohort).
  const { data, error } = await sb.from('selection_applications')
    .select('id, status, vep_status_raw, vep_offer_extended_at, vep_offer_reminder_sent_at, email')
    .eq('status', 'approved').eq('vep_status_raw', 'OfferExtended').is('vep_offer_reminder_sent_at', null);
  assert.ok(!error, error?.message);
  for (const r of data || []) {
    assert.equal(r.status, 'approved');
    assert.equal(r.vep_status_raw, 'OfferExtended');
    assert.equal(r.vep_offer_reminder_sent_at, null);
    assert.ok(r.vep_offer_extended_at, 'qualifying row must have the offer anchor stamped (backfill/trigger)');
  }
});
