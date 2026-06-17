/**
 * Contract: #321 seed-side guard — onboarding_progress.volunteer_term respects an existing
 * issued cert at SEED time (mig 20260805000198).
 *
 * Background: mig …018 installed trg_complete_volunteer_term_on_cert, which fires AFTER INSERT
 * ON certificates. It cannot fire when the onboarding row is created AFTER the cert already
 * exists (lazy seed / re-init) — exactly the case it documented as out-of-scope. A real phantom
 * surfaced 2026-06-16 (member with a March cert got a fresh pending volunteer_term row), reddening
 * the live p233-321 test. This migration adds the symmetric onboarding-side guard, mirroring the
 * existing trg_vep_acceptance_auto_complete_on_seed.
 *
 * Static (reads the migration source) → runs without DB env. Live behavior (seed→auto-complete,
 * backfill, 0 phantoms) was validated at apply time via a rolled-back probe; the live p233-321
 * test guards the data-state invariant going forward.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const MIG_PATH = 'supabase/migrations/20260805000198_p233_321_complete_volunteer_term_on_seed.sql';
const MIG = readFileSync(MIG_PATH, 'utf8');

describe('#321 seed-guard — onboarding-side completion trigger (mig …198)', () => {
  it('migration exists', () => {
    assert.ok(existsSync(MIG_PATH));
  });

  it('defines the SECURITY DEFINER seed-guard function with a pinned search_path', () => {
    assert.match(MIG, /CREATE OR REPLACE FUNCTION public\._trg_complete_volunteer_term_on_seed\(\)/);
    assert.match(MIG, /SECURITY DEFINER/);
    assert.match(MIG, /SET search_path = 'public', 'pg_temp'/);
  });

  it('completes the row using the member\'s latest ISSUED cert (historical completed_at)', () => {
    assert.match(MIG, /AND c\.type = 'volunteer_agreement'\s*\n\s*AND c\.status = 'issued'/);
    assert.match(MIG, /NEW\.status\s*:=\s*'completed'/);
    assert.match(MIG, /NEW\.completed_at\s*:=\s*COALESCE\(v_cert\.issued_at, now\(\)\)/);
    assert.match(MIG, /'completed_via', 'cert_seed_guard'/);
  });

  it('guards NULL member_id (pre-onboarding rows can have no member cert)', () => {
    assert.match(MIG, /IF NEW\.member_id IS NULL THEN RETURN NEW; END IF;/);
  });

  it('fires BEFORE INSERT, per-row, scoped to volunteer_term + pending (mirrors vep_acceptance precedent)', () => {
    assert.match(MIG, /CREATE TRIGGER trg_complete_volunteer_term_on_seed\s*\n\s*BEFORE INSERT ON public\.onboarding_progress/);
    assert.match(MIG, /FOR EACH ROW/);
    assert.match(MIG, /WHEN \(NEW\.step_key = 'volunteer_term' AND NEW\.status = 'pending'\)/);
  });

  it('backfills current phantoms idempotently and asserts 0 remain (sanity)', () => {
    assert.match(MIG, /'completed_via', 'p233_seed_backfill'/);
    assert.match(MIG, /seed-guard sanity FAIL/);
  });

  it('reloads the PostgREST schema cache', () => {
    assert.match(MIG, /NOTIFY pgrst, 'reload schema'/);
  });
});
