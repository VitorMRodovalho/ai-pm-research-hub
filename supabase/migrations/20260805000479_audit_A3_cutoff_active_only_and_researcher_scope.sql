-- Audit 2026-07-21 (docs/audit/2026-07-21_scoring_merit_audit.md) — Finding A3 (MÉDIA) + decisões do owner
-- (2026-07-21 ratificada; execução Onda 2 em 2026-07-23).
--
-- A3 parte 1 (corte active-only): _compute_pert_cutoff_core aceitava p_filter_active_only mas NUNCA
-- o usava (só logava 'filter_active_only_legacy_arg'). O cohort do corte incluía candidatos já
-- rejeitados, puxando a régua para baixo. Ciclo 4 researcher: com rejeitados = 130.89; só ativos =
-- 142.69 (o min sobe de 58.50 p/ 93.50). Decisão do owner: ativar active-only, semântica RETROATIVA
-- (ciente do impacto nos 7 aprovados entre 130.9 e 142.7 — NÃO revogar aprovação; tratar display via
-- badge admin, ver src/pages/admin/selection.astro).
--
-- A3 parte 2 (cross-role, "corrigir agora" — decisão do owner 2026-07-23): o corte objetivo é
-- researcher-only, mas o UPDATE carimbava pert_target_score em TODAS as linhas do ciclo (inclusive
-- líderes), e get_cutoff_dispatch_health / _selection_cutoff_pending_cron comparavam obj>=pert_target
-- sem filtro de role. Correção em 3 frentes:
--   (F1) _compute_pert_cutoff_core: o UPDATE da coluna objetiva passa a escopar role_applied = p_role.
--   (F3) get_cutoff_dispatch_health: cohort pendente ganha AND role_applied = 'researcher'.
--   (F4) _selection_cutoff_pending_cron: cohort de dispatch ganha AND role_applied = 'researcher'.
--   (DML) nulificar pert_target_score/band de líderes (resíduo do carimbo cross-role; 14 linhas ao
--         vivo em 2026-07-23: 11 no cycle4-2026 + 3 no cycle3-2026-b2). Isso torna get_selection_dashboard,
--         get_selection_rankings, get_pert_cutoff_summary, get_application_score_breakdown e
--         get_evaluation_form researcher-only "de graça" (MAX ignora NULL; leituras por-linha viram NULL
--         para líder = correto, líder usa leader_extra_cutoff).
-- Base = corpo VIVO via pg_get_functiondef; nenhuma outra linha muda.
--
-- APLICAÇÃO (sessão main): após apply, recomputar SÓ o corte objetivo researcher p/ materializar 142.69:
--   SELECT public._compute_pert_cutoff_core('08c1e301-9f7b-4d01-a13c-43ac7775c0f7','researcher', TRUE,
--                                            'objective_score_avg', <actor_member_id>);
--   NÃO rodar compute_application_scores em massa (re-dispararia a cascata da régua final_score_pert
--   histórica que a Onda 1 limpou).

