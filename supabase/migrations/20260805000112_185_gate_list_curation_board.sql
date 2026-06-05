-- =====================================================================
-- #185 (Item 2) — gate the ungated list_curation_board reader
-- =====================================================================
-- WHAT: add the standard V4 curation gate to list_curation_board(). It was
--   the ONLY curation SECURITY DEFINER reader with no auth gate — it ran
--   `RETURN QUERY SELECT ... FROM hub_resources` straight, returning all 330
--   hub_resources rows (incl. 83 unpublished) to ANY authenticated member,
--   bypassing the V4 contract that every sibling curation RPC enforces.
--   Wired live as the legacy fallback at CuratorshipBoardIsland.tsx (the same
--   super-kanban view get_curation_dashboard serves), so it gets the SAME gate:
--   curate_content OR write_board.
--
-- WHY: #245 fixed the 3 active-queue readers (mig 20260805000098) but left
--   list_curation_board as a deferred Item-2. PM decision 2026-06-05: keep the
--   broad curate_content OR write_board queue gate (no member loses access) and
--   close this leak. #185 Item-1 (tighten to curators-only) closed as by-design.
--
-- SCOPE LOCK: gate-only. The RETURN QUERY body (hub_resources projection,
--   p_status filter, ORDER BY, suggest_tags) is reproduced byte-equivalent;
--   only the auth gate is prepended. Signature unchanged (body-only CoR).
--
-- INVARIANTS: check_schema_invariants() unaffected (no invariant touches this fn).
--
-- ROLLBACK: CREATE OR REPLACE list_curation_board from its prior capture
--   (mig 20260311020000 family — ungated body) to remove the gate.
--
-- CROSS-REF: #185, #245, 20260805000098 (sibling gates), ADR-0007 (can() authority).
-- =====================================================================

CREATE OR REPLACE FUNCTION public.list_curation_board(p_status text DEFAULT NULL::text)
 RETURNS SETOF json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (public.can_by_member(v_member_id, 'curate_content')
          OR public.can_by_member(v_member_id, 'write_board')) THEN
    RAISE EXCEPTION 'Curatorship access required';
  END IF;

  RETURN QUERY
  SELECT row_to_json(r) FROM (
    SELECT hr.id, hr.title, hr.asset_type AS type, hr.url, hr.description,
      CASE WHEN hr.is_active THEN 'approved' ELSE 'pending' END AS status,
      i.legacy_tribe_id AS tribe_id, i.title AS tribe_name, m.name AS author_name,
      hr.tags, hr.created_at AS submitted_at,
      NULL::TIMESTAMPTZ AS reviewed_at, NULL::TEXT AS review_notes,
      'hub_resources'::TEXT AS _table,
      COALESCE(hr.source, 'manual') AS source,
      public.suggest_tags(hr.title, hr.asset_type, hr.cycle_code) AS suggested_tags
    FROM hub_resources hr
    LEFT JOIN initiatives i ON i.id = hr.initiative_id
    LEFT JOIN members m ON m.id = hr.author_id
    WHERE (p_status IS NULL
           OR (p_status = 'approved' AND hr.is_active = true)
           OR (p_status = 'pending' AND hr.is_active = false))
    ORDER BY hr.created_at DESC NULLS LAST
  ) r;
END;
$function$;

NOTIFY pgrst, 'reload schema';
