-- #2393, fatia 3 (ADR-0134, decisão do GP em 02/11/2026): marcador de piloto por vaga, parte 2 de 2.
--
-- Depende da parte 1 (vep_opportunities.evaluation_track e _na_avaliacao_geral). Esta parte tira a
-- candidatura de vaga 'line_pilot' das AUTOMAÇÕES da avaliação geral:
--   _get_peer_review_eligibility     sem elegíveis para piloto (dispatch_peer_review_invitations não tem
--                                    chamador hoje; a trava fica para quando tiver).
--   _selection_cutoff_pending_cron   o cron do convite à entrevista geral não pega piloto.
--   notify_selection_cutoff_approved recusa piloto por retorno (ponto único: o cron e os 2 resgates).
--   _compute_pert_cutoff_core        (D2) piloto fora da população e do carimbo do corte.
--   recompute_application_status     piloto fora das transições automáticas; mediana só da geral.
--   calculate_rankings, recalculate_cycle_rankings e get_selection_rankings  (D2) piloto fora do ranking.
--   detect_stuck_selection_funnel    piloto não vira aviso de funil travado.
-- Sem mudança, com o motivo no plano da fatia: o fluxo de entrevista (só depois do convite, que esta
-- parte fecha), finalize_decisions e approve_selection_application (ato do GP), triagem por IA (D3),
-- impedimento, métricas agregadas, worker e import_vep_applications (governados por is_active).
--
-- Os 9 corpos são os das capturas vigentes mais as linhas marcadas "#2393 fatia 3". CREATE OR REPLACE
-- preserva dono e privilégios: nenhum GRANT ou REVOKE muda aqui.

CREATE OR REPLACE FUNCTION public._get_peer_review_eligibility(p_application_id uuid)
 RETURNS TABLE(peer_member_id uuid, peer_name text, peer_email text, load_count integer, last_invited_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_app record;
BEGIN
  SELECT cycle_id, email INTO v_app
  FROM public.selection_applications
  WHERE id = p_application_id;

  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found: %', p_application_id;
  END IF;

  -- #2393 fatia 3: candidatura de vaga piloto da linha não recebe convite de revisão por pares.
  IF NOT public._na_avaliacao_geral(p_application_id) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    m.id AS peer_member_id,
    m.name AS peer_name,
    m.email AS peer_email,
    -- load_count = submitted evals + pending invitations (not yet evaluated)
    (
      SELECT count(*)::int
      FROM public.selection_evaluations e
      JOIN public.selection_applications sa ON sa.id = e.application_id
      WHERE e.evaluator_id = m.id AND sa.cycle_id = v_app.cycle_id
    )
    +
    (
      SELECT count(*)::int
      FROM public.notifications n
      JOIN public.selection_applications sa ON sa.id = n.source_id
      WHERE n.type = 'peer_review_requested'
        AND n.recipient_id = m.id
        AND sa.cycle_id = v_app.cycle_id
        AND NOT EXISTS (
          SELECT 1 FROM public.selection_evaluations e2
          WHERE e2.application_id = n.source_id AND e2.evaluator_id = m.id
        )
    ) AS load_count,
    -- last_invited_at: most recent peer_review_requested notification in cycle
    (
      SELECT max(n.created_at)
      FROM public.notifications n
      JOIN public.selection_applications sa ON sa.id = n.source_id
      WHERE n.type = 'peer_review_requested'
        AND n.recipient_id = m.id
        AND sa.cycle_id = v_app.cycle_id
    ) AS last_invited_at
  FROM public.selection_committee sc
  JOIN public.members m ON m.id = sc.member_id
  WHERE sc.cycle_id = v_app.cycle_id
    AND sc.role IN ('evaluator', 'lead')
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.type = 'peer_review_requested'
        AND n.recipient_id = m.id
        AND n.source_id = p_application_id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.selection_evaluations e
      WHERE e.application_id = p_application_id
        AND e.evaluator_id = m.id
    )
    AND m.email != v_app.email
  ORDER BY load_count ASC, last_invited_at ASC NULLS FIRST, m.name ASC;
END;
$function$
;

