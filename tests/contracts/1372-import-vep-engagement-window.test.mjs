/**
 * Contract: #1372 — the VEP import must not fan a per-vaga end_date across a person's engagements.
 *
 * Recurrence of #1362 (2026-07-13): a NEW VEP import (135 apps) re-demoted Paulo Jr (pmi 1158211)
 * from tribe_leader to `guest`. Root cause = ONE bug, not two: the pmi-vep-sync worker's
 * setEngagementEndDateSource wrote `end_date` on ALL of a person's active engagements
 * (person-scoped), but PMI VEP `serviceEndDateUTC` is a PER-VAGA fact (one selection application =
 * one Núcleo service contract). Processing Paulo's researcher application (contract ended
 * 2026-06-30) stamped that stale end_date onto:
 *   - his promoted-leader engagement (contract 2027-06-30)  -> expires-before-contract -> guest
 *   - his July workgroup engagements                        -> end_date < start_date (invalid window)
 * The trigger trg_sync_role_cache (AFTER INSERT/UPDATE ON engagements) then re-derived
 * operational_role from the now-stale window. The workgroup INSERT itself writes end_date=NULL
 * (default); the 2026-06-30 came from the same fan-out (metadata end_date_source='pmi_vep').
 *
 * Durable fix (owner decision 2026-07-13 — scope per vaga):
 *   1. setEngagementEndDateSource takes applicationId and scopes the `pmi_vep` write to the
 *      engagement linked to THAT selection application (never person-wide). No app link -> no write.
 *   2. Fail-safe guard: never write end_date < start_date.
 *   3. Writer-agnostic backstop: CHECK constraint engagements_end_after_start_check
 *      (migration 20260805000438) — any future writer producing end<start fails at write time.
 *
 * Live proof (prod ldrfrvwhxsmgaabwmaik, 2026-07-13, this session — re-run before merge):
 *   - Invariants 0/0 (no active engagement expires before contract; none with end<start).
 *   - 0 existing end<start rows across all statuses before adding the CHECK.
 *   - Paulo operational_role = tribe_leader.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000438_1372_engagement_end_after_start_check.sql');
const DB_TS = resolve(ROOT, 'cloudflare-workers/pmi-vep-sync/src/db.ts');
const INDEX_TS = resolve(ROOT, 'cloudflare-workers/pmi-vep-sync/src/index.ts');

const mig = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const dbTs = existsSync(DB_TS) ? readFileSync(DB_TS, 'utf8') : '';
const indexTs = existsSync(INDEX_TS) ? readFileSync(INDEX_TS, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── Static: the CHECK-constraint migration is wired ─────────────────────────────
test('#1372: CHECK-constraint migration present', () => {
  assert.ok(existsSync(MIG), 'migration file exists');
});

test('#1372: migration adds engagements_end_after_start_check (end_date IS NULL OR end_date >= start_date)', () => {
  assert.match(mig, /ADD CONSTRAINT engagements_end_after_start_check/);
  assert.match(mig, /CHECK\s*\(\s*end_date IS NULL OR end_date >= start_date\s*\)/);
});

// ── Static: the worker no longer fans a per-vaga end date person-wide ────────────
test('#1372: setEngagementEndDateSource takes an applicationId parameter', () => {
  assert.match(dbTs, /export async function setEngagementEndDateSource\([\s\S]*?applicationId: string \| null,/);
});

test('#1372: the pmi_vep write is scoped to the vaga (selection_application_id), and bails without a link', () => {
  // scope filter present
  assert.match(dbTs, /\.eq\('selection_application_id', applicationId\)/);
  // no application link -> touch nothing (never person-wide for pmi_vep)
  assert.match(dbTs, /if \(!applicationId\) return 0;/);
});

test('#1372: the end_date write is guarded to never precede start_date', () => {
  assert.match(dbTs, /if \(endDate >= row\.start_date\)/);
  // start_date is selected so the guard has the data
  assert.match(dbTs, /\.select\('id, metadata, end_date, start_date'\)/);
});

test('#1372: the import call site passes the dbApplicationId (result.id)', () => {
  assert.match(indexTs, /setEngagementEndDateSource\(db, personId, result\.id, 'pmi_vep', endDate\)/);
});

// ── DB-gated: the live invariant holds (writer-agnostic) ─────────────────────────
test('#1372 DB: no active engagement has end_date < start_date', { skip: dbGated ? false : skipMsg }, async () => {
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
