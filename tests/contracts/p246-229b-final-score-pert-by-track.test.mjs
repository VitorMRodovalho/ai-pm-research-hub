import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const MIGRATION_PATH = 'supabase/migrations/20260805000027_p246_229b_final_score_pert_by_track.sql';
const MIGRATION_SQL = readFileSync(MIGRATION_PATH, 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;

const sb = SUPABASE_URL && SUPABASE_SRK ? createClient(SUPABASE_URL, SUPABASE_SRK, {
  auth: { persistSession: false }
}) : null;

describe('p246 #229b Foundation — final-score PERT régua by track', () => {
  describe('migration static assertions', () => {
    it('migration file exists at canonical timestamp', () => {
      assert.ok(MIGRATION_SQL.length > 0, 'migration file must exist');
    });

    it('declares 6 new final_score_pert_* columns on selection_applications', () => {
      const cols = [
        'final_score_pert_target numeric',
        'final_score_pert_band_lower numeric',
        'final_score_pert_band_upper numeric',
        'final_score_pert_cutoff_method text',
        'final_score_pert_cohort_n integer',
        'final_score_pert_calc_at timestamptz',
      ];
      for (const col of cols) {
        assert.ok(
          MIGRATION_SQL.includes(`ADD COLUMN IF NOT EXISTS ${col}`),
          `migration must add column: ${col}`
        );
      }
    });

    it('_compute_pert_cutoff_core CREATE OR REPLACE preserves 5-arg signature with defaults', () => {
      assert.match(
        MIGRATION_SQL,
        /CREATE OR REPLACE FUNCTION public\._compute_pert_cutoff_core\(\s*p_cycle_id uuid,\s*p_role text DEFAULT 'researcher'::text,\s*p_filter_active_only boolean DEFAULT true,\s*p_score_column text DEFAULT 'objective_score_avg'::text,\s*p_actor_id uuid DEFAULT NULL::uuid\s*\) RETURNS jsonb/,
        'must preserve 5-arg signature with all 4 default values intact (no DROP+CREATE — back-compat)'
      );
    });

    it('_compute_pert_cutoff_core branches on v_is_final_score for UPDATE path', () => {
      assert.match(MIGRATION_SQL, /v_is_final_score := \(p_score_column = 'final_score'\);/);
      assert.match(
        MIGRATION_SQL,
        /ELSIF v_is_final_score THEN\s*UPDATE public\.selection_applications\s*SET final_score_pert_target = v_target,\s*final_score_pert_band_lower = v_band_lower,\s*final_score_pert_band_upper = v_band_upper,\s*final_score_pert_cutoff_method = v_method,\s*final_score_pert_cohort_n = v_n,\s*final_score_pert_calc_at = now\(\)\s*WHERE cycle_id = p_cycle_id\s*AND role_applied = p_role;/,
        'final_score UPDATE must be track-scoped via AND role_applied = p_role (PM rule: separate cohorts per track)'
      );
    });

    it('final_score fallback target lookup is track-aware (filters by role_applied = p_role)', () => {
      assert.match(
        MIGRATION_SQL,
        /IF v_is_final_score THEN\s*SELECT MAX\(final_score_pert_target\)\s*INTO v_fallback_target\s*FROM public\.selection_applications\s*WHERE cycle_id != p_cycle_id\s*AND role_applied = p_role\s*AND final_score_pert_target IS NOT NULL;/,
        'final_score fallback must scope by track to avoid mixing researcher/leader scales'
      );
    });

    it('recompute_all_active_pert_cutoffs computes final_score for BOTH tracks per cycle', () => {
      assert.match(
        MIGRATION_SQL,
        /v_result_fs_researcher := public\._compute_pert_cutoff_core\(v_cycle\.id, 'researcher', true, 'final_score', NULL\);/,
        'recompute must invoke for researcher final_score'
      );
      assert.match(
        MIGRATION_SQL,
        /v_result_fs_leader := public\._compute_pert_cutoff_core\(v_cycle\.id, 'leader', true, 'final_score', NULL\);/,
        'recompute must invoke for leader final_score'
      );
    });

    it('recompute audit metadata declares 4 dimensions (objective + leader_extra + 2 final tracks)', () => {
      assert.match(
        MIGRATION_SQL,
        /'dimensions', jsonb_build_array\('objective', 'leader_extra', 'final_score_researcher', 'final_score_leader'\)/,
        'recompute audit log must declare all 4 dimensions for downstream observability'
      );
    });

    it('get_selection_dashboard.cycle exposes both new final_score_cutoff blocks', () => {
      assert.match(
        MIGRATION_SQL,
        /'final_score_cutoff_researcher', \(SELECT jsonb_build_object\([\s\S]*?\) FROM public\.selection_applications WHERE cycle_id = v_cycle_id AND role_applied = 'researcher'\)/,
        'cycle.final_score_cutoff_researcher must be scoped to researcher-track apps'
      );
      assert.match(
        MIGRATION_SQL,
        /'final_score_cutoff_leader', \(SELECT jsonb_build_object\([\s\S]*?\) FROM public\.selection_applications WHERE cycle_id = v_cycle_id AND role_applied = 'leader'\)/,
        'cycle.final_score_cutoff_leader must be scoped to leader-track apps'
      );
    });

    it('get_selection_dashboard.applications[] exposes interview_score + 6 final_score_pert_* fields', () => {
      const fields = [
        "'interview_score', a.interview_score",
        "'final_score_pert_target', a.final_score_pert_target",
        "'final_score_pert_band_lower', a.final_score_pert_band_lower",
        "'final_score_pert_band_upper', a.final_score_pert_band_upper",
        "'final_score_pert_cutoff_method', a.final_score_pert_cutoff_method",
        "'final_score_pert_cohort_n', a.final_score_pert_cohort_n",
        "'final_score_pert_calc_at', a.final_score_pert_calc_at",
      ];
      for (const f of fields) {
        assert.ok(
          MIGRATION_SQL.includes(f),
          `applications[] must expose: ${f}`
        );
      }
    });

    it('per-app new fields are in chunk 2 (after the || merge) to stay under PG 100-arg cap', () => {
      // chunk 2 starts right after the first jsonb_build_object closes and `||` appears
      const chunkBoundary = MIGRATION_SQL.indexOf('|| jsonb_build_object');
      assert.ok(chunkBoundary > 0, 'must have chunk merge via ||');
      const firstFinalScorePertTarget = MIGRATION_SQL.indexOf("'final_score_pert_target', a.final_score_pert_target");
      assert.ok(firstFinalScorePertTarget > chunkBoundary, 'new per-app fields must live in chunk 2 (PG 100-arg cap)');
    });

    it('SECURITY DEFINER + pinned search_path preserved on all 3 functions', () => {
      const funcs = ['_compute_pert_cutoff_core', 'recompute_all_active_pert_cutoffs', 'get_selection_dashboard'];
      for (const f of funcs) {
        const fnBody = MIGRATION_SQL.split(`FUNCTION public.${f}`)[1];
        assert.ok(fnBody, `${f} must be present`);
        const fnDef = fnBody.split('$$;')[0];
        assert.ok(fnDef.includes('SECURITY DEFINER'), `${f} must be SECURITY DEFINER`);
        assert.ok(fnDef.includes("SET search_path TO 'public', 'pg_temp'"), `${f} must pin search_path`);
      }
    });

    it('NOTIFY pgrst trailer present', () => {
      assert.match(MIGRATION_SQL, /NOTIFY pgrst, 'reload schema';/);
    });
  });

  describe('forward-defense: PM constraints (do-not list)', () => {
    it('no interview score régua introduced (no interview_score_pert_* columns or RPC branch)', () => {
      assert.doesNotMatch(MIGRATION_SQL, /ADD COLUMN.+interview_score_pert/);
      assert.doesNotMatch(MIGRATION_SQL, /interview_score_pert_target/);
    });

    it('leader_extra stays separate (not merged into objective branch)', () => {
      // leader_extra and final_score must be separate ELSIF branches, not collapsed
      const elseifCount = (MIGRATION_SQL.match(/ELSIF v_is_final_score THEN/g) || []).length;
      assert.equal(elseifCount, 1, 'must have exactly one ELSIF v_is_final_score branch (sibling to v_is_leader_extra)');
    });

    it('final_score régua not used to coerce status (no automatic decision change in this migration)', () => {
      // PM rule: "não mudar decisão final automaticamente sem PM aprovar política".
      // Migration must not contain selection_applications status writes (other than indirectly via RPCs we control).
      assert.doesNotMatch(MIGRATION_SQL, /UPDATE public\.selection_applications SET status =/);
    });
  });

  if (sb) {
    describe('DB-gated assertions (with SUPABASE_SERVICE_ROLE_KEY)', () => {
      it('6 new columns exist on selection_applications', async () => {
        const probe = await sb
          .from('selection_applications')
          .select('id, final_score_pert_target, final_score_pert_band_lower, final_score_pert_band_upper, final_score_pert_cutoff_method, final_score_pert_cohort_n, final_score_pert_calc_at')
          .limit(1);
        if (probe.error) {
          assert.fail(`expected to select new columns; got error: ${probe.error.message}`);
        }
        assert.ok(probe.data !== null, 'should return data array (possibly empty) without column error');
      });

      it('cycle4 researcher-track apps have final_score_pert_target populated (after recompute)', async () => {
        // Scope to cycle4 via inner-join on selection_cycles to avoid hitting historical
        // cycles where recompute never ran (those would have NULL régua).
        const { data, error } = await sb
          .from('selection_applications')
          .select('final_score_pert_target, final_score_pert_cohort_n, final_score_pert_cutoff_method, role_applied, selection_cycles!inner(cycle_code)')
          .eq('role_applied', 'researcher')
          .eq('selection_cycles.cycle_code', 'cycle4-2026')
          .not('final_score', 'is', null)
          .limit(5);
        if (error) {
          assert.fail(`probe error: ${error.message}`);
        }
        assert.ok(data && data.length > 0, 'expect at least 1 cycle4 researcher with final_score populated');
        const hasDynamic = data.some(r => r.final_score_pert_cutoff_method === 'dynamic');
        assert.ok(hasDynamic, 'expect at least one cycle4 researcher with dynamic final_score régua post-recompute');
      });

      it('cycle4 leader-track apps have method=disabled (cohort_n<10 historical leaders)', async () => {
        const { data, error } = await sb
          .from('selection_applications')
          .select('final_score_pert_cutoff_method, final_score_pert_cohort_n, role_applied, selection_cycles!inner(cycle_code)')
          .eq('role_applied', 'leader')
          .eq('selection_cycles.cycle_code', 'cycle4-2026')
          .not('final_score', 'is', null)
          .limit(5);
        if (error) {
          assert.fail(`probe error: ${error.message}`);
        }
        if (data && data.length > 0) {
          const allDisabled = data.every(r => r.final_score_pert_cutoff_method === 'disabled');
          assert.ok(
            allDisabled,
            `cycle4 leader-track final régua should be disabled (cohort_n<10); got: ${JSON.stringify(data.map(r => r.final_score_pert_cutoff_method))}`
          );
        }
      });
    });
  } else {
    describe('DB-gated assertions', () => {
      it.skip('SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY not set — DB checks skipped', () => {});
    });
  }
});
