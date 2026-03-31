-- New RPCs for MCP tools 46-47

-- get_my_credly_status: returns badges, verification date, CPMAI status
CREATE OR REPLACE FUNCTION public.get_my_credly_status()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_member record;
BEGIN
  SELECT id, credly_url, credly_verified_at, credly_badges, cpmai_certified
  INTO v_member FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;

  RETURN jsonb_build_object(
    'credly_url', v_member.credly_url,
    'verified_at', v_member.credly_verified_at,
    'cpmai_certified', COALESCE(v_member.cpmai_certified, false),
    'badges', COALESCE(v_member.credly_badges, '[]'::jsonb),
    'badge_count', CASE WHEN v_member.credly_badges IS NOT NULL THEN jsonb_array_length(v_member.credly_badges) ELSE 0 END,
    'has_credly', v_member.credly_url IS NOT NULL AND v_member.credly_url != ''
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_credly_status() TO authenticated;

-- get_board_activities: returns recent board lifecycle events
CREATE OR REPLACE FUNCTION public.get_board_activities(
  p_board_id uuid DEFAULT NULL,
  p_limit int DEFAULT 20
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_member record;
  v_result jsonb;
BEGIN
  SELECT id, tribe_id, is_superadmin, operational_role
  INTO v_member FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(evt)::jsonb ORDER BY evt.created_at DESC), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      ble.id,
      ble.action,
      ble.previous_status,
      ble.new_status,
      ble.reason,
      ble.created_at,
      ble.review_round,
      bi.title as item_title,
      m.name as actor_name
    FROM board_lifecycle_events ble
    JOIN board_items bi ON bi.id = ble.item_id
    LEFT JOIN members m ON m.id = ble.actor_member_id
    WHERE (p_board_id IS NULL OR ble.board_id = p_board_id)
    ORDER BY ble.created_at DESC
    LIMIT p_limit
  ) evt;

  RETURN jsonb_build_object(
    'activities', v_result,
    'count', jsonb_array_length(v_result)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_board_activities(uuid, int) TO authenticated;
