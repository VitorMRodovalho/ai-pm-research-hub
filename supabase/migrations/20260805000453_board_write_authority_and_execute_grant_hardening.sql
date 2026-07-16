-- Board/card write-path authority hardening + EXECUTE grant tightening.
--
-- Context: the board/card write RPCs accreted with the write authority enforced only
-- in the MCP EF layer (a resourceless canV4 check), while the SECURITY DEFINER RPC
-- bodies themselves carried no authority gate and (in several cases) a default/explicit
-- EXECUTE grant to PUBLIC/anon. Direct /rest/v1/rpc callers therefore bypassed the EF
-- gate entirely. This migration moves the authority + confidential (#785, ADR-0105)
-- carve-out into the RPC bodies (defense in depth, mirrors update_checklist_item) and
-- removes the unnecessary PUBLIC/anon EXECUTE surface (#965 REVOKE-FROM-PUBLIC-anon rule).
--
-- rls_can_see_item(item)  -> rls_can_see_board(board) -> rls_can_see_initiative(initiative)
-- is the canonical confidential-visibility predicate; used here as an AND condition on the
-- write path so it can only restrict, never grant (legitimate writers already see the card).

-- ── 1. delete_board_item — add caller resolution + #785 + write authority ─────────────
CREATE OR REPLACE FUNCTION public.delete_board_item(p_item_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_board_id uuid;
  v_old_status text;
  v_actor uuid;
  v_authorized boolean;
BEGIN
  SELECT board_id, status INTO v_board_id, v_old_status
  FROM board_items WHERE id = p_item_id;
  IF v_board_id IS NULL THEN RAISE EXCEPTION 'Card not found'; END IF;

  SELECT m.id INTO v_actor FROM members m WHERE m.auth_id = auth.uid() LIMIT 1;
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Unauthorized: authentication required'; END IF;

  IF NOT public.rls_can_see_item(p_item_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access this card';
  END IF;

  v_authorized := public.can_by_member(v_actor, 'write_board')
    OR EXISTS (SELECT 1 FROM board_items bi WHERE bi.id = p_item_id AND bi.assignee_id = v_actor)
    OR EXISTS (SELECT 1 FROM board_members bm WHERE bm.board_id = v_board_id AND bm.member_id = v_actor AND bm.board_role IN ('admin', 'editor'));
  IF NOT v_authorized THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission, card ownership, or board editor role';
  END IF;

  UPDATE board_items
  SET status = 'archived', updated_at = now()
  WHERE id = p_item_id;

  INSERT INTO board_lifecycle_events
    (board_id, item_id, action, previous_status, new_status, reason, actor_member_id)
  VALUES
    (v_board_id, p_item_id, 'archived', v_old_status, 'archived', p_reason, v_actor);
END;
$function$;

-- ── 2. duplicate_board_item — add caller resolution + #785 (source + target) + authority ─
CREATE OR REPLACE FUNCTION public.duplicate_board_item(p_item_id uuid, p_target_board_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_new_id uuid;
  v_board_id uuid;
  v_max_pos int;
  v_actor uuid;
  v_authorized boolean;
BEGIN
  SELECT coalesce(p_target_board_id, board_id) INTO v_board_id
  FROM board_items WHERE id = p_item_id;
  IF v_board_id IS NULL THEN RAISE EXCEPTION 'Source card not found'; END IF;

  SELECT m.id INTO v_actor FROM members m WHERE m.auth_id = auth.uid() LIMIT 1;
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Unauthorized: authentication required'; END IF;

  IF NOT public.rls_can_see_item(p_item_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access source card';
  END IF;
  IF NOT public.rls_can_see_board(v_board_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access target board';
  END IF;

  v_authorized := public.can_by_member(v_actor, 'write_board')
    OR EXISTS (SELECT 1 FROM board_members bm WHERE bm.board_id = v_board_id AND bm.member_id = v_actor AND bm.board_role IN ('admin', 'editor'));
  IF NOT v_authorized THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission or board editor role on the target board';
  END IF;

  SELECT coalesce(max(position), -1) + 1 INTO v_max_pos
  FROM board_items WHERE board_id = v_board_id AND status = 'backlog';

  INSERT INTO board_items (
    board_id, title, description, tags, labels, checklist, attachments, cycle, position, status
  )
  SELECT v_board_id, title || ' (cópia)', description, tags, labels, checklist, attachments, cycle, v_max_pos, 'backlog'
  FROM board_items WHERE id = p_item_id
  RETURNING id INTO v_new_id;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
  VALUES (v_board_id, v_new_id, 'created', 'Duplicado de ' || p_item_id::text, v_actor);

  RETURN v_new_id;
END;
$function$;

-- ── 3. create_mirror_card — add #785 (source + target) + write authority ──────────────
CREATE OR REPLACE FUNCTION public.create_mirror_card(p_source_item_id uuid, p_target_board_id uuid, p_target_status text DEFAULT 'backlog'::text, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_member_id uuid;
  v_source record;
  v_mirror_id uuid;
  v_max_pos integer;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = v_caller_id LIMIT 1;

  SELECT * INTO v_source FROM public.board_items WHERE id = p_source_item_id;
  IF v_source IS NULL THEN RAISE EXCEPTION 'Source card not found'; END IF;

  IF NOT public.rls_can_see_item(p_source_item_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access source card';
  END IF;
  IF NOT public.rls_can_see_board(p_target_board_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access target board';
  END IF;
  IF NOT (public.can_by_member(v_member_id, 'write_board')
          OR EXISTS (SELECT 1 FROM public.board_members bm WHERE bm.board_id = p_target_board_id AND bm.member_id = v_member_id AND bm.board_role IN ('admin', 'editor'))) THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission or board editor role on the target board';
  END IF;

  SELECT COALESCE(MAX(position), 0) + 1 INTO v_max_pos
  FROM public.board_items
  WHERE board_id = p_target_board_id AND status = p_target_status;

  INSERT INTO public.board_items (
    board_id, title, description, status, tags,
    mirror_source_id, is_mirror, position
  ) VALUES (
    p_target_board_id,
    v_source.title,
    COALESCE(p_notes, v_source.description),
    p_target_status,
    v_source.tags,
    p_source_item_id,
    true,
    v_max_pos
  )
  RETURNING id INTO v_mirror_id;

  UPDATE public.board_items
  SET mirror_target_id = v_mirror_id
  WHERE id = p_source_item_id;

  INSERT INTO public.board_lifecycle_events (item_id, board_id, action, new_status, reason, actor_member_id)
  VALUES
    (p_source_item_id, v_source.board_id, 'mirror_created', v_mirror_id::text,
     'Card espelho criado no board ' || p_target_board_id::text, v_member_id),
    (v_mirror_id, p_target_board_id, 'mirror_created', p_source_item_id::text,
     'Espelho do card: ' || v_source.title, v_member_id);

  RETURN v_mirror_id;
END;
$function$;

-- ── 4. update_card_forecast — add #785 + write authority ──────────────────────────────
CREATE OR REPLACE FUNCTION public.update_card_forecast(p_board_item_id uuid, p_new_forecast date, p_justification text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_member_id uuid;
  v_old_forecast date;
  v_board_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = v_caller_id LIMIT 1;

  SELECT forecast_date, board_id INTO v_old_forecast, v_board_id
  FROM public.board_items WHERE id = p_board_item_id;
  IF v_board_id IS NULL THEN RAISE EXCEPTION 'Card not found'; END IF;

  IF NOT public.rls_can_see_item(p_board_item_id) THEN
    RAISE EXCEPTION 'Unauthorized: cannot access this card';
  END IF;
  IF NOT (public.can_by_member(v_member_id, 'write_board')
          OR EXISTS (SELECT 1 FROM public.board_members bm WHERE bm.board_id = v_board_id AND bm.member_id = v_member_id AND bm.board_role IN ('admin', 'editor'))) THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission or board editor role';
  END IF;

  UPDATE public.board_items
  SET forecast_date = p_new_forecast
  WHERE id = p_board_item_id;

  INSERT INTO public.board_lifecycle_events (
    item_id, board_id, action, previous_status, new_status, reason, actor_member_id
  ) VALUES (
    p_board_item_id,
    v_board_id,
    'forecast_update',
    v_old_forecast::text,
    p_new_forecast::text,
    p_justification,
    v_member_id
  );
END;
$function$;

-- ── 5. register_card_drive_file — add #785 + write authority ──────────────────────────
CREATE OR REPLACE FUNCTION public.register_card_drive_file(p_board_item_id uuid, p_drive_file_id text, p_drive_file_url text, p_filename text, p_mime_type text DEFAULT NULL::text, p_size_bytes bigint DEFAULT NULL::bigint, p_uploaded_via text DEFAULT 'platform'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_new_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF NOT public.rls_can_see_item(p_board_item_id) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: cannot access this card');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'write_board')
     AND NOT EXISTS (SELECT 1 FROM public.board_items bi JOIN public.board_members bm ON bm.board_id = bi.board_id WHERE bi.id = p_board_item_id AND bm.member_id = v_caller_id AND bm.board_role IN ('admin', 'editor'))
     AND NOT EXISTS (SELECT 1 FROM public.board_items bi WHERE bi.id = p_board_item_id AND bi.assignee_id = v_caller_id) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires write_board permission, card ownership, or board editor role');
  END IF;

  IF p_uploaded_via NOT IN ('platform', 'drive_native_synced') THEN
    RETURN jsonb_build_object('error', 'Invalid uploaded_via — must be platform or drive_native_synced');
  END IF;

  INSERT INTO public.board_item_files (
    board_item_id, drive_file_id, drive_file_url, filename, mime_type,
    size_bytes, uploaded_by, uploaded_via
  ) VALUES (
    p_board_item_id, p_drive_file_id, p_drive_file_url, p_filename,
    p_mime_type, p_size_bytes, v_caller_id, p_uploaded_via
  )
  RETURNING id INTO v_new_id;

  RETURN jsonb_build_object(
    'success', true,
    'file_id', v_new_id,
    'drive_file_id', p_drive_file_id
  );
END;
$function$;

-- ── 6. EXECUTE grant tightening — remove unnecessary PUBLIC/anon surface (#965) ────────
-- Card write RPCs: authenticated (+ service_role for internal callers) is sufficient; the
-- bodies now enforce authority. Direct anon calls have no legitimate consumer.
REVOKE EXECUTE ON FUNCTION public.delete_board_item(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.duplicate_board_item(uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.create_mirror_card(uuid, uuid, text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.update_card_forecast(uuid, date, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.move_board_item(uuid, text, integer, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_archive_board_item(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_restore_board_item(uuid, text, text) FROM PUBLIC, anon;

-- Notification + initiative primitives: called internally by other SECURITY DEFINER RPCs
-- (which run as owner) and by authenticated web/MCP paths; no anon consumer.
REVOKE EXECUTE ON FUNCTION public.create_notification(uuid, text, text, uuid, text, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.create_notification(uuid, text, text, uuid, text, uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.create_notification(uuid, text, text, text, text, text, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.create_initiative(text, text, text, jsonb, uuid, text) FROM PUBLIC, anon;

-- Event/member self RPCs (already gated internally; drop the redundant anon surface).
REVOKE EXECUTE ON FUNCTION public.manage_action_items(uuid, jsonb) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.upsert_event_agenda(uuid, text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.member_self_update(text, text, text, text, boolean) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.dismiss_onboarding() FROM PUBLIC, anon;
