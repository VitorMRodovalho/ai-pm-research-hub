-- #2862 (G3) e #2621 (G1): curadoria pelo criterio da RPC.
-- As 4 leitoras da fila de curadoria passam a exigir curate_content OU participate_in_governance_review,
-- o mesmo criterio da tela. get_artifact_classification ganha can_submit_curation, com a regra de
-- autoridade de submit_for_curation, para a tela mostrar o envio so a quem a RPC aceita.
-- Corpos recriados a partir da captura vigente, igual ao corpo vivo (md5 conferido antes do pacote).
-- Nenhuma assinatura muda; CREATE OR REPLACE mantem a ACL.

-- list_curation_board: captura vigente 20260825031531_1977_can_anywhere_portao_resourceless_explicito.sql
CREATE OR REPLACE FUNCTION public.list_curation_board(p_status text DEFAULT NULL::text)
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
  -- #2862: o mesmo criterio da tela de curadoria (curate_content OU revisor de governanca).
  IF NOT (public.can_by_member(v_member_id, 'curate_content')
          OR public.can_by_member(v_member_id, 'participate_in_governance_review')) THEN
    RAISE EXCEPTION 'Curatorship access required';
  END IF;

  RETURN QUERY
  SELECT row_to_json(r) FROM (
    SELECT hr.id, hr.title, hr.asset_type AS type, hr.url, hr.description,
      CASE WHEN hr.is_active THEN 'approved' ELSE 'pending' END AS status,
      i.legacy_tribe_id AS tribe_id, i.title AS tribe_name, m.name AS author_name,
      hr.tags, hr.created_at AS submitted_at,
      NULL::TIMESTAMPTZ AS reviewed_at, NULL::TEXT AS review_notes,
      'hub_resources'::TEXT AS _table,
      COALESCE(hr.source, 'manual') AS source,
      public.suggest_tags(hr.title, hr.asset_type, hr.cycle_code) AS suggested_tags
    FROM hub_resources hr
    LEFT JOIN initiatives i ON i.id = hr.initiative_id
    LEFT JOIN members m ON m.id = hr.author_id
    WHERE (p_status IS NULL
           OR (p_status = 'approved' AND hr.is_active = true)
           OR (p_status = 'pending' AND hr.is_active = false))
    ORDER BY hr.created_at DESC NULLS LAST
  ) r;
END;
$function$;

