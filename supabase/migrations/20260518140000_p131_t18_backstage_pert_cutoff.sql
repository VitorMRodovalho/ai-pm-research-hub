-- p131 T-18 backstage — Decisão F híbrida (schema + RPC, sem UI badge)
-- ============================================================================
--
-- Driver: Decisão F do p129 (defer T-18 PERT cutoff feature) revisada em p131
-- pós-auditoria. Recomendação aceita: implementar A+B (schema + RPC) AGORA mas
-- NÃO C (UI badge ao evaluator). Resultado:
--   - Régua dinâmica calculada e armazenada para cycles em andamento
--   - Disponível só backstage (admin/PM via SQL ou dashboard interno futuro)
--   - Zero anchoring bias em evaluators (sediment p93 #120 — AI scores não
--     visíveis antes da nota humana)
--   - Cycle 5 baseline limpo: dados históricos cycle 4 acumulam SEM contaminação
--   - Quando ligarmos UI badge no cycle 5, dados já estão lá → toggle de feature flag
--
-- Sem regressão: todas as colunas são NULL-permissive. Aplicações existentes
-- continuam funcionando. RPC compute_pert_cutoff é idempotente.
--
-- Rollback: ALTER TABLE selection_applications DROP COLUMN pert_target_score,
--           pert_band_lower, pert_band_upper, pert_cutoff_method, pert_cohort_n,
--           pert_calc_at; DROP FUNCTION compute_pert_cutoff. Sem dependências
--           circulares.
-- ============================================================================

-- 1) Schema additions (6 cols)
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS pert_target_score numeric,
  ADD COLUMN IF NOT EXISTS pert_band_lower numeric,
  ADD COLUMN IF NOT EXISTS pert_band_upper numeric,
  ADD COLUMN IF NOT EXISTS pert_cutoff_method text
    CHECK (pert_cutoff_method IS NULL OR pert_cutoff_method IN ('dynamic','historical_fallback','disabled')),
  ADD COLUMN IF NOT EXISTS pert_cohort_n int,
  ADD COLUMN IF NOT EXISTS pert_calc_at timestamptz;

COMMENT ON COLUMN public.selection_applications.pert_target_score IS
  'p131 T-18 backstage: régua PERT calculada para o cycle desta application via compute_pert_cutoff(). Computada como (2*min + 4*avg + 2*max)/8 sobre cohort histórica (default: approved researchers de cycles anteriores). Não exposta ao evaluator UI até cycle 5.';

COMMENT ON COLUMN public.selection_applications.pert_band_lower IS
  'p131 T-18: limite inferior da banda de tolerância (default target * 0.90 = -10%). Score abaixo deste valor = "atenção, abaixo da régua".';

COMMENT ON COLUMN public.selection_applications.pert_band_upper IS
  'p131 T-18: limite superior da banda (default target * 1.10 = +10%). Score acima = "acima da régua, candidate forte".';

COMMENT ON COLUMN public.selection_applications.pert_cutoff_method IS
  'p131 T-18: método usado: dynamic (n>=10 → cohort histórica suficiente), historical_fallback (n<10 → uso último target conhecido), disabled (cycle não habilitado para PERT cutoff).';

COMMENT ON COLUMN public.selection_applications.pert_cohort_n IS
  'p131 T-18: tamanho da cohort histórica usada no cálculo. Decisão C p129: n>=10 dynamic; n<10 fallback.';

COMMENT ON COLUMN public.selection_applications.pert_calc_at IS
  'p131 T-18: timestamp da última execução de compute_pert_cutoff() para esta row. NULL = nunca calculado.';

