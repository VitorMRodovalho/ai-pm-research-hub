-- #785 part 2 — content readers MISSED by part 1 (caught by the
-- _audit_secdef_initiative_reader_gates recurrence guard):
--   get_board_members (board roster — was one of the original named leak readers),
--   list_card_partners (a card's partner links),
--   get_curation_queue_state (leaked confidential items into the curator queue),
--   list_webinars_v2 + get_publication_submission_detail (initiative-linked content).
-- Bodies are verbatim + the gate; behavior-neutral except the confidential initiative.

-- get_board_members(p_board_id uuid)
CREATE OR REPLACE FUNCTION public.get_board_members(p_board_id uuid)
 RETURNS TABLE(id uuid, name text, photo_url text, operational_role text, board_role text, designations text[], can_curate boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_board record;
  v_board_legacy_tribe_id int;
BEGIN
  SELECT pb.* INTO v_board FROM project_boards pb WHERE pb.id = p_board_id;
  IF NOT FOUND THEN RETURN; END IF;

  -- #785: confidential initiative visibility gate
  IF NOT public.rls_can_see_board(p_board_id) THEN RETURN; END IF;

  SELECT i.legacy_tribe_id INTO v_board_legacy_tribe_id
  FROM public.initiatives i WHERE i.id = v_board.initiative_id;

  RETURN QUERY
  SELECT DISTINCT ON (q.id)
    q.id, q.name, q.photo_url, q.operational_role, q.board_role, q.designations,
    public.can_by_member(q.id, 'curate_content') AS can_curate
  FROM (
    -- Priority 1: tribe members (legacy tribe_id match — applies to research_tribe boards)
    SELECT m.id, m.name, m.photo_url, m.operational_role, 'tribe_member'::text as board_role, m.designations, 1 as priority
    FROM members m
    WHERE v_board_legacy_tribe_id IS NOT NULL
      AND m.tribe_id = v_board_legacy_tribe_id
      AND m.is_active = true
      AND m.member_status = 'active'
    UNION ALL
    -- Priority 2: explicitly added to board_members
    SELECT bm.member_id, m.name, m.photo_url, m.operational_role, bm.board_role, m.designations, 2
    FROM board_members bm
    JOIN members m ON m.id = bm.member_id
    WHERE bm.board_id = p_board_id
      AND m.is_active = true
    UNION ALL
    -- Priority 3: all curators
    SELECT m.id, m.name, m.photo_url, m.operational_role, 'curator'::text, m.designations, 3
    FROM members m
    WHERE 'curator' = ANY(m.designations)
      AND m.is_active = true
    UNION ALL
    -- Priority 4: GP / superadmin
    -- p180 ADR-0011 V4: replaced operational_role IN ('manager','deputy_manager')
    -- with can_by_member(manage_platform) → covers volunteer × {co_gp, deputy_manager,
    -- manager}. Co_gp now visible as 'gp' priority (was already visible via
    -- priority-5 engagement_member if initiative engagement exists).
    SELECT m.id, m.name, m.photo_url, m.operational_role, 'gp'::text, m.designations, 4
    FROM members m
    WHERE m.is_active = true
      AND (m.is_superadmin = true OR public.can_by_member(m.id, 'manage_platform'))
    UNION ALL
    -- Priority 5: NEW — members with active engagement on the board's initiative
    -- Closes Mayanna Item 02: workgroup/committee/study_group members were
    -- invisible because legacy_tribe_id NULL skipped priority 1.
    SELECT m.id, m.name, m.photo_url, m.operational_role, 'engagement_member'::text, m.designations, 5
    FROM members m
    JOIN persons p ON p.id = m.person_id
    JOIN engagements e ON e.person_id = p.id
    WHERE e.initiative_id = v_board.initiative_id
      AND e.status = 'active'
      AND m.is_active = true
      AND m.member_status = 'active'
  ) q
  ORDER BY q.id, q.priority;
END;
$function$;

-- list_card_partners(p_board_item_id uuid)
CREATE OR REPLACE FUNCTION public.list_card_partners(p_board_item_id uuid)
 RETURNS TABLE(link_id uuid, link_role text, link_notes text, linked_at timestamp with time zone, linked_by_name text, partner_entity_id uuid, partner_name text, partner_entity_type text, partner_chapter text, partner_status text, partner_contact_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT m.id INTO v_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_member_id IS NULL THEN RETURN; END IF;

  -- #785: confidential initiative visibility gate (item->board->initiative)
  IF NOT public.rls_can_see_item(p_board_item_id) THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    pc.id, pc.link_role, pc.notes, pc.created_at, cm.name,
    pe.id, pe.name, pe.entity_type, pe.chapter, pe.status, pe.contact_name
  FROM public.partner_cards pc
  JOIN public.partner_entities pe ON pe.id = pc.partner_entity_id
  LEFT JOIN public.members cm ON cm.id = pc.created_by
  WHERE pc.board_item_id = p_board_item_id
  ORDER BY pc.created_at DESC;
END;
$function$;

-- list_webinars_v2(p_status text, p_chapter text, p_tribe_id integer)
CREATE OR REPLACE FUNCTION public.list_webinars_v2(p_status text DEFAULT NULL::text, p_chapter text DEFAULT NULL::text, p_tribe_id integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_result jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.scheduled_at DESC), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      w.id, w.title, w.description, w.scheduled_at, w.duration_min,
      w.status, w.chapter_code,
      i.legacy_tribe_id AS tribe_id,
      w.organizer_id,
      w.co_manager_ids, w.meeting_link, w.youtube_url, w.notes,
      w.event_id, w.board_item_id,
      w.created_at, w.updated_at,
      m.name AS organizer_name,
      i.title AS tribe_name,
      e.date AS event_date,
      e.type AS event_type,
      (SELECT COUNT(*) FROM public.attendance a WHERE a.event_id = w.event_id AND a.present = true) AS attendee_count,
      (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', cm.id, 'name', cm.name)), '[]'::jsonb)
       FROM public.members cm WHERE cm.id = ANY(w.co_manager_ids)) AS co_managers,
      bi.title AS board_item_title,
      bi.status AS board_item_status
    FROM public.webinars w
    LEFT JOIN public.members m ON m.id = w.organizer_id
    LEFT JOIN public.initiatives i ON i.id = w.initiative_id
    LEFT JOIN public.events e ON e.id = w.event_id
    LEFT JOIN public.board_items bi ON bi.id = w.board_item_id
    WHERE (p_status IS NULL OR w.status = p_status)
      AND (p_chapter IS NULL OR w.chapter_code = p_chapter)
      AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
      AND public.rls_can_see_initiative(w.initiative_id)
  ) r;
  RETURN v_result;
END; $function$;

-- get_publication_submission_detail(p_submission_id uuid)
CREATE OR REPLACE FUNCTION public.get_publication_submission_detail(p_submission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'submission', jsonb_build_object(
      'id', ps.id, 'title', ps.title, 'abstract', ps.abstract,
      'target_type', ps.target_type::text, 'target_name', ps.target_name,
      'target_url', ps.target_url, 'status', ps.status::text,
      'submission_date', ps.submission_date, 'review_deadline', ps.review_deadline,
      'acceptance_date', ps.acceptance_date, 'presentation_date', ps.presentation_date,
      'primary_author_id', ps.primary_author_id, 'primary_author_name', m.name,
      'estimated_cost_brl', ps.estimated_cost_brl, 'actual_cost_brl', ps.actual_cost_brl,
      'cost_paid_by', ps.cost_paid_by, 'reviewer_feedback', ps.reviewer_feedback,
      'doi_or_url', ps.doi_or_url,
      'tribe_id', i.legacy_tribe_id, 'tribe_name', i.title,
      'board_item_id', ps.board_item_id, 'created_by', ps.created_by,
      'created_at', ps.created_at, 'updated_at', ps.updated_at
    ),
    'authors', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', psa.id, 'member_id', psa.member_id, 'member_name', am.name,
        'author_order', psa.author_order, 'is_corresponding', psa.is_corresponding
      ) ORDER BY psa.author_order), '[]'::jsonb)
      FROM public.publication_submission_authors psa
      JOIN public.members am ON am.id = psa.member_id
      WHERE psa.submission_id = ps.id
    )
  )
  INTO v_result
  FROM public.publication_submissions ps
  LEFT JOIN public.members m ON m.id = ps.primary_author_id
  LEFT JOIN public.initiatives i ON i.id = ps.initiative_id
  WHERE ps.id = p_submission_id
    AND public.rls_can_see_initiative(ps.initiative_id)  -- #785
  ;
  RETURN v_result;