-- ============================================================================
-- F1. _compute_pert_cutoff_core — honrar p_filter_active_only + escopar UPDATE objetivo a role.
-- ============================================================================
CREATE OR REPLACE FUNCTION public._compute_pert_cutoff_core(p_cycle_id uuid, p_role text DEFAULT 'researcher'::text, p_filter_active_only boolean DEFAULT true, p_score_column text DEFAULT 'objective_score_avg'::text, p_actor_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_cycle record;
  v_cohort record;
  v_target numeric;
  v_band_lower numeric;
  v_band_upper numeric;
  v_method text;
  v_n int;
  v_updated_rows int;
  v_fallback_target numeric;
  v_is_leader_extra boolean;
  v_is_final_score boolean;
BEGIN
  IF p_score_column NOT IN ('objective_score_avg', 'final_score', 'research_score', 'leader_extra_pert_score') THEN
    RETURN jsonb_build_object(
      'error', 'invalid_score_column',
      'allowed', jsonb_build_array('objective_score_avg', 'final_score', 'research_score', 'leader_extra_pert_score'),
      'received', p_score_column
    );
  END IF;

  v_is_leader_extra := (p_score_column = 'leader_extra_pert_score');
  v_is_final_score := (p_score_column = 'final_score');

  SELECT sc.id, sc.cycle_code INTO v_cycle FROM public.selection_cycles sc WHERE sc.id = p_cycle_id;
  IF v_cycle.id IS NULL THEN
    RETURN jsonb_build_object('error', 'cycle_not_found', 'cycle_id', p_cycle_id);
  END IF;

  WITH cohort_apps AS (
    SELECT
      CASE p_score_column
        WHEN 'objective_score_avg' THEN sa.objective_score_avg
        WHEN 'final_score' THEN sa.final_score
        WHEN 'research_score' THEN sa.research_score
        WHEN 'leader_extra_pert_score' THEN sa.leader_extra_pert_score
      END AS s
    FROM public.selection_applications sa
    WHERE sa.cycle_id = p_cycle_id
      AND sa.role_applied = p_role
      -- Audit A3: honrar p_filter_active_only — excluir status terminais fora do processo.
      AND (NOT p_filter_active_only
           OR sa.status NOT IN ('rejected', 'withdrawn', 'cancelled', 'objective_cutoff', 'merged'))
      AND CASE p_score_column
            WHEN 'objective_score_avg' THEN sa.objective_score_avg IS NOT NULL
            WHEN 'research_score' THEN sa.research_score IS NOT NULL
            WHEN 'leader_extra_pert_score' THEN sa.leader_extra_pert_score IS NOT NULL
            WHEN 'final_score' THEN
              sa.final_score IS NOT NULL
              AND sa.interview_score IS NOT NULL
              AND (
                p_role != 'leader'
                OR sa.leader_extra_pert_score IS NOT NULL
              )
          END
  )
  SELECT COUNT(*)::int AS n, MIN(s) AS s_min, MAX(s) AS s_max, AVG(s) AS s_avg
  INTO v_cohort FROM cohort_apps;

  v_n := COALESCE(v_cohort.n, 0);

  IF v_n >= 10 THEN
    v_target := (2 * v_cohort.s_min + 4 * v_cohort.s_avg + 2 * v_cohort.s_max) / 8;
    v_method := 'dynamic';
  ELSE
    IF v_is_final_score THEN
      SELECT MAX(final_score_pert_target)
      INTO v_fallback_target
      FROM public.selection_applications
      WHERE cycle_id != p_cycle_id
        AND role_applied = p_role
        AND final_score_pert_target IS NOT NULL;
    ELSE
      SELECT MAX(CASE WHEN v_is_leader_extra THEN leader_extra_pert_target ELSE pert_target_score END)
      INTO v_fallback_target
      FROM public.selection_applications
      WHERE cycle_id != p_cycle_id
        AND CASE WHEN v_is_leader_extra THEN leader_extra_pert_target IS NOT NULL ELSE pert_target_score IS NOT NULL END;
    END IF;
    IF v_fallback_target IS NULL THEN
      v_target := NULL; v_method := 'disabled';
    ELSE
      v_target := v_fallback_target; v_method := 'historical_fallback';
    END IF;
  END IF;

  IF v_target IS NOT NULL THEN
    v_band_lower := v_target * 0.75;
    v_band_upper := v_target;
  END IF;

  IF v_is_leader_extra THEN
    -- Audit A3 (cross-role, simetria): a régua leader_extra é por-role — carimbar SÓ as linhas do role
    -- (evita o espelho do bug objetivo; latente hoje, mas trava regressão futura). p_role='leader' aqui.
    UPDATE public.selection_applications
    SET leader_extra_pert_target = v_target,
        leader_extra_pert_band_lower = v_band_lower,
        leader_extra_pert_band_upper = v_band_upper,
        leader_extra_pert_cutoff_method = v_method,
        leader_extra_pert_cohort_n = v_n,
        leader_extra_pert_calc_at = now()
    WHERE cycle_id = p_cycle_id
      AND role_applied = p_role;
  ELSIF v_is_final_score THEN
    UPDATE public.selection_applications
    SET final_score_pert_target = v_target,
        final_score_pert_band_lower = v_band_lower,
        final_score_pert_band_upper = v_band_upper,
        final_score_pert_cutoff_method = v_method,
        final_score_pert_cohort_n = v_n,
        final_score_pert_calc_at = now()
    WHERE cycle_id = p_cycle_id
      AND role_applied = p_role;
  ELSE
    -- Audit A3 (cross-role): o corte objetivo/research é researcher-only — carimbar SÓ as linhas do role.
    UPDATE public.selection_applications
    SET pert_target_score = v_target,
        pert_band_lower = v_band_lower,
        pert_band_upper = v_band_upper,
        pert_cutoff_method = v_method,
        pert_cohort_n = v_n,
        pert_calc_at = now()
    WHERE cycle_id = p_cycle_id
      AND role_applied = p_role;
  END IF;
  GET DIAGNOSTICS v_updated_rows = ROW_COUNT;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    p_actor_id, 'pert_cutoff_computed', 'selection_cycle', p_cycle_id,
    jsonb_build_object(
      'cycle_code', v_cycle.cycle_code,
      'role', p_role,
      'score_column_used', p_score_column,
      'filter_active_only', p_filter_active_only,
      'cohort_scope', CASE WHEN p_filter_active_only THEN 'active_applications_by_role' ELSE 'all_applications_by_role' END,
      'final_score_requires_complete_components', v_is_final_score,
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
    jsonb_build_object('source', '_compute_pert_cutoff_core', 'actor_kind', CASE WHEN p_actor_id IS NULL THEN 'system' ELSE 'human' END, 'cr', 'CR-042', 'audit', 'A3-active-only-2026-07-21')
  );

  RETURN jsonb_build_object(
    'success', true, 'cycle_id', p_cycle_id, 'cycle_code', v_cycle.cycle_code,
    'role', p_role, 'score_column_used', p_score_column,
    'cohort_scope', CASE WHEN p_filter_active_only THEN 'active_applications_by_role' ELSE 'all_applications_by_role' END,
    'cohort_n', v_n,
    'cohort_stats', jsonb_build_object('min', v_cohort.s_min, 'max', v_cohort.s_max, 'avg', v_cohort.s_avg),
    'target_score', v_target, 'band_lower', v_band_lower, 'band_upper', v_band_upper,
    'method', v_method, 'rows_updated', v_updated_rows, 'computed_at', now()
  );
END;
$function$;

-- ============================================================================
-- F3. get_cutoff_dispatch_health — cohort pendente do corte objetivo é researcher-only.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_cutoff_dispatch_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cutoff_runs jsonb;
  v_rescue_runs jsonb;
  v_cutoff_last timestamptz;
  v_rescue_last timestamptz;
  v_cutoff_job jsonb;
  v_rescue_job jsonb;
  v_pending_cutoff int;
  v_pending_stuck int;
  v_signal text;
BEGIN
  -- Authority: same gate as the other selection read surfaces.
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- last 7 runs of each cron, newest first (source: aggregate audit rows).
  SELECT COALESCE(jsonb_agg(r ORDER BY (r->>'run_at') DESC), '[]'::jsonb), MAX((r->>'run_at')::timestamptz)
  INTO v_cutoff_runs, v_cutoff_last
  FROM (
    SELECT jsonb_build_object(
             'run_at', COALESCE(l.metadata->>'run_at', l.created_at::text),
             'dispatched_count', (l.metadata->>'dispatched_count'),
             'error_count', (l.metadata->>'error_count'),
             'cycle_codes_touched', l.metadata->'cycle_codes_touched'
           ) AS r
    FROM public.admin_audit_log l
    WHERE l.action = 'selection.cutoff_pending_cron_run'
    ORDER BY l.created_at DESC
    LIMIT 7
  ) s;

  SELECT COALESCE(jsonb_agg(r ORDER BY (r->>'run_at') DESC), '[]'::jsonb), MAX((r->>'run_at')::timestamptz)
  INTO v_rescue_runs, v_rescue_last
  FROM (
    SELECT jsonb_build_object(
             'run_at', COALESCE(l.metadata->>'run_at', l.created_at::text),
             'rescued_count', (l.metadata->>'rescued_count'),
             'error_count', (l.metadata->>'error_count')
           ) AS r
    FROM public.admin_audit_log l
    WHERE l.action = 'selection.stuck_rescue_cron_run'
    ORDER BY l.created_at DESC
    LIMIT 7
  ) s;

  -- cron registrations
  SELECT jsonb_build_object('registered', count(*) > 0, 'active', bool_or(active), 'schedule', MAX(schedule))
  INTO v_cutoff_job FROM cron.job WHERE jobname = 'selection-cutoff-pending-daily';
  SELECT jsonb_build_object('registered', count(*) > 0, 'active', bool_or(active), 'schedule', MAX(schedule))
  INTO v_rescue_job FROM cron.job WHERE jobname = 'selection-stuck-scheduled-rescue-daily';

  -- live pending cohorts (the work the crons would pick up next).
  SELECT count(*) INTO v_pending_cutoff
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE a.status IN ('screening', 'interview_pending')
    AND a.role_applied = 'researcher'   -- Audit A3: objective cutoff is researcher-only
    AND a.objective_score_avg IS NOT NULL
    AND a.pert_target_score IS NOT NULL
    AND a.objective_score_avg >= a.pert_target_score
    AND a.cutoff_approved_email_sent_at IS NULL
    AND c.status = 'open';

  SELECT count(*) INTO v_pending_stuck
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE a.status = 'interview_scheduled'
    AND c.status = 'open'
    AND EXISTS (
      SELECT 1 FROM public.selection_interviews si
      WHERE si.application_id = a.id
        AND si.status = 'scheduled'
        AND si.conducted_at IS NULL
        AND si.scheduled_at IS NOT NULL
        AND si.scheduled_at < now() - interval '48 hours'
    );

  -- health: red if there is pending work and the relevant cron is silent > 26h (daily + grace);
  -- yellow if a cron is unregistered/inactive or has never fired; green otherwise.
  v_signal := 'green';
  IF COALESCE((v_cutoff_job->>'registered')::boolean, false) = false
     OR COALESCE((v_cutoff_job->>'active')::boolean, false) = false
     OR COALESCE((v_rescue_job->>'registered')::boolean, false) = false
     OR COALESCE((v_rescue_job->>'active')::boolean, false) = false
     OR v_cutoff_last IS NULL
     OR v_rescue_last IS NULL THEN   -- either cron never-fired = not-yet-proven = yellow
    v_signal := 'yellow';
  END IF;
  IF (v_pending_cutoff > 0 AND (v_cutoff_last IS NULL OR v_cutoff_last < now() - interval '26 hours'))
     OR (v_pending_stuck > 0 AND (v_rescue_last IS NULL OR v_rescue_last < now() - interval '26 hours')) THEN
    v_signal := 'red';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'health_signal', v_signal,
    'cutoff_pending', jsonb_build_object(
      'job', v_cutoff_job,
      'last_run_at', v_cutoff_last,
      'recent_runs', v_cutoff_runs,
      'pending_now', v_pending_cutoff
    ),
    'stuck_rescue', jsonb_build_object(
      'job', v_rescue_job,
      'last_run_at', v_rescue_last,
      'recent_runs', v_rescue_runs,
      'pending_now', v_pending_stuck
    ),
    'generated_at', now()
  );