CREATE OR REPLACE FUNCTION public._selection_cutoff_pending_cron()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_app record;
  v_result jsonb;
  v_dispatched int := 0;
  v_refused int := 0;
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
      AND public._na_avaliacao_geral(a.id)                -- #2393 fatia 3: piloto da linha não recebe o convite geral
    ORDER BY a.objective_score_avg DESC
    LIMIT 50                                               -- runaway cap
  LOOP
    -- Subtransação por linha: uma candidatura ruim (ex.: CUTOFF_NO_BOOKING_URL) nunca aborta a volta.
    BEGIN
      v_result := public.notify_selection_cutoff_approved(v_app.app_id);

      IF COALESCE((v_result->>'email_sent')::boolean, false) THEN
        v_dispatched := v_dispatched + 1;
        IF NOT (v_app.cycle_code = ANY (v_cycles)) THEN
          v_cycles := array_append(v_cycles, v_app.cycle_code);
        END IF;
      ELSIF COALESCE((v_result->>'success')::boolean, true) IS NOT TRUE THEN
        -- #1594: recusa de gate chega por retorno, não por exceção. Contá-la como despacho seria
        -- reportar e-mail que não saiu.
        v_refused := v_refused + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors + 1;
    END;
  END LOOP;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL, 'selection.cutoff_pending_cron_run', 'system', NULL,
    jsonb_build_object('dispatched_count', v_dispatched, 'refused_count', v_refused, 'error_count', v_errors),
    jsonb_build_object(
      'dispatched_count', v_dispatched,
      'refused_count', v_refused,
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
    'refused_count', v_refused,
    'error_count', v_errors,
    'cycle_codes_touched', to_jsonb(v_cycles),
    'run_at', v_run_at
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_selection_cutoff_approved(p_application_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_cycle record;
  v_committee record;
  v_first_name text;
  v_objective_done int;
  -- roteamento v1 (#355) — vindo do helper compartilhado (#1595)
  v_resolved_url text;
  v_resolution_path text;
  v_resolved_evaluator_id uuid;
  -- p282 #411 W2a: cron/service context flag (ADR-0028)
  v_is_cron boolean := false;
  -- #1584 A6: o link que vai para o candidato é o do token, não o do Google
  v_dispatch jsonb;
  v_token_url text;
BEGIN
  -- Authority gate — mesmo de dispatch_peer_review_invitations (committee lead OU manage_member).
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    -- ADR-0028 cron/service bypass: sessão sem JWT (pg_cron) ou service_role é o caminho
    -- automatizado. Um ghost autenticado tem auth.uid() não-nulo + claims presentes, então cai no
    -- ELSE e levanta.
    IF current_setting('request.jwt.claims', true) IS NULL OR auth.role() = 'service_role' THEN
      v_is_cron := true;  -- v_caller segue NULL → actor_id NULL (linha de sistema)
    ELSE
      RAISE EXCEPTION 'Unauthorized: member not found';
    END IF;
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  IF NOT v_is_cron THEN
    SELECT * INTO v_committee
    FROM public.selection_committee
    WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead';

    IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_member'::text) THEN
      RAISE EXCEPTION 'Unauthorized: must be committee lead or have manage_member';
    END IF;
  END IF;

  -- #2393 fatia 3: candidatura de vaga piloto da linha não recebe o convite da entrevista geral. Recusa
  -- por retorno, como a recusa de gate (#1594): o cron a conta como recusada, e os 2 resgates também.
  IF NOT public._na_avaliacao_geral(p_application_id) THEN
    RETURN jsonb_build_object(
      'success', false,
      'application_id', p_application_id,
      'email_sent', false,
      'reason', 'pilot_track'
    );
  END IF;

  -- Idempotência: disparo único por candidatura
  IF v_app.cutoff_approved_email_sent_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'application_id', p_application_id,
      'email_sent', false,
      'reason', 'already_sent',
      'previously_sent_at', v_app.cutoff_approved_email_sent_at
    );
  END IF;

  IF v_app.email IS NULL THEN
    RAISE EXCEPTION 'Application has no email — cannot dispatch';
  END IF;

  -- #1450 — gate de fase objetiva. NUNCA despachar o convite de agendamento antes de o candidato
  -- ter fechado a fase objetiva. Mantido explícito aqui (além do P0003 do core) porque a mensagem
  -- nomeia o #1450 e é o que o teste de contrato daquele arco afirma. Segue levantando: acontece
  -- ANTES de qualquer emissão, então não há linha de auditoria para perder.
  IF v_app.objective_score_avg IS NULL THEN
    RAISE EXCEPTION 'GATE_NO_SCORE: objective_score_avg not computed for application % — the interview-scheduling invite must not be sent before the objective phase completes (#1450).', p_application_id
      USING ERRCODE = 'P0003';
  END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  -- ============================================================
  -- #1595 — resolve + emite token + grava a linha de despacho, tudo pela fonte única.
  -- ============================================================
  v_dispatch := public._dispatch_interview_booking_link(
    p_application_id, v_caller.id, CASE WHEN v_is_cron THEN 'cron' ELSE 'manual' END
  );

  IF COALESCE((v_dispatch->>'success')::boolean, false) IS NOT TRUE THEN
    IF v_dispatch->>'failure_code' = 'NO_BOOKING_URL' THEN
      -- Nada foi emitido nem gravado ainda: levantar aqui é seguro e preserva o contrato P0020.
      RAISE EXCEPTION 'CUTOFF_NO_BOOKING_URL: no resolvable booking URL for application % (cycle %, role %); set selection_cycles.interview_booking_url or seed selection_committee with per-evaluator URLs',
        p_application_id, v_app.cycle_id, v_app.role_applied USING ERRCODE = 'P0020';
    END IF;

    -- #1594 — recusa de gate: abortar o e-mail EXPLICITAMENTE, sem exceção. A linha de
    -- gate_attempts que o core acabou de gravar só sobrevive se esta transação commitar.
    RETURN jsonb_build_object(
      'success', false,
      'application_id', p_application_id,
      'email_sent', false,
      'reason', 'gate_refused',
      'gate_failed_code', v_dispatch->>'gate_failed_code',
      'gate_failed_reason', v_dispatch->>'gate_failed_reason',
      'message', v_dispatch->>'message'
    );
  END IF;

  v_token_url            := v_dispatch->>'booking_url';
  v_resolved_url         := v_dispatch->>'resolved_url';
  v_resolution_path      := v_dispatch->>'resolution_path';
  v_resolved_evaluator_id := NULLIF(v_dispatch->>'resolved_evaluator_id', '')::uuid;

  -- Sanidade de threshold (informativa).
  SELECT count(*)::int INTO v_objective_done
  FROM public.selection_evaluations
  WHERE application_id = p_application_id
    AND evaluation_type = 'objective';

  v_first_name := COALESCE(
    NULLIF(trim(v_app.first_name), ''),
    NULLIF(split_part(v_app.applicant_name, ' ', 1), ''),
    'candidato(a)'
  );

  -- Despacho via campaign_send_one_off — #1584 A6: passa o link do TOKEN.
  PERFORM public.campaign_send_one_off(
    p_template_slug := 'selection_cutoff_approved',
    p_to_email := v_app.email,
    p_variables := jsonb_build_object(
      'first_name', v_first_name,
      'interview_booking_url', v_token_url
    ),
    p_metadata := jsonb_build_object(
      'source', 'notify_selection_cutoff_approved',
      'application_id', p_application_id,
      'cycle_id', v_app.cycle_id,
      'cycle_code', v_cycle.cycle_code,
      'objective_done', v_objective_done,
      'research_score', v_app.research_score,
      'resolution_path', v_resolution_path,
      'resolved_evaluator_id', v_resolved_evaluator_id,
      'link_kind', 'governed_token'
    )
  );

  -- Carimbo de idempotência pós-envio.
  UPDATE public.selection_applications
  SET cutoff_approved_email_sent_at = now(),
      updated_at = now()
  WHERE id = p_application_id;

  INSERT INTO public.admin_audit_log (
    actor_id, action, target_type, target_id, changes, metadata
  ) VALUES (
    v_caller.id,
    'selection.cutoff_approved_email_dispatched',
    'selection_application',
    p_application_id,
    jsonb_build_object(
      'cutoff_approved_email_sent_at_before', NULL,
      'cutoff_approved_email_sent_at_after', now(),
      'recipient_email', v_app.email
    ),
    jsonb_build_object(
      'cycle_id', v_app.cycle_id,
      'cycle_code', v_cycle.cycle_code,
      'objective_done', v_objective_done,
      'research_score', v_app.research_score,
      'interview_booking_url', v_resolved_url,
      'resolution_path', v_resolution_path,
      'resolved_evaluator_id', v_resolved_evaluator_id,
      'role_applied', v_app.role_applied,
      'dispatch_source', CASE WHEN v_is_cron THEN 'cron' ELSE 'manual' END,
      'token_prefix', left(COALESCE(v_dispatch->>'token', ''), 8),
      'gate_mode', v_dispatch->>'gate_mode',
      'link_kind', 'governed_token',
      'rpc_version', 'p1594_p1595'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'application_id', p_application_id,
    'cycle_id', v_app.cycle_id,
    'email_sent', true,
    'recipient_email_redacted', LEFT(v_app.email, 2) || '***' || RIGHT(v_app.email, 4),
    'objective_done', v_objective_done,
    'research_score', v_app.research_score,
    'resolution_path', v_resolution_path,
    'resolved_evaluator_id', v_resolved_evaluator_id,
    'link_kind', 'governed_token',
    'gate_mode', v_dispatch->>'gate_mode',
    'token_expires_at', v_dispatch->>'expires_at'
  );
END;
$function$;

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
      AND public._na_avaliacao_geral(sa.id)  -- #2393 fatia 3 (D2): piloto da linha fora da população do corte
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
      AND role_applied = p_role
      AND public._na_avaliacao_geral(id);  -- #2393 fatia 3: o corte geral não é carimbado no piloto
  ELSIF v_is_final_score THEN
    UPDATE public.selection_applications
    SET final_score_pert_target = v_target,
        final_score_pert_band_lower = v_band_lower,
        final_score_pert_band_upper = v_band_upper,
        final_score_pert_cutoff_method = v_method,
        final_score_pert_cohort_n = v_n,
        final_score_pert_calc_at = now()
    WHERE cycle_id = p_cycle_id
      AND role_applied = p_role
      AND public._na_avaliacao_geral(id);  -- #2393 fatia 3: o corte geral não é carimbado no piloto
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
      AND role_applied = p_role
      AND public._na_avaliacao_geral(id);  -- #2393 fatia 3: o corte geral não é carimbado no piloto
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

CREATE OR REPLACE FUNCTION public.recompute_application_status(
  p_application_id uuid DEFAULT NULL::uuid,
  p_cycle_id uuid DEFAULT NULL::uuid,
  p_dry_run boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_caller_id uuid;
  v_changes jsonb := '[]'::jsonb;
  v_changed int := 0;
  v_suppressed int := 0;
  v_landed text;
  v_evaluated int := 0;
  v_rec record;
  -- pipeline-stage rank used for the forward-only guard
  v_ladder text[] := ARRAY['submitted','screening','objective_eval','objective_cutoff',
                           'interview_pending','interview_scheduled','interview_done','final_eval'];
BEGIN
  -- Auth: authenticated callers need manage_platform. A no-JWT context
  -- (pg_cron / service_role) is the self-healing path and is allowed; anon is
  -- blocked by the GRANT ladder below, not by reaching here.
  IF auth.uid() IS NOT NULL THEN
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'Unauthorized: manage_platform required';
    END IF;
  END IF;

  FOR v_rec IN
    WITH ev AS (
      SELECT application_id,
             count(*) FILTER (WHERE evaluation_type = 'objective' AND submitted_at IS NOT NULL) AS obj_n
      FROM public.selection_evaluations
      GROUP BY application_id
    ),
    iv AS (
      SELECT application_id,
             bool_or(conducted_at IS NOT NULL OR status = 'completed') AS conducted,
             bool_or(status IN ('scheduled','rescheduled'))            AS sched_active,
             bool_or(status NOT IN ('cancelled','noshow'))             AS has_live_row
      FROM public.selection_interviews
      GROUP BY application_id
    ),
    fully AS (
      -- precise: a CONDUCTED interview row whose EVERY assigned interviewer
      -- submitted an interview eval (mirrors submit_interview_scores' completion
      -- gate; avoids advancing a partial 2-interviewer interview to final_eval).
      SELECT DISTINCT a.id
      FROM public.selection_applications a
      JOIN public.selection_interviews si ON si.application_id = a.id
        AND (si.conducted_at IS NOT NULL OR si.status = 'completed')
        AND si.status NOT IN ('cancelled','noshow')
      WHERE COALESCE(array_length(si.interviewer_ids, 1), 0) >= 1
        AND NOT EXISTS (
          SELECT 1 FROM unnest(si.interviewer_ids) AS iid
          WHERE NOT EXISTS (
            SELECT 1 FROM public.selection_evaluations se
            WHERE se.application_id = a.id
              AND se.evaluator_id = iid
              AND se.evaluation_type = 'interview'
              AND se.submitted_at IS NOT NULL
          )
        )
    ),
    cyc_median AS (
      -- #1468: corte objetivo por mediana e researcher-only (alinha a A3/mig 479).
      SELECT cycle_id,
             ROUND((percentile_cont(0.5) WITHIN GROUP (ORDER BY objective_score_avg))::numeric * 0.75, 2) AS cutoff
      FROM public.selection_applications
      WHERE objective_score_avg IS NOT NULL
        AND role_applied = 'researcher'
        AND public._na_avaliacao_geral(id)  -- #2393 fatia 3 (D2): mediana só da avaliação geral
      GROUP BY cycle_id
    ),
    base AS (
      SELECT a.id, a.applicant_name, a.cycle_id, a.status AS cur,
             c.min_evaluators, cm.cutoff, a.objective_score_avg, a.interview_score,
             COALESCE(ev.obj_n, 0)        AS obj_n,
             COALESCE(iv.conducted, false) AS conducted,
             COALESCE(iv.sched_active, false) AS sched_active,
             COALESCE(iv.has_live_row, false) AS has_live_row,
             (f.id IS NOT NULL)            AS fully_scored
      FROM public.selection_applications a
      JOIN public.selection_cycles c ON c.id = a.cycle_id
      LEFT JOIN ev ON ev.application_id = a.id
      LEFT JOIN iv ON iv.application_id = a.id
      LEFT JOIN cyc_median cm ON cm.cycle_id = a.cycle_id
      LEFT JOIN fully f ON f.id = a.id
      WHERE (p_application_id IS NULL OR a.id = p_application_id)
        AND (p_cycle_id IS NULL OR a.cycle_id = p_cycle_id)
        AND public._na_avaliacao_geral(a.id)  -- #2393 fatia 3: piloto da linha fora das transições automáticas
    ),
    canon AS (
      SELECT *,
        CASE
          WHEN fully_scored OR (interview_score IS NOT NULL AND NOT has_live_row) THEN 'final_eval'
          WHEN conducted    THEN 'interview_done'
          WHEN sched_active THEN 'interview_scheduled'
          WHEN obj_n >= min_evaluators AND objective_score_avg IS NOT NULL THEN
            CASE WHEN cutoff > 0 AND objective_score_avg < cutoff THEN 'objective_cutoff'
                 ELSE 'interview_pending' END
          ELSE NULL
        END AS canonical
      FROM base
    ),
    ranked AS (
      SELECT *,
             array_position(v_ladder, cur)       AS cur_r,
             array_position(v_ladder, canonical) AS can_r
      FROM canon
    )
    SELECT id, applicant_name, cycle_id, cur, canonical, obj_n, objective_score_avg,
           interview_score, conducted, sched_active, fully_scored, cutoff
    FROM ranked
    WHERE cur NOT IN ('approved','rejected','converted','withdrawn','cancelled','waitlist','interview_noshow')
      AND canonical IS NOT NULL
      AND canonical <> cur
      AND ( can_r > cur_r
            OR (can_r = cur_r AND cur IN ('objective_cutoff','interview_pending')) )
  LOOP
    IF NOT p_dry_run THEN
      UPDATE public.selection_applications
         SET status = v_rec.canonical, updated_at = now()
       WHERE id = v_rec.id
         AND status = v_rec.cur   -- snapshot guard: skip if changed concurrently
      RETURNING status INTO v_landed;

      IF FOUND THEN
        -- #1613 — o gate de entrada pode ter SUPRIMIDO a transição devolvendo OLD.status.
        -- O UPDATE encontra a linha do mesmo jeito, então ler o status GRAVADO é o que
        -- separa "aplicou" de "foi recusado". O trigger já registrou o porquê.
        IF v_landed IS DISTINCT FROM v_rec.canonical THEN
          v_suppressed := v_suppressed + 1;
          v_changes := v_changes || jsonb_build_object(
            'application_id', v_rec.id,
            'applicant_name', v_rec.applicant_name,
            'cycle_id',       v_rec.cycle_id,
            'from',           v_rec.cur,
            'to',             v_rec.canonical,
            'landed',         v_landed,
            'suppressed',     true
          );
          CONTINUE;
        END IF;

        v_changed := v_changed + 1;
        v_changes := v_changes || jsonb_build_object(
          'application_id', v_rec.id,
          'applicant_name', v_rec.applicant_name,
          'cycle_id',       v_rec.cycle_id,
          'from',           v_rec.cur,
          'to',             v_rec.canonical
        );

        INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
        VALUES (
          v_caller_id,
          'selection.status_recomputed',
          'selection_application',
          v_rec.id,
          jsonb_build_object('status', jsonb_build_object('from', v_rec.cur, 'to', v_rec.canonical)),
          jsonb_build_object(
            'source',   'recompute_application_status',
            'cycle_id', v_rec.cycle_id,
            'facts', jsonb_build_object(
              'objective_evals',        v_rec.obj_n,
              'objective_score_avg',    v_rec.objective_score_avg,
              'interview_score',        v_rec.interview_score,
              'interview_conducted',    v_rec.conducted,
              'interview_scheduled',    v_rec.sched_active,
              'interview_fully_scored', v_rec.fully_scored,
              'objective_cutoff',       v_rec.cutoff
            )
          )
        );
      END IF;
    ELSE
      v_changed := v_changed + 1;
      v_changes := v_changes || jsonb_build_object(
        'application_id', v_rec.id,
        'applicant_name', v_rec.applicant_name,
        'cycle_id',       v_rec.cycle_id,
        'from',           v_rec.cur,
        'to',             v_rec.canonical
      );
    END IF;
  END LOOP;

  SELECT count(*) INTO v_evaluated
  FROM public.selection_applications a
  WHERE (p_application_id IS NULL OR a.id = p_application_id)
    AND (p_cycle_id IS NULL OR a.cycle_id = p_cycle_id);

  RETURN jsonb_build_object(
    'success',    true,
    'dry_run',    p_dry_run,
    'evaluated',  v_evaluated,
    'changed',    v_changed,
    'suppressed', v_suppressed,
    'changes',    v_changes
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.calculate_rankings(p_cycle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_cycle record;
  v_committee record;
  v_median numeric;
  v_cutoff numeric;
  v_p90 numeric;
  v_ranked jsonb;
  v_updated_count int := 0;
BEGIN
  -- 1. Auth
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- 2. Get cycle
  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = p_cycle_id;
  IF v_cycle IS NULL THEN
    RAISE EXCEPTION 'Cycle not found';
  END IF;

  -- 3. V4 authorization: committee lead (resource) or platform admin
  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = p_cycle_id AND member_id = v_caller.id AND role = 'lead';

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: must be committee lead or platform admin';
  END IF;

  -- 4. Calculate overall rankings (by final_score DESC)
  WITH scored AS (
    SELECT id, chapter, final_score
    FROM public.selection_applications
    WHERE cycle_id = p_cycle_id
      AND final_score IS NOT NULL
      AND status NOT IN ('withdrawn', 'cancelled')
      AND public._na_avaliacao_geral(id)  -- #2393 fatia 3 (D2)
  ),
  ranked_overall AS (
    SELECT id, ROW_NUMBER() OVER (ORDER BY final_score DESC) AS r_overall
    FROM scored
  ),
  ranked_chapter AS (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY chapter ORDER BY final_score DESC) AS r_chapter
    FROM scored
  )
  UPDATE public.selection_applications a
  SET rank_overall = ro.r_overall,
      rank_chapter = rc.r_chapter,
      updated_at = now()
  FROM ranked_overall ro
  JOIN ranked_chapter rc ON rc.id = ro.id
  WHERE a.id = ro.id;

  GET DIAGNOSTICS v_updated_count = ROW_COUNT;

  -- 5. Calculate median and cutoff for recommendations
  SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY final_score)
  INTO v_median
  FROM public.selection_applications
  WHERE cycle_id = p_cycle_id
    AND final_score IS NOT NULL
    AND status NOT IN ('withdrawn', 'cancelled')
    AND public._na_avaliacao_geral(id);  -- #2393 fatia 3 (D2)

  v_cutoff := ROUND(COALESCE(v_median, 0) * 0.75, 2);

  -- 90th percentile for leader conversion recommendation
  SELECT PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY objective_score_avg)
  INTO v_p90
  FROM public.selection_applications
  WHERE cycle_id = p_cycle_id
    AND objective_score_avg IS NOT NULL
    AND role_applied = 'researcher'
    AND status NOT IN ('withdrawn', 'cancelled')
    AND public._na_avaliacao_geral(id);  -- #2393 fatia 3 (D2)

  -- 6. Build ranked results with recommendations
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'application_id', a.id,
      'applicant_name', a.applicant_name,
      'email', a.email,
      'chapter', a.chapter,
      'role_applied', a.role_applied,
      'objective_score_avg', a.objective_score_avg,
      'interview_score', a.interview_score,
      'final_score', a.final_score,
      'rank_chapter', a.rank_chapter,
      'rank_overall', a.rank_overall,
      'status', a.status,
      'tags', a.tags,
      'recommendation', CASE
        WHEN a.final_score >= v_median THEN 'approve'
        WHEN a.final_score >= v_cutoff THEN 'waitlist'
        ELSE 'reject'
      END,
      'flag_convert_to_leader', CASE
        WHEN a.role_applied = 'researcher'
          AND a.objective_score_avg IS NOT NULL
          AND v_p90 IS NOT NULL
          AND a.objective_score_avg >= v_p90
        THEN true
        ELSE false
      END
    ) ORDER BY a.rank_overall NULLS LAST
  ), '[]'::jsonb)
  INTO v_ranked
  FROM public.selection_applications a
  WHERE a.cycle_id = p_cycle_id
    AND a.status NOT IN ('withdrawn', 'cancelled')
    AND public._na_avaliacao_geral(a.id);  -- #2393 fatia 3 (D2)

  RETURN jsonb_build_object(
    'cycle_id', p_cycle_id,
    'updated_count', v_updated_count,
    'median_score', v_median,
    'cutoff_75pct', v_cutoff,
    'p90_objective', v_p90,
    'rankings', v_ranked
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.recalculate_cycle_rankings(p_cycle_id uuid, p_reason text DEFAULT 'manual'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_researcher_count int;
  v_leader_count int;
  v_snapshot_id uuid;
BEGIN
  -- Auth (admin only)
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform permission for ranking recalc';
  END IF;

  -- Reset ranks
  UPDATE selection_applications
  SET rank_researcher = NULL, rank_leader = NULL
  WHERE cycle_id = p_cycle_id;

  -- Ranking 1: researcher track (Standard Competition Ranking via RANK())
  -- Includes: role_applied='researcher' OR promotion_path='direct_researcher'
  -- Excludes: promoted to leader AND leader app already approved/converted (they're not researchers anymore)
  WITH ranked AS (
    SELECT a.id,
      RANK() OVER (
        ORDER BY a.research_score DESC NULLS LAST, a.applicant_name ASC
      ) as rnk
    FROM selection_applications a
    WHERE a.cycle_id = p_cycle_id
      AND a.role_applied = 'researcher'
      AND a.research_score IS NOT NULL
      AND a.status NOT IN ('withdrawn','rejected','cancelled')
      AND public._na_avaliacao_geral(a.id)  -- #2393 fatia 3 (D2)
      AND NOT EXISTS (
        -- Exclude if linked leader app is approved/converted
        SELECT 1 FROM selection_applications la
        WHERE la.id = a.linked_application_id
          AND la.role_applied = 'leader'
          AND la.status IN ('approved','converted')
      )
  )
  UPDATE selection_applications a
  SET rank_researcher = r.rnk
  FROM ranked r WHERE a.id = r.id;

  GET DIAGNOSTICS v_researcher_count = ROW_COUNT;

  -- Ranking 2: leader track
  WITH ranked AS (
    SELECT a.id,
      RANK() OVER (
        ORDER BY a.leader_score DESC NULLS LAST, a.applicant_name ASC
      ) as rnk
    FROM selection_applications a
    WHERE a.cycle_id = p_cycle_id
      AND (a.role_applied = 'leader' OR a.promotion_path = 'triaged_to_leader')
      AND a.leader_score IS NOT NULL
      AND a.status NOT IN ('withdrawn','rejected','cancelled')
      AND public._na_avaliacao_geral(a.id)  -- #2393 fatia 3 (D2)
  )
  UPDATE selection_applications a
  SET rank_leader = r.rnk
  FROM ranked r WHERE a.id = r.id;

  GET DIAGNOSTICS v_leader_count = ROW_COUNT;

  -- Audit snapshot
  INSERT INTO selection_ranking_snapshots (cycle_id, triggered_by, reason, rankings, formula_version)
  SELECT p_cycle_id, v_caller_id, p_reason,
    jsonb_agg(jsonb_build_object(
      'application_id', id,
      'applicant_name', applicant_name,
      'role_applied', role_applied,
      'promotion_path', promotion_path,
      'research_score', research_score,
      'leader_score', leader_score,
      'rank_researcher', rank_researcher,
      'rank_leader', rank_leader,
      'status', status
    )),
    'v1.0-cr047'
  FROM selection_applications
  WHERE cycle_id = p_cycle_id
  RETURNING id INTO v_snapshot_id;

  RETURN jsonb_build_object(
    'success', true,
    'cycle_id', p_cycle_id,
    'researcher_ranked', v_researcher_count,
    'leader_ranked', v_leader_count,
    'snapshot_id', v_snapshot_id,
    'formula_version', 'v1.0-cr047',
    'formula', jsonb_build_object(
      'research_score', 'objective_pert + interview_pert',
      'leader_score', 'research_score * 0.7 + leader_extra_pert * 0.3',
      'tiebreaker', 'RANK() OVER (..., applicant_name ASC) — Standard Competition Ranking ISO 80000-2'
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_selection_rankings(p_cycle_code text DEFAULT NULL::text, p_track text DEFAULT 'both'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_id uuid;
  v_pert_cutoff jsonb;
  v_researcher jsonb;
  v_leader jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Unauthorized: admin/GP/curator only');
  END IF;

  IF p_cycle_code IS NOT NULL THEN
    SELECT id INTO v_cycle_id FROM public.selection_cycles WHERE cycle_code = p_cycle_code;
  ELSE
    -- #1801 — era `ORDER BY created_at DESC LIMIT 1`.
    v_cycle_id := public.selection_active_cycle_id();
  END IF;

  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'No cycle found');
  END IF;

  -- ADR-0109 COI recusal
  IF public.selection_coi_recused(v_caller_id, v_cycle_id) THEN
    RETURN jsonb_build_object('error', 'recused_conflict_of_interest',
      'detail', 'Você é candidato(a) neste ciclo — as visões de seleção estão impedidas por conflito de interesse (ADR-0109).');
  END IF;

  SELECT jsonb_build_object(
    'target_score', MAX(pert_target_score),
    'band_lower', MAX(pert_band_lower),
    'band_upper', MAX(pert_band_upper),
    'cohort_n', MAX(pert_cohort_n),
    'method', MAX(pert_cutoff_method),
    'calc_at', MAX(pert_calc_at)
  ) INTO v_pert_cutoff
  FROM public.selection_applications WHERE cycle_id = v_cycle_id;

  -- Audit A1: rank calculado ao vivo (RANK() sobre research_score), mesmos filtros de
  -- recalculate_cycle_rankings; inclui TODAS as linhas ranqueáveis (não descarta rank NULL).
  IF p_track IN ('researcher', 'both') THEN
    WITH ranked AS (
      SELECT a.applicant_name, a.chapter, a.research_score, a.status, a.promotion_path,
             a.pert_band_lower, a.pert_band_upper,
             RANK() OVER (ORDER BY a.research_score DESC NULLS LAST, a.applicant_name ASC) AS live_rank
      FROM public.selection_applications a
      WHERE a.cycle_id = v_cycle_id
        AND a.role_applied = 'researcher'
        AND a.research_score IS NOT NULL
        AND a.status NOT IN ('withdrawn','rejected','cancelled','merged')
        AND public._na_avaliacao_geral(a.id)  -- #2393 fatia 3 (D2)
        AND NOT EXISTS (
          SELECT 1 FROM public.selection_applications la
          WHERE la.id = a.linked_application_id
            AND la.role_applied = 'leader'
            AND la.status IN ('approved','converted')
        )
    )
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'rank', live_rank,
      'applicant_name', applicant_name,
      'chapter', chapter,
      'research_score', research_score,
      'status', status,
      'promotion_path', promotion_path,
      'pert_band_position', CASE
        WHEN research_score IS NULL OR pert_band_lower IS NULL OR pert_band_upper IS NULL THEN NULL
        WHEN research_score < pert_band_lower THEN 'below'
        WHEN research_score > pert_band_upper THEN 'above'
        ELSE 'within'
      END
    ) ORDER BY live_rank), '[]'::jsonb)
    INTO v_researcher
    FROM ranked;
  END IF;

  IF p_track IN ('leader', 'both') THEN
    WITH ranked AS (
      SELECT a.applicant_name, a.chapter, a.research_score, a.leader_score, a.status, a.promotion_path,
             a.pert_band_lower, a.pert_band_upper,
             RANK() OVER (ORDER BY a.leader_score DESC NULLS LAST, a.applicant_name ASC) AS live_rank
      FROM public.selection_applications a
      WHERE a.cycle_id = v_cycle_id
        AND (a.role_applied = 'leader' OR a.promotion_path = 'triaged_to_leader')
        AND a.leader_score IS NOT NULL
        AND a.status NOT IN ('withdrawn','rejected','cancelled','merged')
        AND public._na_avaliacao_geral(a.id)  -- #2393 fatia 3 (D2)
    )
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'rank', live_rank,
      'applicant_name', applicant_name,
      'chapter', chapter,
      'research_score', research_score,
      'leader_score', leader_score,
      'status', status,
      'promotion_path', promotion_path,
      'pert_band_position', CASE
        WHEN leader_score IS NULL OR pert_band_lower IS NULL OR pert_band_upper IS NULL THEN NULL
        WHEN leader_score < pert_band_lower THEN 'below'
        WHEN leader_score > pert_band_upper THEN 'above'
        ELSE 'within'
      END
    ) ORDER BY live_rank), '[]'::jsonb)
    INTO v_leader
    FROM ranked;
  END IF;

  RETURN jsonb_build_object(
    'cycle_id', v_cycle_id,
    'track', p_track,
    'pert_cutoff', v_pert_cutoff,
    'rank_source', 'live_readtime',
    'researcher_track', COALESCE(v_researcher, '[]'::jsonb),
    'leader_track', COALESCE(v_leader, '[]'::jsonb),
    'formula', jsonb_build_object(
      'research_score', 'objective_pert + interview_pert',
      'leader_score', 'research_score * 0.7 + leader_extra_pert * 0.3',
      'tiebreaker', 'Standard Competition Ranking (ISO 80000-2) + applicant_name ASC'
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.detect_stuck_selection_funnel(p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_run_at         timestamptz := now();
  v_booking_grace  interval;
  v_noshow_grace   interval;
  v_uninvited_grace interval;
  v_unbooked_apps  int := 0;
  v_noshow_apps    int := 0;
  v_uninvited_apps int := 0;
  v_notified       int := 0;
BEGIN
  -- Config-driven windows (fallback ao literal se a row sumir) — padrao J4.
  SELECT value_interval INTO v_booking_grace FROM public.sla_policies WHERE policy_key = 'interview_booking_grace';
  IF v_booking_grace IS NULL THEN v_booking_grace := interval '10 days'; END IF;
  SELECT value_interval INTO v_noshow_grace FROM public.sla_policies WHERE policy_key = 'noshow_recovery_grace';
  IF v_noshow_grace IS NULL THEN v_noshow_grace := interval '3 days'; END IF;
  SELECT value_interval INTO v_uninvited_grace FROM public.sla_policies WHERE policy_key = 'eligible_uninvited_grace';
  IF v_uninvited_grace IS NULL THEN v_uninvited_grace := interval '2 days'; END IF;

  WITH active_cycle AS (
    -- Correcao causa 1: por STATUS, nunca por `created_at` (que e data de escrita da linha,
    -- e um backfill historico a torna a mais nova). Sem LIMIT 1: se houver dois ciclos abertos,
    -- os dois sao varridos em vez de um sumir calado.
    SELECT id FROM public.selection_cycles WHERE status = 'open'
  ),
  stuck AS (
    -- Bucket A — invited_never_booked (= D5): convidado, sem nenhuma linha de
    -- entrevista, envelhecido alem do booking grace. interview_reschedule_requested_at
    -- IS NULL exclui quem esta no fluxo de reschedule (job33 cuida).
    SELECT
      a.id AS application_id,
      'selection_candidate_unbooked'::text AS n_type,
      'Candidato convidado ainda sem agendar entrevista'::text AS n_title,
      format(
        '%s foi convidado(a) ha %s dia%s e ainda nao agendou a entrevista (sem agendamento registrado). Abra a candidatura em /admin/selection para re-convidar ou encerrar.',
        COALESCE(NULLIF(trim(a.applicant_name), ''),
                 NULLIF(trim(a.first_name || ' ' || COALESCE(a.last_name, '')), ''),
                 'Candidato'),  -- sem email no body (LGPD minimizacao; nome cobre 100% + link identifica)
        EXTRACT(DAY FROM now() - a.cutoff_approved_email_sent_at)::int,
        CASE WHEN EXTRACT(DAY FROM now() - a.cutoff_approved_email_sent_at)::int = 1 THEN '' ELSE 's' END
      ) AS n_body
    FROM public.selection_applications a
    JOIN active_cycle ac ON ac.id = a.cycle_id
    WHERE a.status = 'interview_pending'
      AND a.cutoff_approved_email_sent_at IS NOT NULL
      AND a.interview_reschedule_requested_at IS NULL
      AND a.cutoff_approved_email_sent_at < now() - v_booking_grace
      AND NOT EXISTS (
        SELECT 1 FROM public.selection_interviews si WHERE si.application_id = a.id
      )

    UNION ALL

    -- Bucket B — noshow_not_recovered (= D3): tem linha noshow, sem recuperacao
    -- POSTERIOR ao ultimo noshow (qualificado por created_at — evita falso-negativo
    -- de completed-antes-de-noshow), sem futuro agendado (exclui Hanae), envelhecido.
    SELECT
      a.id AS application_id,
      'selection_noshow_unrecovered'::text AS n_type,
      'No-show de entrevista sem recuperacao'::text AS n_title,
      format(
        '%s teve no-show de entrevista ha %s dia%s e segue sem nova entrevista agendada. Abra a candidatura em /admin/selection para re-convidar ou encerrar.',
        COALESCE(NULLIF(trim(a.applicant_name), ''),
                 NULLIF(trim(a.first_name || ' ' || COALESCE(a.last_name, '')), ''),
                 'Candidato'),  -- sem email no body (LGPD minimizacao; nome cobre 100% + link identifica)
        EXTRACT(DAY FROM now() - ns.last_noshow_at)::int,
        CASE WHEN EXTRACT(DAY FROM now() - ns.last_noshow_at)::int = 1 THEN '' ELSE 's' END
      ) AS n_body
    FROM public.selection_applications a
    JOIN active_cycle ac ON ac.id = a.cycle_id
    JOIN LATERAL (
      SELECT max(si.created_at) AS last_noshow_created,
             -- scheduled_at e nullable; fallback p/ created_at (NOT NULL) evita
             -- que um noshow sem horario suma silenciosamente do bucket (review MEDIUM).
             COALESCE(max(si.scheduled_at), max(si.created_at)) AS last_noshow_at
      FROM public.selection_interviews si
      WHERE si.application_id = a.id AND si.status = 'noshow'
    ) ns ON ns.last_noshow_created IS NOT NULL
    WHERE a.status = 'interview_pending'
      AND ns.last_noshow_at < now() - v_noshow_grace
      AND a.cutoff_approved_email_sent_at < now() - v_booking_grace  -- D3 (mig 219): nao notificar no-show JA re-convidado (anti-falso-positivo: o auto-rescue re-seta cutoff=now(); convite fresco != preso)
      AND NOT EXISTS (
        SELECT 1 FROM public.selection_interviews si2
        WHERE si2.application_id = a.id
          AND si2.status IN ('scheduled', 'completed')
          AND si2.created_at > ns.last_noshow_created
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.selection_interviews si3
        WHERE si3.application_id = a.id
          AND si3.status IN ('scheduled', 'rescheduled')
          AND si3.scheduled_at > now()
      )

    UNION ALL

    -- Bucket C — eligible_uninvited (#1586(b)): ELEGIVEL ao convite e convite algum foi
    -- despachado. Ancora em `eligible_at` (a 2a avaliacao), nao em `cutoff_approved_email_sent_at`,
    -- que e NULL por definicao nesta coorte. Sem linha de entrevista: quem ja tem entrevista
    -- marcada foi convidado por fora da maquinaria (medido: 24 candidaturas do ciclo 4 tem linha
    -- de entrevista com ZERO log de despacho) e nao esta preso.
    SELECT
      a.id AS application_id,
      'selection_candidate_eligible_uninvited'::text AS n_type,
      'Candidato elegivel a entrevista e nunca convidado'::text AS n_title,
      format(
        '%s esta elegivel ao convite de entrevista ha %s dia%s (2 avaliacoes + nota objetiva) e NUNCA recebeu convite: nao ha despacho registrado nem entrevista marcada. Abra a candidatura em /admin/selection para convidar ou encerrar.',
        COALESCE(NULLIF(trim(a.applicant_name), ''),
                 NULLIF(trim(a.first_name || ' ' || COALESCE(a.last_name, '')), ''),
                 'Candidato'),  -- sem email no body (LGPD minimizacao), igual aos buckets A e B
        EXTRACT(DAY FROM now() - el.eligible_at)::int,
        CASE WHEN EXTRACT(DAY FROM now() - el.eligible_at)::int = 1 THEN '' ELSE 's' END
      ) AS n_body
    FROM public.selection_applications a
    JOIN active_cycle ac ON ac.id = a.cycle_id
    JOIN LATERAL (
      -- Instante em que ficou elegivel = quando a 2a avaliacao caiu. `LIMIT 2` + `max` da
      -- exatamente a 2a por ordem cronologica; avaliacoes posteriores nao adiam o relogio.
      SELECT max(created_at) AS eligible_at, count(*) AS n_eval
      FROM (
        SELECT created_at FROM public.selection_evaluations
        WHERE application_id = a.id ORDER BY created_at LIMIT 2
      ) first_two
    ) el ON el.n_eval >= 2
    WHERE a.status = 'interview_pending'
      AND a.cutoff_approved_email_sent_at IS NULL          -- o anchor que os buckets A e B perdem
      AND a.interview_reschedule_requested_at IS NULL
      AND a.objective_score_avg IS NOT NULL                -- 3o gate do core ja satisfeito
      AND el.eligible_at < now() - v_uninvited_grace
      AND NOT EXISTS (
        SELECT 1 FROM public.selection_interviews si WHERE si.application_id = a.id
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.selection_dispatch_url_log d WHERE d.application_id = a.id
      )
  ),
  -- Fan-out: 1 nudge por manager (GP). ADR-0011 Amendment A.
  targets AS (
    SELECT s.application_id, s.n_type, s.n_title, s.n_body, m.id AS recipient_id
    FROM stuck s
    CROSS JOIN public.members m
    WHERE m.operational_role = 'manager'
      AND public._na_avaliacao_geral(s.application_id)  -- #2393 fatia 3: piloto da linha não vira falso "travado"
  ),
  -- Idempotencia: 1 nudge por (manager, app) a cada 7 dias, filtrando pelos 3 types.
  to_insert AS (
    SELECT t.*
    FROM targets t
    WHERE NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.recipient_id = t.recipient_id
        AND n.source_type = 'selection_application'
        AND n.source_id   = t.application_id
        AND n.type IN ('selection_candidate_unbooked', 'selection_noshow_unrecovered',
                       'selection_candidate_eligible_uninvited')
        AND n.created_at > now() - interval '7 days'
    )
  ),
  inserted AS (
    INSERT INTO public.notifications (
      recipient_id, type, title, body, link, source_type, source_id, delivery_mode
    )
    SELECT
      ti.recipient_id, ti.n_type, ti.n_title, ti.n_body,
      '/admin/selection/applications/' || ti.application_id::text,
      'selection_application', ti.application_id,
      public._delivery_mode_for(ti.n_type)
    FROM to_insert ti
    WHERE NOT p_dry_run            -- dry_run: nao insere; ainda reporta a coorte
    RETURNING 1
  )
  SELECT
    (SELECT count(DISTINCT application_id) FROM stuck WHERE n_type = 'selection_candidate_unbooked')::int,
    (SELECT count(DISTINCT application_id) FROM stuck WHERE n_type = 'selection_noshow_unrecovered')::int,
    (SELECT count(DISTINCT application_id) FROM stuck WHERE n_type = 'selection_candidate_eligible_uninvited')::int,
    (SELECT count(*) FROM inserted)::int
  INTO v_unbooked_apps, v_noshow_apps, v_uninvited_apps, v_notified;

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'unbooked_apps', v_unbooked_apps,
    'noshow_apps', v_noshow_apps,
    'eligible_uninvited_apps', v_uninvited_apps,
    'notified', v_notified,
    'booking_grace_days', round(EXTRACT(EPOCH FROM v_booking_grace) / 86400.0, 1),
    'noshow_grace_days', round(EXTRACT(EPOCH FROM v_noshow_grace) / 86400.0, 1),
    'eligible_uninvited_grace_days', round(EXTRACT(EPOCH FROM v_uninvited_grace) / 86400.0, 1),
    'run_at', v_run_at
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
