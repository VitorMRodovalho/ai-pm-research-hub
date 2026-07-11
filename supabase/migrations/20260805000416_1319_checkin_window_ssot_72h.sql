-- #1319 — self check-in window as SSOT (platform_settings), default 72h (was hardcoded 48h).
-- The register_own_presence RPC is the server-side gate (enforcement); the frontend mirrors
-- read src/lib/attendance-window.ts, locked to this setting by a contract test.
-- Changing the window = UPDATE platform_settings + bump the FE constant (no other code edit).

INSERT INTO public.platform_settings (key, value, description)
VALUES (
  'attendance.self_checkin_window_hours',
  '72'::jsonb,
  'Hours after an event during which a member may self check-in via register_own_presence (manage_event holders bypass). Frontend mirror: src/lib/attendance-window.ts.'
)
ON CONFLICT (key) DO UPDATE
  SET value = EXCLUDED.value,
      description = EXCLUDED.description;

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
  v_event_ts           timestamptz;
  v_is_admin           boolean;
  v_has_rules          boolean;
  v_in_audience        boolean;
  v_window_hours       int;
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
$function$;
