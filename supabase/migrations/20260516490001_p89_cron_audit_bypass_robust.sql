-- p89 cron audit follow-up — bypass robust em get_weekly_tribe_digest
--
-- Discovery durante p89: a primeira fix em 20260516490000 usou só
-- `auth.role() = 'service_role'` para bypass, mas isso NÃO cobre cron context
-- (cron não tem JWT — auth.role() retorna NULL).
--
-- Validation pós-deploy via SELECT generate_weekly_leader_digest_cron() ainda
-- falhava com "Unauthorized: only tribe leader or manage_member can read tribe
-- digest" — confirmou que auth.role() bypass insuficiente.
--
-- Fix robusto: também bypassar quando current_setting('request.jwt.claims',
-- true) IS NULL (true em cron, false em authenticated/anon/service_role).
-- Aceita ambos os cenários: EF service_role + cron direto.
--
-- Validation: SELECT generate_weekly_leader_digest_cron() agora retorna 7 rows
-- (7 tribes ativas, 7 leaders notificados) — confirmou fix em produção.
--
-- Reference: ADR-0028 service-role-bypass-adapter-pattern.md (Amendment p89:
-- robust adapter para cron sem JWT context).

CREATE OR REPLACE FUNCTION public.get_weekly_tribe_digest(p_tribe_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_tribe record;
  v_window_start timestamptz := date_trunc('day', now()) - interval '7 days';
  v_result jsonb;
  v_is_leader boolean;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  SELECT * INTO v_tribe FROM public.tribes WHERE id = p_tribe_id;
  IF v_tribe IS NULL THEN RAISE EXCEPTION 'Tribe not found: %', p_tribe_id; END IF;

  -- ADR-0028 robust service_role bypass:
  --   (a) auth.role() = 'service_role' → EF chamou via service_role JWT
  --   (b) current_setting('request.jwt.claims', true) IS NULL → cron context (sem JWT)
  -- Aceitamos ambos pois esta função produz apenas agregados privacy-preserving
  -- (sem dados individuais), e é trusted internal helper de cron orchestrator.
  IF auth.role() = 'service_role'
     OR current_setting('request.jwt.claims', true) IS NULL THEN
    NULL;  -- machine/cron caller — bypass auth gate
  ELSE
    v_is_leader := (v_caller_id IS NOT NULL AND v_caller_id = v_tribe.leader_member_id);
    IF NOT v_is_leader AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
      RAISE EXCEPTION 'Unauthorized: only tribe leader or manage_member can read tribe digest';
    END IF;
  END IF;

  SELECT jsonb_build_object(
    'tribe_id', p_tribe_id,
    'tribe_name', v_tribe.name,
    'leader_member_id', v_tribe.leader_member_id,
    'generated_at', now(),
    'window_start', v_window_start,
    'aggregates', jsonb_build_object(
      'active_members', COALESCE((
        SELECT count(*) FROM public.members m
        WHERE m.tribe_id = p_tribe_id AND m.current_cycle_active = true
      ), 0),
      'members_with_overdue_cards', COALESCE((
        SELECT count(DISTINCT bi.assignee_id) FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        JOIN public.initiatives i ON i.id = pb.initiative_id
        JOIN public.members m ON m.id = bi.assignee_id
        WHERE i.legacy_tribe_id = p_tribe_id
          AND m.tribe_id = p_tribe_id
          AND bi.status NOT IN ('done', 'archived')
          AND bi.due_date < CURRENT_DATE
      ), 0),
      'cards_overdue_total', COALESCE((
        SELECT count(*) FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        JOIN public.initiatives i ON i.id = pb.initiative_id
        WHERE i.legacy_tribe_id = p_tribe_id
          AND bi.status NOT IN ('done', 'archived')
          AND bi.due_date < CURRENT_DATE
      ), 0),
      'cards_due_next_7d', COALESCE((
        SELECT count(*) FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        JOIN public.initiatives i ON i.id = pb.initiative_id
        WHERE i.legacy_tribe_id = p_tribe_id
          AND bi.status NOT IN ('done', 'archived')
          AND bi.due_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '7 days'
      ), 0),
      'cards_without_assignee', COALESCE((
        SELECT count(*) FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        JOIN public.initiatives i ON i.id = pb.initiative_id
        WHERE i.legacy_tribe_id = p_tribe_id
          AND bi.status NOT IN ('done', 'archived')
          AND bi.assignee_id IS NULL
      ), 0),
      'cards_without_due_date', COALESCE((
        SELECT count(*) FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        JOIN public.initiatives i ON i.id = pb.initiative_id
        WHERE i.legacy_tribe_id = p_tribe_id
          AND bi.status NOT IN ('done', 'archived')
          AND bi.due_date IS NULL
      ), 0),
      'cards_completed_window', COALESCE((
        SELECT count(*) FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        JOIN public.initiatives i ON i.id = pb.initiative_id
        WHERE i.legacy_tribe_id = p_tribe_id
          AND bi.status IN ('done')
          AND bi.updated_at >= v_window_start
      ), 0),
      'tribe_health_pct', COALESCE((
        SELECT CASE
          WHEN count(*) FILTER (WHERE bi.status NOT IN ('done', 'archived')) = 0 THEN 100
          ELSE (100.0 * count(*) FILTER (WHERE bi.status NOT IN ('done', 'archived') AND bi.due_date IS NOT NULL)
                / NULLIF(count(*) FILTER (WHERE bi.status NOT IN ('done', 'archived')), 0))::int
        END
        FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        JOIN public.initiatives i ON i.id = pb.initiative_id
        WHERE i.legacy_tribe_id = p_tribe_id
      ), 100)
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

COMMENT ON FUNCTION public.get_weekly_tribe_digest(integer) IS
  'Build weekly per-tribe digest (privacy-preserving aggregates). Auth: tribe leader OR manage_member; service_role/cron bypass via auth.role() OR (request.jwt.claims IS NULL) (ADR-0028 robust adapter — anteriormente bypass restrito a auth.role() falhava em cron sem JWT).';

NOTIFY pgrst, 'reload schema';