END; $function$;

-- get_curation_queue_state(p_status text) — gate the q CTE so confidential
-- initiative items never enter the curator/governance queue for non-engaged callers.
CREATE OR REPLACE FUNCTION public.get_curation_queue_state(p_status text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_can_curate boolean;
  v_can_write_board boolean;
  v_can_govern boolean;
  v_can_manage boolean;
  v_drive_visible boolean;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  v_can_curate := public.can_by_member(v_member_id, 'curate_content');
  v_can_write_board := public.can_by_member(v_member_id, 'write_board');
  v_can_govern := public.can_by_member(v_member_id, 'participate_in_governance_review');
  IF NOT (v_can_curate OR v_can_write_board OR v_can_govern) THEN
    RAISE EXCEPTION 'Curatorship access required';
  END IF;
  -- Drive grant state mirrors the get_board_item_drive_access read gate.
  v_can_manage := public.can_by_member(v_member_id, 'manage_platform');
  v_drive_visible := (v_can_curate OR v_can_manage);

  WITH q AS (
    SELECT bi.id, bi.title, bi.curation_status, bi.curation_due_at, bi.board_id,
           bi.reviewer_id, bi.leader_reviewer_id, bi.created_by, bi.created_at,
           bi.peer_review_completed_at, bi.peer_review_waived,
           bi.leader_review_completed_at, bi.leader_review_decision,
           pb.board_name, i.legacy_tribe_id AS tribe_id, i.title AS tribe_name,
           COALESCE(sc.reviewers_required, 2) AS reviewers_required,
           (SELECT COALESCE(max(ble.review_round), 1) FROM public.board_lifecycle_events ble
              WHERE ble.item_id = bi.id AND ble.action = 'reviewer_assigned') AS current_round
    FROM public.board_items bi
    JOIN public.project_boards pb ON pb.id = bi.board_id
    LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
    LEFT JOIN public.board_sla_config sc ON sc.board_id = bi.board_id
    WHERE bi.status <> 'archived' AND pb.is_active = true
      AND bi.curation_status IN ('peer_review', 'leader_review', 'curation_pending')
      AND (p_status IS NULL OR bi.curation_status = p_status)
      AND public.rls_can_see_initiative(pb.initiative_id)  -- #785
  ),
  -- Per-file Drive status (mirrors get_board_item_drive_access's per-file CASE):
  --   error  = any failed|revoke_failed grant for the file
  --   pending= any pending_grant grant
  --   ready  = any granted grant
  --   else   = 'pending' (file with no resolvable active grant)
  -- Only computed when the caller may see Drive state (avoids needless work).
  dfile AS (
    SELECT bif.board_item_id, bif.drive_file_id,
      CASE
        WHEN count(*) FILTER (WHERE g.status IN ('failed','revoke_failed')) > 0 THEN 'error'
        WHEN count(*) FILTER (WHERE g.status = 'pending_grant') > 0           THEN 'pending'
        WHEN count(*) FILTER (WHERE g.status = 'granted') > 0                 THEN 'ready'
        ELSE 'pending'
      END AS file_status
    FROM public.board_item_files bif
    LEFT JOIN public.drive_curation_grants g
      ON g.drive_file_id = bif.drive_file_id AND g.board_item_id = bif.board_item_id
    WHERE v_drive_visible
      AND bif.deleted_at IS NULL
      AND bif.board_item_id IN (SELECT id FROM q)
    GROUP BY bif.board_item_id, bif.drive_file_id
  ),
  -- Item-level rollup (error > pending > ready > pending) + distinct error messages.
  drive AS (
    SELECT
      f.board_item_id,
      count(*) AS file_count,
      CASE
        WHEN bool_or(f.file_status = 'error')   THEN 'error'
        WHEN bool_or(f.file_status = 'pending') THEN 'pending'
        WHEN bool_or(f.file_status = 'ready')   THEN 'ready'
        ELSE 'pending'
      END AS overall_when_files,
      (SELECT COALESCE(jsonb_agg(DISTINCT (g2.api_error->>'message'))
                FILTER (WHERE g2.api_error IS NOT NULL), '[]'::jsonb)
         FROM public.drive_curation_grants g2
        WHERE g2.board_item_id = f.board_item_id
          AND g2.status IN ('failed','revoke_failed')
          AND EXISTS (SELECT 1 FROM public.board_item_files bif2
                       WHERE bif2.board_item_id = f.board_item_id
                         AND bif2.drive_file_id = g2.drive_file_id
                         AND bif2.deleted_at IS NULL)) AS errors
    FROM dfile f
    GROUP BY f.board_item_id
  )
  SELECT jsonb_build_object(
    'items', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'origin_type', 'board_item',
        'origin_id', q.id,
        'id', q.id, 'title', q.title,
        'curation_status', q.curation_status,
        'board_id', q.board_id, 'board_name', q.board_name,
        'tribe_id', q.tribe_id, 'tribe_name', q.tribe_name,
        'reviewer_id', q.reviewer_id, 'reviewer_name', rm.name,
        'leader_reviewer_id', q.leader_reviewer_id,
        'review_round', q.current_round,
        'review_count', (SELECT count(*) FROM public.curation_review_log crl WHERE crl.board_item_id = q.id AND crl.review_round = q.current_round),
        'reviews_approved', (SELECT count(DISTINCT crl.curator_id) FROM public.curation_review_log crl WHERE crl.board_item_id = q.id AND crl.decision = 'approved' AND crl.review_round = q.current_round),
        'reviewers_required', q.reviewers_required,
        'peer_review_completed_at', q.peer_review_completed_at,
        'leader_review_completed_at', q.leader_review_completed_at,
        'due_at', q.curation_due_at,
        'sla_status', CASE
          WHEN q.curation_due_at IS NULL THEN 'no_sla'
          WHEN q.curation_due_at < now() THEN 'overdue'
          WHEN q.curation_due_at < now() + interval '2 days' THEN 'warning'
          ELSE 'on_time' END,
        'caller_reviewed_this_round', EXISTS (SELECT 1 FROM public.curation_review_log crl WHERE crl.board_item_id = q.id AND crl.curator_id = v_member_id AND crl.review_round = q.current_round),
        -- #190 Drive layer (gated to curate_content OR manage_platform; null otherwise).
        'drive_permission_status', CASE WHEN v_drive_visible
          THEN (CASE WHEN dr.board_item_id IS NULL THEN 'missing' ELSE dr.overall_when_files END)
          ELSE NULL END,
        'drive_grant_role', CASE WHEN v_drive_visible AND dr.board_item_id IS NOT NULL THEN 'commenter' ELSE NULL END,
        'drive_grant_errors', CASE WHEN v_drive_visible THEN COALESCE(dr.errors, '[]'::jsonb) ELSE NULL END,
        'missing_drive_access', CASE WHEN v_drive_visible THEN (dr.board_item_id IS NULL) ELSE NULL END,
        'temporary_access_expires_or_revokes_on', CASE WHEN v_drive_visible THEN q.curation_due_at ELSE NULL END,
        'eligible_actions', (
          SELECT COALESCE(jsonb_agg(a.act), '[]'::jsonb) FROM (
            SELECT 'submit_review'::text AS act
              WHERE v_can_govern
                AND q.curation_status = 'curation_pending'
                AND NOT EXISTS (SELECT 1 FROM public.curation_review_log crl WHERE crl.board_item_id = q.id AND crl.curator_id = v_member_id AND crl.review_round = q.current_round)
            UNION ALL SELECT 'assign_reviewer' WHERE v_can_govern
            UNION ALL SELECT 'publish' WHERE q.curation_status = 'curation_pending' AND v_can_govern
          ) a
        )
      ) ORDER BY
        CASE
          WHEN q.curation_due_at IS NOT NULL AND q.curation_due_at < now() THEN 0
          WHEN q.curation_due_at IS NOT NULL AND q.curation_due_at < now() + interval '2 days' THEN 1
          ELSE 2 END,
        q.curation_due_at ASC NULLS LAST)
      FROM q
      LEFT JOIN public.members rm ON rm.id = q.reviewer_id
      LEFT JOIN drive dr ON dr.board_item_id = q.id
    ), '[]'::jsonb),
    'summary', jsonb_build_object(
      'total', (SELECT count(*) FROM q),
      'by_status', (SELECT COALESCE(jsonb_object_agg(s.curation_status, s.c), '{}'::jsonb) FROM (SELECT curation_status, count(*) c FROM q GROUP BY curation_status) s),
      'overdue', (SELECT count(*) FROM q WHERE curation_due_at < now())
    ),
    'caller', jsonb_build_object(
      'member_id', v_member_id,
      'can_curate', v_can_curate,
      'can_write_board', v_can_write_board,
      'can_govern', v_can_govern,
      'can_see_drive', v_drive_visible
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
