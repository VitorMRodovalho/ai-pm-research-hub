-- Fix: notifications with null actor_id now show 'Sistema' instead of null actor_name
-- Also used by MCP tool get_my_notifications

CREATE OR REPLACE FUNCTION public.get_my_notifications(p_limit integer DEFAULT 20, p_unread_only boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_member_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN '[]'::jsonb; END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(r)), '[]'::jsonb) INTO v_result
  FROM (
    SELECT n.id, n.type, n.title, n.body, n.link, n.source_type, n.source_id,
           n.actor_id, COALESCE(m.name, 'Sistema') AS actor_name, n.is_read, n.created_at
    FROM notifications n
    LEFT JOIN members m ON m.id = n.actor_id
    WHERE n.recipient_id = v_member_id
      AND (NOT p_unread_only OR n.is_read = false)
    ORDER BY n.created_at DESC
    LIMIT p_limit
  ) r;

  RETURN v_result;
END;
$function$;
