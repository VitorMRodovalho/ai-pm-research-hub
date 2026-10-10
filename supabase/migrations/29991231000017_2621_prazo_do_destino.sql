-- =====================================================================================
-- #2621: prazo do destino no card (decisao do GP de 09/10/2026: "no card, ja")
--
-- O autor pode ter um prazo de destino (submissao, newsletter, evento) que a plataforma nao
-- conhecia; ele so se resolvia por mensagem. O card ganha dois campos opcionais, destino e
-- data-alvo, gravados por set_curation_target (mesma autoridade de complete_peer_review: autoria,
-- lideranca da iniciativa ou governanca), e as listas da curadoria mostram os dois campos com o
-- alerta quando o prazo da curadoria passa da data-alvo (data em America/Sao_Paulo). Quando a 2B
-- da #2565 criar o produto na aprovacao, estes campos migram para ele.
--
-- list_curation_pending_board_items e get_curation_queue_state: corpos montados sobre o vivo
-- (md5 normalizado == captura 20260825031531, conferido em 09/10); so ganham os tres campos.
-- ROLLBACK: reaplicar a captura 20260825031531 das duas funcoes; DROP FUNCTION
--   set_curation_target(uuid, text, date); ALTER TABLE public.board_items DROP COLUMN
--   curation_target_venue, DROP COLUMN curation_target_date.
-- =====================================================================================

ALTER TABLE public.board_items
  ADD COLUMN IF NOT EXISTS curation_target_venue text NULL,
  ADD COLUMN IF NOT EXISTS curation_target_date date NULL;

COMMENT ON COLUMN public.board_items.curation_target_venue IS
  '#2621: destino do artefato com prazo proprio (submissao, newsletter, evento). Opcional; gravado por set_curation_target.';
COMMENT ON COLUMN public.board_items.curation_target_date IS
  '#2621: data-alvo do destino. Opcional; as listas da curadoria alertam quando curation_due_at passa dela.';

