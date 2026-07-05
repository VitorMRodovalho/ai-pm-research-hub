-- #1113: tribe/initiative roadmap read + authoring surface (fast-follow #1103 item 3).
-- The onboarding step `leader_roadmap` (mig 339) asks the leader to programme artefacts across the
-- 6/12/18-month horizons; this migration adds the read + write RPCs over
-- initiatives.metadata.roadmap = {"h6":[...], "h12":[...], "h18":[...]}.
--
-- Read mirrors get_initiative_stats: gated by rls_can_see_initiative() so a confidential
-- initiative's roadmap is only visible to engaged members + GP (ADR-0105). Non-confidential
-- roadmaps are readable by anon (the tribe page is partially public), same surface as the stats RPC.
--
-- Write is leader-scoped: can_by_member('write_board','initiative', id) — the same authority the
-- page uses to gate leader UI (isLeaderOfThisTribeV4 → canFor('write_board',{initiative})) — OR
-- platform admin. Verified live: a tribe_leader on their own initiative passes, a researcher fails.

-- ── read ────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_initiative_roadmap(p_initiative_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_roadmap jsonb;
  v_found   boolean;
BEGIN
  -- confidentiality gate (mirror get_initiative_stats)
  IF NOT public.rls_can_see_initiative(p_initiative_id) THEN
    RETURN jsonb_build_object('error', 'Initiative not found');
  END IF;

  SELECT COALESCE(metadata->'roadmap', '{}'::jsonb), true
    INTO v_roadmap, v_found
  FROM public.initiatives WHERE id = p_initiative_id;

  IF v_found IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'Initiative not found');
  END IF;

  -- normalise: always return the 3 horizons as arrays (graceful empty)
  RETURN jsonb_build_object(
    'initiative_id', p_initiative_id,
    'roadmap', jsonb_build_object(
      'h6',  COALESCE(v_roadmap->'h6',  '[]'::jsonb),
      'h12', COALESCE(v_roadmap->'h12', '[]'::jsonb),
      'h18', COALESCE(v_roadmap->'h18', '[]'::jsonb)
    )
  );
END;
$function$;

-- ── write (leader authoring) ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_initiative_roadmap(p_initiative_id uuid, p_roadmap jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_clean     jsonb;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- initiative-scoped leader authority OR platform admin
  IF NOT (
       public.can_by_member(v_member_id, 'write_board', 'initiative', p_initiative_id)
    OR public.can_by_member(v_member_id, 'manage_platform', NULL, NULL)
  ) THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board on this initiative';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.initiatives WHERE id = p_initiative_id) THEN
    RAISE EXCEPTION 'Initiative not found';
  END IF;

  -- validate shape: object with h6/h12/h18 arrays (missing horizon → empty array)
  IF p_roadmap IS NULL OR jsonb_typeof(p_roadmap) <> 'object' THEN
    RAISE EXCEPTION 'roadmap must be a JSON object with h6/h12/h18 arrays';
  END IF;

  v_clean := jsonb_build_object(
    'h6',  COALESCE(p_roadmap->'h6',  '[]'::jsonb),
    'h12', COALESCE(p_roadmap->'h12', '[]'::jsonb),
    'h18', COALESCE(p_roadmap->'h18', '[]'::jsonb)
  );

  IF jsonb_typeof(v_clean->'h6')  <> 'array'
     OR jsonb_typeof(v_clean->'h12') <> 'array'
     OR jsonb_typeof(v_clean->'h18') <> 'array' THEN
    RAISE EXCEPTION 'h6/h12/h18 must be JSON arrays';
  END IF;

  UPDATE public.initiatives
     SET metadata   = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{roadmap}', v_clean),
         updated_at = now()
   WHERE id = p_initiative_id;

  RETURN jsonb_build_object('success', true, 'initiative_id', p_initiative_id, 'roadmap', v_clean);
END;
$function$;

-- ── grants ───────────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.get_initiative_roadmap(uuid) FROM public;
REVOKE ALL ON FUNCTION public.set_initiative_roadmap(uuid, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.get_initiative_roadmap(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_initiative_roadmap(uuid, jsonb) TO authenticated;
