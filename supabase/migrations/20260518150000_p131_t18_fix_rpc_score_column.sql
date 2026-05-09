-- p131 T-18 follow-up — fix compute_pert_cutoff para usar objective_score_avg
-- ============================================================================
--
-- Driver: descoberta inline 2026-05-09 ~14:30 BRT (handoff p131 follow-up).
-- RPC compute_pert_cutoff deployado em 5576b91 usava `final_score` por default,
-- gerando régua 265.96 para cycle 3 batch 1 (n=24). Handoff p129 documentou
-- 166.65 como régua canonical, calculada sobre `objective_score_avg`. Cycle 4
-- foi populado inline com objective_score_avg (target 167.02, banda 150.32-
-- 183.72) com autorização do PM. Esta migration corrige o RPC para que
-- próximas invocações usem a coluna correta por default.
--
-- Mudança de assinatura: DROP + CREATE (adiciona param p_score_column).
-- Novo param: p_score_column text DEFAULT 'objective_score_avg'.
-- Whitelist: 'objective_score_avg' | 'final_score' | 'research_score'.
-- Implementação via CASE expression (sem dynamic SQL — mais seguro).
--
-- Compatibilidade: chamadas anteriores ao RPC com 3 args (ou menos) continuam
-- funcionando, mas agora COLUNA DEFAULT É objective_score_avg, não final_score.
-- Isto é breaking change semântico mas alinhado com a metodologia canonical
-- documentada no p129. Caller que precisar do comportamento antigo passa
-- p_score_column => 'final_score' explicitamente.
--
-- Rollback: DROP + recriar versão anterior (commit 5576b91 tem a fonte).
-- ============================================================================

DROP FUNCTION IF EXISTS public.compute_pert_cutoff(uuid, text, boolean);

