-- #190 (Drive layer) — surface curation Drive grant state in the queue envelope.
--
-- Post-#301 (ADR-0108): drive_curation_grants tracks temporary governed Drive
-- access for curation. get_curation_queue_state is the normalized envelope the
-- curator MCP tools wrap. This adds, per item, an item-level rollup of Drive
-- access state so a curator/governance reviewer sees grant readiness alongside
-- SLA/review state — mirroring get_board_item_drive_access's per-file→overall
-- derivation exactly so the queue chip and the modal badge always agree.
--
-- New per-item fields:
--   drive_permission_status                 missing | pending | error | ready
--   drive_grant_role                        'commenter' when files exist, else null
--   drive_grant_errors                      jsonb[] of distinct API error messages
--   missing_drive_access                    bool (0 non-deleted board_item_files)
--   temporary_access_expires_or_revokes_on  = curation_due_at (= item-RPC expires_or_revokes_on)
--
-- GATE (PM-ratified): the Drive fields are populated ONLY for callers with
-- curate_content OR manage_platform — consistent with the read gate of
-- get_board_item_drive_access. write_board-only / govern-only callers (who can
-- read the queue but cannot open the item-RPC) get NULL Drive fields. This
-- avoids opening a second, broader read surface over grant state.
--
-- Behavior-neutral at ship: 0 grants, 0 queue items with board_item_files ->
-- every item resolves to missing_drive_access=true / drive_permission_status='missing'.
--
-- Same signature -> CREATE OR REPLACE. Rollback: re-apply 20260805000121.

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

GRANT EXECUTE ON FUNCTION public.get_curation_queue_state(text) TO authenticated;
