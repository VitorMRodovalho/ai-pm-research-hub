-- W-MCP-1: search_board_items RPC for MCP server
-- GC-132

CREATE OR REPLACE FUNCTION search_board_items(
  p_query text,
  p_tribe_id integer DEFAULT NULL
)
RETURNS SETOF json
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member_id uuid;
  v_tribe_id integer;
BEGIN
  SELECT id, tribe_id INTO v_member_id, v_tribe_id FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'auth_required'; END IF;

  -- Use caller's tribe if not specified
  IF p_tribe_id IS NULL THEN p_tribe_id := v_tribe_id; END IF;

  RETURN QUERY
  SELECT row_to_json(r)
  FROM (
    SELECT bi.id, bi.title, bi.description, bi.status, bi.tags, bi.due_date, bi.assignee_id
    FROM board_items bi
    JOIN project_boards pb ON pb.id = bi.board_id
    WHERE pb.tribe_id = p_tribe_id
      AND bi.status != 'archived'
      AND (bi.title ILIKE '%' || p_query || '%' OR bi.description ILIKE '%' || p_query || '%')
    ORDER BY bi.updated_at DESC
    LIMIT 20
  ) r;
END;
$$;

GRANT EXECUTE ON FUNCTION search_board_items TO authenticated;