-- get_curation_dashboard: captura vigente 20260825031531_1977_can_anywhere_portao_resourceless_explicito.sql
CREATE OR REPLACE FUNCTION public.get_curation_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  -- #2862: o mesmo criterio da tela de curadoria (curate_content OU revisor de governanca).
  IF NOT (public.can_by_member(v_member_id, 'curate_content')
          OR public.can_by_member(v_member_id, 'participate_in_governance_review')) THEN
    RAISE EXCEPTION 'Curatorship access required';
  END IF;

  SELECT jsonb_build_object(
    'items', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', bi.id, 'title', bi.title, 'description', bi.description,
        'status', bi.status, 'curation_status', bi.curation_status,
        'curation_due_at', bi.curation_due_at, 'board_id', bi.board_id,
        'board_name', pb.board_name, 'tribe_id', i.legacy_tribe_id, 'tribe_name', i.title,
        'assignee_id', bi.assignee_id, 'assignee_name', am.name,
        'reviewer_id', bi.reviewer_id, 'reviewer_name', rm.name,
        'tags', bi.tags, 'attachments', bi.attachments,
        'created_at', bi.created_at, 'updated_at', bi.updated_at,
        'review_count', (SELECT count(*) FROM curation_review_log crl WHERE crl.board_item_id = bi.id AND crl.review_round = (SELECT coalesce(max(ble.review_round), 1) FROM board_lifecycle_events ble WHERE ble.item_id = bi.id AND ble.action = 'reviewer_assigned')),
        'reviews_approved', (SELECT count(DISTINCT crl.curator_id) FROM curation_review_log crl WHERE crl.board_item_id = bi.id AND crl.decision = 'approved' AND crl.review_round = (SELECT coalesce(max(ble.review_round), 1) FROM board_lifecycle_events ble WHERE ble.item_id = bi.id AND ble.action = 'reviewer_assigned')),
        'reviewers_required', COALESCE(sc.reviewers_required, 2),
        'sla_status', CASE
          WHEN bi.curation_due_at IS NULL THEN 'no_sla'
          WHEN bi.curation_due_at < now() THEN 'overdue'
          WHEN bi.curation_due_at < now() + interval '2 days' THEN 'warning'
          ELSE 'on_time'
        END,
        'review_history', (
          SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id', crl2.id, 'curator_name', cm.name, 'decision', crl2.decision,
            'feedback', crl2.feedback_notes, 'scores', crl2.criteria_scores,
            'completed_at', crl2.completed_at
          ) ORDER BY crl2.completed_at DESC), '[]'::jsonb)
          FROM curation_review_log crl2
          LEFT JOIN members cm ON cm.id = crl2.curator_id
          WHERE crl2.board_item_id = bi.id
        )
      ) ORDER BY
        CASE
          WHEN bi.curation_due_at IS NOT NULL AND bi.curation_due_at < now() THEN 0
          WHEN bi.curation_due_at IS NOT NULL AND bi.curation_due_at < now() + interval '2 days' THEN 1
          ELSE 2
        END,
        bi.curation_due_at ASC NULLS LAST
      )
      FROM board_items bi
      JOIN project_boards pb ON pb.id = bi.board_id
      LEFT JOIN initiatives i ON i.id = pb.initiative_id
      LEFT JOIN members am ON am.id = bi.assignee_id
      LEFT JOIN members rm ON rm.id = bi.reviewer_id
      LEFT JOIN board_sla_config sc ON sc.board_id = bi.board_id
      WHERE bi.curation_status = 'curation_pending'
        AND bi.status <> 'archived'
        AND pb.is_active = true
        AND public.rls_can_see_initiative(pb.initiative_id)  -- #785 PR-3: curation excludes confidential
    ), '[]'::jsonb),
    'summary', jsonb_build_object(
      'total_pending', (SELECT count(*) FROM board_items bi2 JOIN project_boards pb2 ON pb2.id = bi2.board_id WHERE bi2.curation_status = 'curation_pending' AND bi2.status <> 'archived' AND pb2.is_active = true AND public.rls_can_see_initiative(pb2.initiative_id)),
      'overdue', (SELECT count(*) FROM board_items bi3 JOIN project_boards pb3 ON pb3.id = bi3.board_id WHERE bi3.curation_status = 'curation_pending' AND bi3.curation_due_at < now() AND bi3.status <> 'archived' AND pb3.is_active = true AND public.rls_can_see_initiative(pb3.initiative_id))
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- list_curation_pending_board_items: captura vigente 20261010043301_2621_prazo_do_destino.sql
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
  -- #2862: o mesmo criterio da tela de curadoria (curate_content OU revisor de governanca).
  IF NOT (public.can_by_member(v_member_id, 'curate_content')
          OR public.can_by_member(v_member_id, 'participate_in_governance_review')) THEN
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

-- get_curation_queue_state: captura vigente 20261010043301_2621_prazo_do_destino.sql
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
  -- #2862: o mesmo criterio da tela de curadoria. v_can_write_board segue so no bloco caller.
  IF NOT (v_can_curate OR v_can_govern) THEN
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

-- get_artifact_classification: captura vigente 20260924203601_2455_revisor_de_governanca_ve_o_botao_da_revisao.sql
CREATE OR REPLACE FUNCTION public.get_artifact_classification(p_item_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_caller uuid;
  v_item   public.board_items%ROWTYPE;
  v_init   uuid;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_item FROM public.board_items WHERE id = p_item_id;
  -- Gate confidencial (ADR-0105): quem nao ve o card nao ve a classificacao dele.
  IF NOT FOUND OR NOT public.rls_can_see_item(p_item_id) THEN
    RAISE EXCEPTION 'Item not found';
  END IF;

  SELECT pb.initiative_id INTO v_init FROM public.project_boards pb WHERE pb.id = v_item.board_id;

  RETURN jsonb_build_object(
    'is_portfolio_item', coalesce(v_item.is_portfolio_item, false),
    'needs_curation', public._board_item_needs_curation(p_item_id),
    'type', (SELECT g.name FROM public.board_item_tag_assignments a JOIN public.tags g ON g.id = a.tag_id
              WHERE a.board_item_id = p_item_id AND g.tier = 'system' AND g.domain = 'board_item'
                AND g.name <> 'entregavel_lider'
              ORDER BY g.requires_curation DESC, g.display_order LIMIT 1),
    'subtype', (SELECT g.name FROM public.board_item_tag_assignments a JOIN public.tags g ON g.id = a.tag_id
                 WHERE a.board_item_id = p_item_id AND g.tier = 'administrative' AND g.domain = 'board_item'
                   AND g.requires_curation IS TRUE
                 ORDER BY g.display_order LIMIT 1),
    'suggested', public.portfolio_suggest_item_type(v_item.title, v_item.tags),
    'can_edit', (v_init IS NOT NULL AND public.can_by_member(v_caller, 'manage_board_admin', 'initiative', v_init))
                OR public.can_by_member(v_caller, 'manage_platform'),
    -- #2455: quem a complete_leader_review aceita, pela MESMA regra: lider da iniciativa (vinculo
    -- ativo) ou revisor de governanca. A tela usa isto em vez de reimplementar a regra.
    'can_leader_review', (v_init IS NOT NULL AND EXISTS (
                            SELECT 1 FROM public.engagements e
                              JOIN public.persons p ON p.id = e.person_id
                             WHERE e.initiative_id = v_init AND e.status = 'active'
                               AND e.role = 'leader' AND p.auth_id = auth.uid()))
                         OR public.can_by_member(v_caller, 'participate_in_governance_review'),
    -- #2621 (G1): quem a submit_for_curation aceita, pela MESMA regra de autoridade: revisor de
    -- governanca, ou tribe_leader com vinculo ativo de lider na iniciativa do quadro. A tela usa
    -- isto em vez de reimplementar a regra. Status e elegibilidade continuam com a tela e a RPC.
    'can_submit_curation', public.can_by_member(v_caller, 'participate_in_governance_review')
                           OR (v_init IS NOT NULL
                               AND EXISTS (SELECT 1 FROM public.members m
                                            WHERE m.id = v_caller AND m.operational_role = 'tribe_leader')
                               AND EXISTS (SELECT 1 FROM public.engagements e
                                             JOIN public.persons p ON p.id = e.person_id
                                            WHERE e.initiative_id = v_init AND e.status = 'active'
                                              AND e.role = 'leader' AND p.auth_id = auth.uid())),
    'types', (SELECT jsonb_agg(jsonb_build_object('name', g.name, 'label_pt', g.label_pt, 'label_en', g.label_en,
                                                  'label_es', g.label_es, 'requires_curation', g.requires_curation)
                               ORDER BY g.display_order)
                FROM public.tags g
               WHERE g.tier = 'system' AND g.domain = 'board_item' AND g.name <> 'entregavel_lider'),
    'subtypes', (SELECT jsonb_agg(jsonb_build_object('name', g.name, 'label_pt', g.label_pt, 'label_en', g.label_en,
                                                     'label_es', g.label_es)
                                  ORDER BY g.display_order)
                   FROM public.tags g
                  WHERE g.tier = 'administrative' AND g.domain = 'board_item' AND g.requires_curation IS TRUE)
  );
END;
$fn$;
