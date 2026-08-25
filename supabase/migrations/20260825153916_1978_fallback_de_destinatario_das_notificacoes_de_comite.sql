-- ============================================================================
-- #1978 - as 4 notificacoes de comite ganham destinatario quando o ciclo nao tem lead
-- ----------------------------------------------------------------------------
-- MEDIDO EM 25/08/2026 (destinatarios que o predicado ATUAL `role='lead'` alcanca):
--
--   ciclo             status   destinatarios hoje   comite do ciclo
--   cycle4-2026       open     1                    7
--   cycle3-2026       closed   2                    2
--   cycle3-2026-b2    closed   1                    4
--   cycle2-2025       closed   0                    0   <-- nem lead, nem comite
--
--   membros ativos com manage_platform (audiencia do ultimo degrau) ....... 2
--
-- Quatro superficies enderecam `role='lead'` exclusivo. Com zero linhas,
-- `PERFORM create_notification(...) FROM ... WHERE role='lead'` nao chama nada: nao
-- falha, nao avisa, nao grava. Foi assim que `selection_interview_noshow`,
-- `selection_application_two_strike_closed` e `selection_evaluation_complete` ficaram
-- com 0 linhas em `notifications` para sempre, contra 3.771 notificacoes de outros
-- tipos em 90 dias (controle positivo da #1978).
--
-- ESTA E A MESMA CLASSE DA #1813, e a decisao do PM e a mesma: fallback ESTRUTURAL, nao
-- nomeacao de lead. Designar um lead resolve hoje e volta a falhar calado no proximo
-- ciclo que abrir sem lead - contencao por dado nao e contencao por estrutura. O ciclo
-- aberto so tem lead hoje porque a #1978 corrigiu o dado em 25/08; nada impede a
-- regressao de configuracao de se repetir.
--
-- NOTIFICACAO NAO E PORTAO: isto nao amplia autoridade nenhuma. Os 12 portoes presos a
-- `role='lead'` seguem intocados, e o portao de `mark_interview_status` tambem - a unica
-- ocorrencia de `role='lead'` que resta nela e ele.
--
-- DESENHO:
--   1. A resolucao vira `_selection_cycle_recipients(cycle_id)`, irma por-ciclo da
--      `_selection_consistency_recipients()` do #1813 (que e global). Funcao propria
--      porque assim o teste exerce a audiencia sem provocar notificacao.
--   2. Escada de 3 degraus, cada um so quando o anterior e VAZIO:
--        lead do ciclo -> comite do ciclo -> membros ativos com manage_platform.
--      O degrau 2 existe porque `cycle2-2025` prova que "sem lead" e "sem comite" sao
--      estados diferentes, e o degrau 3 e o unico que nao pode ser vazio.
--   3. O degrau 2 NAO expoe PII nova. Medido: o gate de `get_selection_dashboard` e
--      `is_selection_committee_member(caller, cycle_id)`, que NAO filtra papel - todo
--      membro do comite do ciclo, observer inclusive, ja le o dashboard com o nome e o
--      capitulo do candidato. A notificacao aponta para essa mesma tela.
--   4. O cron varre N ciclos, entao resolve por ciclo via LATERAL e mantem o DISTINCT.
--      A variavel deixou de se chamar `v_lead`: ela pode nao conter um lead.
--
-- O QUE ESTA MIGRATION NAO FAZ, de proposito:
--   - Nao acrescenta guarda `recipient = actor`. A sobrecarga de 7 argumentos de
--     `create_notification` nunca teve essa guarda (medido: das 3 sobrecargas, so as de
--     6 e 7 args COM `p_actor_id` a tem), entao o lead que marca no-show ja se
--     auto-notifica hoje. Excluir o ator poderia reesvaziar a lista, que e o defeito que
--     esta migration existe para fechar.
--   - Nao mexe nos 12 portoes presos a `role='lead'` (guard preventivo: #1983).
--
-- ROLLBACK:
--   DROP FUNCTION public._selection_cycle_recipients(uuid);
--   (e recriar as 3 funcoes a partir das capturas de 20260825034018, 20260825012323 e
--    20260805000171, que sao as imediatamente anteriores a esta.)
-- ============================================================================

CREATE OR REPLACE FUNCTION public._selection_cycle_recipients(p_cycle_id uuid)
RETURNS TABLE(member_id uuid, via text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH leads AS (
    -- Degrau 1: o lead do ciclo segue sendo o destinatario natural. Este ramo reproduz
    -- o predicado que as 4 superficies usavam sozinho ate aqui.
    SELECT DISTINCT sc.member_id AS id
    FROM public.selection_committee sc
    WHERE sc.cycle_id = p_cycle_id
      AND sc.role = 'lead'
      AND sc.member_id IS NOT NULL
  ),
  committee AS (
    -- Degrau 2: SO quando o ciclo nao tem lead nenhum. Audiencia identica a que
    -- `get_selection_dashboard` ja serve - o gate dela e
    -- `is_selection_committee_member(caller, cycle_id)`, sem filtro de papel.
    SELECT DISTINCT sc.member_id AS id
    FROM public.selection_committee sc
    WHERE NOT EXISTS (SELECT 1 FROM leads)
      AND sc.cycle_id = p_cycle_id
      AND sc.member_id IS NOT NULL
  )
  SELECT l.id, 'lead'::text FROM leads l
  UNION ALL
  SELECT c.id, 'committee'::text FROM committee c
  UNION ALL
  -- Degrau 3: SO quando o ciclo nao tem lead NEM comite (medido: `cycle2-2025`, 0
  -- linhas de comite). Padrao de audiencia de GP ja canonico na plataforma, o mesmo de
  -- `_alert_sweep_cron` e de `_selection_consistency_recipients`.
  SELECT m.id, 'manage_platform'::text
  FROM public.members m
  WHERE NOT EXISTS (SELECT 1 FROM leads)
    AND NOT EXISTS (SELECT 1 FROM committee)
    AND m.is_active
    AND public.can_by_member(m.id, 'manage_platform');
$function$;

COMMENT ON FUNCTION public._selection_cycle_recipients(uuid) IS
  '#1978 - destinatario das notificacoes de comite de UM ciclo, em escada: lead do ciclo; '
  'sem lead, o comite do ciclo; sem comite, quem tem manage_platform. Irma por-ciclo da '
  '_selection_consistency_recipients() do #1813, que e global. A coluna `via` diz por qual '
  'degrau a pessoa entrou, para o teste distinguir "alertou o lead" de "caiu no fallback".';

-- CREATE FUNCTION concede EXECUTE a PUBLIC; a resolucao expoe ids de membro.
-- As 3 chamadoras sao SECURITY DEFINER e pertencem a `postgres`, entao numa chamada
-- SECDEF->SECDEF o EXECUTE e verificado como o DONO: revogar de `authenticated` NAO as
-- alcanca (mesma mecanica registrada no #1631 e medida no #1551).
REVOKE ALL ON FUNCTION public._selection_cycle_recipients(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._selection_cycle_recipients(uuid) TO service_role;

-- ----------------------------------------------------------------------------
-- As 3 funcoes abaixo sao a CAPTURA do Phase C, com a UNICA mudanca sendo a troca do
-- `FROM public.selection_committee sc WHERE ... role='lead'` pela resolucao acima (e, no
-- cron, o LATERAL + o rename de `v_lead`). Nao acrescente comentario que nao esteja no
-- que foi aplicado, ou o md5 do prosrc deixa de bater e o guard acusa drift.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.mark_interview_status(
  p_interview_id uuid,
  p_status text,
  p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_interview record;
  v_app record;
  v_cycle record;
  v_new_app_status text;
  v_prior_status text;
  v_first_name text;
  v_booking_url text;
  v_deadline_date text;
  v_send_result jsonb := NULL;
  v_noshow_count int;
  v_two_strike_applied boolean := false;
  v_two_strike_send jsonb := NULL;
  v_dispatch jsonb := NULL;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  IF p_status NOT IN ('noshow', 'cancelled', 'rescheduled', 'completed') THEN
    RAISE EXCEPTION 'Invalid interview status: %', p_status;
  END IF;

  SELECT * INTO v_interview FROM public.selection_interviews WHERE id = p_interview_id;
  IF v_interview IS NULL THEN
    RAISE EXCEPTION 'Interview not found';
  END IF;

  v_prior_status := v_interview.status;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = v_interview.application_id;
  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  IF NOT (
    v_caller.id = ANY(v_interview.interviewer_ids)
    OR public.can_by_member(v_caller.id, 'manage_platform'::text)
    OR EXISTS (
      SELECT 1 FROM public.selection_committee
      WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead'
    )
  ) THEN
    -- #1978: paridade com o ramo do #1972, que nasceu so em submit_interview_scores.
    -- Aqui ele importa MAIS: em 'noshow', 'cancelled' e 'rescheduled' a entrevista nao
    -- aconteceu, entao NUNCA havera submissao de nota para criar a designacao antes. Sem
    -- este ramo esses tres status nao tem caminho nenhum para quem nao e GP.
    -- Medido em 25/08/2026 no ciclo aberto (cycle4-2026): 7 no comite, ZERO com role='lead',
    -- 5 dos 7 podiam lancar nota e nao podiam marcar no-show.
    -- Mesmo criterio do #1972: comite DO CICLO com can_interview, so com a lista VAZIA,
    -- designacao existente nunca e sobrescrita, e a reivindicacao deixa rastro.
    IF cardinality(coalesce(v_interview.interviewer_ids, ARRAY[]::uuid[])) = 0
       AND EXISTS (
         SELECT 1 FROM public.selection_committee sc
         WHERE sc.member_id = v_caller.id
           AND sc.cycle_id = v_app.cycle_id
           AND sc.can_interview
       ) THEN
      UPDATE public.selection_interviews
      SET interviewer_ids = ARRAY[v_caller.id]
      WHERE id = p_interview_id;
      v_interview.interviewer_ids := ARRAY[v_caller.id];

      INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
      VALUES (
        v_caller.id, 'selection.interview_self_assigned', 'selection_interview', p_interview_id,
        jsonb_build_object('interviewer_id', v_caller.id, 'application_id', v_app.id),
        jsonb_build_object('reason', 'lista vazia criada por auto-agendamento', 'issue', 1978,
                           'via', 'mark_interview_status', 'status_pedido', p_status,
                           'cycle_id', v_app.cycle_id)
      );
    ELSE
      RAISE EXCEPTION 'Unauthorized: must be interviewer, committee lead, or platform admin';
    END IF;
  END IF;

  UPDATE public.selection_interviews
  SET status = p_status,
      notes = COALESCE(p_notes, notes),
      conducted_at = CASE WHEN p_status = 'completed' THEN now() ELSE conducted_at END
  WHERE id = p_interview_id;

  v_new_app_status := CASE p_status
    WHEN 'noshow' THEN 'interview_noshow'
    WHEN 'cancelled' THEN 'interview_pending'
    WHEN 'rescheduled' THEN 'interview_pending'
    WHEN 'completed' THEN 'interview_done'
    ELSE v_app.status
  END;

  UPDATE public.selection_applications
  SET status = v_new_app_status, updated_at = now()
  WHERE id = v_interview.application_id
    AND status IN ('interview_scheduled', 'interview_done');

  IF p_status = 'noshow' AND v_prior_status IS DISTINCT FROM 'noshow' THEN
    v_first_name := COALESCE(
      NULLIF(trim(v_app.first_name), ''),
      NULLIF(split_part(v_app.applicant_name, ' ', 1), ''),
      'candidato(a)'
    );

    SELECT count(*) INTO v_noshow_count
    FROM public.selection_interviews
    WHERE application_id = v_interview.application_id
      AND status = 'noshow';

    IF v_noshow_count >= 2 THEN
      -- 2-strike auto-close: status rejected + e-mail de encerramento, sem reagendamento suave
      UPDATE public.selection_applications
      SET status = 'rejected',
          feedback = COALESCE(feedback, '') || E'\n[p152 auto-close ' || to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI') || ' BRT] Encerrado automaticamente após ' || v_noshow_count || ' no-shows na entrevista.',
          updated_at = now()
      WHERE id = v_interview.application_id;

      BEGIN
        v_two_strike_send := public.campaign_send_one_off(
          'interview_two_strike_close',
          v_app.email,
          jsonb_build_object('first_name', v_first_name),
          jsonb_build_object(
            'language', 'pt',
            'recipient_name', COALESCE(v_app.first_name, v_app.applicant_name),
            'source', 'mark_interview_status:two_strike_close',
            'noshow_count', v_noshow_count
          )
        );
      EXCEPTION WHEN OTHERS THEN
        v_two_strike_send := jsonb_build_object('error', SQLERRM);
      END;

      v_two_strike_applied := true;

      PERFORM public.create_notification(
        sc.member_id,
        'selection_application_two_strike_closed',
        '2-strike encerrado: ' || v_app.applicant_name,
        v_app.applicant_name || ' teve ' || v_noshow_count || ' no-shows. Processo encerrado automaticamente + email enviado. Override manual via Status select.',
        '/admin/selection',
        'selection_application',
        v_interview.application_id
      )
      FROM public._selection_cycle_recipients(v_app.cycle_id) sc;
    ELSE
      -- 1º no-show: e-mail de reagendamento suave (caminho P1), agora com LINK DE TOKEN (#1595).
      v_dispatch := public._dispatch_interview_booking_link(
        v_interview.application_id, v_caller.id, 'mark_interview_status:noshow'
      );
      v_deadline_date := to_char((now() + interval '7 days') AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY');

      IF COALESCE((v_dispatch->>'success')::boolean, false) THEN
        v_booking_url := v_dispatch->>'booking_url';

        BEGIN
          v_send_result := public.campaign_send_one_off(
            'interview_noshow_soft_reschedule',
            v_app.email,
            jsonb_build_object(
              'first_name', v_first_name,
              'booking_url', v_booking_url,
              'deadline_date', v_deadline_date
            ),
            jsonb_build_object(
              'language', 'pt',
              'recipient_name', COALESCE(v_app.first_name, v_app.applicant_name),
              'source', 'mark_interview_status:noshow',
              'link_kind', 'governed_token',
              'gate_mode', v_dispatch->>'gate_mode'
            )
          );
        EXCEPTION WHEN OTHERS THEN
          v_send_result := jsonb_build_object('error', SQLERRM);
        END;
      ELSE
        -- Sem link governado não sai e-mail: mandar o link cru era exatamente o defeito da #1595.
        v_send_result := jsonb_build_object(
          'error', 'booking_link_unavailable',
          'failure_code', v_dispatch->>'failure_code',
          'gate_failed_code', v_dispatch->>'gate_failed_code'
        );
      END IF;
    END IF;
  END IF;

  IF p_status = 'noshow' AND NOT v_two_strike_applied THEN
    PERFORM public.create_notification(
      sc.member_id,
      'selection_interview_noshow',
      'No-show: ' || v_app.applicant_name,
      v_app.applicant_name || ' (' || COALESCE(v_app.chapter, '') || ') não compareceu à entrevista agendada.',
      '/admin/selection',
      'selection_interview',
      p_interview_id
    )
    FROM public._selection_cycle_recipients(v_app.cycle_id) sc;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'interview_status', p_status,
    'application_status', CASE WHEN v_two_strike_applied THEN 'rejected' ELSE v_new_app_status END,
    'email_dispatched', v_send_result IS NOT NULL AND (v_send_result ? 'send_id'),
    'email_send_result', v_send_result,
    'two_strike_applied', v_two_strike_applied,
    'noshow_count', v_noshow_count,
    'two_strike_email', v_two_strike_send,
    'link_kind', CASE WHEN COALESCE((v_dispatch->>'success')::boolean, false) THEN 'governed_token' ELSE NULL END,
    'gate_mode', v_dispatch->>'gate_mode'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.submit_interview_scores(
  p_interview_id uuid,
  p_scores jsonb,
  p_theme text DEFAULT NULL::text,
  p_notes text DEFAULT NULL::text,
  p_criterion_notes jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_interview record;
  v_app record;
  v_cycle record;
  v_criteria jsonb;
  v_criterion jsonb;
  v_key text;
  v_score numeric;
  v_weight numeric;
  v_weighted_sum numeric := 0;
  v_eval_id uuid;
  v_all_interviewers_submitted boolean;
  v_all_subtotals numeric[];
  v_pert_score numeric;
  v_min_sub numeric;
  v_max_sub numeric;
  v_avg_sub numeric;
BEGIN
  -- 1. Auth
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- 2. Get interview + application + cycle
  SELECT * INTO v_interview FROM public.selection_interviews WHERE id = p_interview_id;
  IF v_interview IS NULL THEN
    RAISE EXCEPTION 'Interview not found';
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = v_interview.application_id;
  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  -- 3. V4 authorization: interviewer (resource) or platform admin
  IF NOT (v_caller.id = ANY(v_interview.interviewer_ids))
     AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    -- #1972: `x = ANY('{}')` e falso para TODOS, entao lista vazia nao designa ninguem e
    -- so quem tem manage_platform passava. O auto-agendamento
    -- (sync_calendar_booking_to_interview) cria a entrevista com ARRAY[]::uuid[] hardcoded,
    -- porque o payload do webhook nao carrega identidade de entrevistador. Quem conduziu a
    -- entrevista ficava barrado por um campo que NENHUM caminho preenchia: medido em
    -- 24/08/2026, 25 das 26 entrevistas sem entrevistador vieram dali.
    --
    -- Aqui a designacao e CRIADA, nao contornada. Exige comite DO CICLO com can_interview,
    -- grava o chamador como entrevistador e deixa rastro em admin_audit_log. So atua com a
    -- lista VAZIA: designacao existente nunca e sobrescrita, entao o vinculo
    -- entrevistador-entrevista continua sendo o que decide.
    IF cardinality(coalesce(v_interview.interviewer_ids, ARRAY[]::uuid[])) = 0
       AND EXISTS (
         SELECT 1 FROM public.selection_committee sc
         WHERE sc.member_id = v_caller.id
           AND sc.cycle_id = v_app.cycle_id
           AND sc.can_interview
       ) THEN
      UPDATE public.selection_interviews
      SET interviewer_ids = ARRAY[v_caller.id]
      WHERE id = p_interview_id;
      v_interview.interviewer_ids := ARRAY[v_caller.id];

      INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
      VALUES (
        v_caller.id, 'selection.interview_self_assigned', 'selection_interview', p_interview_id,
        jsonb_build_object('interviewer_id', v_caller.id, 'application_id', v_app.id),
        jsonb_build_object('reason', 'lista vazia criada por auto-agendamento', 'issue', 1972, 'cycle_id', v_app.cycle_id)
      );
    ELSE
      RAISE EXCEPTION 'Unauthorized: not an assigned interviewer';
    END IF;
  END IF;

  -- 4. Get interview criteria and calculate weighted subtotal
  v_criteria := v_cycle.interview_criteria;

  FOR v_criterion IN SELECT * FROM jsonb_array_elements(v_criteria)
  LOOP
    v_key := v_criterion ->> 'key';
    v_weight := COALESCE((v_criterion ->> 'weight')::numeric, 1);

    IF NOT (p_scores ? v_key) THEN
      RAISE EXCEPTION 'Missing score for criterion: %', v_key;
    END IF;

    v_score := (p_scores ->> v_key)::numeric;
    v_weighted_sum := v_weighted_sum + (v_weight * v_score);
  END LOOP;

  -- 5. Upsert evaluation (interview type) — trigger trg_recompute_application_scores
  -- fires AFTER this and writes correct research_score + final_score.
  INSERT INTO public.selection_evaluations (
    application_id, evaluator_id, evaluation_type,
    scores, weighted_subtotal, notes, criterion_notes, submitted_at
  ) VALUES (
    v_interview.application_id, v_caller.id, 'interview',
    p_scores, ROUND(v_weighted_sum, 2), p_notes, COALESCE(p_criterion_notes, '{}'::jsonb), now()
  )
  ON CONFLICT (application_id, evaluator_id, evaluation_type)
  DO UPDATE SET
    scores = EXCLUDED.scores,
    weighted_subtotal = EXCLUDED.weighted_subtotal,
    notes = EXCLUDED.notes,
    criterion_notes = EXCLUDED.criterion_notes,
    submitted_at = now()
  RETURNING id INTO v_eval_id;

  -- 6. Update interview theme if provided
  IF p_theme IS NOT NULL THEN
    UPDATE public.selection_interviews
    SET theme_of_interest = p_theme
    WHERE id = p_interview_id;
  END IF;

  -- 7. WATCH-240.A (p241): mark interview as conducted as soon as ANY interviewer
  -- submits scores. The act of submitting a scored evaluation is canonical evidence
  -- that the interview took place. Pre-WATCH-240.A this UPDATE only fired inside
  -- the all-submitted branch below, leaving partial-submit apps stuck in
  -- 'interview_pending'. The p240 trigger _trg_sync_interview_to_app_status
  -- (migration 20260805000025) keys on conducted_at + status changes of
  -- selection_interviews and is the canonical owner of app status sync to
  -- 'interview_done' (idempotent + terminal-guarded). Idempotency guard below
  -- prevents overwriting an earlier conducted_at (e.g., set by mark_interview_status
  -- or a previous submit_interview_scores call from a different evaluator).
  IF v_interview.conducted_at IS NULL THEN
    UPDATE public.selection_interviews
    SET conducted_at = now()
    WHERE id = p_interview_id;
  END IF;

  -- 8. Check if all interviewers submitted
  v_all_interviewers_submitted := NOT EXISTS (
    SELECT 1 FROM unnest(v_interview.interviewer_ids) iid
    WHERE NOT EXISTS (
      SELECT 1 FROM public.selection_evaluations
      WHERE application_id = v_interview.application_id
        AND evaluator_id = iid
        AND evaluation_type = 'interview'
        AND submitted_at IS NOT NULL
    )
  );

  -- 9. If all submitted: mark interview row complete + PERT + advance app to
  -- final_eval. (final_score recomputed by trg_recompute_application_scores via
  -- compute_application_scores when the interview evaluation INSERT fires.)
  -- conducted_at was already set in step 7 (idempotent) — only the interview
  -- lifecycle status moves to 'completed' here, signalling the row is sealed.
  IF v_all_interviewers_submitted THEN
    UPDATE public.selection_interviews
    SET status = 'completed'
    WHERE id = p_interview_id;

    SELECT ARRAY_AGG(weighted_subtotal ORDER BY weighted_subtotal)
    INTO v_all_subtotals
    FROM public.selection_evaluations
    WHERE application_id = v_interview.application_id
      AND evaluation_type = 'interview'
      AND submitted_at IS NOT NULL;

    v_min_sub := v_all_subtotals[1];
    v_max_sub := v_all_subtotals[array_upper(v_all_subtotals, 1)];
    SELECT AVG(unnest) INTO v_avg_sub FROM unnest(v_all_subtotals);

    v_pert_score := ROUND((2 * v_min_sub + 4 * v_avg_sub + 2 * v_max_sub) / 8, 2);

    -- final_score is recomputed by trg_recompute_application_scores via
    -- compute_application_scores when the interview evaluation INSERT fires.
    -- We only update interview_score (display column) and status here.
    UPDATE public.selection_applications
    SET interview_score = v_pert_score,
        status = 'final_eval',
        updated_at = now()
    WHERE id = v_interview.application_id;

    -- Re-fetch app after trigger has run, so notification reflects the corrected
    -- research_score / final_score.
    SELECT * INTO v_app FROM public.selection_applications WHERE id = v_interview.application_id;

    PERFORM public.create_notification(
      sc.member_id,
      'selection_evaluation_complete',
      'Avaliação completa: ' || v_app.applicant_name,
      'Todas as avaliações (objetiva + entrevista) de ' || v_app.applicant_name || ' foram concluídas. Nota final: ' || ROUND(COALESCE(v_app.final_score, v_app.research_score, 0), 2),
      '/admin/selection',
      'selection_application',
      v_app.id
    )
    FROM public._selection_cycle_recipients(v_app.cycle_id) sc;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'evaluation_id', v_eval_id,
    'weighted_subtotal', ROUND(v_weighted_sum, 2),
    'all_interviewers_submitted', v_all_interviewers_submitted,
    'pert_interview_score', v_pert_score
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public._selection_status_recompute_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result jsonb;
  v_changed int;
  v_affected_cycles uuid[];
  v_recipient record;
BEGIN
  -- #693 — honor HARD terminal VEP decisions first (pull declined/withdrawn/
  -- expired apps out of the active funnel) so the in-flight recompute below
  -- never re-evaluates a row VEP has already terminated. Idempotent; self-audited.
  PERFORM public.reconcile_vep_terminal_status(NULL, false);

  -- apply mode over every cycle; forward-only + terminal-safe + audited inside.
  v_result := public.recompute_application_status(NULL, NULL, false);
  v_changed := COALESCE((v_result->>'changed')::int, 0);

  IF v_changed > 0 THEN
    SELECT array_agg(DISTINCT (c->>'cycle_id')::uuid) INTO v_affected_cycles
    FROM jsonb_array_elements(v_result->'changes') AS c;

    -- #1978: alerta o destinatario resolvido de cada ciclo afetado (o lead; sem lead, o
    -- comite do ciclo; sem comite, manage_platform). Antes o predicado era role='lead'
    -- exclusivo, e ciclo sem lead nao rodava o laco nenhuma vez (root fix = #472 corr.#2).
    FOR v_recipient IN
      SELECT DISTINCT r.member_id
      FROM unnest(v_affected_cycles) AS ac(cycle_id)
      CROSS JOIN LATERAL public._selection_cycle_recipients(ac.cycle_id) r
      WHERE r.member_id IS NOT NULL
    LOOP
      PERFORM public.create_notification(
        v_recipient.member_id,
        'selection_status_auto_healed',
        'Status de candidatos corrigido automaticamente',
        v_changed || ' candidato(s) tiveram o status recomputado a partir das avaliações/entrevistas '
          || '(possível clobber de re-import VEP — ver #472). Revise em /admin/selection.',
        '/admin/selection',
        'selection_cycle',
        v_affected_cycles[1]
      );
    END LOOP;
  END IF;

  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
