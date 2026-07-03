-- =====================================================================================
-- #105 — get_my_meetings: member self-service "minhas reuniões" list backing the personal
--        dashboard widget (workspace). Discoverability: a new member could not find where to
--        mark presence (handoff 2026-04-25, Item 6). Backs 3 client-side buckets:
--          - Próximas          → event_date >= today
--          - Recentes sem marcar → event_date in [today-7, today) AND attendance_present IS NULL
--          - Histórico         → event_date < today AND attendance_present = true
--
-- SCOPING: mirrors get_near_events exactly — caller's own tribe events (initiatives whose
--   legacy_tribe_id = my tribe) + general events (initiative_id IS NULL), with the #785
--   confidential-initiative gate (rls_can_see_initiative). Member-scoped via auth.uid()
--   (no caller-supplied id → no IDOR). Cancelled events excluded. Per-caller attendance
--   (present/excused) via LEFT JOIN on the (event_id, member_id) unique key (no fan-out).
--
-- The self-mark CTA on "Recentes sem marcar" reuses the existing register_own_presence (the same
--   RPC as the workspace check-in banner), so the widget HONOURS the canonical 48h self-check-in
--   window + audience gate — no new write RPC and no policy bypass.
--
-- GRANTS: authenticated only (member-facing); REVOKE public/anon.
-- =====================================================================================
CREATE OR REPLACE FUNCTION public.get_my_meetings(
  p_days_back integer DEFAULT 30,
  p_days_forward integer DEFAULT 60
)
RETURNS TABLE(
  event_id uuid,
  event_title text,
  event_date date,
  event_type text,
  duration_minutes integer,
  initiative_id uuid,
  initiative_title text,
  attendance_present boolean,
  excused boolean
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_member_id uuid;
  v_tribe_id integer;
BEGIN
  SELECT m.id, m.tribe_id INTO v_member_id, v_tribe_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  RETURN QUERY
  SELECT
    e.id,
    e.title,
    e.date,
    e.type,
    e.duration_minutes,
    e.initiative_id,
    i.title,
    a.present,
    a.excused
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  LEFT JOIN public.attendance a ON a.event_id = e.id AND a.member_id = v_member_id
  WHERE e.status <> 'cancelled'
    AND e.date BETWEEN (CURRENT_DATE - p_days_back) AND (CURRENT_DATE + p_days_forward)
    AND (e.initiative_id IS NULL OR i.legacy_tribe_id = v_tribe_id)
    AND public.rls_can_see_initiative(e.initiative_id)  -- #785 confidential gate
  ORDER BY e.date DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_my_meetings(integer, integer) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_my_meetings(integer, integer) TO authenticated;
