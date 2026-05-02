-- p89 cron audit findings — 2 P0 fixes
--
-- BUG #1 (P0): send-weekly-leader-digest cron 100% failure
--   Root cause: get_weekly_tribe_digest faz auth.uid() check mas é chamada
--   de generate_weekly_leader_digest_cron via cron context (auth.uid()=null).
--   Pattern fix: ADR-0028 service_role bypass adapter.
--   Impact: tribe leaders nunca receberam digest semanal desde criação do cron.
--
-- BUG #2 (P0): DUPLICATE weekly-card-digest-saturday + send-weekly-member-digest
--   Both fire Saturday 12:00 UTC e ambos chamam generate_weekly_member_digest_cron().
--   weekly-card-digest-saturday (jobid 23) → SELECT direto da RPC
--   send-weekly-member-digest (jobid 26) → EF wrapper que chama mesma RPC
--   Impact: members recebendo DUPLA notificação digest cada sábado → 2 emails
--   Fix: drop jobid 23 (RPC direta), manter EF wrapper (orchestrator com observability)
--
-- Reference: ADR-0028 service-role-bypass-adapter-pattern.md

-- ============================================================================
-- BUG #1 fix: get_weekly_tribe_digest com service_role bypass (ADR-0028)
-- ============================================================================

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

  -- ADR-0028 service_role bypass: cron orchestrator (generate_weekly_leader_digest_cron)
  -- chama esta RPC para construir digest agregado por tribo. Não há auth.uid() em
  -- cron context — service_role bypass é seguro pois (a) nenhum dado individual
  -- exposed (apenas agregados privacy-preserving), (b) caller é trusted internal
  -- function chamada exclusivamente de pg_cron.
  IF auth.role() = 'service_role' THEN
    -- bypass auth gate
    NULL;
  ELSE
    -- Auth: caller must be the tribe's leader OR have manage_member
    v_is_leader := (v_caller_id IS NOT NULL AND v_caller_id = v_tribe.leader_member_id);
    IF NOT v_is_leader AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
      RAISE EXCEPTION 'Unauthorized: only tribe leader or manage_member can read tribe digest';
    END IF;
  END IF;

  -- Aggregate ONLY (privacy-preserving — no individual member names or card titles)
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
  'Build weekly per-tribe digest (privacy-preserving aggregates, no individual data). Auth: tribe leader OR manage_member; service_role bypass para cron orchestrator (ADR-0028 — generate_weekly_leader_digest_cron). Fix p89: anteriormente cron falhava 100% pois auth.uid()=null em cron context.';

-- ============================================================================
-- BUG #2 fix: drop weekly-card-digest-saturday (jobid 23)
--   Manter send-weekly-member-digest (jobid 26) — EF wrapper com observability
-- ============================================================================

DO $$
DECLARE
  v_jobid bigint;
BEGIN
  SELECT jobid INTO v_jobid FROM cron.job WHERE jobname = 'weekly-card-digest-saturday';
  IF v_jobid IS NOT NULL THEN
    PERFORM cron.unschedule(v_jobid);
    RAISE NOTICE 'Dropped duplicate cron weekly-card-digest-saturday (jobid=%)', v_jobid;
  ELSE
    RAISE NOTICE 'Cron weekly-card-digest-saturday already absent — idempotent skip';
  END IF;
END $$;

-- ============================================================================
-- Audit log entry (governance trail)
-- ============================================================================

INSERT INTO public.admin_audit_log (
  actor_id,
  action,
  target_type,
  target_id,
  changes,
  metadata
)
SELECT
  m.id,
  'cron.audit_p89',
  'cron_job',
  NULL,
  jsonb_build_object(
    'fix_1', jsonb_build_object(
      'function', 'get_weekly_tribe_digest',
      'change', 'add ADR-0028 service_role bypass',
      'impact', 'send-weekly-leader-digest cron now succeeds; tribe leaders begin receiving weekly digest'
    ),
    'fix_2', jsonb_build_object(
      'cron_dropped', 'weekly-card-digest-saturday',
      'cron_kept', 'send-weekly-member-digest',
      'change', 'drop duplicate Saturday 12:00 cron — EF wrapper preserves observability',
      'impact', 'eliminates double weekly digest emails to members'
    )
  ),
  jsonb_build_object(
    'session', 'p89',
    'audit_skill', '/audit + cron audit',
    'reference_adr', 'ADR-0028'
  )
FROM public.members m
WHERE m.is_superadmin = true AND m.auth_id IS NOT NULL
ORDER BY m.created_at LIMIT 1;

NOTIFY pgrst, 'reload schema';
