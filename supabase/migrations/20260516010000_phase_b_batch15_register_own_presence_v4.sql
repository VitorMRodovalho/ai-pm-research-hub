-- Phase B'' batch 15.1: register_own_presence V3 hardcoded bypass → V4 can_by_member('manage_event')
-- V3 bypass: is_superadmin OR operational_role IN ('manager', 'deputy_manager', 'tribe_leader')
-- V4 mapping: manage_event covers manager/deputy_manager/tribe_leader (= volunteer leader) + is_superadmin via can() short-circuit
-- Impact: V3=8 active members, V4=8 active members (clean match)
CREATE OR REPLACE FUNCTION public.register_own_presence(p_event_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_event_date date;
  v_event_ts timestamptz;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid();

  IF v_member_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  SELECT date INTO v_event_date FROM public.events WHERE id = p_event_id;
  IF v_event_date IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'event_not_found');
  END IF;

  v_event_ts := v_event_date::timestamptz;

  -- Time window check: V4 manage_event holders bypass (subsumes V3 sa/manager/deputy_manager/tribe_leader)
  IF NOT public.can_by_member(v_member_id, 'manage_event'::text) THEN
    -- 48h window (was 24h)
    IF now() > v_event_ts + interval '48 hours' THEN
      RETURN json_build_object('success', false, 'error', 'checkin_window_expired',
        'message', 'O prazo de 48h para check-in expirou. Solicite ao gestor.');
    END IF;
    IF now() < v_event_ts - interval '2 hours' THEN
      RETURN json_build_object('success', false, 'error', 'checkin_too_early',
        'message', 'O check-in abre 2h antes do evento.');
    END IF;
  END IF;

  INSERT INTO public.attendance (event_id, member_id, checked_in_at)
  VALUES (p_event_id, v_member_id, now())
  ON CONFLICT (event_id, member_id)
  DO UPDATE SET checked_in_at = now();

  RETURN json_build_object('success', true, 'member_id', v_member_id);
END;
$function$;
