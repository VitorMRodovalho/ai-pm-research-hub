-- p277 — set_event_champions (focused write) + get_event_champion_suggestions force-derive
-- (gamification rule-wiring probe, Feature 2 — "champions da noite" capture UI backend).
--
-- WHAT:
--   1. set_event_champions(p_event_id, p_champion_ids[]) — a FOCUSED writer of
--      events.suggested_champion_ids (the "champions da noite" tags). Unlike meeting_close it does
--      NOT stamp minutes / close the meeting — setting champions ≠ closing. Gates manage_event OR
--      award_champion + same-org; validates <=10 ids, all members in the caller's org (mirrors
--      meeting_close); an empty/NULL list clears the tags. The actual award (award_champion) still
--      enforces presence + surface scope — this only curates the suggestion list.
--   2. get_event_champion_suggestions gains p_force_derive (DEFAULT false). When true, it skips the
--      manual-override branch and always derives the present-member pool — so the capture picker
--      can show the full pool even after a selection has been saved. The award modal keeps calling
--      it with 1 arg (override-first, unchanged behavior).
--
-- WHY: turns the verbal "champions da noite" recognition into events.suggested_champion_ids from a
--   meeting-detail UI, which then flows to the award modal (F3 override branch) → award_champion.
--
-- ROLLBACK: DROP set_event_champions; re-CREATE the 1-arg get_event_champion_suggestions (059 body).

-- ── 1. force-derive param on the suggestions reader ─────────────────────────
DROP FUNCTION IF EXISTS public.get_event_champion_suggestions(uuid);
CREATE OR REPLACE FUNCTION public.get_event_champion_suggestions(p_event_id uuid, p_force_derive boolean DEFAULT false)
 RETURNS TABLE(member_id uuid, member_name text, designation_summary text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_org uuid;
  v_event_org uuid;
  v_suggestions uuid[];
  v_cycle_start date;
BEGIN
  SELECT id, organization_id INTO v_caller_id, v_caller_org
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event')
     AND NOT public.can_by_member(v_caller_id, 'award_champion') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event or award_champion';
  END IF;

  SELECT e.suggested_champion_ids, e.organization_id INTO v_suggestions, v_event_org
  FROM public.events e WHERE e.id = p_event_id;

  IF v_event_org IS NULL THEN
    RAISE EXCEPTION 'event_not_found';
  END IF;
  IF v_event_org != v_caller_org THEN
    RAISE EXCEPTION 'event_not_in_caller_org';
  END IF;

  -- Manual override: a curator pre-set the champions-of-the-night → honor it (unless force-derive).
  IF NOT p_force_derive AND v_suggestions IS NOT NULL AND cardinality(v_suggestions) > 0 THEN
    RETURN QUERY
    SELECT
      m.id, m.name,
      CASE WHEN cardinality(m.designations) > 0
        THEN array_to_string(m.designations, ', ')
        ELSE COALESCE(m.operational_role, '—')
      END
    FROM public.members m
    WHERE m.id = ANY(v_suggestions)
      AND m.organization_id = v_caller_org
    ORDER BY m.name;
    RETURN;
  END IF;

  -- Derived: members PRESENT at the event, ranked by current-cycle contribution. Top 12, caller excluded.
  SELECT cycle_start INTO v_cycle_start FROM public.cycles WHERE is_current = true LIMIT 1;

  RETURN QUERY
  SELECT
    m.id, m.name,
    CASE WHEN cardinality(m.designations) > 0
      THEN array_to_string(m.designations, ', ')
      ELSE COALESCE(m.operational_role, '—')
    END
  FROM public.attendance a
  JOIN public.members m ON m.id = a.member_id
  LEFT JOIN LATERAL (
    SELECT COALESCE(SUM(gp.points), 0) AS cyc_pts
    FROM public.gamification_points gp
    WHERE gp.member_id = m.id
      AND gp.created_at >= COALESCE(v_cycle_start, DATE '2026-01-01')
  ) sig ON true
  WHERE a.event_id = p_event_id
    AND a.present = true
    AND m.organization_id = v_caller_org
    AND m.id <> v_caller_id
  ORDER BY sig.cyc_pts DESC, m.name
  LIMIT 12;
END;
$function$;

-- ── 2. focused writer for the champions-of-the-night tags ───────────────────
CREATE OR REPLACE FUNCTION public.set_event_champions(p_event_id uuid, p_champion_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_org uuid;
  v_event_org uuid;
  v_validated uuid[];
  v_invalid uuid[];
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id, organization_id INTO v_caller_id, v_caller_org
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event')
     AND NOT public.can_by_member(v_caller_id, 'award_champion') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event or award_champion';
  END IF;

  SELECT organization_id INTO v_event_org FROM public.events WHERE id = p_event_id;
  IF v_event_org IS NULL THEN RETURN jsonb_build_object('error', 'event_not_found'); END IF;
  IF v_event_org != v_caller_org THEN RETURN jsonb_build_object('error', 'event_not_in_caller_org'); END IF;

  -- empty / NULL → clear the tags
  IF p_champion_ids IS NULL OR cardinality(p_champion_ids) = 0 THEN
    UPDATE public.events SET suggested_champion_ids = NULL, updated_at = now() WHERE id = p_event_id;
    RETURN jsonb_build_object('success', true, 'count', 0, 'stored', NULL);
  END IF;

  IF cardinality(p_champion_ids) > 10 THEN
    RETURN jsonb_build_object('error', 'too_many', 'detail', 'max 10 champions per event');
  END IF;

  -- validate all ids are members of the caller's org (mirrors meeting_close)
  SELECT array_agg(DISTINCT s) INTO v_invalid
  FROM unnest(p_champion_ids) AS s
  WHERE NOT EXISTS (SELECT 1 FROM public.members m WHERE m.id = s AND m.organization_id = v_caller_org);
  IF v_invalid IS NOT NULL AND cardinality(v_invalid) > 0 THEN
    RETURN jsonb_build_object('error', 'invalid_members', 'detail', 'unknown or out-of-org member ids: ' || array_to_string(v_invalid, ', '));
  END IF;

  SELECT array_agg(DISTINCT s ORDER BY s) INTO v_validated FROM unnest(p_champion_ids) AS s;

  UPDATE public.events SET suggested_champion_ids = v_validated, updated_at = now() WHERE id = p_event_id;

  RETURN jsonb_build_object('success', true, 'count', cardinality(v_validated), 'stored', v_validated);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.set_event_champions(uuid, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_event_champions(uuid, uuid[]) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
