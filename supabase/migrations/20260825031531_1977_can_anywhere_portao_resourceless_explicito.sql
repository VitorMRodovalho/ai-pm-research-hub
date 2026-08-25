-- #1977: `_can_anywhere()` -- o portao resourceless deixa de ser implicito.
--
-- Etapa 3 do procedimento de escopo de `write_board` (etapas 1 e 2 em #1945 e #1953). Restaram 6
-- RPCs de curadoria e comms cujo portao pergunta, com razao, "esta pessoa e alguem de curadoria /
-- board / comms em ALGUM lugar?". Ate aqui essa pergunta era feita pela forma de 2 argumentos de
-- `can_by_member`, que resolve o caso sem recurso dependendo de `legacy_tribe_id`.
--
-- Essa coluna so e preenchida quando a iniciativa e uma TRIBO. Autoridade escopada a iniciativa que
-- nao e tribo (comite, congresso) portanto NAO passava sem recurso, mesmo com combo seedado e
-- vigente -- medido em 3 pessoas, que passam assim que o proprio recurso e informado.
--
-- `_can_anywhere` e a traducao explicita da pergunta: mesma consulta de `can()`, sem ramo de
-- recurso e sem a coluna legada. `can()` fica INTOCADA, exatamente como `can_org` (#1945) fez.
-- E SUPERCONJUNTO do comportamento de hoje: ninguem perde acesso.
--
-- O carve-out p195 (`participate_in_governance_review` com engajamento apenas ativo) e replicado
-- porque `can()` e `can_org()` o tem: um helper que o omitisse negaria comentario em governanca
-- para quem tem contra-assinatura pendente.
--
-- Prefixo `_can_`: o reconhecedor de autoridade V4 do ADR-0011 aceita `can()`, `can_by_member`,
-- `rls_can` e `_can_*`. Um nome sem o prefixo deixaria de ser reconhecido como portao V4.
--
-- Troca SO o ramo de `write_board` nas 6. Os ramos `curate_content`, `manage_event`,
-- `manage_member` e `participate_in_governance_review` seguem intactos e pertencem as suas ondas.
--
-- Os corpos abaixo sao a captura vigente de cada funcao, com UM termo trocado. Igualdade com o
-- corpo vivo conferida por md5 do corpo normalizado antes desta migration ser escrita.

CREATE OR REPLACE FUNCTION public._can_anywhere(p_person_id uuid, p_action text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- "Tem esta autoridade em ALGUM lugar?" -- deliberadamente sem recurso.
  --
  -- Diferenca para `can()` sem recurso: aqui o escopo `initiative` vale por EXISTIR o vinculo com
  -- uma iniciativa, e nao por `legacy_tribe_id` estar preenchida. A coluna legada distingue tribo de
  -- comite/congresso, que e uma distincao de MIGRACAO, nao de autoridade.
  --
  -- Diferenca para `can_org()`: aquela aceita SO organization/global. Esta aceita tambem o escopo
  -- de iniciativa, porque a pergunta nao e "manda na organizacao inteira?" e sim "manda em algum
  -- lugar?".
  SELECT EXISTS (
    SELECT 1
    FROM public.auth_engagements ae
    JOIN public.engagement_kind_permissions ekp
      ON ekp.kind = ae.kind AND ekp.role = ae.role AND ekp.action = p_action
    WHERE ae.person_id = p_person_id
      AND (
        ae.is_authoritative = true
        -- mesmo carve-out p195 de can()/can_org(): comentario em governanca nao exige termo.
        OR (p_action = 'participate_in_governance_review' AND ae.status = 'active')
      )
      AND (
        ekp.scope IN ('organization', 'global')
        OR (ekp.scope = 'initiative' AND ae.initiative_id IS NOT NULL)
      )
  );
$function$;

CREATE OR REPLACE FUNCTION public._can_anywhere_by_member(p_member_id uuid, p_action text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT public._can_anywhere(
    (SELECT id FROM public.persons WHERE legacy_member_id = p_member_id),
    p_action
  );
$function$;

-- Portao nasce com EXECUTE para PUBLIC (logo, para `anon`). Mesmo tratamento de `can_org` (#1945).
REVOKE ALL ON FUNCTION public._can_anywhere(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._can_anywhere_by_member(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._can_anywhere(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._can_anywhere_by_member(uuid, text) TO authenticated, service_role;


-- get_comms_pipeline: captura 20260516630000 (20260516630000_p95_131_comms_self_service_pipeline.sql), um termo trocado.
CREATE OR REPLACE FUNCTION public.get_comms_pipeline()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_now timestamptz := now();
  v_urgent_count int;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT (
    public._can_anywhere_by_member(v_caller_id, 'write_board') OR
    public.can_by_member(v_caller_id, 'manage_event') OR
    public.can_by_member(v_caller_id, 'manage_member')
  ) THEN
    RAISE EXCEPTION 'Unauthorized: requires comms/board/admin authority';
  END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.scheduled_at), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      w.id AS webinar_id,
      w.title,
      w.scheduled_at,
      w.status,
      w.chapter_code,
      w.format_type,
      w.series_id,
      COALESCE(ps.title_i18n->>'pt-BR', ps.slug) AS series_title,
      ps.slug AS series_slug,
      w.series_position,
      w.tribe_anchors,
      i.title AS initiative_title,
      m.name AS organizer_name,
      w.briefing_doc_url,
      w.sympla_event_url,
      w.promo_kit_url,
      w.comms_kickoff_at,
      (w.briefing_doc_url IS NOT NULL) AS has_briefing,
      (w.sympla_event_url IS NOT NULL) AS has_sympla,
      (w.promo_kit_url IS NOT NULL) AS has_promo_kit,
      (w.comms_kickoff_at IS NOT NULL) AS comms_kickoff_logged,
      (w.scheduled_at - interval '30 days') AS d30_due_at,
      EXTRACT(EPOCH FROM (w.scheduled_at - v_now))::bigint / 86400 AS days_until,
      CASE
        WHEN w.briefing_doc_url IS NOT NULL
         AND w.sympla_event_url IS NOT NULL
         AND w.promo_kit_url IS NOT NULL THEN 'ready'
        WHEN w.briefing_doc_url IS NULL
         AND w.sympla_event_url IS NULL
         AND w.promo_kit_url IS NULL THEN 'not_started'
        ELSE 'in_progress'
      END AS readiness,
      (
        w.scheduled_at <= v_now + interval '30 days'
        AND w.scheduled_at > v_now
        AND (w.briefing_doc_url IS NULL OR w.sympla_event_url IS NULL OR w.promo_kit_url IS NULL)
      ) AS urgent
    FROM public.webinars w
    LEFT JOIN public.initiatives i ON i.id = w.initiative_id
    LEFT JOIN public.members m ON m.id = w.organizer_id
    LEFT JOIN public.publication_series ps ON ps.id = w.series_id
    WHERE w.status IN ('planned', 'confirmed')
      AND w.scheduled_at >= v_now - interval '7 days'
    ORDER BY w.scheduled_at
  ) r;

  SELECT COUNT(*) INTO v_urgent_count
  FROM public.webinars w
  WHERE w.status IN ('planned', 'confirmed')
    AND w.scheduled_at <= v_now + interval '30 days'
    AND w.scheduled_at > v_now
    AND (w.briefing_doc_url IS NULL OR w.sympla_event_url IS NULL OR w.promo_kit_url IS NULL);

  RETURN jsonb_build_object(
    'webinars', v_result,
    'count', jsonb_array_length(v_result),
    'urgent_count', v_urgent_count,
    'generated_at', v_now
  );
END; $function$;


-- get_curation_dashboard: captura 20260805000233 (20260805000233_p785_pr3_confidential_initiative_rpcs.sql), um termo trocado.
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
  IF NOT (public.can_by_member(v_member_id, 'curate_content')
          OR public._can_anywhere_by_member(v_member_id, 'write_board')) THEN
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


-- get_curation_queue_state: captura 20260805000275 (20260805000275_p785_gate_content_readers_part2.sql), um termo trocado.
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


-- list_curation_board: captura 20260805000112 (20260805000112_185_gate_list_curation_board.sql), um termo trocado.
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
  IF NOT (public.can_by_member(v_member_id, 'curate_content')
          OR public._can_anywhere_by_member(v_member_id, 'write_board')) THEN
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


-- list_curation_pending_board_items: captura 20260805000233 (20260805000233_p785_pr3_confidential_initiative_rpcs.sql), um termo trocado.
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


-- update_webinar_comms_assets: captura 20260516630000 (20260516630000_p95_131_comms_self_service_pipeline.sql), um termo trocado.
CREATE OR REPLACE FUNCTION public.update_webinar_comms_assets(
  p_webinar_id uuid,
  p_briefing_doc_url text DEFAULT NULL,
  p_sympla_event_url text DEFAULT NULL,
  p_promo_kit_url text DEFAULT NULL,
  p_mark_kickoff boolean DEFAULT FALSE
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_webinar_exists boolean := false;
  v_updated text[] := '{}';
  v_old_record jsonb;
  v_new_record jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT (
    public._can_anywhere_by_member(v_caller_id, 'write_board') OR
    public.can_by_member(v_caller_id, 'manage_event') OR
    public.can_by_member(v_caller_id, 'manage_member')
  ) THEN
    RAISE EXCEPTION 'Unauthorized: requires comms/board/admin authority';
  END IF;

  SELECT
    jsonb_build_object(
      'briefing_doc_url', briefing_doc_url,
      'sympla_event_url', sympla_event_url,
      'promo_kit_url', promo_kit_url,
      'comms_kickoff_at', comms_kickoff_at
    ),
    true
  INTO v_old_record, v_webinar_exists
  FROM public.webinars WHERE id = p_webinar_id;

  IF NOT v_webinar_exists THEN
    RAISE EXCEPTION 'Webinar not found: %', p_webinar_id;
  END IF;

  IF p_briefing_doc_url IS NOT NULL THEN
    UPDATE public.webinars SET briefing_doc_url = p_briefing_doc_url, updated_at = now() WHERE id = p_webinar_id;
    v_updated := array_append(v_updated, 'briefing_doc_url');
  END IF;
  IF p_sympla_event_url IS NOT NULL THEN
    UPDATE public.webinars SET sympla_event_url = p_sympla_event_url, updated_at = now() WHERE id = p_webinar_id;
    v_updated := array_append(v_updated, 'sympla_event_url');
  END IF;
  IF p_promo_kit_url IS NOT NULL THEN
    UPDATE public.webinars SET promo_kit_url = p_promo_kit_url, updated_at = now() WHERE id = p_webinar_id;
    v_updated := array_append(v_updated, 'promo_kit_url');
  END IF;
  IF p_mark_kickoff THEN
    UPDATE public.webinars SET comms_kickoff_at = now(), updated_at = now()
    WHERE id = p_webinar_id AND comms_kickoff_at IS NULL;
    IF FOUND THEN v_updated := array_append(v_updated, 'comms_kickoff_at'); END IF;
  END IF;

  IF array_length(v_updated, 1) IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'webinar_id', p_webinar_id,
      'message', 'no fields provided'
    );
  END IF;

  SELECT jsonb_build_object(
    'briefing_doc_url', briefing_doc_url,
    'sympla_event_url', sympla_event_url,
    'promo_kit_url', promo_kit_url,
    'comms_kickoff_at', comms_kickoff_at
  )
  INTO v_new_record
  FROM public.webinars WHERE id = p_webinar_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller_id,
    'update_webinar_comms_assets',
    'webinar',
    p_webinar_id,
    jsonb_build_object(
      'before', v_old_record,
      'after',  v_new_record,
      'updated_fields', to_jsonb(v_updated)
    ),
    jsonb_build_object('source', 'mcp', 'issue', '#131')
  );

  RETURN jsonb_build_object(
    'success', true,
    'webinar_id', p_webinar_id,
    'updated_fields', to_jsonb(v_updated)
  );
END; $function$;
