-- ADR-0037: Phase B'' V3→V4 conversion — get_chapter_needs + get_org_chart
-- via Opção B reuse view_internal_analytics + manage_platform.
--
-- get_chapter_needs: 3-path ladder (manage_platform broad / view_internal_analytics own-chapter
--   / chapter_board engagement Path Y for board_member preservation).
-- get_org_chart: pure view_internal_analytics (drift loss precedent — 6 tribe_leaders + Sarah).
--
-- See docs/adr/ADR-0037-chapter-needs-and-org-chart-v4-conversion.md
-- Rollback: re-apply 20260404020000 (chapter_needs) + 20260320100012 (org_chart).

CREATE OR REPLACE FUNCTION public.get_chapter_needs(p_chapter text DEFAULT NULL)
RETURNS TABLE(
  id uuid,
  chapter text,
  category text,
  title text,
  description text,
  status text,
  admin_notes text,
  submitted_by_name text,
  created_at timestamp with time zone,
  updated_at timestamp with time zone
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_chapter text;
  v_caller_person_id uuid;
  v_chapter text;
BEGIN
  SELECT m.id, m.chapter, m.person_id
    INTO v_caller_id, v_caller_chapter, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid() LIMIT 1;

  IF v_caller_id IS NULL THEN RETURN; END IF;

  -- V4 ladder (replaces V3 designation-based gate, ADR-0037)
  IF public.can_by_member(v_caller_id, 'manage_platform') THEN
    -- Path A (broad): manager + co_gp + deputy_manager — free p_chapter
    v_chapter := COALESCE(p_chapter, v_caller_chapter);
  ELSIF public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    -- Path B (chapter): sponsor + chapter_liaison + chapter_board × liaison — own chapter
    v_chapter := v_caller_chapter;
  ELSIF EXISTS (
    SELECT 1 FROM public.auth_engagements ae
    WHERE ae.person_id = v_caller_person_id
      AND ae.kind = 'chapter_board'
      AND ae.status = 'active'
  ) THEN
    -- Path Y (chapter_board preservation): chapter_board × any role — own chapter
    v_chapter := v_caller_chapter;
  ELSE
    RETURN;
  END IF;

  RETURN QUERY
  SELECT cn.id, cn.chapter, cn.category, cn.title, cn.description,
         cn.status, cn.admin_notes, m.name,
         cn.created_at, cn.updated_at
  FROM public.chapter_needs cn
  JOIN public.members m ON m.id = cn.submitted_by
  WHERE (v_chapter IS NULL OR cn.chapter = v_chapter)
  ORDER BY cn.created_at DESC
  LIMIT 50;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_org_chart()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'authentication_required');
  END IF;

  -- V4 gate (replaces V3 operational_role + designation check, ADR-0037)
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT jsonb_build_object(
    'superadmins', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('name', name, 'role', operational_role))
      FROM public.members WHERE is_superadmin = true AND is_active = true
    ), '[]'::jsonb),
    'tiers', jsonb_build_object(
      'tier1', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('name', name, 'role', operational_role, 'designations', designations))
        FROM public.members WHERE operational_role = 'manager' AND is_active = true
        OR (designations && ARRAY['deputy_manager'] AND is_active = true)
      ), '[]'::jsonb),
      'tier2', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('name', name, 'chapter', chapter, 'role', operational_role, 'has_account', auth_id IS NOT NULL))
        FROM public.members WHERE operational_role IN ('sponsor','chapter_liaison') AND current_cycle_active = true
      ), '[]'::jsonb),
      'tier3', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('name', name, 'tribe_id', tribe_id, 'tribe_name', (SELECT t.name FROM public.tribes t WHERE t.id = members.tribe_id)))
        FROM public.members WHERE operational_role = 'tribe_leader' AND is_active = true
      ), '[]'::jsonb),
      'tier5_count', (SELECT count(*) FROM public.members WHERE operational_role = 'researcher' AND current_cycle_active = true),
      'tier7_count', (SELECT count(*) FROM public.members WHERE operational_role = 'observer' AND is_active = true),
      'tier8_count', (SELECT count(*) FROM public.members WHERE operational_role = 'candidate')
    ),
    'designations', jsonb_build_object(
      'curators', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('name', name, 'is_active', is_active))
        FROM public.members WHERE 'curator' = ANY(designations)
      ), '[]'::jsonb),
      'comms', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('name', name))
        FROM public.members WHERE designations && ARRAY['comms_leader','comms_member'] AND is_active = true
      ), '[]'::jsonb),
      'ambassadors', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('name', name, 'chapter', chapter))
        FROM public.members WHERE 'ambassador' = ANY(designations) AND is_active = true
      ), '[]'::jsonb),
      'founders', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('name', name))
        FROM public.members WHERE 'founder' = ANY(designations)
      ), '[]'::jsonb)
    ),
    'stakeholder_auth_gap', (
      SELECT count(*) FROM public.members
      WHERE operational_role IN ('sponsor','chapter_liaison')
      AND auth_id IS NULL AND current_cycle_active = true
    ),
    'total_active', (SELECT count(*) FROM public.members WHERE current_cycle_active = true)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

NOTIFY pgrst, 'reload schema';
