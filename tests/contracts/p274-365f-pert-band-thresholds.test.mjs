import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const MIGRATION_PATH = 'supabase/migrations/20260805000051_p274_365f_pert_band_thresholds.sql';
const SQL = readFileSync(MIGRATION_PATH, 'utf8');
const PT = readFileSync('src/i18n/pt-BR.ts', 'utf8');
const EN = readFileSync('src/i18n/en-US.ts', 'utf8');
const ES = readFileSync('src/i18n/es-LATAM.ts', 'utf8');

describe('p274 #365f — CR-042 PERT band thresholds', () => {
  it('preserves _compute_pert_cutoff_core 5-arg signature and defaults', () => {
    assert.match(
      SQL,
      /CREATE OR REPLACE FUNCTION public\._compute_pert_cutoff_core\(\s*p_cycle_id uuid,\s*p_role text DEFAULT 'researcher'::text,\s*p_filter_active_only boolean DEFAULT true,\s*p_score_column text DEFAULT 'objective_score_avg'::text,\s*p_actor_id uuid DEFAULT NULL::uuid\s*\) RETURNS jsonb/,
      'must preserve function identity and all defaults for existing callers'
    );
  });

  it('sets CR-042 band bounds to 75% of PERT through PERT', () => {
    assert.match(SQL, /v_band_lower := v_target \* 0\.75;/);
    assert.match(SQL, /v_band_upper := v_target;/);
    assert.doesNotMatch(SQL, /v_band_lower := v_target \* 0\.90;/);
    assert.doesNotMatch(SQL, /v_band_upper := v_target \* 1\.10;/);
  });

  it('keeps p273 current-cycle cohort semantics intact', () => {
    assert.match(SQL, /FROM public\.selection_applications sa\s*WHERE sa\.cycle_id = p_cycle_id\s*AND sa\.role_applied = p_role/);
    assert.doesNotMatch(SQL, /WITH prior_cycles AS/i);
    assert.doesNotMatch(SQL, /JOIN public\.engagements e/);
    assert.doesNotMatch(SQL, /sa\.status = 'approved'/);
  });

  it('keeps CR-042 PERT target formula unchanged', () => {
    assert.match(SQL, /v_target := \(2 \* v_cohort\.s_min \+ 4 \* v_cohort\.s_avg \+ 2 \* v_cohort\.s_max\) \/ 8;/);
  });

  it('does not auto-decide candidates while recalibrating bands', () => {
    assert.doesNotMatch(SQL, /UPDATE public\.selection_applications\s+SET\s+status\s*=/i);
    assert.doesNotMatch(SQL, /status\s*=\s*'(approved|rejected|converted|waitlisted)'/i);
  });

  it('runs retroactive recompute and reloads PostgREST schema cache', () => {
    assert.match(SQL, /PERFORM public\.recompute_all_active_pert_cutoffs\(\);/);
    assert.match(SQL, /NOTIFY pgrst, 'reload schema';/);
  });

  it('documents the band semantics on function and columns', () => {
    assert.match(SQL, /Band semantics: below < 75% of PERT, in-band = 75% of PERT through PERT, above > PERT/);
    assert.match(SQL, /COMMENT ON COLUMN public\.selection_applications\.pert_band_lower IS\s*'p274 #365f: lower PERT band bound = target \* 0\.75/);
    assert.match(SQL, /COMMENT ON COLUMN public\.selection_applications\.pert_band_upper IS\s*'p274 #365f: upper PERT band bound = target/);
    assert.match(SQL, /COMMENT ON COLUMN public\.selection_applications\.final_score_pert_band_lower IS/);
    assert.match(SQL, /COMMENT ON COLUMN public\.selection_applications\.leader_extra_pert_band_upper IS/);
  });

  it('updates UI tooltip copy in all locales to explain the 75%-to-PERT band', () => {
    assert.match(PT, /Banda = 75% do PERT até o PERT/);
    assert.match(EN, /Band = 75% of PERT through PERT/);
    assert.match(ES, /Banda = 75% del PERT hasta el PERT/);
  });
});