CREATE OR REPLACE FUNCTION public.compute_pert_cutoff(
  p_cycle_id uuid,
  p_role text DEFAULT 'researcher',
  p_filter_active_only boolean DEFAULT true,
  p_score_column text DEFAULT 'objective_score_avg'
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record;
  v_cycle record;
  v_cohort record;
  v_target numeric;
  v_band_lower numeric;
  v_band_upper numeric;
  v_method text;
  v_n int;
  v_updated_rows int;
  v_fallback_target numeric;
BEGIN
  -- Auth gate
  SELECT m.id, m.name INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;
  IF NOT public.can_by_member(v_member.id, 'manage_member') THEN
    RETURN jsonb_build_object('error', 'access_denied', 'required', 'manage_member');
  END IF;

  -- p131 follow-up: whitelist de score_column. Reduz superfície e evita
  -- dynamic SQL com identifier injection.
  IF p_score_column NOT IN ('objective_score_avg', 'final_score', 'research_score') THEN
    RETURN jsonb_build_object(
      'error', 'invalid_score_column',
      'allowed', jsonb_build_array('objective_score_avg', 'final_score', 'research_score'),
      'received', p_score_column
    );
  END IF;

  -- Cycle target validation
  SELECT sc.id, sc.cycle_code INTO v_cycle
  FROM public.selection_cycles sc WHERE sc.id = p_cycle_id;
  IF v_cycle.id IS NULL THEN
    RETURN jsonb_build_object('error', 'cycle_not_found');
  END IF;

  -- Cohort: approved applications role=p_role, em cycles ANTERIORES, com
  -- score na coluna selecionada. CASE-based column selection (sem dynamic SQL).
  WITH prior_cycles AS (
    SELECT id FROM public.selection_cycles
    WHERE id != p_cycle_id
      AND created_at < (SELECT created_at FROM public.selection_cycles WHERE id = p_cycle_id)
  ),
  cohort_apps AS (
    SELECT
      CASE p_score_column
        WHEN 'objective_score_avg' THEN sa.objective_score_avg
        WHEN 'final_score' THEN sa.final_score
        WHEN 'research_score' THEN sa.research_score
      END AS s
    FROM public.selection_applications sa
    WHERE sa.cycle_id IN (SELECT id FROM prior_cycles)
      AND sa.role_applied = p_role
      AND sa.status = 'approved'
      AND CASE p_score_column
            WHEN 'objective_score_avg' THEN sa.objective_score_avg IS NOT NULL
            WHEN 'final_score' THEN sa.final_score IS NOT NULL
            WHEN 'research_score' THEN sa.research_score IS NOT NULL
          END
      AND (
        NOT p_filter_active_only
        OR EXISTS (
          SELECT 1 FROM public.engagements e
          JOIN public.persons pp ON pp.id = e.person_id
          WHERE pp.legacy_member_id IS NOT NULL
            AND e.kind = 'volunteer'
            AND e.role = p_role
            AND e.status = 'active'
            AND lower(coalesce(sa.email,'')) IN (
              SELECT lower(m.email) FROM public.members m
              WHERE m.id = pp.legacy_member_id AND m.email IS NOT NULL
            )
        )
      )
  )
  SELECT
    COUNT(*)::int AS n,
    MIN(s) AS s_min,
    MAX(s) AS s_max,
    AVG(s) AS s_avg
  INTO v_cohort
  FROM cohort_apps;

  v_n := COALESCE(v_cohort.n, 0);

  -- Decisão C: n>=10 dynamic / n<10 fallback histórico / sem histórico = disabled
  IF v_n >= 10 THEN
    v_target := (2 * v_cohort.s_min + 4 * v_cohort.s_avg + 2 * v_cohort.s_max) / 8;
    v_method := 'dynamic';
  ELSE
    SELECT MAX(pert_target_score) INTO v_fallback_target
    FROM public.selection_applications
    WHERE pert_target_score IS NOT NULL
      AND cycle_id != p_cycle_id;
    IF v_fallback_target IS NULL THEN
      v_target := NULL;
      v_method := 'disabled';
    ELSE
      v_target := v_fallback_target;
      v_method := 'historical_fallback';
    END IF;
  END IF;

  -- Decisão D: banda ±10%
  IF v_target IS NOT NULL THEN
    v_band_lower := v_target * 0.90;
    v_band_upper := v_target * 1.10;
  END IF;

  -- Update cycle target rows
  UPDATE public.selection_applications
  SET pert_target_score = v_target,
      pert_band_lower = v_band_lower,
      pert_band_upper = v_band_upper,
      pert_cutoff_method = v_method,
      pert_cohort_n = v_n,
      pert_calc_at = now()
  WHERE cycle_id = p_cycle_id;
  GET DIAGNOSTICS v_updated_rows = ROW_COUNT;

  -- Audit log (now includes score_column_used)
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_member.id,
    'pert_cutoff_computed',
    'selection_cycle',
    p_cycle_id,
    jsonb_build_object(
      'cycle_code', v_cycle.cycle_code,
      'role', p_role,
      'score_column_used', p_score_column,
      'filter_active_only', p_filter_active_only,
      'cohort_n', v_n,
      'cohort_min', v_cohort.s_min,
      'cohort_max', v_cohort.s_max,
      'cohort_avg', v_cohort.s_avg,
      'target_score', v_target,
      'band_lower', v_band_lower,
      'band_upper', v_band_upper,
      'method', v_method,
      'rows_updated', v_updated_rows
    ),
    jsonb_build_object(
      'source', 'compute_pert_cutoff',
      'p131_t18_backstage', true,
      'p131_followup_score_column_default_objective_score_avg', true
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'cycle_id', p_cycle_id,
    'cycle_code', v_cycle.cycle_code,
    'role', p_role,
    'score_column_used', p_score_column,
    'cohort_n', v_n,
    'cohort_stats', jsonb_build_object(
      'min', v_cohort.s_min,
      'max', v_cohort.s_max,
      'avg', v_cohort.s_avg
    ),
    'target_score', v_target,
    'band_lower', v_band_lower,
    'band_upper', v_band_upper,
    'method', v_method,
    'rows_updated', v_updated_rows,
    'computed_at', now()
  );
END;
$function$;

COMMENT ON FUNCTION public.compute_pert_cutoff(uuid, text, boolean, text) IS
  'p131 T-18 backstage v2 (Decisão F híbrida + p131 followup score_column fix): calcula régua PERT (2*min + 4*avg + 2*max)/8 sobre cohort histórica configurável. p_score_column DEFAULT ''objective_score_avg'' (canonical handoff p129 = 166.65 ≈ 167.02). Whitelist: objective_score_avg | final_score | research_score. Decisão C: n>=10 dynamic, n<10 fallback histórico, n<10 sem histórico = disabled. Decisão D: banda ±10% target. Auth gate: manage_member. Idempotente. Backstage-only — UI badge defer cycle 5.';

NOTIFY pgrst, 'reload schema';
