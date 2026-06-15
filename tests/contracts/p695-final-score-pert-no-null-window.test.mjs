import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// #695 — no app may have final_score set while final_score_pert_cutoff_method stays NULL.
// compute_application_scores writes final_score per app but never stamped the PERT régua,
// leaving a NULL window until the weekly cron. p695 closes it with a row trigger
// (trg_final_score_pert_refresh) on selection_applications that delegates to
// _compute_pert_cutoff_core(..., 'final_score', ...).

const MIGRATION_PATH = 'supabase/migrations/20260805000176_p695_final_score_pert_no_null_window.sql';
const MIGRATION_SQL = readFileSync(MIGRATION_PATH, 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;

const sb = SUPABASE_URL && SUPABASE_SRK ? createClient(SUPABASE_URL, SUPABASE_SRK, {
  auth: { persistSession: false }
}) : null;

describe('p695 — final_score PERT NULL-window closed by trigger', () => {
  describe('migration static assertions', () => {
    it('migration file exists at canonical timestamp', () => {
      assert.ok(MIGRATION_SQL.length > 0, 'migration file must exist');
    });

    it('defines the trigger function _trg_recompute_final_score_pert (SECDEF + pinned search_path)', () => {
      assert.match(
        MIGRATION_SQL,
        /CREATE OR REPLACE FUNCTION public\._trg_recompute_final_score_pert\(\)\s*RETURNS trigger/,
        'trigger function must be declared'
      );
      const fnBody = MIGRATION_SQL.split('FUNCTION public._trg_recompute_final_score_pert')[1].split('$$;')[0];
      assert.ok(fnBody.includes('SECURITY DEFINER'), 'must be SECURITY DEFINER');
      assert.ok(fnBody.includes("SET search_path TO 'public', 'pg_temp'"), 'must pin search_path');
    });

    it('trigger function delegates to _compute_pert_cutoff_core with the final_score column', () => {
      assert.match(
        MIGRATION_SQL,
        /PERFORM public\._compute_pert_cutoff_core\(NEW\.cycle_id, NEW\.role_applied, true, 'final_score', NULL\);/,
        'must recompute the track-resolved final_score régua for the row'
      );
    });

    it('trigger fires AFTER INSERT OR UPDATE OF final_score (recursion-safe scope)', () => {
      // Scoping to `UPDATE OF final_score` is what makes it recursion-safe: the core UPDATEs
      // only final_score_pert_* columns, so the core write cannot re-fire this trigger.
      assert.match(
        MIGRATION_SQL,
        /CREATE TRIGGER trg_final_score_pert_refresh\s*AFTER INSERT OR UPDATE OF final_score ON public\.selection_applications\s*FOR EACH ROW\s*EXECUTE FUNCTION public\._trg_recompute_final_score_pert\(\);/,
        'trigger must scope UPDATE to the final_score column only'
      );
    });

    it('heals the currently-open window via the canonical recompute', () => {
      assert.match(
        MIGRATION_SQL,
        /SELECT public\.recompute_all_active_pert_cutoffs\(\);/,
        'migration must heal any app scored since the last cron run'
      );
    });

    it('forward-defense: must NOT write selection_applications.status (no auto-decision)', () => {
      assert.doesNotMatch(MIGRATION_SQL, /UPDATE public\.selection_applications SET status =/);
    });
  });

  if (sb) {
    describe('DB-gated assertions (with SUPABASE_SERVICE_ROLE_KEY)', () => {
      it('INVARIANT: zero active-cycle apps with final_score set but PERT method NULL', async () => {
        // The bug (#695): an app scored mid-cycle sat with final_score NOT NULL and
        // final_score_pert_cutoff_method NULL until the weekly cron. The trigger closes it.
        const { data, error } = await sb
          .from('selection_applications')
          .select('id, role_applied, final_score, final_score_pert_cutoff_method, selection_cycles!inner(cycle_code, phase)')
          .in('selection_cycles.phase', ['evaluating', 'interviews', 'open_apps'])
          .not('final_score', 'is', null)
          .is('final_score_pert_cutoff_method', null);
        if (error) {
          assert.fail(`probe error: ${error.message}`);
        }
        assert.equal(
          data.length, 0,
          `expected 0 active-cycle apps in the NULL window; got ${data.length}: ${JSON.stringify(data.map(r => ({ id: r.id, role: r.role_applied, fs: r.final_score })))}`
        );
      });
    });
  } else {
    describe('DB-gated assertions', () => {
      it.skip('SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY not set — DB checks skipped', () => {});
    });
  }
});
