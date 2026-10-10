-- #2671 — Reserva de entrevista feita com e-mail diferente da candidatura: sugestão e vínculo pela tela; e a fila
-- de exceção do /admin/selection sem ruído. Decisão do GP (10/10/2026, repassada pela orquestradora).
--
-- Medido em 10/10/2026 (selection_booking_attempts não resolvidas): 40 linhas; 35 no_application, 4 cycle_closed,
-- 1 status_not_allowed; 37 suprimidas (o poller parou de registrar, mas seguiam "acionáveis"); 4 já passadas;
-- 26 com e-mail de membro por members.email/secondary_emails (27 somando member_emails e persons de membro ou login):
-- outros compromissos da agenda de entrevistas (GP, contas institucionais, comissão), não candidatos.
--
-- (0) _booking_guest_is_internal(email): o endereço é de membro ou de quem tem login (members.email/secondary_emails,
--     member_emails, persons com login) E o dono não tem candidatura em ciclo aberto/ativo por nenhum dos endereços
--     dele. A segunda metade existe porque membro também se candidata: reservar com outro endereço cadastrado não
--     pode esconder o candidato (medido 10/10: 0 casos hoje, a regra é para os próximos ciclos).
-- (1) get_booking_exception_queue(p_include_resolved, p_include_hidden) — DROP + CREATE (muda o retorno):
--     * endereço interno (0) NUNCA aparece;
--     * suprimida ou com horário passado fica OCULTA por padrão (p_include_hidden = true a traz, marcada);
--     * actionable = no_application, não resolvida, não suprimida e não passada: é o que o título conta;
--     * suggestions (só para no_application ainda aberta): até 3 candidaturas de ciclo aberto/ativo, status ainda em
--       seleção e sem entrevista ativa, primeiro as que um e-mail secundário liga ao convidado (persons e members
--       .secondary_emails), depois por semelhança do nome com o e-mail do convidado (pg_trgm). Só de ciclo em que quem
--       pergunta é comissão (lead/evaluator), ou de qualquer ciclo para manage_member/manage_platform: é quem pode
--       vincular, e nome de candidato é dado pessoal.
--     Mesmo portão de antes (comissão de qualquer ciclo, manage_platform, manage_member, view_internal_analytics).
-- (2) link_booking_to_application(calendar_event_id, guest_email, application_id): registra a entrevista da reserva na
--     candidatura escolhida, pela mesma regra do webhook (sync_calendar_booking_to_interview): ciclo aberto/ativo,
--     status ainda em seleção, fase objetiva concluída (#1450, mais estrito que o webhook, que isenta quem já está em
--     interview_scheduled), evento ainda sem entrevista, candidatura sem entrevista ativa, convidado não interno (0).
--     interviewer_ids fica vazio: a reserva não guarda os convidados entrevistadores. O gatilho da entrevista
--     tira a candidatura de needs_reschedule, e os lembretes de remarcação (process_pending_reschedule_nudges, que
--     só olham needs_reschedule) param. A reserva fica resolvida. Portão: comissão (lead/evaluator) do ciclo da
--     candidatura, ou manage_member, ou manage_platform. Trilha em admin_audit_log.
--     O par (evento, convidado) é a chave: um evento pode ter mais de um convidado (membro + candidato).
--     Se o poller ler o evento de novo, record_booking_attempt preserva resolved_at (a reserva não volta à fila) mas
--     regrava last_outcome = no_application; por isso a sugestão e o "acionável" exigem resolved_at nulo.
--     A trilha guarda o id da reserva, não o e-mail do convidado (dado de terceiro já está na própria reserva).
--     O e-mail alternativo NÃO é gravado na candidatura: nova reserva com ele volta à fila e se vincula de novo.
--
-- Rollback: DROP das três funções (link_booking_to_application(text, text, uuid), _booking_guest_is_internal(text)); recriar get_booking_exception_queue(boolean) pela captura 20260805000512
--   (com o REVOKE/GRANT de lá).

