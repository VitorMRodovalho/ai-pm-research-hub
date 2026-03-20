-- GC-102: Org Chart RPC for admin governance page
-- Returns 3-dimension organizational structure

DROP FUNCTION IF EXISTS get_org_chart();
CREATE FUNCTION get_org_chart()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE v_caller record; v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  IF v_caller.is_superadmin IS NOT TRUE
    AND v_caller.operational_role NOT IN ('manager','sponsor','chapter_liaison','tribe_leader')
    AND NOT (v_caller.designations && ARRAY['deputy_manager','curator'])
  THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT jsonb_build_object(
    'superadmins', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('name', name, 'role', operational_role))
      FROM members WHERE is_superadmin = true AND is_active = true
    ), '[]'::jsonb),
    'tiers', jsonb_build_object(
      'tier1', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('name', name, 'role', operational_role, 'designations', designations))
        FROM members WHERE operational_role = 'manager' AND is_active = true
        OR (designations && ARRAY['deputy_manager'] AND is_active = true)
      ), '[]'::jsonb),
      'tier2', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('name', name, 'chapter', chapter, 'role', operational_role, 'has_account', auth_id IS NOT NULL))
        FROM members WHERE operational_role IN ('sponsor','chapter_liaison') AND current_cycle_active = true
      ), '[]'::jsonb),
      'tier3', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('name', name, 'tribe_id', tribe_id, 'tribe_name', (SELECT t.name FROM tribes t WHERE t.id = members.tribe_id)))
        FROM members WHERE operational_role = 'tribe_leader' AND is_active = true
      ), '[]'::jsonb),
      'tier5_count', (SELECT count(*) FROM members WHERE operational_role = 'researcher' AND current_cycle_active = true),
      'tier7_count', (SELECT count(*) FROM members WHERE operational_role = 'observer' AND is_active = true),
      'tier8_count', (SELECT count(*) FROM members WHERE operational_role = 'candidate')
    ),
    'designations', jsonb_build_object(
      'curators', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('name', name, 'is_active', is_active))
        FROM members WHERE 'curator' = ANY(designations)
      ), '[]'::jsonb),
      'comms', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('name', name))
        FROM members WHERE designations && ARRAY['comms_leader','comms_member'] AND is_active = true
      ), '[]'::jsonb),
      'ambassadors', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('name', name, 'chapter', chapter))
        FROM members WHERE 'ambassador' = ANY(designations) AND is_active = true
      ), '[]'::jsonb),
      'founders', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('name', name))
        FROM members WHERE 'founder' = ANY(designations)
      ), '[]'::jsonb)
    ),
    'stakeholder_auth_gap', (
      SELECT count(*) FROM members
      WHERE operational_role IN ('sponsor','chapter_liaison')
      AND auth_id IS NULL AND current_cycle_active = true
    ),
    'total_active', (SELECT count(*) FROM members WHERE current_cycle_active = true)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

NOTIFY pgrst, 'reload schema';
