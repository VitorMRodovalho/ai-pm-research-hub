-- Item 10 (handoff 2026-04-25): fix mark_member_excused + bulk_mark_excused +
-- mark_member_present anti-patterns + cleanup 2 remaining corrupted records +
-- add CHECK constraint preventing present=TRUE AND excused=TRUE.
--
-- Background:
-- - Sessão 25/Abr corrigiu 20/22 registros corrompidos via Ação E
-- - 2 ambíguos restaram (Cíntia 05/03 + Fabricia 02/04). PM decidiu Hipótese A:
--   registros criados nos próprios dias dos eventos = present prevalece;
--   excused tardio (gap >22 dias) é signal de erro. Fix: excused=false.
-- - Funções continuam buggy → próxima chamada cria mais corrompidos
-- - Sem CHECK constraint, nada previne reincidência

UPDATE public.attendance
SET excused = false, excuse_reason = NULL, updated_at = now()
WHERE present = true AND excused = true;

DROP FUNCTION IF EXISTS public.mark_member_excused(uuid, uuid, boolean, text);
CREATE FUNCTION public.mark_member_excused(
  p_event_id uuid,
  p_member_id uuid,
  p_excused boolean DEFAULT true,
  p_reason text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid; v_caller_role text; v_is_admin boolean; v_caller_tribe int;
BEGIN
  SELECT id, operational_role, is_superadmin, tribe_id
  INTO v_caller_id, v_caller_role, v_is_admin, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF v_is_admin = true OR v_caller_role IN ('manager', 'deputy_manager') THEN NULL;
  ELSIF v_caller_role = 'tribe_leader' THEN
    IF NOT EXISTS (
      SELECT 1 FROM members m WHERE m.id = p_member_id AND m.tribe_id = v_caller_tribe
    ) THEN
      RAISE EXCEPTION 'Tribe leaders can only mark excused for their own tribe members';
    END IF;
  ELSE
    RAISE EXCEPTION 'Unauthorized: requires admin, manager, or tribe leader role';
  END IF;

  IF p_excused THEN
    INSERT INTO public.attendance (event_id, member_id, present, excused, excuse_reason)
    VALUES (p_event_id, p_member_id, false, true, p_reason)
    ON CONFLICT (event_id, member_id) DO UPDATE SET
      present = false,
      excused = true,
      excuse_reason = p_reason,
      updated_at = now();
  ELSE
    UPDATE public.attendance SET excused = false, excuse_reason = NULL, updated_at = now()
    WHERE event_id = p_event_id AND member_id = p_member_id;
  END IF;

  RETURN json_build_object('success', true, 'excused', p_excused);
END;
$function$;

DROP FUNCTION IF EXISTS public.bulk_mark_excused(uuid, date, date, text);
CREATE FUNCTION public.bulk_mark_excused(
  p_member_id uuid,
  p_date_from date,
  p_date_to date,
  p_reason text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid; v_caller_role text; v_is_admin boolean; v_caller_tribe int;
  v_member_tribe int;
  v_count int := 0;
BEGIN
  SELECT id, operational_role, is_superadmin, tribe_id
  INTO v_caller_id, v_caller_role, v_is_admin, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT tribe_id INTO v_member_tribe FROM public.members WHERE id = p_member_id;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event permission';
  END IF;
  IF v_caller_role = 'tribe_leader' AND v_caller_tribe IS DISTINCT FROM v_member_tribe THEN
    RAISE EXCEPTION 'Unauthorized: tribe_leader can only manage members of own tribe';
  END IF;

  INSERT INTO public.attendance (event_id, member_id, present, excused, excuse_reason)
  SELECT e.id, p_member_id, false, true, p_reason
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.date >= p_date_from AND e.date <= p_date_to
    AND e.type IN ('geral', 'tribo', 'lideranca', 'kickoff', 'comms')
    AND (
      e.type IN ('geral', 'kickoff')
      OR (e.type = 'tribo' AND i.legacy_tribe_id = v_member_tribe)
      OR (e.type = 'lideranca' AND EXISTS (SELECT 1 FROM members m WHERE m.id = p_member_id AND m.operational_role IN ('manager', 'deputy_manager', 'tribe_leader')))
    )
    AND NOT EXISTS (SELECT 1 FROM attendance a WHERE a.event_id = e.id AND a.member_id = p_member_id AND a.excused = false)
  ON CONFLICT (event_id, member_id) DO UPDATE SET
    present = false,
    excused = true,
    excuse_reason = p_reason,
    updated_at = now();

  GET DIAGNOSTICS v_count = ROW_COUNT;

  RETURN json_build_object('success', true, 'events_marked', v_count, 'date_from', p_date_from, 'date_to', p_date_to);
END;
$function$;

DROP FUNCTION IF EXISTS public.mark_member_present(uuid, uuid, boolean);
CREATE FUNCTION public.mark_member_present(
  p_event_id uuid,
  p_member_id uuid,
  p_present boolean
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid; v_caller_role text; v_is_admin boolean; v_caller_tribe int;
BEGIN
  SELECT id, operational_role, is_superadmin, tribe_id
  INTO v_caller_id, v_caller_role, v_is_admin, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF v_caller_id = p_member_id THEN NULL;
  ELSIF v_is_admin = true OR v_caller_role IN ('manager', 'deputy_manager') THEN NULL;
  ELSIF v_caller_role = 'tribe_leader' THEN
    IF NOT EXISTS (
      SELECT 1 FROM members m WHERE m.id = p_member_id AND m.tribe_id = v_caller_tribe
    ) THEN
      RAISE EXCEPTION 'Tribe leaders can only mark attendance for their own tribe members';
    END IF;
  ELSE
    RAISE EXCEPTION 'Unauthorized: can only mark own presence or requires admin/leader role';
  END IF;

  IF p_present THEN
    INSERT INTO public.attendance (event_id, member_id, present, excused)
    VALUES (p_event_id, p_member_id, true, false)
    ON CONFLICT (event_id, member_id) DO UPDATE SET
      present = true, excused = false, updated_at = now();
  ELSE
    INSERT INTO public.attendance (event_id, member_id, present, excused)
    VALUES (p_event_id, p_member_id, false, false)
    ON CONFLICT (event_id, member_id) DO UPDATE SET
      present = false, updated_at = now();
  END IF;
  RETURN json_build_object('success', true);
END;
$function$;

ALTER TABLE public.attendance
  ADD CONSTRAINT attendance_present_excused_exclusive
  CHECK (NOT (present = true AND excused = true));

NOTIFY pgrst, 'reload schema';
