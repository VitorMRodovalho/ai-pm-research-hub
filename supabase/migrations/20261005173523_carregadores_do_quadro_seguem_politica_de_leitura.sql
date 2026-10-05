-- Carregadores do quadro seguem a política de leitura de board_items.
--
-- A tabela board_items só deixa ler, pela API, quem é membro com vínculo vigente
-- (board_items_read_members: rls_is_authoritative_member()). get_board e list_board_items são
-- SECURITY DEFINER e checavam só o portão de quadro confidencial. Passam a aplicar a mesma regra
-- da tabela a quem chama pela API; chamadas internas (service_role, cron) seguem iguais.
-- get_board_by_domain delega para get_board. list_legacy_board_items_for_tribe já exige o líder da
-- tribo ou manage_member e não muda.

CREATE OR REPLACE FUNCTION public.get_board(p_board_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  -- Leitura pela API segue a política de leitura de board_items (board_items_read_members).
  -- Chamadas internas (service_role, cron) não passam por aqui.
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN
    RETURN NULL;
  END IF;

  -- #785 PR-3: confidential gate (board→initiative via SECDEF resolver, bypasses RLS)
  IF NOT public.rls_can_see_board(p_board_id) THEN
    RETURN NULL;
  END IF;

  SELECT jsonb_build_object(
    'board', (
      SELECT jsonb_build_object(
        'id', b.id,
        'board_name', b.board_name,
        'tribe_id', public.resolve_tribe_id(b.initiative_id),
        'source', b.source,
        'columns', b.columns,
        'is_active', b.is_active,
        'domain_key', b.domain_key,
        'board_scope', b.board_scope,
        'cycle_scope', b.cycle_scope
      )
      FROM project_boards b WHERE b.id = p_board_id
    ),
    'items', (
      SELECT coalesce(jsonb_agg(
        jsonb_build_object(
          'id', i.id,
          'title', i.title,
          'description', i.description,
          'status', i.status,
          'assignee_id', i.assignee_id,
          'assignee_name', am.name,
          'reviewer_id', i.reviewer_id,
          'reviewer_name', rm.name,
          'tags', i.tags,
          'labels', i.labels,
          'due_date', i.due_date,
          'baseline_date', i.baseline_date,
          'forecast_date', i.forecast_date,
          'actual_completion_date', i.actual_completion_date,
          'mirror_source_id', i.mirror_source_id,
          'mirror_target_id', i.mirror_target_id,
          'is_mirror', i.is_mirror,
          'position', i.position,
          'attachments', i.attachments,
          'checklist', i.checklist,
          'curation_status', i.curation_status,
          'curation_due_at', i.curation_due_at,
          'cycle', i.cycle,
          'is_portfolio_item', i.is_portfolio_item,
          'source_card_id', i.source_card_id,
          'source_board', i.source_board,
          'created_at', i.created_at,
          'updated_at', i.updated_at,
          'assignments', coalesce((
            SELECT jsonb_agg(jsonb_build_object(
              'member_id', bia.member_id,
              'name', bm.name,
              'avatar_url', bm.photo_url,
              'role', bia.role
            ) ORDER BY
              CASE bia.role WHEN 'author' THEN 0 WHEN 'reviewer' THEN 1 WHEN 'curation_reviewer' THEN 2 ELSE 3 END,
              bia.assigned_at
            )
            FROM board_item_assignments bia
            JOIN members bm ON bm.id = bia.member_id
            WHERE bia.item_id = i.id
          ), '[]'::jsonb)
        ) ORDER BY i.position
      ), '[]'::jsonb)
      FROM board_items i
      LEFT JOIN members am ON am.id = i.assignee_id
      LEFT JOIN members rm ON rm.id = i.reviewer_id
      WHERE i.board_id = p_board_id
        AND i.status <> 'archived'
    )
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_board_items(p_board_id uuid, p_status text DEFAULT NULL::text)
 RETURNS SETOF json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Leitura pela API segue a política de leitura de board_items (board_items_read_members).
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN RETURN; END IF;
  IF NOT public.rls_can_see_board(p_board_id) THEN RETURN; END IF;  -- #785
  RETURN QUERY
  SELECT row_to_json(r) FROM (
    SELECT
      bi.id,
      bi.title,
      bi.description,
      bi.status,
      bi.curation_status,
      bi.reviewer_id,
      bi.tags,
      bi.labels,
      bi.due_date,
      bi.position,
      bi.cycle,
      bi.is_portfolio_item,
      bi.attachments,
      bi.checklist,
      bi.created_at,
      bi.updated_at,
      m.name AS assignee_name,
      m.photo_url AS assignee_photo,
      rm.name AS reviewer_name
    FROM board_items bi
    LEFT JOIN members m ON m.id = bi.assignee_id
    LEFT JOIN members rm ON rm.id = bi.reviewer_id
    WHERE bi.board_id = p_board_id
      AND (p_status IS NULL OR bi.status = p_status)
      AND bi.status <> 'archived'
    ORDER BY bi.position ASC, bi.created_at DESC
  ) r;
END;
$function$;
