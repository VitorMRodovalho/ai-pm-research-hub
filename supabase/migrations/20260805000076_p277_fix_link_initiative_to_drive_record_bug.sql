-- ════════════════════════════════════════════════════════════════
-- p277 triage (#420 sibling): repair live-broken link_initiative_to_drive RPC
-- ════════════════════════════════════════════════════════════════
-- BUG: the duplicate-check did `SELECT id INTO v_existing.id` where v_existing is an
-- UNASSIGNED `record` → plpgsql raises `record "v_existing" is not assigned yet` on EVERY
-- call, before the INSERT. The RPC was 100% dead (folders never linked; surfaced by the
-- nucleo-wiki session linking initiative 6e9af7a8). Reported via MCP link_initiative_to_drive.
-- FIX: use a scalar `v_existing_id uuid` instead of a record field. Same signature ⇒
-- CREATE OR REPLACE; search_path='' + SECURITY DEFINER + auth/authority gates preserved.
-- ROLLBACK: re-apply the prior body (record-based) — but that body is non-functional.
-- ════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.link_initiative_to_drive(p_initiative_id uuid, p_drive_folder_id text, p_drive_folder_url text, p_drive_folder_name text DEFAULT NULL::text, p_link_purpose text DEFAULT 'workspace'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_is_authorized boolean;
  v_existing_id uuid;
  v_new_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF p_link_purpose NOT IN ('workspace', 'minutes', 'archive', 'shared_resources') THEN
    RETURN jsonb_build_object('error', 'Invalid link_purpose. Use: workspace | minutes | archive | shared_resources');
  END IF;

  -- Authority: manage_member (admin) OR can(write, initiative, p_initiative_id) (leader scope)
  v_is_authorized := public.can_by_member(v_caller_id, 'manage_member')
    OR public.can(v_caller_id, 'write', 'initiative', p_initiative_id);

  IF NOT v_is_authorized THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_member or write on initiative');
  END IF;

  IF coalesce(trim(p_drive_folder_id), '') = '' OR coalesce(trim(p_drive_folder_url), '') = '' THEN
    RETURN jsonb_build_object('error', 'drive_folder_id and drive_folder_url required');
  END IF;

  SELECT id INTO v_existing_id FROM public.initiative_drive_links
  WHERE initiative_id = p_initiative_id AND drive_folder_id = p_drive_folder_id
    AND link_purpose = p_link_purpose AND unlinked_at IS NULL;
  IF v_existing_id IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'existing', true, 'link_id', v_existing_id);
  END IF;

  INSERT INTO public.initiative_drive_links (
    initiative_id, drive_folder_id, drive_folder_url, drive_folder_name, link_purpose, linked_by
  ) VALUES (
    p_initiative_id, p_drive_folder_id, p_drive_folder_url, p_drive_folder_name, p_link_purpose, v_caller_id
  )
  RETURNING id INTO v_new_id;

  RETURN jsonb_build_object(
    'success', true,
    'link_id', v_new_id,
    'initiative_id', p_initiative_id,
    'drive_folder_id', p_drive_folder_id,
    'link_purpose', p_link_purpose
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
