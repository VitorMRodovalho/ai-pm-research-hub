/**
 * Contract: #766 J4 (SLA/cadence configurable) — PR1/2 (config foundation).
 *
 * Externalizes the 4 real SLA windows that were hardcoded in the selection crons into a config
 * table (sla_policies), tunable by the GP via update_sla_policy (gated by manage_platform) WITHOUT
 * a deploy. PR2 = admin UI. Scope (PM): only the 4 true SLAs; dedup/idempotency (7d) and lookback
 * (365d) windows stay hardcoded.
 *
 * The PARITY guarantee this contract enforces: each seeded value MUST equal the literal the cron
 * falls back to when the row is missing — i.e. the migration changes WHERE the default lives, not
 * WHAT it is. No schema invariant is added (config is mutable). DB assertions are read-only and do
 * NOT pin volatile prod counts.
 *
 * Migration: 20260805000206_766_j4_sla_policies_config.sql.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');
const MIG = read('supabase/migrations/20260805000206_766_j4_sla_policies_config.sql');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// The 4 SLA windows: policy_key -> { fallback literal in the cron, expected seeded interval }.
// fallbackLiteral is the exact `interval '...'` text the cron defaults to; seededText is the
// canonical value the row holds (parity = these encode the same duration).
const POLICIES = [
  { key: 'interview_overdue_grace', fallback: "interval '24 hours'", canon: '24:00:00' },
  { key: 'stuck_scheduled_grace', fallback: "interval '48 hours'", canon: '48:00:00' },
  { key: 'reschedule_nudge_initial', fallback: "interval '3 days'", canon: '3 days' },
  { key: 'reschedule_nudge_repeat', fallback: "interval '3 days'", canon: '3 days' },
];

// ── Offline: migration shape ───────────────────────────────────────────────────
test('migration: creates sla_policies with positive-interval CHECK and category CHECK', () => {
  assert.ok(MIG, 'PR1 migration exists');
  assert.match(MIG, /CREATE TABLE IF NOT EXISTS public\.sla_policies/);
  assert.match(MIG, /value_interval\s+interval NOT NULL CHECK \(value_interval > interval '0'\)/);
  assert.match(MIG, /category\s+text NOT NULL CHECK \(category IN \('sla','idempotency','lookback'\)\)/);
});

test('migration: updated_by FK is auth.users(id) (NOT members.id) and stores auth.uid()', () => {
  assert.match(MIG, /updated_by\s+uuid REFERENCES auth\.users\(id\) ON DELETE SET NULL/);
  assert.match(MIG, /SET value_interval = p_value, updated_at = now\(\), updated_by = auth\.uid\(\)/);
});

test('migration: RLS is enabled, SELECT-only for authenticated, no direct write policy', () => {
  assert.match(MIG, /ALTER TABLE public\.sla_policies ENABLE ROW LEVEL SECURITY/);
  assert.match(MIG, /CREATE POLICY sla_policies_select_authenticated ON public\.sla_policies\s+FOR SELECT TO authenticated USING \(true\)/);
  // No INSERT/UPDATE/DELETE policy is created — mutations only via the SECURITY DEFINER RPC.
  assert.ok(!/FOR (INSERT|UPDATE|DELETE)/.test(MIG), 'no direct write policy may exist');
});

test('migration: update_sla_policy is SECURITY DEFINER, gated by can_by_member(manage_platform), REVOKEd', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.update_sla_policy\(p_key text, p_value interval\)/);
  assert.match(MIG, /SECURITY DEFINER SET search_path = ''/);
  assert.match(MIG, /public\.can_by_member\(v_member_id, 'manage_platform'\)/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.update_sla_policy\(text, interval\) FROM PUBLIC, anon/);
  assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\.update_sla_policy\(text, interval\) TO authenticated/);
});

test('migration: each cron reads its policy_key from sla_policies AND falls back to the OLD literal (parity)', () => {
  for (const p of POLICIES) {
    const re = new RegExp(`policy_key = '${p.key}'`);
    assert.match(MIG, re, `${p.key} is SELECTed from sla_policies`);
    // The fallback literal must equal the old hardcoded default — this is the parity guarantee.
    const fbRe = new RegExp(`:= ${p.fallback.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`);
    assert.match(MIG, fbRe, `${p.key} falls back to ${p.fallback}`);
  }
});

test('migration: the 7-day interview idempotency window stays hardcoded (NOT an SLA, out of scope)', () => {
  // Guard against accidental scope creep: the dedup window must NOT become a policy_key.
  assert.match(MIG, /n\.created_at > now\(\) - interval '7 days'/);
  assert.ok(!/'interview_idempotency'/.test(MIG), 'idempotency window must not be externalized in PR1');
});

// ── DB-gated: live seed at parity ────────────────────────────────────────────────
test('DB: sla_policies holds exactly the 4 SLA windows, all category=sla', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.from('sla_policies').select('policy_key, category');
  assert.ok(!error, error?.message);
  const keys = (data || []).map((r) => r.policy_key).sort();
  assert.deepEqual(keys, POLICIES.map((p) => p.key).sort(), 'exactly the 4 SLA policy keys');
  assert.ok((data || []).every((r) => r.category === 'sla'), 'all 4 are category=sla');
});

test('DB: each seeded value_interval is at PARITY with the cron fallback literal', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.from('sla_policies').select('policy_key, value_interval');
  assert.ok(!error, error?.message);
  const byKey = Object.fromEntries((data || []).map((r) => [r.policy_key, r.value_interval]));
  for (const p of POLICIES) {
    // PostgREST renders interval as e.g. "24:00:00" or "3 days"; compare to the canonical form.
    assert.equal(byKey[p.key], p.canon, `${p.key} seeded at parity (${p.canon})`);
  }
});
