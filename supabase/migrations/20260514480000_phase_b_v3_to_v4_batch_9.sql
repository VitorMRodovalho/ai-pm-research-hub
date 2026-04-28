-- Phase B'' V3 → V4 batch 9: 2 functions converted.
-- Auth surface preserved exactly via existing helpers / V4 actions.

-- 1. admin_bulk_mark_attendance — delegate to _can_manage_event helper.
CREATE OR REPLACE FUNCTION public.admin_bulk_mark_attendance(
  p_event_id uuid,
  p_member_ids uuid[],
  p_present boolean
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_count int := 0;
  v_mid uuid;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  IF NOT public._can_manage_event(p_event_id) THEN
    RETURN json_build_object('success', false, 'error', 'permission_denied');
  END IF;

  IF p_present THEN
    FOREACH v_mid IN ARRAY p_member_ids LOOP
      INSERT INTO public.attendance (event_id, member_id, checked_in_at, marked_by)
      VALUES (p_event_id, v_mid, now(), v_caller_id)
      ON CONFLICT (event_id, member_id)
      DO UPDATE SET checked_in_at = now(), marked_by = v_caller_id;
      v_count := v_count + 1;
    END LOOP;
  ELSE
    FOREACH v_mid IN ARRAY p_member_ids LOOP
      DELETE FROM public.attendance WHERE event_id = p_event_id AND member_id = v_mid;
      v_count := v_count + 1;
    END LOOP;
  END IF;

  RETURN json_build_object('success', true, 'marked', v_count);
END;
$function$;

COMMENT ON FUNCTION public.admin_bulk_mark_attendance(uuid, uuid[], boolean) IS
'Phase B''V4: bulk attendance toggle for an event. Authority: _can_manage_event (org admin via can_by_member manage_event, or tribe-scoped leader/researcher own-tribe).';

-- 2. create_change_note — opener OR can_by_member(manage_platform).
CREATE OR REPLACE FUNCTION public.create_change_note(p_chain_id uuid, p_body text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_active boolean;
  v_chain record;
  v_comment_id uuid;
BEGIN
  SELECT m.id, m.is_active INTO v_caller_id, v_caller_active
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL OR v_caller_active = false THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  SELECT ac.id, ac.version_id, ac.opened_by INTO v_chain
  FROM public.approval_chains ac WHERE ac.id = p_chain_id;
  IF v_chain.id IS NULL THEN
    RETURN jsonb_build_object('error', 'chain_not_found');
  END IF;

  IF NOT (
    v_chain.opened_by = v_caller_id
    OR public.can_by_member(v_caller_id, 'manage_platform')
  ) THEN
    RETURN jsonb_build_object('error', 'not_authorized');
  END IF;

  IF length(COALESCE(p_body, '')) = 0 THEN
    RETURN jsonb_build_object('error', 'empty_body');
  END IF;

  INSERT INTO public.document_comments (document_version_id, author_id, body, visibility)
  VALUES (v_chain.version_id, v_caller_id, p_body, 'change_notes')
  RETURNING id INTO v_comment_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'change_note_created', 'document_comment', v_comment_id,
    jsonb_build_object('chain_id', p_chain_id, 'version_id', v_chain.version_id));

  RETURN jsonb_build_object('success', true, 'comment_id', v_comment_id);
END;
$function$;

COMMENT ON FUNCTION public.create_change_note(uuid, text) IS
'Phase B''V4: post a change_note comment on an approval chain. Authority: caller is chain.opened_by (submitter) OR can_by_member(manage_platform) (GP/admin). Audit-logged.';

NOTIFY pgrst, 'reload schema';
