-- p276 — Fix #2: gate em register_own_presence baseado em event_audience_rules
--
-- WHAT: Add an audience-rules gate to public.register_own_presence so that
--       self-checkin only succeeds for callers whose member_id matches at
--       least one mandatory rule in event_audience_rules for the event.
--       Falls back open (legacy behaviour) when the event has zero rules.
--       Admins with V4 'manage_event' bypass the gate (and the existing
--       time-window check). Signature unchanged: p_event_id uuid → json.
--
-- WHY:  Pre-fix register_own_presence only checked the -2h / +48h time
--       window. Any authenticated member could mark attendance on any event
--       inside that window, even if the event was visibility='leadership'
--       and the member was a researcher / observer / guest. This bypassed
--       the audience-rules data the trigger _auto_audience_rule_on_meeting_tag
--       was already inserting and contradicted the meeting's stated audience.
--
-- HOW:  Supported target_type values mirror event_audience_rules schema:
--         role                       — caller.operational_role = target_value,
--                                      OR target_value present in caller.designations
--                                      (handles deputy_manager / co_gp which are
--                                      designations, not operational_role values)
--         tribe                      — caller.tribe_id::text = target_value
--         all_active_operational     — caller.current_cycle_active AND role <> 'guest'
--         specific_members           — caller exists in event_invited_members
--       Gate evaluation: EXISTS check across the rules array. Empty rules
--       set → bypass entirely (preserves prior behaviour for legacy events).
--       SECDEF + search_path=public, pg_temp preserved. NOTIFY pgrst.
--
-- ROLLBACK: re-run CREATE OR REPLACE with the prior body that contained
--       only the time-window check before the INSERT/ON CONFLICT block
--       (no v_has_rules / v_in_audience / EXISTS evaluation).

CREATE OR REPLACE FUNCTION public.register_own_presence(p_event_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_member_id          uuid;
  v_member_role        text;
  v_member_designations text[];
  v_member_tribe       int;
  v_member_active      boolean;
  v_event_date         date;
  v_event_ts           timestamptz;
  v_is_admin           boolean;
  v_has_rules          boolean;
  v_in_audience        boolean;
BEGIN
  SELECT id, operational_role, designations, tribe_id, current_cycle_active
    INTO v_member_id, v_member_role, v_member_designations, v_member_tribe, v_member_active
  FROM public.members WHERE auth_id = auth.uid();

  IF v_member_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  SELECT date INTO v_event_date FROM public.events WHERE id = p_event_id;
  IF v_event_date IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'event_not_found');
  END IF;

  v_event_ts := v_event_date::timestamptz;
  v_is_admin := public.can_by_member(v_member_id, 'manage_event'::text);

  -- Time window check: V4 manage_event holders bypass
  IF NOT v_is_admin THEN
    -- 48h window (was 24h)
    IF now() > v_event_ts + interval '48 hours' THEN
      RETURN json_build_object('success', false, 'error', 'checkin_window_expired',
        'message', 'O prazo de 48h para check-in expirou. Solicite ao gestor.');
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
                AND COALESCE(v_member_active, false) = true
                AND v_member_role <> 'guest')
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

  INSERT INTO public.attendance (event_id, member_id, checked_in_at)
  VALUES (p_event_id, v_member_id, now())
  ON CONFLICT (event_id, member_id)
  DO UPDATE SET checked_in_at = now();

  RETURN json_build_object('success', true, 'member_id', v_member_id);
END;
$$;

NOTIFY pgrst, 'reload schema';