-- ── (0) endereço interno ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._booking_guest_is_internal(p_email text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  WITH owners AS (
    -- dono do endereço: o membro (por members ou member_emails) ou a pessoa com login
    SELECT 'm:' || m.id::text AS k FROM public.members m
     WHERE lower(m.email) = lower(btrim(p_email))
        OR lower(btrim(p_email)) = ANY (SELECT lower(x) FROM unnest(m.secondary_emails) x)
    UNION SELECT 'm:' || me.member_id::text FROM public.member_emails me WHERE lower(me.email::text) = lower(btrim(p_email))
    UNION SELECT CASE WHEN p.legacy_member_id IS NOT NULL THEN 'm:' || p.legacy_member_id::text ELSE 'p:' || p.id::text END
      FROM public.persons p
     WHERE (p.legacy_member_id IS NOT NULL OR p.auth_id IS NOT NULL)
       AND (lower(p.email) = lower(btrim(p_email))
            OR lower(btrim(p_email)) = ANY (SELECT lower(x) FROM unnest(p.secondary_emails) x))
  ),
  owner_addresses AS (
    SELECT lower(m.email) AS e FROM public.members m JOIN owners o ON o.k = 'm:' || m.id::text
    UNION SELECT lower(x) FROM public.members m JOIN owners o ON o.k = 'm:' || m.id::text, unnest(m.secondary_emails) x
    UNION SELECT lower(me.email::text) FROM public.member_emails me JOIN owners o ON o.k = 'm:' || me.member_id::text
    UNION SELECT lower(p.email) FROM public.persons p JOIN owners o
            ON o.k = CASE WHEN p.legacy_member_id IS NOT NULL THEN 'm:' || p.legacy_member_id::text ELSE 'p:' || p.id::text END
    UNION SELECT lower(x) FROM public.persons p JOIN owners o
            ON o.k = CASE WHEN p.legacy_member_id IS NOT NULL THEN 'm:' || p.legacy_member_id::text ELSE 'p:' || p.id::text END,
          unnest(p.secondary_emails) x
  )
  SELECT EXISTS (SELECT 1 FROM owners)
     AND NOT EXISTS (
       SELECT 1 FROM public.selection_applications a
       JOIN public.selection_cycles c ON c.id = a.cycle_id
       WHERE c.status IN ('open', 'active') AND a.anonymized_at IS NULL
         AND lower(a.email) IN (SELECT e FROM owner_addresses)
     );
$function$;

REVOKE ALL ON FUNCTION public._booking_guest_is_internal(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._booking_guest_is_internal(text) TO service_role;

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
  v_caller_id uuid;
  v_is_manager boolean := false;
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
    v_caller_id := v_caller.id;
    v_is_manager := public.can_by_member(v_caller.id, 'manage_platform'::text)
                    OR public.can_by_member(v_caller.id, 'manage_member'::text);
  END IF;

  RETURN QUERY
  WITH base AS (
    SELECT ba.*,
           (ba.last_scheduled_at IS NOT NULL AND ba.last_scheduled_at < now()) AS past
    FROM public.selection_booking_attempts ba
    WHERE (p_include_resolved OR ba.resolved_at IS NULL)
      -- endereço interno nunca aparece: é outro compromisso da agenda, não candidato
      AND NOT public._booking_guest_is_internal(ba.guest_email)
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
         CASE WHEN b.last_outcome <> 'no_application' OR b.resolved_at IS NOT NULL THEN '[]'::jsonb ELSE COALESCE((
           WITH aliases AS (
             -- endereço principal de quem cadastrou o convidado como e-mail secundário (calculado uma vez por reserva)
             SELECT lower(p.email) AS e FROM public.persons p
              WHERE lower(b.guest_email) = ANY (SELECT lower(y) FROM unnest(p.secondary_emails) y)
             UNION SELECT lower(mm.email) FROM public.members mm
              WHERE lower(b.guest_email) = ANY (SELECT lower(y) FROM unnest(mm.secondary_emails) y)
           )
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
             CROSS JOIN LATERAL (SELECT lower(a.email) IN (SELECT al.e FROM aliases al) AS hit) alt
             WHERE c.status IN ('open', 'active')
               AND a.status = ANY (v_allow)
               AND a.anonymized_at IS NULL
               -- só de ciclo em que quem pergunta pode vincular (contexto interno sem JWT vê tudo)
               AND (v_caller_id IS NULL OR v_is_manager
                    OR EXISTS (SELECT 1 FROM public.selection_committee sc2
                               WHERE sc2.cycle_id = a.cycle_id AND sc2.member_id = v_caller_id
                                 AND sc2.role IN ('lead', 'evaluator')))
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
  v_new_status   text;
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
  -- a fila não mostra endereço interno; o vínculo também não aceita (vale para quem chama a RPC direto)
  IF public._booking_guest_is_internal(v_attempt.guest_email) THEN
    RAISE EXCEPTION 'Booking guest is an internal address, not a candidate' USING ERRCODE = 'check_violation';
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
  IF EXISTS (SELECT 1 FROM public.selection_interviews si
             WHERE si.application_id = v_app.id AND si.status IN ('scheduled', 'rescheduled', 'completed')) THEN
    RAISE EXCEPTION 'Application already has an active interview' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.selection_interviews (application_id, interviewer_ids, scheduled_at, duration_minutes,
                                           status, calendar_event_id)
  VALUES (v_app.id, ARRAY[]::uuid[], v_attempt.last_scheduled_at, 30, 'scheduled', p_calendar_event_id)
  RETURNING id INTO v_interview_id;

  IF v_app.status IN ('submitted', 'in_review', 'interview_pending') THEN
    UPDATE public.selection_applications SET status = 'interview_scheduled', updated_at = now() WHERE id = v_app.id
    RETURNING status INTO v_new_status;
    -- o gatilho de entrada de etapa (#1613) pode devolver o status; vale o que pousou
    v_status_changed := v_new_status IS DISTINCT FROM v_app.status;
  END IF;

  UPDATE public.selection_booking_attempts
  SET resolved_at = now(), last_outcome = 'matched', outcome_changed_at = now()
  WHERE id = v_attempt.id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (v_caller, 'selection.booking_linked_manually', 'selection_interview', v_interview_id,
          jsonb_build_object('application_id', v_app.id, 'booking_attempt_id', v_attempt.id,
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
  -- nenhum endereço interno na fila, mesmo com ocultas e resolvidas
  SELECT count(*) INTO v_n
  FROM public.get_booking_exception_queue(true, true) q
  WHERE public._booking_guest_is_internal(q.guest_email);
  IF v_n <> 0 THEN RAISE EXCEPTION '#2671: % linha(s) com endereço interno na fila', v_n; END IF;

  -- reserva resolvida não carrega sugestão
  SELECT count(*) INTO v_n FROM public.get_booking_exception_queue(true, true) q
  WHERE q.resolved_at IS NOT NULL AND jsonb_array_length(q.suggestions) > 0;
  IF v_n <> 0 THEN RAISE EXCEPTION '#2671: % reserva(s) resolvida(s) com sugestão', v_n; END IF;

  -- acionável nunca é suprimida nem passada
  SELECT count(*) INTO v_n FROM public.get_booking_exception_queue(false, true) q
  WHERE q.actionable AND (q.suppressed OR q.is_past);
  IF v_n <> 0 THEN RAISE EXCEPTION '#2671: % acionável(is) suprimida(s) ou passada(s)', v_n; END IF;

  -- a visão padrão não traz oculta
  SELECT count(*) INTO v_n FROM public.get_booking_exception_queue(false, false) q WHERE q.hidden;
  IF v_n <> 0 THEN RAISE EXCEPTION '#2671: a visão padrão trouxe % oculta(s)', v_n; END IF;

  IF has_function_privilege('anon', 'public.link_booking_to_application(text, text, uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.get_booking_exception_queue(boolean, boolean)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public._booking_guest_is_internal(text)', 'EXECUTE') THEN
    RAISE EXCEPTION '#2671: anon executa uma das funções, ou authenticated executa o auxiliar';
  END IF;
END
$postcondition$;

NOTIFY pgrst, 'reload schema';
