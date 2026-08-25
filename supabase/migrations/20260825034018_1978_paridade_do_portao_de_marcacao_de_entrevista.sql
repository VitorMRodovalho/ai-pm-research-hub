-- #1978 — paridade do portao: `mark_interview_status` ganha o ramo de reivindicacao do #1972.
--
-- SINTOMA MEDIDO (25/08/2026): o unico ciclo ABERTO (`cycle4-2026`, phase=evaluating) tem 7
-- pessoas no comite e ZERO com `role='lead'` — os papeis usados sao so `evaluator` e `observer`.
-- Nesse estado, 5 dos 7 podiam lancar nota de entrevista (pelo ramo criado no #1972) e NAO
-- podiam marcar no-show, cancelamento ou reagendamento. So os 2 com `manage_platform` passavam.
--
-- POR QUE O #1972 NAO COBRIU ISTO: la a reivindicacao nasce dentro de `submit_interview_scores`,
-- entao quem submete nota vira o entrevistador designado e passa a partir dali. Em 'noshow',
-- 'cancelled' e 'rescheduled' a entrevista NAO aconteceu, logo nao existe submissao de nota que
-- crie a designacao antes. Para esses tres status nao havia caminho nenhum fora do GP.
--
-- O CONSERTO NAO AMPLIA O PORTAO, pelo mesmo motivo do #1972: trocar "designado para ESTA
-- entrevista" por "pode entrevistar em geral" apagaria o vinculo entrevistador-entrevista. Aqui o
-- vinculo e ESCRITO — quem reivindica precisa ser do comite DO CICLO com `can_interview`, vira o
-- entrevistador designado da linha e deixa rastro em `admin_audit_log`. So atua com a lista
-- VAZIA; designacao existente nunca e sobrescrita.
--
-- O ramo de `role='lead'` continua onde estava: este conserto nao o substitui, cobre o vao que
-- ele deixa quando o ciclo nao tem lead designado. As outras 12 RPCs que dependem de
-- `role='lead'` exclusivo, e as 4 superficies de notificacao sem destinatario, seguem na #1978.
--
-- ATENCAO: o corpo abaixo e a CAPTURA do Phase C. Nao acrescente comentario que nao esteja no que
-- foi aplicado, ou o md5 do prosrc deixa de bater e o guard acusa drift.

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
      FROM public.selection_committee sc
      WHERE sc.cycle_id = v_app.cycle_id AND sc.role = 'lead';
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
    FROM public.selection_committee sc
    WHERE sc.cycle_id = v_app.cycle_id AND sc.role = 'lead';
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
NOTIFY pgrst, 'reload schema';
