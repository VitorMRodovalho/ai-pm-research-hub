/**
 * Contract: #1362 — an active engagement's authority window must not expire before its contract.
 *
 * Regression (2026-07-13): the VEP JSON import re-fired sync_operational_role_cache on Paulo Jr
 * (pmi 1158211), a researcher promoted to tribe leader, and he dropped to `guest`. operational_role
 * derives from auth_engagements.is_authoritative, which requires `end_date IS NULL OR end_date >=
 * CURRENT_DATE`. His leader engagement pointed at the leader application (contract 2026-07-01 ->
 * 2027-06-30) but kept the OLD researcher-contract dates (end 2026-06-30). Once that passed and any
 * trigger re-fired, authority silently vanished.
 *
 * Root cause = engagement date drift vs the #1316 SSOT (selection_applications.nucleo_contract_end).
 * Fix (migration 20260805000435): approve_selection_application sources end_date from the contract
 * on INSERT and EXTENDS it on the promotion path; plus an idempotent backfill.
 *
 * Guard = a writer-agnostic invariant: no matter which RPC mutates an engagement, an active
 * engagement linked to a still-active contract must not expire before that contract, and must never
 * have end_date < start_date.
 *
 * Live proof (prod ldrfrvwhxsmgaabwmaik, 2026-07-13, this session — re-run before merge):
 *  - Blast radius of the import demotion = 1 (Paulo). Latent bomb defused = 1 (Honorio 7304044,
 *    engagement end 2026-12-31 vs contract 2027-06-30). Hotfix + backfill -> 0 divergence.
 *  - Paulo recomputed to tribe_leader after end_date -> 2027-06-30.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000435_1362_engagement_authority_window_tracks_contract.sql');
const mig = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── Static: the migration wires the contract-tracking fix ───────────────────────
test('#1362: migration present', () => {
  assert.ok(existsSync(MIG), 'migration file exists');
});

test('#1362: approve INSERT sources engagement end_date from the Núcleo contract (SSOT first)', () => {
  // The engagement end_date COALESCE must prefer v_app.nucleo_contract_end over the cycle close.
  assert.match(mig, /COALESCE\(\s*\n\s*v_app\.nucleo_contract_end,\s*\n\s*v_cycle_end_date,/);
});

test('#1362: approve promotion path EXTENDS end_date to the new contract (never shrinks)', () => {
  // The promotion/renewal UPDATE conditionally extends end_date to the new contract end. These
  // tokens are unique to that branch (the INSERT uses a COALESCE, the backfill qualifies e./sa.).
  assert.match(mig, /end_date = CASE\s*\n\s*WHEN end_date IS NOT NULL/);
  assert.match(mig, /AND end_date < v_app\.nucleo_contract_end\s*\n\s*THEN v_app\.nucleo_contract_end/);
  // must not blindly overwrite (would shrink a NULL/longer window)
  assert.match(mig, /THEN v_app\.nucleo_contract_end\s*\n\s*ELSE end_date/);
});

test('#1362: idempotent backfill aligns expired-early windows + NULLs invalid end<start', () => {
  assert.match(mig, /SET end_date = sa\.nucleo_contract_end[\s\S]*?e\.end_date < sa\.nucleo_contract_end/);
  assert.match(mig, /SET end_date = NULL[\s\S]*?end_date < start_date/);
  assert.match(mig, /NOTIFY\s+pgrst/);
});

// ── DB-gated: the live invariant holds ─────────────────────────────────────────
test('#1362 DB: no active engagement expires before its still-active linked contract', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: engs, error: e1 } = await sb
    .from('engagements')
    .select('id, start_date, end_date, selection_application_id')
    .eq('status', 'active')
    .not('selection_application_id', 'is', null)
    .not('end_date', 'is', null);
  assert.ok(!e1, e1?.message);

  const appIds = [...new Set(engs.map((e) => e.selection_application_id))];
  const { data: apps, error: e2 } = await sb
    .from('selection_applications')
    .select('id, nucleo_contract_end')
    .in('id', appIds);
  assert.ok(!e2, e2?.message);
  const contractEnd = new Map(apps.map((a) => [a.id, a.nucleo_contract_end]));

  const violations = engs.filter((e) => {
    const cEnd = contractEnd.get(e.selection_application_id);
    return cEnd && e.end_date < cEnd; // engagement window expires before the contract does
  });
  assert.equal(violations.length, 0,
    `active engagement(s) expire before their contract (silent authority loss): ${JSON.stringify(violations.slice(0, 10))}`);
});

test('#1362 DB: no active engagement has end_date < start_date (invalid window)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb
    .from('engagements')
    .select('id, start_date, end_date')
    .eq('status', 'active')
    .not('end_date', 'is', null);
  assert.ok(!error, error?.message);
  const invalid = data.filter((e) => e.end_date < e.start_date);
  assert.equal(invalid.length, 0, `active engagement(s) with end_date < start_date: ${JSON.stringify(invalid.slice(0, 10))}`);
});
