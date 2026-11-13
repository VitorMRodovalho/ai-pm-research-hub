-- #3052 (ajuste): no autoatendimento de presenca, so quem tem a capacidade manage_event escopada
-- ao evento (_manage_event_scope_ok) escapa da regra do check-in proprio. O Path Y de
-- _can_manage_event (todo pesquisador gere os eventos da propria tribo, #3054) deixava o caso mais
-- comum, o pesquisador marcando a si mesmo na propria tribo, sem janela, audiencia nem status.
-- Marcar OUTRA pessoa segue pelo _can_manage_event, sem mudanca.
CREATE OR REPLACE FUNCTION public.mark_member_present(p_event_id uuid, p_member_id uuid, p_present boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_gate      json;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF v_caller_id = p_member_id THEN
    -- #3052: autoatendimento de presenca segue a regra do check-in proprio. So a capacidade
    -- escopada escapa dela: o Path Y de _can_manage_event (pesquisador na propria tribo) nao.
    IF p_present AND NOT public._manage_event_scope_ok(v_caller_id, p_event_id) THEN
      v_gate := public.register_own_presence(p_event_id);
      IF NOT COALESCE((v_gate ->> 'success')::boolean, false) THEN
        RETURN v_gate;
      END IF;
    END IF;
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
