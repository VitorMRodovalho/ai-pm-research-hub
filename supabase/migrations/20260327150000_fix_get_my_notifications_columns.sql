-- Fix get_my_notifications: remove references to non-existent columns
-- actor_id and source_title do not exist in notifications table.
-- The live RPC was out of sync with the schema.

CREATE OR REPLACE FUNCTION get_my_notifications(
  p_limit int DEFAULT 20,
  p_unread_only boolean DEFAULT false
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_member_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN '[]'::jsonb; END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(r)), '[]'::jsonb) INTO v_result
  FROM (
    SELECT n.id, n.type, n.title, n.body, n.link, n.source_type, n.source_id, n.is_read, n.created_at
    FROM notifications n
    WHERE n.recipient_id = v_member_id
      AND (NOT p_unread_only OR n.is_read = false)
    ORDER BY n.created_at DESC
    LIMIT p_limit
  ) r;

  RETURN v_result;
END;
$$;
