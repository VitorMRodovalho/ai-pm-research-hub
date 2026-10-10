-- #2671 — Reserva de entrevista feita com e-mail diferente da candidatura: sugestão e vínculo pela tela; e a fila
-- de exceção do /admin/selection sem ruído. Decisão do GP (10/10/2026, repassada pela orquestradora).
--
-- Medido em 10/10/2026 (selection_booking_attempts não resolvidas): 40 linhas; 35 no_application, 4 cycle_closed,
-- 1 status_not_allowed; 37 suprimidas (o poller parou de registrar, mas seguiam "acionáveis"); 4 já passadas;
-- 26 com e-mail de membro por members.email/secondary_emails (27 somando member_emails e persons de membro ou login):
-- outros compromissos da agenda de entrevistas (GP, contas institucionais, comissão), não candidatos.
--
-- (1) get_booking_exception_queue(p_include_resolved, p_include_hidden) — DROP + CREATE (muda o retorno):
--     * e-mail de membro ou de quem tem login NUNCA aparece;
--     * suprimida ou com horário passado fica OCULTA por padrão (p_include_hidden = true a traz, marcada);
--     * actionable = no_application, não resolvida, não suprimida e não passada: é o que o título conta;
--     * suggestions (só para no_application): até 3 candidaturas de ciclo aberto/ativo e status ainda em seleção,
--       primeiro as que um e-mail secundário liga ao convidado (persons.secondary_emails, members.secondary_emails,
--       member_emails), depois por semelhança do nome com o e-mail do convidado (pg_trgm).
--     Mesmo portão de antes (comissão de qualquer ciclo, manage_platform, manage_member, view_internal_analytics).
-- (2) link_booking_to_application(calendar_event_id, guest_email, application_id): registra a entrevista da reserva na
--     candidatura escolhida, pela mesma regra do webhook (sync_calendar_booking_to_interview): ciclo aberto/ativo,
--     status ainda em seleção, fase objetiva concluída (#1450), evento ainda sem entrevista. O gatilho da entrevista
--     tira a candidatura de needs_reschedule, e os lembretes de remarcação (process_pending_reschedule_nudges, que
--     só olham needs_reschedule) param. A reserva fica resolvida. Portão: comissão (lead/evaluator) do ciclo da
--     candidatura, ou manage_member, ou manage_platform. Trilha em admin_audit_log.
--     O par (evento, convidado) é a chave: um evento pode ter mais de um convidado (membro + candidato).
--     Se o poller ler o evento de novo, record_booking_attempt preserva resolved_at, e a reserva não volta à fila.
--     O e-mail alternativo NÃO é gravado na candidatura: nova reserva com ele volta à fila e se vincula de novo.
--
-- Rollback: DROP das duas funções (link_booking_to_application(text, text, uuid)); recriar get_booking_exception_queue(boolean) pela captura 20260805000512
--   (com o REVOKE/GRANT de lá).

DROP FUNCTION IF EXISTS public.get_booking_exception_queue(boolean);

CREATE OR REPLACE FUNCTION public.get_booking_exception_queue(
  p_include_resolved boolean DEFAULT false,
  p_include_hidden boolean DEFAULT false
)
 RETURNS TABLE(calendar_event_id text, guest_email text, attempts integer, first_seen_at timestamptz,
               last_seen_at timestamptz, last_outcome text, actionable boolean, suppressed boolean,
               resolved_at timestamptz, last_scheduled_at timestamptz, application_id uuid, applicant_name text,
               app_status text, is_past boolean, hidden boolean, suggestions jsonb)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_allow constant text[] := ARRAY['submitted', 'screening', 'objective_eval', 'objective_cutoff',
                                   'interview_pending', 'interview_scheduled'];
BEGIN
  -- Gate: a fila expõe e-mail de candidato (PII). Mesma escada de antes: comissão de QUALQUER ciclo, ou
  -- autoridade de plataforma/membro/análise. Contexto sem JWT (pg_cron / service_role) é o caminho interno.
  IF auth.uid() IS NOT NULL THEN
    SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
    IF v_caller IS NULL THEN
      RAISE EXCEPTION 'Unauthorized: member not found';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.selection_committee sc WHERE sc.member_id = v_caller.id)
       AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text)
       AND NOT public.can_by_member(v_caller.id, 'manage_member'::text)
       AND NOT public.can_by_member(v_caller.id, 'view_internal_analytics'::text)
    THEN
      RAISE EXCEPTION 'Unauthorized: must be selection committee or have manage_platform/manage_member/view_internal_analytics';
    END IF;
  END IF;

  RETURN QUERY
  WITH member_addresses AS (
    SELECT lower(m.email) AS e FROM public.members m WHERE m.email IS NOT NULL
    UNION SELECT lower(se) FROM public.members m, unnest(m.secondary_emails) se
    UNION SELECT lower(me.email::text) FROM public.member_emails me
    UNION SELECT lower(p.email) FROM public.persons p WHERE p.legacy_member_id IS NOT NULL OR p.auth_id IS NOT NULL
    UNION SELECT lower(se) FROM public.persons p, unnest(p.secondary_emails) se
     WHERE p.legacy_member_id IS NOT NULL OR p.auth_id IS NOT NULL
  ),
  base AS (
    SELECT ba.*,
           (ba.last_scheduled_at IS NOT NULL AND ba.last_scheduled_at < now()) AS past
    FROM public.selection_booking_attempts ba
    WHERE (p_include_resolved OR ba.resolved_at IS NULL)
      -- e-mail de membro ou de quem tem login nunca aparece: é outro compromisso da agenda, não candidato
      AND NOT EXISTS (SELECT 1 FROM member_addresses ma WHERE ma.e = lower(ba.guest_email))
  )
  SELECT b.calendar_event_id,
         b.guest_email,
         b.attempts,
         b.first_seen_at,
         b.last_seen_at,
         b.last_outcome,
         -- acionável HOJE: buraco real, ainda aberto, com o poller vendo e o horário por vir
         (b.last_outcome = 'no_application' AND b.resolved_at IS NULL
          AND b.suppressed_at IS NULL AND NOT b.past) AS actionable,
         (b.suppressed_at IS NOT NULL) AS suppressed,
         b.resolved_at,
         b.last_scheduled_at,
         m.application_id,
         m.applicant_name,
         m.app_status,
         b.past AS is_past,
         (b.suppressed_at IS NOT NULL OR b.past) AS hidden,
         CASE WHEN b.last_outcome <> 'no_application' THEN '[]'::jsonb ELSE COALESCE((
           SELECT jsonb_agg(s ORDER BY s.rank, s.score DESC)
           FROM (SELECT x.* FROM (
             SELECT DISTINCT ON (a.id)
                    a.id AS application_id, a.applicant_name, a.status, a.cycle_id,
                    (a.objective_score_avg IS NOT NULL) AS objective_done,
                    CASE WHEN alt.hit THEN 'secondary_email' ELSE 'name' END AS reason,
                    CASE WHEN alt.hit THEN 0 ELSE 1 END AS rank,
                    round(similarity(lower(a.applicant_name),
                          regexp_replace(split_part(lower(b.guest_email), '@', 1), '[^a-z]+', ' ', 'g'))::numeric, 2) AS score
             FROM public.selection_applications a
             JOIN public.selection_cycles c ON c.id = a.cycle_id
             CROSS JOIN LATERAL (
               SELECT EXISTS (
                 SELECT 1 FROM public.persons p
                 WHERE lower(b.guest_email) = ANY (SELECT lower(x) FROM unnest(p.secondary_emails) x)
                   AND lower(p.email) = lower(a.email)
               ) OR EXISTS (
                 SELECT 1 FROM public.members mm
                 WHERE lower(b.guest_email) = ANY (SELECT lower(x) FROM unnest(mm.secondary_emails) x)
                   AND lower(mm.email) = lower(a.email)
               ) AS hit
             ) alt
             WHERE c.status IN ('open', 'active')
               AND a.status = ANY (v_allow)
               AND a.anonymized_at IS NULL
               AND NOT EXISTS (SELECT 1 FROM public.selection_interviews si
                               WHERE si.application_id = a.id AND si.status IN ('scheduled', 'rescheduled', 'completed'))
               AND (alt.hit OR similarity(lower(a.applicant_name),
                                          regexp_replace(split_part(lower(b.guest_email), '@', 1), '[^a-z]+', ' ', 'g')) > 0.2)
             ORDER BY a.id
           ) x
           ORDER BY x.rank, x.score DESC
           LIMIT 3) s
         ), '[]'::jsonb) END AS suggestions
  FROM base b
  LEFT JOIN LATERAL public.match_booking_application(b.guest_email) m ON true
  WHERE p_include_hidden OR NOT (b.suppressed_at IS NOT NULL OR b.past)
  ORDER BY (b.last_outcome = 'no_application' AND b.resolved_at IS NULL AND b.suppressed_at IS NULL AND NOT b.past) DESC,
           b.last_seen_at DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_booking_exception_queue(boolean, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_booking_exception_queue(boolean, boolean) TO authenticated, service_role;

-- ── (2) vínculo manual ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.link_booking_to_application(p_calendar_event_id text, p_guest_email text,
                                                              p_application_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_allow constant text[] := ARRAY['submitted', 'screening', 'objective_eval', 'objective_cutoff',
                                   'interview_pending', 'interview_scheduled'];
  v_caller       uuid;
  v_attempt      record;
  v_app          record;
  v_interview_id uuid;
  v_status_changed boolean := false;
BEGIN
  SELECT m.id INTO v_caller FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT a.id, a.status, a.email, a.applicant_name, a.cycle_id, a.objective_score_avg, c.status AS cycle_status
    INTO v_app
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE a.id = p_application_id AND a.anonymized_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Application not found' USING ERRCODE = 'no_data_found';
  END IF;

  -- portão: comissão do ciclo DESTA candidatura, ou autoridade de membro/plataforma
  IF NOT EXISTS (SELECT 1 FROM public.selection_committee sc
                 WHERE sc.cycle_id = v_app.cycle_id AND sc.member_id = v_caller AND sc.role IN ('lead', 'evaluator'))
     AND NOT public.can_by_member(v_caller, 'manage_member')
     AND NOT public.can_by_member(v_caller, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: must be committee of this cycle or have manage_member/manage_platform'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_attempt FROM public.selection_booking_attempts ba
  WHERE ba.calendar_event_id = p_calendar_event_id AND lower(ba.guest_email) = lower(btrim(p_guest_email))
    AND ba.resolved_at IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Open booking not found for this calendar event' USING ERRCODE = 'no_data_found';
  END IF;
  -- só o buraco real se vincula: status_not_allowed e cycle_closed são recusas corretas
  IF v_attempt.last_outcome <> 'no_application' THEN
    RAISE EXCEPTION 'Only bookings without an application can be linked (outcome %)', v_attempt.last_outcome
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_attempt.last_scheduled_at IS NULL THEN
    RAISE EXCEPTION 'Booking has no scheduled time' USING ERRCODE = 'check_violation';
  END IF;

  -- as mesmas regras do webhook (sync_calendar_booking_to_interview)
  IF v_app.cycle_status NOT IN ('open', 'active') OR NOT (v_app.status = ANY (v_allow)) THEN
    RAISE EXCEPTION 'Application is not in an open selection step (cycle %, status %)', v_app.cycle_status, v_app.status
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_app.objective_score_avg IS NULL THEN
    RAISE EXCEPTION 'Application has not completed the objective phase (#1450)' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM public.selection_interviews si WHERE si.calendar_event_id = p_calendar_event_id) THEN
    RAISE EXCEPTION 'This calendar event is already linked to an interview' USING ERRCODE = 'unique_violation';
  END IF;

  INSERT INTO public.selection_interviews (application_id, interviewer_ids, scheduled_at, duration_minutes,
                                           status, calendar_event_id)
  VALUES (v_app.id, ARRAY[]::uuid[], v_attempt.last_scheduled_at, 30, 'scheduled', p_calendar_event_id)
  RETURNING id INTO v_interview_id;

  IF v_app.status IN ('submitted', 'in_review', 'interview_pending') THEN
    UPDATE public.selection_applications SET status = 'interview_scheduled', updated_at = now() WHERE id = v_app.id;
    v_status_changed := true;
  END IF;

  UPDATE public.selection_booking_attempts
  SET resolved_at = now(), last_outcome = 'matched', outcome_changed_at = now()
  WHERE id = v_attempt.id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (v_caller, 'selection.booking_linked_manually', 'selection_interview', v_interview_id,
          jsonb_build_object('application_id', v_app.id, 'guest_email', v_attempt.guest_email,
                             'scheduled_at', v_attempt.last_scheduled_at, 'previous_app_status', v_app.status,
                             'status_changed', v_status_changed),
          jsonb_build_object('calendar_event_id', p_calendar_event_id, 'source', 'link_booking_to_application', 'issue', 2671));

  RETURN jsonb_build_object('success', true, 'interview_id', v_interview_id, 'application_id', v_app.id,
                            'status_changed', v_status_changed);
END;
$function$;

REVOKE ALL ON FUNCTION public.link_booking_to_application(text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.link_booking_to_application(text, text, uuid) TO authenticated, service_role;

-- ── pós-condição ──────────────────────────────────────────────────────────────
DO $postcondition$
DECLARE
  v_n integer;
BEGIN
  -- nenhum e-mail de membro na fila, mesmo com ocultas e resolvidas
  SELECT count(*) INTO v_n
  FROM public.get_booking_exception_queue(true, true) q
  WHERE EXISTS (SELECT 1 FROM public.members m
                WHERE lower(m.email) = lower(q.guest_email)
                   OR lower(q.guest_email) = ANY (SELECT lower(x) FROM unnest(m.secondary_emails) x));
  IF v_n <> 0 THEN RAISE EXCEPTION '#2671: % linha(s) com e-mail de membro na fila', v_n; END IF;

  -- acionável nunca é suprimida nem passada
  SELECT count(*) INTO v_n FROM public.get_booking_exception_queue(false, true) q
  WHERE q.actionable AND (q.suppressed OR q.is_past);
  IF v_n <> 0 THEN RAISE EXCEPTION '#2671: % acionável(is) suprimida(s) ou passada(s)', v_n; END IF;

  -- a visão padrão não traz oculta
  SELECT count(*) INTO v_n FROM public.get_booking_exception_queue(false, false) q WHERE q.hidden;
  IF v_n <> 0 THEN RAISE EXCEPTION '#2671: a visão padrão trouxe % oculta(s)', v_n; END IF;

  IF has_function_privilege('anon', 'public.link_booking_to_application(text, text, uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.get_booking_exception_queue(boolean, boolean)', 'EXECUTE') THEN
    RAISE EXCEPTION '#2671: anon executa uma das funções';
  END IF;
END
$postcondition$;

NOTIFY pgrst, 'reload schema';