END;
$function$;

-- ============================================================================
-- F4. _selection_cutoff_pending_cron — dispatcher do corte objetivo é researcher-only.
-- ============================================================================
CREATE OR REPLACE FUNCTION public._selection_cutoff_pending_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_app record;
  v_dispatched int := 0;
  v_errors int := 0;
  v_cycles text[] := '{}';
  v_run_at timestamptz := now();
BEGIN
  FOR v_app IN
    SELECT a.id AS app_id, c.cycle_code
    FROM public.selection_applications a
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE a.status IN ('screening', 'interview_pending')
      AND a.role_applied = 'researcher'                   -- Audit A3: objective cutoff is researcher-only
      AND a.objective_score_avg IS NOT NULL
      AND a.pert_target_score IS NOT NULL
      AND a.objective_score_avg >= a.pert_target_score   -- STRICT above-target only (NOT in_band)
      AND a.cutoff_approved_email_sent_at IS NULL          -- pre-flight idempotency
      AND c.status = 'open'
    ORDER BY a.objective_score_avg DESC
    LIMIT 50                                               -- runaway cap
  LOOP
    -- Per-row subtransaction: one bad app (e.g. CUTOFF_NO_BOOKING_URL) never aborts the run.
    BEGIN
      PERFORM public.notify_selection_cutoff_approved(v_app.app_id);
      v_dispatched := v_dispatched + 1;
      IF NOT (v_app.cycle_code = ANY (v_cycles)) THEN
        v_cycles := array_append(v_cycles, v_app.cycle_code);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors + 1;
    END;
  END LOOP;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL, 'selection.cutoff_pending_cron_run', 'system', NULL,
    jsonb_build_object('dispatched_count', v_dispatched, 'error_count', v_errors),
    jsonb_build_object(
      'dispatched_count', v_dispatched,
      'error_count', v_errors,
      'cycle_codes_touched', to_jsonb(v_cycles),
      'run_at', v_run_at,
      'limit', 50,
      'policy', 'strict_above_target'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'dispatched_count', v_dispatched,
    'error_count', v_errors,
    'cycle_codes_touched', to_jsonb(v_cycles),
    'run_at', v_run_at
  );
END;
$function$;

-- ============================================================================
-- DML. Nulificar o corte objetivo carimbado em linhas de líder (resíduo do bug cross-role).
-- Idempotente. O corte objetivo é researcher-only; líder usa leader_extra_cutoff.
-- ============================================================================
UPDATE public.selection_applications
SET pert_target_score = NULL,
    pert_band_lower = NULL,
    pert_band_upper = NULL,
    pert_cutoff_method = NULL,
    pert_cohort_n = NULL,
    pert_calc_at = NULL
WHERE role_applied = 'leader'
  AND pert_target_score IS NOT NULL;
