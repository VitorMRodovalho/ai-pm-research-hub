/**
 * Contract: #1316 — Núcleo VEP contract is the SSOT determinant of an approved app's cohort cycle.
 *
 * Migration: supabase/migrations/20260805000434_1316_nucleo_contract_cohort.sql
 * Worker:    cloudflare-workers/pmi-vep-sync/src/{db,script-mapper,index,types}.ts
 *
 * Root cause: cycle assignment was a heuristic over application_date / app_id sequence. The real
 * determinant is the Núcleo CONTRACT START (VEP serviceStartDateUTC, scoped to the opportunity); a
 * 1-year contract crosses two semesters so submission/approval dates do not anchor the cohort. The
 * SSOT rule = the selection_cycle with the greatest open_date <= contract_start (handles the S2 case
 * where contract start 2026-07-01 is AFTER cycle4's application window closed, which window
 * containment cannot).
 *
 * Live proof (prod ldrfrvwhxsmgaabwmaik, 2026-07-13, this session — re-run before merge):
 *  - SSOT rule matched the current cycle_id of all 82 in-db approved apps (49 cycle4 + 32 cycle3 +
 *    1 b2), 0 mismatches — cycle re-assignment is a no-op for approved apps (their heuristic value
 *    was already right); the fix makes it DETERMINISTIC.
 *  - nucleo_contract_cohort_cycle_id: 2026-01-20 -> cycle3, 2026-07-01 -> cycle4, 2026-04-01 -> b2,
 *    2025-08-22 -> NULL (pre-cycle3 legacy, #1284).
 *  - v_nucleo_contract_status distribution: active 70 / no_contract 58 / ended 11 / superseded 1 /
 *    not_engaged 1 (= 141). ended=11 are the desligamentos; superseded=1 is Paulo's researcher app;
 *    not_engaged=1 is the rejected OfferExpired app (291120) that carries offered dates.
 *  - Paulo (pmi_id 1158211, two emails): researcher app 270695 (start 2026-01-20) -> superseded
 *    (leader app 301116 starts later 2026-07-01); leader -> active. He is NEVER dismissed, even when
 *    his researcher end is later set to 2026-06-30, because the CASE checks superseded BEFORE ended.
 *  - Paving moved exactly 12 rejected/withdrawn (no-contract) apps to their window; 0 apps with a
 *    contract moved (approved apps are cohort-driven, untouched).
 *
 * These invariants are asserted statically against the migration + worker source.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000434_1316_nucleo_contract_cohort.sql');
const mig = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const WORKER = resolve(ROOT, 'cloudflare-workers/pmi-vep-sync/src');
const db = existsSync(resolve(WORKER, 'db.ts')) ? readFileSync(resolve(WORKER, 'db.ts'), 'utf8') : '';
const mapper = existsSync(resolve(WORKER, 'script-mapper.ts')) ? readFileSync(resolve(WORKER, 'script-mapper.ts'), 'utf8') : '';
const index = existsSync(resolve(WORKER, 'index.ts')) ? readFileSync(resolve(WORKER, 'index.ts'), 'utf8') : '';

test('#1316: migration present', () => {
  assert.ok(existsSync(MIG), 'migration file exists');
});

test('#1316: adds dedicated nucleo_contract_start/end columns', () => {
  assert.match(mig, /ADD COLUMN IF NOT EXISTS nucleo_contract_start\s+date/);
  assert.match(mig, /ADD COLUMN IF NOT EXISTS nucleo_contract_end\s+date/);
});

test('#1316: cohort SSOT = greatest open_date <= contract_start (NOT window containment)', () => {
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.nucleo_contract_cohort_cycle_id\(p_contract_start date\)/);
  // The rule: open_date <= contract_start, ordered DESC, LIMIT 1.
  assert.match(mig, /sc\.open_date <= p_contract_start/);
  assert.match(mig, /ORDER BY sc\.open_date DESC\s*\n\s*LIMIT 1/);
});

test('#1316: cohort logic does NOT reuse the polluted lifetime columns', () => {
  // The cohort/contract capture must use serviceStartDateUTC, never the lifetime
  // service_first_start_date / service_latest_end_date (cross-chapter VEP history).
  const fnBlock = mig.slice(mig.indexOf('nucleo_contract_cohort_cycle_id'), mig.indexOf('CREATE OR REPLACE VIEW'));
  assert.doesNotMatch(fnBlock, /service_first_start_date|service_latest_end_date/);
});

test('#1316: status view is security_invoker and person-scoped by pmi_id (NOT email)', () => {
  assert.match(mig, /CREATE OR REPLACE VIEW public\.v_nucleo_contract_status\s*\n\s*WITH \(security_invoker = true\)/);
  // The later-contract lookup joins on pmi_id (Paulo holds two emails across his apps).
  assert.match(mig, /c2\.pmi_id = c\.pmi_id/);
  assert.doesNotMatch(mig, /c2\.email = c\.email/);
});

test('#1316: superseded (promotion) is decided BEFORE ended (dismissal) — Paulo guarantee', () => {
  // CASE ordering: has_later_contract -> superseded MUST precede the contract_end -> ended branch,
  // so a short earlier-role contract with a later contract is never read as a dismissal.
  const supIdx = mig.indexOf("THEN 'superseded'");
  const endIdx = mig.indexOf("THEN 'ended'");
  assert.ok(supIdx > 0 && endIdx > 0, 'both branches present');
  assert.ok(supIdx < endIdx, 'superseded branch precedes ended branch');
  // The later contract must itself be an engaged (approved/converted) contract.
  assert.match(mig, /c2\.status IN \('approved', 'converted'\)/);
  assert.match(mig, /c2\.nucleo_contract_start > c\.nucleo_contract_start/);
});

test('#1316: paves selection_cycles windows contiguous + non-overlapping', () => {
  assert.match(mig, /UPDATE public\.selection_cycles SET close_date = DATE '2026-03-27' WHERE cycle_code = 'cycle3-2026'/);
  assert.match(mig, /UPDATE public\.selection_cycles SET close_date = DATE '2026-05-14' WHERE cycle_code = 'cycle3-2026-b2'/);
});

test('#1316: backfills contract columns from the audited export by vep_application_id', () => {
  assert.match(mig, /UPDATE public\.selection_applications sa\s*\n\s*SET nucleo_contract_start = v\.cstart/);
  assert.match(mig, /WHERE sa\.vep_application_id = v\.app_id/);
});

test('#1316: window re-stamp targets ONLY no-contract apps (approved stay cohort-driven)', () => {
  // The re-stamp UPDATE must gate on nucleo_contract_start IS NULL so approved apps are never
  // moved by application_date.
  const restamp = mig.slice(mig.lastIndexOf('SET cycle_id = w.id'));
  assert.match(restamp, /sa\.nucleo_contract_start IS NULL/);
});

test('#1316: worker has the cohort SSOT pure fn mirroring the DB function', () => {
  assert.match(db, /export function pickCohortCycleByContractStart\(/);
  assert.match(db, /c\.open_date <= start/);
});

test('#1316: worker mapper captures the Núcleo contract from serviceStartDateUTC/EndDateUTC', () => {
  assert.match(mapper, /app\.serviceStartDateUTC/);
  assert.match(mapper, /nucleo_contract_start:/);
  assert.match(mapper, /nucleo_contract_end:/);
});

test('#1316: worker assigns cycle by contract cohort BEFORE the temporal date/seq heuristic', () => {
  assert.match(index, /pickCohortCycleByContractStart\(mapped\.nucleo_contract_start, recentCycles\)/);
  // The temporal date redirect is now nested under the no-contract branch.
  const cohortIdx = index.indexOf('pickCohortCycleByContractStart(mapped.nucleo_contract_start');
  const noContractGuard = index.indexOf('} else if (!mapped.nucleo_contract_start) {');
  assert.ok(cohortIdx > 0 && noContractGuard > cohortIdx, 'cohort path precedes the no-contract temporal fallback');
});
