-- Migration: #91 G7 surface — list_orphan_card_assignments RPC
-- Issue: p41 introduced detect_orphan_assignees_from_offboards() which emits
--        board_taxonomy_alerts rows, but there was no read RPC. Admin had to
--        query the table via SQL directly. This RPC enriches the payload with
--        board/member/status data for admin triage.
-- Gate: can_by_member(caller, 'manage_member') — same level as admin_offboard_member.
-- Rollback: DROP FUNCTION public.list_orphan_card_assignments(integer, text, integer);

CREATE OR REPLACE FUNCTION public.list_orphan_card_assignments(
  p_tribe_id integer DEFAULT NULL,
  p_chapter text DEFAULT NULL,
  p_limit integer DEFAULT 100
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_member permission');
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'alert_id', a.id,
    'board_id', a.board_id,
    'board_name', pb.board_name,
    'board_domain_key', pb.domain_key,
    'item_id', (a.payload->>'board_item_id')::uuid,
    'item_title', a.payload->>'item_title',
    'item_status', bi.status,
    'item_updated_at', bi.updated_at,
    'assignee_id', (a.payload->>'assignee_id')::uuid,
    'assignee_name', a.payload->>'assignee_name',
    'assignee_status', a.payload->>'assignee_status',
    'assignee_chapter', m.chapter,
    'assignee_tribe_id', m.tribe_id,
    'detected_at', a.created_at,
    'severity', a.severity
  ) ORDER BY a.created_at DESC), '[]'::jsonb) INTO v_result
  FROM public.board_taxonomy_alerts a
  LEFT JOIN public.project_boards pb ON pb.id = a.board_id
  LEFT JOIN public.board_items bi ON bi.id = (a.payload->>'board_item_id')::uuid
  LEFT JOIN public.members m ON m.id = (a.payload->>'assignee_id')::uuid
  WHERE a.alert_code = 'orphan_assignee_offboard'
    AND a.resolved_at IS NULL
    AND (p_tribe_id IS NULL OR m.tribe_id = p_tribe_id)
    AND (p_chapter IS NULL OR m.chapter = p_chapter)
  LIMIT p_limit;

  RETURN jsonb_build_object(
    'orphan_cards', v_result,
    'total_shown', jsonb_array_length(v_result),
    'filters', jsonb_build_object('tribe_id', p_tribe_id, 'chapter', p_chapter, 'limit', p_limit)
  );
END;
$function$;

COMMENT ON FUNCTION public.list_orphan_card_assignments(integer, text, integer) IS
  '#91 G7 surface — read-only view of unresolved orphan card alerts with board/member enrichment. Gate: manage_member.';

REVOKE ALL ON FUNCTION public.list_orphan_card_assignments(integer, text, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_orphan_card_assignments(integer, text, integer) TO authenticated, service_role;
