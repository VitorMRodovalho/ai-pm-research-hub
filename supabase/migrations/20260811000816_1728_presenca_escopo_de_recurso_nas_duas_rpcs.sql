-- #1728 — mark_member_present e clear_member_attendance passam a gatear pelo RECURSO.
--
-- Ate aqui as duas usavam `can_by_member(caller,'manage_event')` SEM passar o evento. `public.can()`
-- tem o ramo `OR (p_resource_id IS NULL AND ae.legacy_tribe_id IS NOT NULL)`, entao uma chamada sem
-- recurso casa QUALQUER grant: quem lidera uma tribo passava no gate de um evento de outra.
-- Mesma classe que o #1383 fechou em `register_attendance_batch` (_manage_event_scope_ok) e em
-- `admin_bulk_mark_attendance` (_can_manage_event); estas duas ficaram de fora.
--
-- O predicado NAO e reescrito aqui: e o mesmo `_can_manage_event(p_event_id)` que o irmao
-- `admin_bulk_mark_attendance` ja usa (org/global + grant da iniciativa + tribo propria do
-- tribe_leader/researcher + criador do evento). Alinhar duas coortes copiando o predicado da
-- coorte-alvo, em vez de reescrever um equivalente.
--
-- O ramo de autoatendimento (`v_caller_id = p_member_id`) fica intacto: marcar a propria presenca
-- nunca dependeu de manage_event.
--
-- Regressao medida antes de aplicar (10/08/2026): 63 pares evento-ator em TODO o historico, 14
-- atores distintos — 57 passam no gate de hoje, os MESMOS 57 passam no gate novo, 0 regridem e 0
-- ganham acesso. Eventos org-wide ('geral'/'kickoff', sem initiative_id) preservam o comportamento
-- anterior por dentro de `_manage_event_scope_ok`.
--
-- Efeito colateral aceito: evento inexistente agora recusa por autorizacao (`_can_manage_event`
-- devolve false quando nao encontra) em vez de falhar adiante na FK. Recusar num recurso que nao
-- existe e a resposta correta.

CREATE OR REPLACE FUNCTION public.mark_member_present(p_event_id uuid, p_member_id uuid, p_present boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF v_caller_id = p_member_id THEN
    NULL;
  ELSIF NOT public._can_manage_event(p_event_id) THEN
    RAISE EXCEPTION 'Unauthorized: can only mark own presence or requires manage_event permission for this event';
  END IF;

  IF p_present THEN
    INSERT INTO public.attendance (event_id, member_id, present, excused)
    VALUES (p_event_id, p_member_id, true, false)
    ON CONFLICT (event_id, member_id) DO UPDATE SET
      present = true, excused = false, updated_at = now();
  ELSE
    -- #1660 (2026-08-09): p_present=false volta a GRAVAR a falta simples (era DELETE desde o
    -- p199-c). Desfazer o registro continua existindo, com nome proprio:
    -- clear_member_attendance(). A justificativa e limpada junto porque o front so chega aqui
    -- vindo de 'excused' depois de confirmar com o usuario que o motivo sera removido.
    INSERT INTO public.attendance (event_id, member_id, present, excused, excuse_reason)
    VALUES (p_event_id, p_member_id, false, false, NULL)
    ON CONFLICT (event_id, member_id) DO UPDATE SET
      present = false, excused = false, excuse_reason = NULL, updated_at = now();
  END IF;

  RETURN json_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.clear_member_attendance(p_event_id uuid, p_member_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_removed int;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF v_caller_id = p_member_id THEN
    NULL;
  ELSIF NOT public._can_manage_event(p_event_id) THEN
    RAISE EXCEPTION 'Unauthorized: can only clear own attendance or requires manage_event permission for this event';
  END IF;

  DELETE FROM public.attendance WHERE event_id = p_event_id AND member_id = p_member_id;
  GET DIAGNOSTICS v_removed = ROW_COUNT;

  RETURN json_build_object('success', true, 'cleared', v_removed);
END;
$function$;

COMMENT ON FUNCTION public.mark_member_present(uuid, uuid, boolean) IS
  '#1728: gate escopado ao evento (_can_manage_event), nao resourceless. Ramo de autoatendimento preservado.';
COMMENT ON FUNCTION public.clear_member_attendance(uuid, uuid) IS
  '#1728: gate escopado ao evento (_can_manage_event), nao resourceless. Apaga a linha, inclusive linha selada — por isso o escopo importa.';
