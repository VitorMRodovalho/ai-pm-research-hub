-- #1942: o responsavel passa a enxergar o PROPRIO inventario de responsabilidades.
--
-- Antes, o portao era `manage_platform` OU `service_role`, e `p_member_id` e o ALVO,
-- nao o chamador. Medido por contraste em 2026-08-23: um responsavel real pedindo o
-- proprio inventario recebia `Unauthorized: requires manage_platform permission`.
--
-- O carve-out abaixo NAO e escalada: as 7 superficies ja filtram por `p_member_id`, e o
-- gate de confidencialidade (`rls_can_see_initiative`) e avaliado para o chamador, que
-- neste caminho e o proprio alvo. Nao toca `engagement_kind_permissions`.
--
-- Corpo transcrito de `pg_get_functiondef` (producao, 2026-08-23). A UNICA mudanca em
-- relacao ao corpo vivo e o predicado do IF do portao.

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

  -- #1942: + carve-out "si mesmo". Quem pede o proprio inventario passa sem manage_platform.
  IF NOT v_is_service
     AND (
       v_caller IS NULL
       OR (v_caller <> p_member_id AND NOT public.can_by_member(v_caller, 'manage_platform'))
     ) THEN
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

-- #1942: superficie de autoatendimento. Sem parametro, logo NAO pode ser apontada
-- para outra pessoa por construcao. Um corpo so: delega para a funcao acima.
CREATE OR REPLACE FUNCTION public.get_my_responsibilities()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller uuid;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;
  RETURN public.get_member_responsibility_inventory(v_caller);
END;
$function$;

-- `CREATE FUNCTION` nasce com EXECUTE para PUBLIC (logo, para `anon`). Retirar.
REVOKE ALL ON FUNCTION public.get_my_responsibilities() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_member_responsibility_inventory(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_responsibilities() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_member_responsibility_inventory(uuid) TO authenticated, service_role;
