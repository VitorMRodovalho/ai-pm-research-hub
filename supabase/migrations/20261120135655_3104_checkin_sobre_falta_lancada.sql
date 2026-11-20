-- #3104: check-in sobre falta já lançada deixava de dizer "success" com a linha ainda falta.
--
-- register_own_presence fazia ON CONFLICT DO UPDATE SET checked_in_at = now() e devolvia success: com
-- uma linha present = false já gravada, present continuava false e as cinco telas que chamam a função
-- mostravam "Presença registrada". Agora, com linha existente:
--   - já presente: success, sem mudar nada além de preencher checked_in_at se estiver vazio;
--   - falta presumida do selo (notes = _roster_seal_marker(), sem justificativa): vira presença;
--   - outra falta ou justificativa: nada muda, e volta attendance_already_recorded com mensagem.
-- Os portões (cancelado, janela, audiência) ficam iguais e vêm antes. mark_member_present delega a
-- esta função no autoatendimento e devolve a recusa dela, então os dois caminhos passam a concordar.

CREATE OR REPLACE FUNCTION public.register_own_presence(p_event_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id          uuid;
  v_member_role        text;
  v_member_designations text[];
  v_member_tribe       int;
  v_member_active      boolean;
  v_event_date         date;
  v_event_status       text;
  v_event_ts           timestamptz;
  v_is_admin           boolean;
  v_has_rules          boolean;
  v_in_audience        boolean;
  v_window_hours       int;
  v_inserted           int;
  v_present            boolean;
  v_excused            boolean;
  v_notes              text;
BEGIN
  SELECT id, operational_role, designations, tribe_id, current_cycle_active
    INTO v_member_id, v_member_role, v_member_designations, v_member_tribe, v_member_active
  FROM public.members WHERE auth_id = auth.uid();

  IF v_member_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  SELECT date, status INTO v_event_date, v_event_status FROM public.events WHERE id = p_event_id;
  IF v_event_date IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'event_not_found');
  END IF;

  -- #3050: evento cancelado nao recebe check-in, de ninguem.
  IF v_event_status = 'cancelled' THEN
    RETURN json_build_object('success', false, 'error', 'event_cancelled',
      'message', 'Este encontro foi cancelado e nao recebe check-in.');
  END IF;

  v_event_ts := v_event_date::timestamptz;
  v_is_admin := public.can_by_member(v_member_id, 'manage_event'::text);

  -- Time window check: V4 manage_event holders bypass
  IF NOT v_is_admin THEN
    -- self-check-in window (SSOT: platform_settings 'attendance.self_checkin_window_hours', default 72h)
    v_window_hours := COALESCE(
      (public.get_platform_setting('attendance.self_checkin_window_hours') #>> '{}')::int, 72);
    IF now() > v_event_ts + make_interval(hours => v_window_hours) THEN
      RETURN json_build_object('success', false, 'error', 'checkin_window_expired',
        'message', 'O prazo de ' || v_window_hours || 'h para check-in expirou. Solicite ao gestor.');
    END IF;
    IF now() < v_event_ts - interval '2 hours' THEN
      RETURN json_build_object('success', false, 'error', 'checkin_too_early',
        'message', 'O check-in abre 2h antes do evento.');
    END IF;

    -- p276 fix: audience gate — eventos com regras só aceitam quem está na regra.
    SELECT EXISTS (
      SELECT 1 FROM public.event_audience_rules
      WHERE event_id = p_event_id AND attendance_type = 'mandatory'
    ) INTO v_has_rules;

    IF v_has_rules THEN
      SELECT EXISTS (
        SELECT 1 FROM public.event_audience_rules ar
        WHERE ar.event_id = p_event_id
          AND ar.attendance_type = 'mandatory'
          AND (
            (ar.target_type = 'role' AND (
              v_member_role = ar.target_value
              OR ar.target_value = ANY(COALESCE(v_member_designations, '{}'))
            ))
            OR (ar.target_type = 'tribe' AND v_member_tribe IS NOT NULL AND v_member_tribe::text = ar.target_value)
            OR (ar.target_type = 'all_active_operational'
                AND public._in_all_active_operational(v_member_id))
            OR (ar.target_type = 'specific_members' AND EXISTS (
              SELECT 1 FROM public.event_invited_members im
              WHERE im.event_id = p_event_id AND im.member_id = v_member_id
            ))
          )
      ) INTO v_in_audience;

      IF NOT v_in_audience THEN
        RETURN json_build_object('success', false, 'error', 'not_in_audience',
          'message', 'Voce nao esta na audiencia prevista para este evento. Solicite ao gestor para marcar presenca.');
      END IF;
    END IF;
  END IF;

  -- #3104: sem linha, a presença nasce aqui. Com linha, o que já está lançado decide.
  INSERT INTO public.attendance (event_id, member_id, checked_in_at, present, excused)
  VALUES (p_event_id, v_member_id, now(), true, false)
  ON CONFLICT (event_id, member_id) DO NOTHING;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted > 0 THEN
    RETURN json_build_object('success', true, 'member_id', v_member_id);
  END IF;

  SELECT a.present, COALESCE(a.excused, false), a.notes
    INTO v_present, v_excused, v_notes
  FROM public.attendance a
  WHERE a.event_id = p_event_id AND a.member_id = v_member_id
  FOR UPDATE;

  IF v_present THEN
    UPDATE public.attendance SET checked_in_at = COALESCE(checked_in_at, now())
    WHERE event_id = p_event_id AND member_id = v_member_id;
    RETURN json_build_object('success', true, 'member_id', v_member_id, 'already_present', true);
  END IF;

  -- Falta presumida pelo selo: o mesmo critério de unseal_event_attendance (carimbo do selo, sem
  -- presença e sem justificativa). O check-in dentro da janela é a evidência que o selo presumia ausente.
  IF NOT v_excused AND v_notes IS NOT DISTINCT FROM public._roster_seal_marker() THEN
    UPDATE public.attendance SET present = true, checked_in_at = now(), updated_at = now()
    WHERE event_id = p_event_id AND member_id = v_member_id;
    RETURN json_build_object('success', true, 'member_id', v_member_id, 'replaced', 'presumed_absence');
  END IF;

  -- Falta ou justificativa lançada por gente: o check-in não passa por cima, e a tela diz o que há.
  RETURN json_build_object('success', false, 'error', 'attendance_already_recorded',
    'recorded_as', CASE WHEN v_excused THEN 'excused' ELSE 'absent' END,
    'message', CASE WHEN v_excused
      THEN 'Este encontro ja esta registrado como falta justificada. Para mudar para presenca, fale com o gestor do encontro.'
      ELSE 'Este encontro ja esta registrado como falta. Se voce esteve presente, peca ao gestor do encontro para corrigir.' END);
END;
$function$;