CREATE OR REPLACE FUNCTION public.set_curation_target(p_item_id uuid, p_venue text, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller members%ROWTYPE;
  v_item   board_items%ROWTYPE;
  v_initiative_id uuid;
  v_is_authorized boolean := false;
  v_venue  text := nullif(btrim(coalesce(p_venue, '')), '');
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_item FROM public.board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found: %', p_item_id; END IF;
  IF NOT public.rls_can_see_board(v_item.board_id) THEN
    RAISE EXCEPTION 'Item not found: %', p_item_id;
  END IF;

  IF v_item.curation_status NOT IN ('draft', 'peer_review', 'leader_review', 'curation_pending') THEN
    RAISE EXCEPTION 'Target deadline can only be set before publication (current: %)', v_item.curation_status;
  END IF;

  IF length(v_venue) > 200 THEN
    RAISE EXCEPTION 'Target venue too long (max 200 characters)';
  END IF;

  -- Mesma autoridade de complete_peer_review: autoria do card, lideranca da iniciativa ou governanca.
  SELECT pb.initiative_id INTO v_initiative_id
    FROM public.project_boards pb WHERE pb.id = v_item.board_id;

  IF v_item.assignee_id = v_caller.id THEN
    v_is_authorized := true;
  ELSIF EXISTS (
    SELECT 1 FROM public.board_item_assignments bia
    WHERE bia.item_id = p_item_id
      AND bia.member_id = v_caller.id
      AND bia.role IN ('author', 'contributor')
  ) THEN
    v_is_authorized := true;
  ELSIF v_initiative_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.engagements e
    JOIN public.persons p ON p.id = e.person_id
    WHERE e.initiative_id = v_initiative_id
      AND e.status = 'active'
      AND e.role = 'leader'
      AND p.auth_id = auth.uid()
  ) THEN
    v_is_authorized := true;
  ELSIF public.can_by_member(v_caller.id, 'participate_in_governance_review') THEN
    v_is_authorized := true;
  END IF;

  IF NOT v_is_authorized THEN
    RAISE EXCEPTION 'Requires authorship (assignee or assignments role author/contributor), tribe leadership, or governance reviewer authority';
  END IF;

  UPDATE public.board_items
     SET curation_target_venue = v_venue,
         curation_target_date  = p_date,
         updated_at = now()
   WHERE id = p_item_id;

  RETURN jsonb_build_object(
    'card_id', p_item_id,
    'target_venue', v_venue,
    'target_date', p_date,
    'target_at_risk', (p_date IS NOT NULL AND v_item.curation_due_at IS NOT NULL
                       AND (v_item.curation_due_at AT TIME ZONE 'America/Sao_Paulo')::date > p_date)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.set_curation_target(uuid, text, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_curation_target(uuid, text, date) TO authenticated;

CREATE OR REPLACE FUNCTION public.list_curation_pending_board_items()
 RETURNS SETOF json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  -- #245/#185: curation authority = curate_content (designation-derived) OR write_board (admin/manager/tribe-lead).
  IF NOT (public.can_by_member(v_member_id, 'curate_content')
          OR public._can_anywhere_by_member(v_member_id, 'write_board')) THEN
    RAISE EXCEPTION 'Curatorship access required';
  END IF;

  RETURN QUERY
  SELECT row_to_json(r) FROM (
    SELECT
      bi.id, bi.title, bi.description, bi.status,
      bi.curation_status, bi.assignee_id, bi.reviewer_id,
      bi.due_date, bi.curation_due_at, bi.board_id,
      -- #2621: prazo do destino (opcional) e o alerta quando o prazo da curadoria passa dele
      bi.curation_target_venue, bi.curation_target_date,
      (bi.curation_target_date IS NOT NULL AND bi.curation_due_at IS NOT NULL AND (bi.curation_due_at AT TIME ZONE 'America/Sao_Paulo')::date > bi.curation_target_date) AS target_at_risk,
      i.legacy_tribe_id AS tribe_id, i.title AS tribe_name,
      am.name AS assignee_name, rm.name AS reviewer_name,
      bi.created_at, bi.updated_at, bi.attachments,
      (SELECT count(*) FROM public.curation_review_log crl WHERE crl.board_item_id = bi.id) AS review_count,
      (SELECT json_agg(json_build_object(
        'id', crl2.id, 'curator_name', cm.name,
        'decision', crl2.decision, 'feedback', crl2.feedback_notes,
        'scores', crl2.criteria_scores, 'completed_at', crl2.completed_at
       ) ORDER BY crl2.completed_at DESC)
       FROM public.curation_review_log crl2
       LEFT JOIN public.members cm ON cm.id = crl2.curator_id
       WHERE crl2.board_item_id = bi.id
      ) AS review_history
    FROM public.board_items bi
    JOIN public.project_boards pb ON pb.id = bi.board_id
    LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
    LEFT JOIN public.members am ON am.id = bi.assignee_id
    LEFT JOIN public.members rm ON rm.id = bi.reviewer_id
    WHERE bi.curation_status = 'curation_pending'
      AND bi.status <> 'archived'
      AND pb.is_active = true
      AND public.rls_can_see_initiative(pb.initiative_id)  -- #785 PR-3: curation excludes confidential
    ORDER BY bi.curation_due_at ASC NULLS LAST, bi.updated_at DESC
  ) r;
END;
$function$;

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
  v_can_write_board := public._can_anywhere_by_member(v_member_id, 'write_board');
  v_can_govern := public.can_by_member(v_member_id, 'participate_in_governance_review');
  IF NOT (v_can_curate OR v_can_write_board OR v_can_govern) THEN
    RAISE EXCEPTION 'Curatorship access required';
  END IF;
  -- Drive grant state mirrors the get_board_item_drive_access read gate.
  v_can_manage := public.can_by_member(v_member_id, 'manage_platform');
  v_drive_visible := (v_can_curate OR v_can_manage);

  WITH q AS (
    SELECT bi.id, bi.title, bi.curation_status, bi.curation_due_at, bi.board_id,
           bi.curation_target_venue, bi.curation_target_date,
           (bi.curation_target_date IS NOT NULL AND bi.curation_due_at IS NOT NULL AND (bi.curation_due_at AT TIME ZONE 'America/Sao_Paulo')::date > bi.curation_target_date) AS target_at_risk,
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
        -- #2621: prazo do destino (opcional) e o alerta quando o prazo da curadoria passa dele
        'target_venue', q.curation_target_venue,
        'target_date', q.curation_target_date,
        'target_at_risk', q.target_at_risk,
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
