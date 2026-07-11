-- #1293 [EPIC #1020 Onda A] get_member_responsibility_inventory — RPC read-only das 7 superfícies de posse.
--
-- O protocolo de handoff de responsabilidade (#1020) precisa, ANTES de qualquer escrita, de uma fonte
-- unica de verdade do que um membro possui/lidera atraves das 7 superfícies. Hoje isso esta espalhado
-- (board_items.assignee_id, board_items.created_by, board_item_checklists.assigned_to, tribes.leader_member_id,
-- board_items.reviewer_id/curation, meeting_action_items.assignee_id, drive_curation_grants.grantee_member_id)
-- e so ha deteccao pos-fato parcial (detect_orphan_assignees_from_offboards, list_orphan_card_assignments).
--
-- As 7 superfícies (aterradas ao vivo 2026-07-10):
--   1. board_items onde e assignee (aberto)         -> board_items.assignee_id
--   2. cards criados/owned em estado aberto           -> board_items.created_by
--   3. checklist items atribuidos (nao concluidos)    -> board_item_checklists.assigned_to
--   4. lideranca de tribo                             -> tribes.leader_member_id (coluna canonica; nao ha engagement kind de lider)
--   5. curation assignments (revisao ativa)           -> board_items.reviewer_id + curation_status ativo
--   6. action items abertos                           -> meeting_action_items.assignee_id status='open'
--   7. drive grants ativos                            -> drive_curation_grants.grantee_member_id (revoked_at NULL)
--
-- Gate: manage_platform (via can_by_member) OU service_role (MCP/edge/cron). anon revogado.
-- Confidencialidade (ADR-0105): superfícies ligadas a iniciativa (via board -> project_boards.initiative_id)
--   sao filtradas por rls_can_see_initiative(). service_role ve tudo (contexto operacional sem membro).
--   Read-only, STABLE -> fora do sweep de side-effect SECDEF (#965); segue o padrao do #1217.
--
-- Consumida por: integracao de offboard (Onda C), sucessao de lider (Onda D), reconciliacao (Onda E).
-- Rollback: DROP FUNCTION public.get_member_responsibility_inventory(uuid);

CREATE OR REPLACE FUNCTION public.get_member_responsibility_inventory(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller uuid;
  v_is_service boolean;
  v_member_name text;
  v_board_assigned jsonb;
  v_cards_owned jsonb;
  v_checklist jsonb;
  v_tribe_lead jsonb;
  v_curation jsonb;
  v_action jsonb;
  v_drive jsonb;
BEGIN
  -- Gate: manage_platform (GP) OU service_role (MCP OAuth chega como o proprio GP; service p/ edge/cron).
  v_is_service := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  ) = 'service_role';

  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();

  IF NOT v_is_service AND (v_caller IS NULL OR NOT public.can_by_member(v_caller, 'manage_platform')) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_platform permission');
  END IF;

  SELECT name INTO v_member_name FROM public.members WHERE id = p_member_id;
  IF v_member_name IS NULL THEN
    RETURN jsonb_build_object('error', 'Member not found');
  END IF;

  -- 1. board_items onde e assignee (aberto), confidential-gated via board -> initiative
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', bi.id, 'title', bi.title, 'status', bi.status,
    'board_id', bi.board_id, 'board_name', pb.board_name,
    'initiative_id', pb.initiative_id, 'due_date', bi.due_date
  ) ORDER BY bi.updated_at DESC), '[]'::jsonb)
  INTO v_board_assigned
  FROM public.board_items bi
  JOIN public.project_boards pb ON pb.id = bi.board_id
  WHERE bi.assignee_id = p_member_id
    AND bi.status NOT IN ('done', 'archived')
    AND (v_is_service OR pb.initiative_id IS NULL OR public.rls_can_see_initiative(pb.initiative_id));

  -- 2. cards criados/owned em estado aberto
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', bi.id, 'title', bi.title, 'status', bi.status,
    'board_id', bi.board_id, 'board_name', pb.board_name,
    'initiative_id', pb.initiative_id
  ) ORDER BY bi.updated_at DESC), '[]'::jsonb)
  INTO v_cards_owned
  FROM public.board_items bi
  JOIN public.project_boards pb ON pb.id = bi.board_id
  WHERE bi.created_by = p_member_id
    AND bi.status NOT IN ('done', 'archived')
    AND (v_is_service OR pb.initiative_id IS NULL OR public.rls_can_see_initiative(pb.initiative_id));

  -- 3. checklist items atribuidos e nao concluidos
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', c.id, 'text', c.text, 'board_item_id', c.board_item_id,
    'board_item_title', bi.title, 'target_date', c.target_date
  ) ORDER BY c.assigned_at DESC NULLS LAST), '[]'::jsonb)
  INTO v_checklist
  FROM public.board_item_checklists c
  JOIN public.board_items bi ON bi.id = c.board_item_id
  JOIN public.project_boards pb ON pb.id = bi.board_id
  WHERE c.assigned_to = p_member_id
    AND c.is_completed = false
    AND (v_is_service OR pb.initiative_id IS NULL OR public.rls_can_see_initiative(pb.initiative_id));

  -- 4. lideranca de tribo (coluna canonica tribes.leader_member_id)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'tribe_id', t.id, 'tribe_name', t.name, 'quadrant', t.quadrant
  ) ORDER BY t.id), '[]'::jsonb)
  INTO v_tribe_lead
  FROM public.tribes t
  WHERE t.leader_member_id = p_member_id
    AND t.is_active = true;

  -- 5. curation assignments (revisao ativa: reviewer_id + curation_status ativo)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', bi.id, 'title', bi.title, 'curation_status', bi.curation_status,
    'board_id', bi.board_id, 'board_name', pb.board_name,
    'initiative_id', pb.initiative_id, 'curation_due_at', bi.curation_due_at
  ) ORDER BY bi.curation_due_at ASC NULLS LAST), '[]'::jsonb)
  INTO v_curation
  FROM public.board_items bi
  JOIN public.project_boards pb ON pb.id = bi.board_id
  WHERE bi.reviewer_id = p_member_id
    AND bi.curation_status IN ('curation_pending', 'leader_review')
    AND (v_is_service OR pb.initiative_id IS NULL OR public.rls_can_see_initiative(pb.initiative_id));

  -- 6. action items abertos (event-linked; sem gate de iniciativa)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', a.id, 'description', a.description, 'event_id', a.event_id, 'due_date', a.due_date
  ) ORDER BY a.due_date ASC NULLS LAST), '[]'::jsonb)
  INTO v_action
  FROM public.meeting_action_items a
  WHERE a.assignee_id = p_member_id
    AND a.status = 'open';

  -- 7. drive grants ativos (nao revogados), confidential-gated via board_item -> board -> initiative
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', g.id, 'board_item_id', g.board_item_id, 'drive_file_url', g.drive_file_url,
    'role', g.role, 'status', g.status, 'granted_at', g.granted_at
  ) ORDER BY g.granted_at DESC NULLS LAST), '[]'::jsonb)
  INTO v_drive
  FROM public.drive_curation_grants g
  LEFT JOIN public.board_items bi ON bi.id = g.board_item_id
  LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
  WHERE g.grantee_member_id = p_member_id
    AND g.revoked_at IS NULL
    AND (v_is_service OR pb.initiative_id IS NULL OR public.rls_can_see_initiative(pb.initiative_id));

  RETURN jsonb_build_object(
    'member_id', p_member_id,
    'member_name', v_member_name,
    'surfaces', jsonb_build_object(
      'board_items_assigned', jsonb_build_object('count', jsonb_array_length(v_board_assigned), 'items', v_board_assigned),
      'cards_owned',          jsonb_build_object('count', jsonb_array_length(v_cards_owned),    'items', v_cards_owned),
      'checklist_items',      jsonb_build_object('count', jsonb_array_length(v_checklist),      'items', v_checklist),
      'tribe_leadership',     jsonb_build_object('count', jsonb_array_length(v_tribe_lead),     'items', v_tribe_lead),
      'curation_assignments', jsonb_build_object('count', jsonb_array_length(v_curation),       'items', v_curation),
      'action_items',         jsonb_build_object('count', jsonb_array_length(v_action),         'items', v_action),
      'drive_grants',         jsonb_build_object('count', jsonb_array_length(v_drive),          'items', v_drive)
    ),
    'total_items',
      jsonb_array_length(v_board_assigned) + jsonb_array_length(v_cards_owned) +
      jsonb_array_length(v_checklist) + jsonb_array_length(v_tribe_lead) +
      jsonb_array_length(v_curation) + jsonb_array_length(v_action) +
      jsonb_array_length(v_drive)
  );
END;
$function$;

COMMENT ON FUNCTION public.get_member_responsibility_inventory(uuid) IS
  '#1293 [EPIC #1020 Onda A] inventario read-only das 7 superfícies de posse de um membro (board_items assignee/owned, checklist, lideranca de tribo, curation, action items, drive grants). Gate manage_platform + service_role; confidential-gated (rls_can_see_initiative, ADR-0105). Fundacao do protocolo de handoff (#1020) — consumido por offboard (C), sucessao (D), reconciliacao (E).';

REVOKE ALL ON FUNCTION public.get_member_responsibility_inventory(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_member_responsibility_inventory(uuid) TO authenticated, service_role;