-- 2) RPC compute_pert_cutoff
CREATE OR REPLACE FUNCTION public.compute_pert_cutoff(
  p_cycle_id uuid,
  p_role text DEFAULT 'researcher',
  p_filter_active_only boolean DEFAULT true
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
  -- Auth: manage_member gate (mesmo da recirculate_governance_doc)
  SELECT m.id, m.name INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;
  IF NOT public.can_by_member(v_member.id, 'manage_member') THEN
    RETURN jsonb_build_object('error', 'access_denied', 'required', 'manage_member');
  END IF;

  -- Validação cycle target
  SELECT sc.id, sc.cycle_code INTO v_cycle
  FROM public.selection_cycles sc WHERE sc.id = p_cycle_id;
  IF v_cycle.id IS NULL THEN
    RETURN jsonb_build_object('error', 'cycle_not_found');
  END IF;

  -- Cohort: approved applications com role_applied=p_role, em cycles ANTERIORES
  -- (created_at < cycle target). Filter active_only: aplicação tem engagement
  -- ativo correspondente (volunteer + role).
  WITH prior_cycles AS (
    SELECT id FROM public.selection_cycles
    WHERE id != p_cycle_id
      AND created_at < (SELECT created_at FROM public.selection_cycles WHERE id = p_cycle_id)
  ),
  cohort_apps AS (
    SELECT sa.final_score
    FROM public.selection_applications sa
    WHERE sa.cycle_id IN (SELECT id FROM prior_cycles)
      AND sa.role_applied = p_role
      AND sa.status = 'approved'
      AND sa.final_score IS NOT NULL
      AND (
        NOT p_filter_active_only
        OR EXISTS (
          SELECT 1 FROM public.engagements e
          JOIN public.persons p ON p.id = e.person_id
          WHERE p.legacy_member_id IS NOT NULL
            AND e.kind = 'volunteer'
            AND e.role = p_role
            AND e.status = 'active'
            AND lower(coalesce(sa.email,'')) IN (
              SELECT lower(m.email) FROM public.members m
              WHERE m.id = p.legacy_member_id AND m.email IS NOT NULL
            )
        )
      )
  )
  SELECT
    COUNT(*)::int AS n,
    MIN(final_score) AS s_min,
    MAX(final_score) AS s_max,
    AVG(final_score) AS s_avg
  INTO v_cohort
  FROM cohort_apps;

  v_n := COALESCE(v_cohort.n, 0);

  -- Método (Decisão C p129: n>=10 dynamic, n<10 fallback histórico)
  IF v_n >= 10 THEN
    v_target := (2 * v_cohort.s_min + 4 * v_cohort.s_avg + 2 * v_cohort.s_max) / 8;
    v_method := 'dynamic';
  ELSE
    -- Fallback: pegar último pert_target_score conhecido em qualquer cycle anterior
    SELECT MAX(pert_target_score) INTO v_fallback_target
    FROM public.selection_applications
    WHERE pert_target_score IS NOT NULL
      AND cycle_id != p_cycle_id;
    IF v_fallback_target IS NULL THEN
      -- Sem nenhum histórico ainda — disabled (não força um número falso)
      v_target := NULL;
      v_method := 'disabled';
    ELSE
      v_target := v_fallback_target;
      v_method := 'historical_fallback';
    END IF;
  END IF;

  -- Banda: target ± 10% (Decisão D p129: warning >10% drop)
  IF v_target IS NOT NULL THEN
    v_band_lower := v_target * 0.90;
    v_band_upper := v_target * 1.10;
  END IF;

  -- Update todas applications do cycle target com os valores
  UPDATE public.selection_applications
  SET pert_target_score = v_target,
      pert_band_lower = v_band_lower,
      pert_band_upper = v_band_upper,
      pert_cutoff_method = v_method,
      pert_cohort_n = v_n,
      pert_calc_at = now()
  WHERE cycle_id = p_cycle_id;
  GET DIAGNOSTICS v_updated_rows = ROW_COUNT;

  -- Audit log
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_member.id,
    'pert_cutoff_computed',
    'selection_cycle',
    p_cycle_id,
    jsonb_build_object(
      'cycle_code', v_cycle.cycle_code,
      'role', p_role,
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
    jsonb_build_object('source', 'compute_pert_cutoff', 'p131_t18_backstage', true)
  );

  RETURN jsonb_build_object(
    'success', true,
    'cycle_id', p_cycle_id,
    'cycle_code', v_cycle.cycle_code,
    'role', p_role,
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

COMMENT ON FUNCTION public.compute_pert_cutoff(uuid, text, boolean) IS
  'p131 T-18 backstage (Decisão F híbrida p129/p131): calcula régua PERT dinâmica (2*min + 4*avg + 2*max)/8 sobre cohort histórica (cycles anteriores aprovados, role configurável, filtro active_only opcional). Atualiza pert_* cols em todas applications do cycle target. Decisão C: n>=10 dynamic, n<10 fallback histórico (último target conhecido), n<10 sem histórico = disabled. Decisão D: banda ±10% target. Auth gate: manage_member. Idempotente. Resultado backstage-only — UI badge para evaluator fica para cycle 5 (Decisão F preserva integridade da calibração cycle 4 vs anchoring bias).';

-- 3) Helper RPC para query backstage rápida (admin/PM dashboard futuro)
CREATE OR REPLACE FUNCTION public.get_pert_cutoff_summary(p_cycle_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_summary record;
  v_cycle record;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL OR NOT public.can_by_member(v_member_id, 'manage_member') THEN
    RETURN jsonb_build_object('error', 'access_denied');
  END IF;

  SELECT id, cycle_code INTO v_cycle FROM public.selection_cycles WHERE id = p_cycle_id;
  IF v_cycle.id IS NULL THEN RETURN jsonb_build_object('error', 'cycle_not_found'); END IF;

  SELECT
    COUNT(*) AS apps_total,
    COUNT(*) FILTER (WHERE pert_target_score IS NOT NULL) AS apps_with_pert,
    MAX(pert_calc_at) AS last_calc_at,
    MAX(pert_cohort_n) AS cohort_n,
    MAX(pert_target_score) AS target_score,
    MAX(pert_band_lower) AS band_lower,
    MAX(pert_band_upper) AS band_upper,
    MAX(pert_cutoff_method) AS method,
    COUNT(*) FILTER (WHERE final_score IS NOT NULL AND final_score < pert_band_lower) AS below_band,
    COUNT(*) FILTER (WHERE final_score IS NOT NULL AND final_score > pert_band_upper) AS above_band,
    COUNT(*) FILTER (WHERE final_score IS NOT NULL AND final_score BETWEEN pert_band_lower AND pert_band_upper) AS within_band,
    COUNT(*) FILTER (WHERE final_score IS NULL) AS not_yet_scored
  INTO v_summary
  FROM public.selection_applications
  WHERE cycle_id = p_cycle_id;

  RETURN jsonb_build_object(
    'cycle_id', p_cycle_id,
    'cycle_code', v_cycle.cycle_code,
    'apps_total', v_summary.apps_total,
    'apps_with_pert', v_summary.apps_with_pert,
    'last_calc_at', v_summary.last_calc_at,
    'cohort_n', v_summary.cohort_n,
    'target_score', v_summary.target_score,
    'band_lower', v_summary.band_lower,
    'band_upper', v_summary.band_upper,
    'method', v_summary.method,
    'distribution', jsonb_build_object(
      'below_band', v_summary.below_band,
      'within_band', v_summary.within_band,
      'above_band', v_summary.above_band,
      'not_yet_scored', v_summary.not_yet_scored
    )
  );
END;
$function$;

COMMENT ON FUNCTION public.get_pert_cutoff_summary(uuid) IS
  'p131 T-18 backstage: dashboard read-only para admin/PM ver distribuição PERT cutoff de um cycle (apps below/within/above banda, target, método, last_calc). Backstage only.';

NOTIFY pgrst, 'reload schema';
