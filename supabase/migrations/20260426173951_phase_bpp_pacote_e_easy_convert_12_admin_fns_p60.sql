-- Phase B'' Pacote E (p60) — 12 admin_* fns V3→V4 manage_platform
-- All currently SECDEF with V3 gate (members.is_superadmin OR
-- operational_role IN manager/deputy_manager OR co_gp designation),
-- except admin_run_retention_cleanup which uses tighter V3 (no co_gp).
--
-- Privilege expansion safety check (verified pre-apply):
--   V3 broad (11 fns): 2 members (Vitor, Fabricio — superadmin)
--   V3 tight (admin_run_retention_cleanup): 2 (same)
--   V4 manage_platform (engagement_kind_permissions volunteer × {co_gp,
--                       deputy_manager, manager} + is_superadmin override): 2 (same)
--   would_gain: [] / would_lose: []
--   ZERO expansion — clean conversion.
--
-- Hardening: search_path tightened from 'public, pg_temp' → '' (fully-
-- qualified references in body — confirmed pre-apply). Pacote D pattern.

-- ============================================================
-- 1. admin_ensure_communication_tribe
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_ensure_communication_tribe(text, integer, text, text);
CREATE OR REPLACE FUNCTION public.admin_ensure_communication_tribe(
  p_name text,
  p_quadrant integer,
  p_quadrant_name text,
  p_notes text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_tribe record;
  v_new_id integer;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'permission_denied: manage_platform required';
  END IF;

  SELECT *
  INTO v_tribe
  FROM public.tribes t
  WHERE lower(trim(t.name)) IN (
    'tribo comunicacao',
    'tribo comunicação',
    'time de comunicacao',
    'time de comunicação',
    'comunicacao',
    'comunicação'
  )
  ORDER BY t.updated_at DESC NULLS LAST
  LIMIT 1;

  IF v_tribe IS NULL THEN
    SELECT coalesce(max(id), 0) + 1 INTO v_new_id FROM public.tribes;

    INSERT INTO public.tribes (
      id, name, quadrant, quadrant_name, notes, is_active, updated_at, updated_by
    ) VALUES (
      v_new_id,
      trim(p_name),
      coalesce(p_quadrant, 2),
      trim(coalesce(p_quadrant_name, 'Quadrante 2')),
      nullif(trim(coalesce(p_notes, '')), ''),
      true,
      now(),
      v_caller_id
    )
    RETURNING * INTO v_tribe;
  ELSE
    UPDATE public.tribes
    SET is_active = true,
        quadrant = coalesce(p_quadrant, quadrant),
        quadrant_name = coalesce(nullif(trim(p_quadrant_name), ''), quadrant_name),
        updated_at = now(),
        updated_by = v_caller_id
    WHERE id = v_tribe.id
    RETURNING * INTO v_tribe;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'tribe_id', v_tribe.id,
    'tribe_name', v_tribe.name
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_ensure_communication_tribe(text, integer, text, text) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_ensure_communication_tribe(text, integer, text, text) IS
  'Phase B'' V4 conversion (p60 Pacote E): manage_platform gate via can_by_member. Was V3 (is_superadmin OR manager/deputy_manager OR designation co_gp). search_path hardened to ''''.';

-- ============================================================
-- 2. admin_finalize_ingestion_batch
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_finalize_ingestion_batch(uuid, text, jsonb);
CREATE OR REPLACE FUNCTION public.admin_finalize_ingestion_batch(
  p_batch_id uuid,
  p_status text,
  p_summary jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'permission_denied: manage_platform required';
  END IF;

  UPDATE public.ingestion_batches
  SET status = p_status,
      summary = coalesce(p_summary, '{}'::jsonb),
      finished_at = now()
  WHERE id = p_batch_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ingestion batch not found: %', p_batch_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'batch_id', p_batch_id,
    'status', p_status
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_finalize_ingestion_batch(uuid, text, jsonb) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_finalize_ingestion_batch(uuid, text, jsonb) IS
  'Phase B'' V4 conversion (p60 Pacote E): manage_platform gate via can_by_member. Was V3 (is_superadmin OR manager/deputy_manager OR designation co_gp). search_path hardened to ''''.';

-- ============================================================
-- 3. admin_link_board_to_legacy_tribe
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_link_board_to_legacy_tribe(bigint, uuid, text, numeric, text, jsonb);
CREATE OR REPLACE FUNCTION public.admin_link_board_to_legacy_tribe(
  p_legacy_tribe_id bigint,
  p_board_id uuid,
  p_relation_type text,
  p_confidence_score numeric,
  p_notes text,
  p_metadata jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'permission_denied: manage_platform required';
  END IF;

  IF p_relation_type NOT IN ('legacy_snapshot', 'continued_in_current', 'renumbered_continuity') THEN
    RAISE EXCEPTION 'Invalid relation type: %', p_relation_type;
  END IF;

  INSERT INTO public.legacy_tribe_board_links (
    legacy_tribe_id,
    board_id,
    relation_type,
    confidence_score,
    notes,
    metadata
  ) VALUES (
    p_legacy_tribe_id,
    p_board_id,
    p_relation_type,
    greatest(0, least(coalesce(p_confidence_score, 1.00), 1.00)),
    nullif(trim(coalesce(p_notes, '')), ''),
    coalesce(p_metadata, '{}'::jsonb)
  )
  ON CONFLICT (legacy_tribe_id, board_id, relation_type)
  DO UPDATE SET
    confidence_score = excluded.confidence_score,
    notes = excluded.notes,
    metadata = excluded.metadata;

  RETURN jsonb_build_object(
    'success', true,
    'legacy_tribe_id', p_legacy_tribe_id,
    'board_id', p_board_id,
    'relation_type', p_relation_type
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_link_board_to_legacy_tribe(bigint, uuid, text, numeric, text, jsonb) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_link_board_to_legacy_tribe(bigint, uuid, text, numeric, text, jsonb) IS
  'Phase B'' V4 conversion (p60 Pacote E): manage_platform gate via can_by_member. Was V3 (is_superadmin OR manager/deputy_manager OR designation co_gp). search_path hardened to ''''.';

-- ============================================================
-- 4. admin_link_member_to_legacy_tribe
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_link_member_to_legacy_tribe(bigint, uuid, text, text, text, text, numeric, jsonb);
CREATE OR REPLACE FUNCTION public.admin_link_member_to_legacy_tribe(
  p_legacy_tribe_id bigint,
  p_member_id uuid,
  p_cycle_code text,
  p_role_snapshot text,
  p_chapter_snapshot text,
  p_link_type text,
  p_confidence_score numeric,
  p_metadata jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'permission_denied: manage_platform required';
  END IF;

  IF p_link_type NOT IN ('historical_member', 'historical_leader', 'continued_member') THEN
    RAISE EXCEPTION 'Invalid link_type: %', p_link_type;
  END IF;

  IF coalesce(trim(p_cycle_code), '') = '' THEN
    RAISE EXCEPTION 'cycle_code is required';
  END IF;

  INSERT INTO public.legacy_member_links (
    legacy_tribe_id,
    member_id,
    cycle_code,
    role_snapshot,
    chapter_snapshot,
    link_type,
    confidence_score,
    metadata,
    created_by
  ) VALUES (
    p_legacy_tribe_id,
    p_member_id,
    trim(p_cycle_code),
    nullif(trim(coalesce(p_role_snapshot, '')), ''),
    nullif(trim(coalesce(p_chapter_snapshot, '')), ''),
    p_link_type,
    greatest(0, least(coalesce(p_confidence_score, 1.00), 1.00)),
    coalesce(p_metadata, '{}'::jsonb),
    v_caller_id
  )
  ON CONFLICT (legacy_tribe_id, member_id, cycle_code, link_type)
  DO UPDATE SET
    role_snapshot = excluded.role_snapshot,
    chapter_snapshot = excluded.chapter_snapshot,
    confidence_score = excluded.confidence_score,
    metadata = excluded.metadata;

  RETURN jsonb_build_object(
    'success', true,
    'legacy_tribe_id', p_legacy_tribe_id,
    'member_id', p_member_id,
    'cycle_code', trim(p_cycle_code),
    'link_type', p_link_type
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_link_member_to_legacy_tribe(bigint, uuid, text, text, text, text, numeric, jsonb) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_link_member_to_legacy_tribe(bigint, uuid, text, text, text, text, numeric, jsonb) IS
  'Phase B'' V4 conversion (p60 Pacote E): manage_platform gate via can_by_member. Was V3 (is_superadmin OR manager/deputy_manager OR designation co_gp). search_path hardened to ''''.';

-- ============================================================
-- 5. admin_map_notion_item_to_board
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_map_notion_item_to_board(bigint, uuid, text, integer, boolean);
CREATE OR REPLACE FUNCTION public.admin_map_notion_item_to_board(
  p_staging_id bigint,
  p_board_id uuid,
  p_status text,
  p_position integer,
  p_apply_insert boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_stage record;
  v_item_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'permission_denied: manage_platform required';
  END IF;

  IF p_status NOT IN ('backlog', 'todo', 'in_progress', 'review', 'done', 'archived') THEN
    RAISE EXCEPTION 'Invalid board status: %', p_status;
  END IF;

  SELECT * INTO v_stage
  FROM public.notion_import_staging
  WHERE id = p_staging_id;

  IF v_stage IS NULL THEN
    RAISE EXCEPTION 'Notion staging item not found: %', p_staging_id;
  END IF;

  IF p_apply_insert IS true THEN
    INSERT INTO public.board_items (
      board_id,
      title,
      description,
      status,
      tags,
      due_date,
      position,
      source_card_id,
      source_board,
      attachments,
      checklist
    ) VALUES (
      p_board_id,
      v_stage.title,
      v_stage.description,
      p_status,
      v_stage.tags,
      v_stage.due_date,
      coalesce(p_position, 0),
      v_stage.external_item_id,
      'notion',
      '[]'::jsonb,
      '[]'::jsonb
    )
    RETURNING id INTO v_item_id;
  END IF;

  UPDATE public.notion_import_staging
  SET mapped_board_id = p_board_id,
      mapped_item_id = coalesce(v_item_id, mapped_item_id),
      mapped_at = now()
  WHERE id = p_staging_id;

  RETURN jsonb_build_object(
    'success', true,
    'staging_id', p_staging_id,
    'board_id', p_board_id,
    'mapped_item_id', v_item_id
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_map_notion_item_to_board(bigint, uuid, text, integer, boolean) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_map_notion_item_to_board(bigint, uuid, text, integer, boolean) IS
  'Phase B'' V4 conversion (p60 Pacote E): manage_platform gate via can_by_member. Was V3 (is_superadmin OR manager/deputy_manager OR designation co_gp). search_path hardened to ''''.';

-- ============================================================
-- 6. admin_run_retention_cleanup
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_run_retention_cleanup();
CREATE OR REPLACE FUNCTION public.admin_run_retention_cleanup()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_policy record;
  v_affected int;
  v_results jsonb := '[]'::jsonb;
  v_cutoff_date date;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'permission_denied: manage_platform required';
  END IF;

  FOR v_policy IN SELECT * FROM public.data_retention_policy WHERE is_active = true LOOP
    v_cutoff_date := current_date - (v_policy.retention_days || ' days')::interval;
    v_affected := 0;

    IF v_policy.cleanup_type = 'delete' THEN
      IF v_policy.table_name = 'notifications' THEN
        DELETE FROM public.notifications
        WHERE created_at < v_cutoff_date AND read = true;
        GET DIAGNOSTICS v_affected = ROW_COUNT;
      ELSIF v_policy.table_name = 'data_anomaly_log' THEN
        DELETE FROM public.data_anomaly_log
        WHERE detected_at < v_cutoff_date AND status = 'resolved';
        GET DIAGNOSTICS v_affected = ROW_COUNT;
      END IF;

    ELSIF v_policy.cleanup_type = 'anonymize' THEN
      IF v_policy.table_name = 'selection_applications' THEN
        UPDATE public.selection_applications SET
          applicant_name = 'Candidato Anonimizado',
          email = 'anon_' || substr(id::text, 1, 8) || '@removed.local',
          phone = NULL,
          linkedin_url = NULL,
          resume_url = NULL,
          motivation_letter = NULL
        WHERE applied_at < v_cutoff_date
          AND applicant_name != 'Candidato Anonimizado';
        GET DIAGNOSTICS v_affected = ROW_COUNT;
      END IF;

    ELSIF v_policy.cleanup_type = 'archive' THEN
      v_affected := 0;
    END IF;

    v_results := v_results || jsonb_build_object(
      'table', v_policy.table_name,
      'type', v_policy.cleanup_type,
      'affected', v_affected,
      'cutoff', v_cutoff_date
    );
  END LOOP;

  RETURN jsonb_build_object('results', v_results, 'executed_by', v_caller_id, 'executed_at', now());
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_run_retention_cleanup() FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_run_retention_cleanup() IS
  'Phase B'' V4 conversion (p60 Pacote E): manage_platform gate via can_by_member. Was V3 (is_superadmin OR manager/deputy_manager — tighter, no co_gp). search_path hardened to ''''.';

-- ============================================================
-- 7. admin_set_ingestion_source_policy
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_set_ingestion_source_policy(text, boolean, boolean, text);
CREATE OR REPLACE FUNCTION public.admin_set_ingestion_source_policy(
  p_source text,
  p_allow_apply boolean,
  p_require_manual_review boolean,
  p_notes text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'permission_denied: manage_platform required';
  END IF;

  INSERT INTO public.ingestion_source_controls (
    source, allow_apply, require_manual_review, notes, updated_by, updated_at
  )
  VALUES (
    p_source, p_allow_apply, p_require_manual_review, nullif(trim(coalesce(p_notes, '')), ''), v_caller_id, now()
  )
  ON CONFLICT (source)
  DO UPDATE SET
    allow_apply = excluded.allow_apply,
    require_manual_review = excluded.require_manual_review,
    notes = excluded.notes,
    updated_by = v_caller_id,
    updated_at = now();

  RETURN jsonb_build_object(
    'success', true,
    'source', p_source,
    'allow_apply', p_allow_apply,
    'require_manual_review', p_require_manual_review
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_set_ingestion_source_policy(text, boolean, boolean, text) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_set_ingestion_source_policy(text, boolean, boolean, text) IS
  'Phase B'' V4 conversion (p60 Pacote E): manage_platform gate via can_by_member. Was V3 (is_superadmin OR manager/deputy_manager OR designation co_gp). search_path hardened to ''''.';

-- ============================================================
-- 8. admin_start_ingestion_batch
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_start_ingestion_batch(text, text, text);
CREATE OR REPLACE FUNCTION public.admin_start_ingestion_batch(
  p_source text,
  p_mode text,
  p_notes text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_batch_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'permission_denied: manage_platform required';
  END IF;

  INSERT INTO public.ingestion_batches (
    source, mode, status, initiated_by, notes
  ) VALUES (
    p_source,
    p_mode,
    'running',
    v_caller_id,
    nullif(trim(coalesce(p_notes, '')), '')
  )
  RETURNING id INTO v_batch_id;

  RETURN v_batch_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_start_ingestion_batch(text, text, text) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_start_ingestion_batch(text, text, text) IS
  'Phase B'' V4 conversion (p60 Pacote E): manage_platform gate via can_by_member. Was V3 (is_superadmin OR manager/deputy_manager OR designation co_gp). search_path hardened to ''''.';

-- ============================================================
-- 9. admin_upsert_legacy_tribe
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_upsert_legacy_tribe(bigint, text, integer, text, text, text, integer, text, text, text, jsonb);
CREATE OR REPLACE FUNCTION public.admin_upsert_legacy_tribe(
  p_id bigint,
  p_legacy_key text,
  p_tribe_id integer,
  p_cycle_code text,
  p_cycle_label text,
  p_display_name text,
  p_quadrant integer,
  p_chapter text,
  p_status text,
  p_notes text,
  p_metadata jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_id bigint;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'permission_denied: manage_platform required';
  END IF;

  IF coalesce(trim(p_legacy_key), '') = '' THEN
    RAISE EXCEPTION 'legacy_key is required';
  END IF;
  IF coalesce(trim(p_cycle_code), '') = '' THEN
    RAISE EXCEPTION 'cycle_code is required';
  END IF;
  IF coalesce(trim(p_display_name), '') = '' THEN
    RAISE EXCEPTION 'display_name is required';
  END IF;

  IF p_status NOT IN ('active', 'inactive', 'archived') THEN
    RAISE EXCEPTION 'Invalid status: %', p_status;
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.legacy_tribes (
      legacy_key, tribe_id, cycle_code, cycle_label, display_name, quadrant, chapter,
      status, notes, metadata, created_by, updated_by
    ) VALUES (
      trim(p_legacy_key), p_tribe_id, trim(p_cycle_code), nullif(trim(coalesce(p_cycle_label, '')), ''),
      trim(p_display_name), p_quadrant, nullif(trim(coalesce(p_chapter, '')), ''),
      p_status, nullif(trim(coalesce(p_notes, '')), ''), coalesce(p_metadata, '{}'::jsonb),
      v_caller_id, v_caller_id
    )
    ON CONFLICT (legacy_key)
    DO UPDATE SET
      tribe_id = excluded.tribe_id,
      cycle_code = excluded.cycle_code,
      cycle_label = excluded.cycle_label,
      display_name = excluded.display_name,
      quadrant = excluded.quadrant,
      chapter = excluded.chapter,
      status = excluded.status,
      notes = excluded.notes,
      metadata = excluded.metadata,
      updated_by = v_caller_id
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.legacy_tribes
    SET legacy_key = trim(p_legacy_key),
        tribe_id = p_tribe_id,
        cycle_code = trim(p_cycle_code),
        cycle_label = nullif(trim(coalesce(p_cycle_label, '')), ''),
        display_name = trim(p_display_name),
        quadrant = p_quadrant,
        chapter = nullif(trim(coalesce(p_chapter, '')), ''),
        status = p_status,
        notes = nullif(trim(coalesce(p_notes, '')), ''),
        metadata = coalesce(p_metadata, '{}'::jsonb),
        updated_by = v_caller_id
    WHERE id = p_id
    RETURNING id INTO v_id;
  END IF;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Legacy tribe upsert failed';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'legacy_tribe_id', v_id,
    'legacy_key', trim(p_legacy_key)
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_upsert_legacy_tribe(bigint, text, integer, text, text, text, integer, text, text, text, jsonb) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_upsert_legacy_tribe(bigint, text, integer, text, text, text, integer, text, text, text, jsonb) IS
  'Phase B'' V4 conversion (p60 Pacote E): manage_platform gate via can_by_member. Was V3 (is_superadmin OR manager/deputy_manager OR designation co_gp). search_path hardened to ''''.';

-- ============================================================
-- 10. admin_upsert_tribe
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_upsert_tribe(integer, text, integer, text, text, boolean, uuid, text, text, text, text);
CREATE OR REPLACE FUNCTION public.admin_upsert_tribe(
  p_id integer,
  p_name text,
  p_quadrant integer,
  p_quadrant_name text,
  p_notes text,
  p_is_active boolean,
  p_leader_member_id uuid,
  p_meeting_link text,
  p_whatsapp_url text,
  p_drive_url text,
  p_miro_url text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_id integer;
  v_exists boolean;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'permission_denied: manage_platform required';
  END IF;

  IF coalesce(trim(p_name), '') = '' THEN
    RAISE EXCEPTION 'Tribe name is required';
  END IF;

  IF p_quadrant IS NULL OR p_quadrant < 1 OR p_quadrant > 4 THEN
    RAISE EXCEPTION 'Quadrant must be between 1 and 4';
  END IF;

  IF coalesce(trim(p_quadrant_name), '') = '' THEN
    RAISE EXCEPTION 'Quadrant label is required';
  END IF;

  IF p_id IS NULL THEN
    SELECT coalesce(max(id), 0) + 1 INTO v_id FROM public.tribes;
    INSERT INTO public.tribes (
      id, name, quadrant, quadrant_name, notes, is_active, leader_member_id,
      meeting_link, whatsapp_url, drive_url, miro_url, updated_at, updated_by
    ) VALUES (
      v_id, trim(p_name), p_quadrant, trim(p_quadrant_name), nullif(trim(coalesce(p_notes, '')), ''),
      coalesce(p_is_active, true), p_leader_member_id,
      nullif(trim(coalesce(p_meeting_link, '')), ''),
      nullif(trim(coalesce(p_whatsapp_url, '')), ''),
      nullif(trim(coalesce(p_drive_url, '')), ''),
      nullif(trim(coalesce(p_miro_url, '')), ''),
      now(), v_caller_id
    );
  ELSE
    v_id := p_id;
    SELECT exists(SELECT 1 FROM public.tribes WHERE id = v_id) INTO v_exists;
    IF NOT v_exists THEN
      INSERT INTO public.tribes (
        id, name, quadrant, quadrant_name, notes, is_active, leader_member_id,
        meeting_link, whatsapp_url, drive_url, miro_url, updated_at, updated_by
      ) VALUES (
        v_id, trim(p_name), p_quadrant, trim(p_quadrant_name), nullif(trim(coalesce(p_notes, '')), ''),
        coalesce(p_is_active, true), p_leader_member_id,
        nullif(trim(coalesce(p_meeting_link, '')), ''),
        nullif(trim(coalesce(p_whatsapp_url, '')), ''),
        nullif(trim(coalesce(p_drive_url, '')), ''),
        nullif(trim(coalesce(p_miro_url, '')), ''),
        now(), v_caller_id
      );
    ELSE
      UPDATE public.tribes
      SET name = trim(p_name),
          quadrant = p_quadrant,
          quadrant_name = trim(p_quadrant_name),
          notes = nullif(trim(coalesce(p_notes, '')), ''),
          is_active = coalesce(p_is_active, true),
          leader_member_id = p_leader_member_id,
          meeting_link = nullif(trim(coalesce(p_meeting_link, '')), ''),
          whatsapp_url = nullif(trim(coalesce(p_whatsapp_url, '')), ''),
          drive_url = nullif(trim(coalesce(p_drive_url, '')), ''),
          miro_url = nullif(trim(coalesce(p_miro_url, '')), ''),
          updated_at = now(),
          updated_by = v_caller_id
      WHERE id = v_id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'tribe_id', v_id,
    'name', trim(p_name),
    'is_active', coalesce(p_is_active, true)
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_upsert_tribe(integer, text, integer, text, text, boolean, uuid, text, text, text, text) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_upsert_tribe(integer, text, integer, text, text, boolean, uuid, text, text, text, text) IS
  'Phase B'' V4 conversion (p60 Pacote E): manage_platform gate via can_by_member. Was V3 (is_superadmin OR manager/deputy_manager OR designation co_gp). search_path hardened to ''''.';

-- ============================================================
-- 11. admin_upsert_tribe_continuity_override
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_upsert_tribe_continuity_override(text, text, integer, text, integer, text, text, boolean, text, jsonb);
CREATE OR REPLACE FUNCTION public.admin_upsert_tribe_continuity_override(
  p_continuity_key text,
  p_legacy_cycle_code text,
  p_legacy_tribe_id integer,
  p_current_cycle_code text,
  p_current_tribe_id integer,
  p_leader_name text,
  p_continuity_type text,
  p_is_active boolean,
  p_notes text,
  p_metadata jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'permission_denied: manage_platform required';
  END IF;

  IF coalesce(trim(p_continuity_key), '') = '' THEN
    RAISE EXCEPTION 'continuity_key is required';
  END IF;
  IF coalesce(trim(p_legacy_cycle_code), '') = '' THEN
    RAISE EXCEPTION 'legacy_cycle_code is required';
  END IF;
  IF coalesce(trim(p_current_cycle_code), '') = '' THEN
    RAISE EXCEPTION 'current_cycle_code is required';
  END IF;
  IF p_continuity_type NOT IN ('renumbered_continuity', 'same_stream_new_id', 'same_stream_same_id') THEN
    RAISE EXCEPTION 'Invalid continuity_type: %', p_continuity_type;
  END IF;

  INSERT INTO public.tribe_continuity_overrides (
    continuity_key,
    legacy_cycle_code,
    legacy_tribe_id,
    current_cycle_code,
    current_tribe_id,
    leader_name,
    continuity_type,
    is_active,
    notes,
    metadata,
    updated_by
  ) VALUES (
    trim(p_continuity_key),
    trim(p_legacy_cycle_code),
    p_legacy_tribe_id,
    trim(p_current_cycle_code),
    p_current_tribe_id,
    nullif(trim(coalesce(p_leader_name, '')), ''),
    p_continuity_type,
    coalesce(p_is_active, true),
    nullif(trim(coalesce(p_notes, '')), ''),
    coalesce(p_metadata, '{}'::jsonb),
    v_caller_id
  )
  ON CONFLICT (continuity_key)
  DO UPDATE SET
    legacy_cycle_code = excluded.legacy_cycle_code,
    legacy_tribe_id = excluded.legacy_tribe_id,
    current_cycle_code = excluded.current_cycle_code,
    current_tribe_id = excluded.current_tribe_id,
    leader_name = excluded.leader_name,
    continuity_type = excluded.continuity_type,
    is_active = excluded.is_active,
    notes = excluded.notes,
    metadata = excluded.metadata,
    updated_by = v_caller_id;

  RETURN jsonb_build_object(
    'success', true,
    'continuity_key', trim(p_continuity_key),
    'continuity_type', p_continuity_type
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_upsert_tribe_continuity_override(text, text, integer, text, integer, text, text, boolean, text, jsonb) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_upsert_tribe_continuity_override(text, text, integer, text, integer, text, text, boolean, text, jsonb) IS
  'Phase B'' V4 conversion (p60 Pacote E): manage_platform gate via can_by_member. Was V3 (is_superadmin OR manager/deputy_manager OR designation co_gp). search_path hardened to ''''.';

-- ============================================================
-- 12. admin_upsert_tribe_lineage
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_upsert_tribe_lineage(bigint, integer, integer, text, text, text, jsonb, boolean);
CREATE OR REPLACE FUNCTION public.admin_upsert_tribe_lineage(
  p_id bigint,
  p_legacy_tribe_id integer,
  p_current_tribe_id integer,
  p_relation_type text,
  p_cycle_scope text,
  p_notes text,
  p_metadata jsonb,
  p_is_active boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_id bigint;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'permission_denied: manage_platform required';
  END IF;

  IF p_legacy_tribe_id IS NULL OR p_current_tribe_id IS NULL THEN
    RAISE EXCEPTION 'Legacy and current tribe IDs are required';
  END IF;

  IF p_relation_type NOT IN ('continues_as', 'renumbered_to', 'merged_into', 'split_from', 'legacy_of') THEN
    RAISE EXCEPTION 'Invalid relation type: %', p_relation_type;
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.tribe_lineage (
      legacy_tribe_id,
      current_tribe_id,
      relation_type,
      cycle_scope,
      notes,
      metadata,
      is_active,
      created_by,
      updated_by
    ) VALUES (
      p_legacy_tribe_id,
      p_current_tribe_id,
      p_relation_type,
      nullif(trim(coalesce(p_cycle_scope, '')), ''),
      nullif(trim(coalesce(p_notes, '')), ''),
      coalesce(p_metadata, '{}'::jsonb),
      coalesce(p_is_active, true),
      v_caller_id,
      v_caller_id
    )
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.tribe_lineage
    SET legacy_tribe_id = p_legacy_tribe_id,
        current_tribe_id = p_current_tribe_id,
        relation_type = p_relation_type,
        cycle_scope = nullif(trim(coalesce(p_cycle_scope, '')), ''),
        notes = nullif(trim(coalesce(p_notes, '')), ''),
        metadata = coalesce(p_metadata, '{}'::jsonb),
        is_active = coalesce(p_is_active, true),
        updated_by = v_caller_id
    WHERE id = p_id
    RETURNING id INTO v_id;

    IF v_id IS NULL THEN
      RAISE EXCEPTION 'Lineage entry not found: %', p_id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'id', v_id,
    'legacy_tribe_id', p_legacy_tribe_id,
    'current_tribe_id', p_current_tribe_id,
    'relation_type', p_relation_type,
    'is_active', coalesce(p_is_active, true)
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_upsert_tribe_lineage(bigint, integer, integer, text, text, text, jsonb, boolean) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_upsert_tribe_lineage(bigint, integer, integer, text, text, text, jsonb, boolean) IS
  'Phase B'' V4 conversion (p60 Pacote E): manage_platform gate via can_by_member. Was V3 (is_superadmin OR manager/deputy_manager OR designation co_gp). search_path hardened to ''''.';

NOTIFY pgrst, 'reload schema';
