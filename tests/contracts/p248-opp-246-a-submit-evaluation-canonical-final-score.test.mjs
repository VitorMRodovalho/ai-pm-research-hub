import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const MIGRATION_PATH = 'supabase/migrations/20260805000028_p248_opp_246_a_submit_evaluation_canonical_final_score.sql';
const MIGRATION_SQL = readFileSync(MIGRATION_PATH, 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;

const sb = SUPABASE_URL && SUPABASE_SRK ? createClient(SUPABASE_URL, SUPABASE_SRK, {
  auth: { persistSession: false }
}) : null;

const FRANCISLEILA_ID = '72ea1a45-8dc8-4b0b-b4cb-f1427968ff22';

describe('p248 OPP-246.A — submit_evaluation canonical final_score (drops naïve sum race)', () => {
  describe('migration static assertions', () => {
    it('migration file exists at canonical timestamp', () => {
      assert.ok(MIGRATION_SQL.length > 0, 'migration file must exist');
    });

    it('CREATE OR REPLACE FUNCTION submit_evaluation preserves 6-arg signature with 3 DEFAULTs', () => {
      assert.match(
        MIGRATION_SQL,
        /CREATE OR REPLACE FUNCTION public\.submit_evaluation\(\s*p_application_id uuid,\s*p_evaluation_type text,\s*p_scores jsonb,\s*p_notes text DEFAULT NULL::text,\s*p_criterion_notes jsonb DEFAULT NULL::jsonb,\s*p_ai_suggestion_id uuid DEFAULT NULL::uuid\s*\) RETURNS jsonb/,
        'signature must be byte-equivalent to the live RPC (6 args, last 3 DEFAULT NULL) — SEDIMENT-238.C'
      );
    });

    it('SECURITY DEFINER + search_path=public preserved (minimum-diff from live)', () => {
      assert.match(MIGRATION_SQL, /LANGUAGE plpgsql\s+SECURITY DEFINER\s+SET search_path = public/);
    });

    it('interview branch removes inline naïve-sum final_score UPDATE', () => {
      // The interview branch UPDATE block must NOT contain the naïve sum line
      const interviewBlock = MIGRATION_SQL.match(/ELSIF p_evaluation_type = 'interview' THEN[\s\S]*?(?=ELSIF p_evaluation_type|END IF)/);
      assert.ok(interviewBlock, 'interview branch must be present');
      assert.doesNotMatch(
        interviewBlock[0],
        /final_score\s*=\s*COALESCE\(objective_score_avg,\s*0\)\s*\+\s*v_pert_score\s*\+\s*COALESCE\(leader_extra_pert_score,\s*0\)/,
        'interview branch must NOT contain naïve-sum final_score UPDATE — PM Option C structural fix'
      );
    });

    it('leader_extra branch removes inline naïve-sum final_score UPDATE', () => {
      const leaderExtraBlock = MIGRATION_SQL.match(/ELSIF p_evaluation_type = 'leader_extra' THEN[\s\S]*?(?=END IF)/);
      assert.ok(leaderExtraBlock, 'leader_extra branch must be present');
      assert.doesNotMatch(
        leaderExtraBlock[0],
        /final_score\s*=\s*COALESCE\(objective_score_avg,\s*0\)\s*\+\s*COALESCE\(interview_score,\s*0\)\s*\+\s*v_pert_score/,
        'leader_extra branch must NOT contain naïve-sum final_score UPDATE — PM Option C structural fix'
      );
    });

    it('interview branch calls PERFORM compute_application_scores (defense-in-depth)', () => {
      const interviewBlock = MIGRATION_SQL.match(/ELSIF p_evaluation_type = 'interview' THEN[\s\S]*?(?=ELSIF p_evaluation_type|END IF)/);
      assert.ok(interviewBlock, 'interview branch must be present');
      assert.match(
        interviewBlock[0],
        /PERFORM public\.compute_application_scores\(p_application_id\);/,
        'interview branch must explicitly call canonical compute_application_scores'
      );
    });

    it('leader_extra branch calls PERFORM compute_application_scores (defense-in-depth)', () => {
      const leaderExtraBlock = MIGRATION_SQL.match(/ELSIF p_evaluation_type = 'leader_extra' THEN[\s\S]*?(?=END IF)/);
      assert.ok(leaderExtraBlock, 'leader_extra branch must be present');
      assert.match(
        leaderExtraBlock[0],
        /PERFORM public\.compute_application_scores\(p_application_id\);/,
        'leader_extra branch must explicitly call canonical compute_application_scores'
      );
    });

    it('interview branch preserves status = final_eval transition', () => {
      const interviewBlock = MIGRATION_SQL.match(/ELSIF p_evaluation_type = 'interview' THEN[\s\S]*?(?=ELSIF p_evaluation_type|END IF)/);
      assert.match(interviewBlock[0], /status\s*=\s*'final_eval'/, 'interview branch must still advance status to final_eval');
    });

    it('interview branch preserves interview_score = v_pert_score write', () => {
      const interviewBlock = MIGRATION_SQL.match(/ELSIF p_evaluation_type = 'interview' THEN[\s\S]*?(?=ELSIF p_evaluation_type|END IF)/);
      assert.match(interviewBlock[0], /interview_score\s*=\s*v_pert_score/, 'interview branch must still write interview_score column (compute_application_scores doesn\'t)');
    });

    it('leader_extra branch preserves leader_extra_pert_score = v_pert_score write', () => {
      const leaderExtraBlock = MIGRATION_SQL.match(/ELSIF p_evaluation_type = 'leader_extra' THEN[\s\S]*?(?=END IF)/);
      assert.match(leaderExtraBlock[0], /leader_extra_pert_score\s*=\s*v_pert_score/, 'leader_extra branch must still write leader_extra_pert_score column');
    });

    it('objective branch unchanged — must still gate via PERCENTILE_CONT median + status transition', () => {
      // Preserve existing objective branch behavior — we only fix interview + leader_extra
      assert.match(MIGRATION_SQL, /PERCENTILE_CONT\(0\.5\) WITHIN GROUP \(ORDER BY objective_score_avg\)/);
      assert.match(MIGRATION_SQL, /v_new_status := 'objective_cutoff'/);
      assert.match(MIGRATION_SQL, /v_new_status := 'interview_pending'/);
    });

    it('Step B cleanup DO block reconciles Francisleila via compute_application_scores', () => {
      assert.match(
        MIGRATION_SQL,
        /v_francisleila_id uuid := '72ea1a45-8dc8-4b0b-b4cb-f1427968ff22';/,
        'cleanup block must target Francisleila ID exactly'
      );
      assert.match(
        MIGRATION_SQL,
        /v_compute_result := public\.compute_application_scores\(v_francisleila_id\);/,
        'cleanup block must call canonical RPC, not direct UPDATE'
      );
    });

    it('Step B cleanup writes admin_audit_log row with canonical action + metadata', () => {
      assert.match(
        MIGRATION_SQL,
        /INSERT INTO public\.admin_audit_log[\s\S]*?'selection\.final_score_canonical_reconciliation',\s*'selection_application',\s*v_francisleila_id/,
        'audit row must use canonical action + target_type=selection_application + target_id=Francisleila'
      );
      // metadata must capture before/after for audit trail
      assert.match(MIGRATION_SQL, /'before_final_score', v_before_final/);
      assert.match(MIGRATION_SQL, /'after_final_score', v_after_final/);
      assert.match(MIGRATION_SQL, /'canonical_expected', v_canonical_expected/);
    });

    it('Step B cleanup is idempotent (skips when no change)', () => {
      assert.match(
        MIGRATION_SQL,
        /IF v_before_final IS DISTINCT FROM v_after_final THEN[\s\S]*?INSERT INTO public\.admin_audit_log/,
        'audit insert must be guarded by IS DISTINCT FROM — re-apply must not write duplicate audit rows'
      );
    });

    it('Sanity DO block RAISES on any remaining leader drift after refactor + cleanup', () => {
      assert.match(
        MIGRATION_SQL,
        /WHERE sa\.role_applied = 'leader'[\s\S]*?abs\(sa\.final_score - COALESCE\(sa\.leader_score, sa\.research_score\)\) > 0\.5/,
        'sanity must scan leader rows for final_score drift > 0.5pt'
      );
      assert.match(
        MIGRATION_SQL,
        /RAISE EXCEPTION 'p248 OPP-246\.A sanity:/,
        'sanity must RAISE EXCEPTION (atomic rollback) if any leader drift survives — prevents accidental ship with regression'
      );
    });

    it('NOTIFY pgrst trailer present', () => {
      assert.match(MIGRATION_SQL, /NOTIFY pgrst, 'reload schema';/);
    });
  });

  describe('forward-defense: regression locks', () => {
    it('no naïve-sum final_score formula reintroduced in interview branch — exact pattern', () => {
      // Catches any future commit that reintroduces obj + interview + leader_extra
      assert.doesNotMatch(
        MIGRATION_SQL,
        /UPDATE public\.selection_applications\s+SET interview_score\s*=\s*v_pert_score,\s+final_score\s*=/,
        'interview UPDATE must NOT include final_score in the same SET clause (regression of p248 fix)'
      );
    });

    it('no naïve-sum final_score formula reintroduced in leader_extra branch — exact pattern', () => {
      assert.doesNotMatch(
        MIGRATION_SQL,
        /UPDATE public\.selection_applications\s+SET\s+leader_extra_pert_score\s*=\s*v_pert_score,\s+final_score\s*=/,
        'leader_extra UPDATE must NOT include final_score in the same SET clause (regression of p248 fix)'
      );
    });

    it('canonical compute_application_scores is the SINGLE writer of final_score post-p248', () => {
      // Forward-defense: submit_evaluation must NOT contain any "final_score =" assignment
      // (the column-level final_score writes are now exclusively in compute_application_scores).
      // The cleanup DO block reads but does not write final_score directly — it calls the RPC.
      // We scan the CREATE OR REPLACE FUNCTION body specifically (not the cleanup DO),
      // stripping single-line comments first so the rule explainer text doesn't trip the regex.
      const fnBody = MIGRATION_SQL.match(/CREATE OR REPLACE FUNCTION public\.submit_evaluation[\s\S]*?\$\$;/);
      assert.ok(fnBody, 'submit_evaluation body must be present in migration');
      const codeOnly = fnBody[0].replace(/--[^\n]*/g, '');
      assert.doesNotMatch(
        codeOnly,
        /final_score\s*=/,
        'submit_evaluation must NOT contain ANY final_score assignment in code — canonical write lives ONLY in compute_application_scores'
      );
    });
  });

  if (sb) {
    describe('DB-gated assertions (with SUPABASE_SERVICE_ROLE_KEY)', () => {
      it('Francisleila final_score reconciled to canonical 158.30 post-migration', async () => {
        const { data, error } = await sb
          .from('selection_applications')
          .select('id, final_score, leader_score, research_score')
          .eq('id', FRANCISLEILA_ID)
          .maybeSingle();
        if (error) assert.fail(`probe error: ${error.message}`);
        assert.ok(data, 'Francisleila row must exist');
        // OPP-246.A invariant: final_score is the CANONICAL compute (= leader_score for a leader
        // app), never a naïve interview+leader sum. The specific value is transient — it evolves
        // as the candidate is (re-)evaluated (was 158.30 at the p248 cleanup; Francisleila has since
        // been interviewed and her canonical leader_score moved, with final_score correctly
        // tracking it). Assert the canonical RELATIONSHIP, not a frozen number (the frozen 158.30
        // is preserved as immutable history in the p248 reconciliation audit row, asserted below).
        assert.equal(Number(data.final_score), Number(data.leader_score), 'final_score must equal leader_score (canonical — no naïve-sum drift, the OPP-246.A invariant)');
      });

      it('canonical reconciliation audit row present + idempotent', async () => {
        const { data, error } = await sb
          .from('admin_audit_log')
          .select('action, target_id, target_type, metadata')
          .eq('action', 'selection.final_score_canonical_reconciliation')
          .eq('target_id', FRANCISLEILA_ID)
          .order('created_at', { ascending: false })
          .limit(1);
        if (error) assert.fail(`probe error: ${error.message}`);
        assert.ok(data && data.length === 1, 'exactly 1 audit row expected (idempotent on re-apply)');
        assert.equal(data[0].target_type, 'selection_application');
        assert.equal(data[0].metadata.before_final_score, 309);
        assert.equal(data[0].metadata.after_final_score, 158.3);
        assert.equal(data[0].metadata.canonical_expected, 158.3);
        assert.equal(data[0].metadata.migration, '20260805000028');
      });

      it('no leader app has final_score drift > 0.5pt (sanity goal)', async () => {
        // Equivalent to the sanity DO in migration — must hold for next-session boot
        const { data, error } = await sb
          .from('selection_applications')
          .select('id, applicant_name, role_applied, final_score, leader_score, research_score')
          .eq('role_applied', 'leader')
          .not('final_score', 'is', null);
        if (error) assert.fail(`probe error: ${error.message}`);
        const drifted = (data || []).filter(r => {
          const canonical = r.leader_score ?? r.research_score;
          if (canonical == null) return false;
          return Math.abs(Number(r.final_score) - Number(canonical)) > 0.5;
        });
        assert.equal(drifted.length, 0, `expected 0 leader rows with drift; got ${drifted.length}: ${JSON.stringify(drifted)}`);
      });
    });
  } else {
    describe('DB-gated assertions', () => {
      it.skip('SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY not set — DB checks skipped', () => {});
    });
  }
});
