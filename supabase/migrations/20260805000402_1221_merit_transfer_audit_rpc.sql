-- #1221 fatia 1 (Part A): advisory audit of merit-transfer on COMPLETED cards.
--
-- Business rule (feedback-merit-immutable-on-completed-work, PM 2026-07-08): the merit of
-- completed work is immutable and belongs to whoever did it. Archiving a tribe, a member exit,
-- or a leadership transition may only move the FUTURE (backlog/to-do) — never reassign the credit
-- of already-completed cards to the new leader, the GP, or a third party.
--
-- WHY advisory (not a hard invariant): grounded live 2026-07-10 — board_lifecycle_events covers only
-- ~26% of completed cards (117/449), so a history-based baseline-0 gate would be blind to the other
-- 74%; and a current-state gate ("completed card assigned to a leader/GP") false-positives on leaders
-- who legitimately do work. So this is a REVIEW QUEUE for a human (GP), not a CI gate: it surfaces the
-- suspicious set with enough context to judge, and self-reassignments (actor == current assignee) are
-- filtered out to cut the known benign noise (a doer re-touching their own done card).
--
-- Two flags:
--   'reassigned_after_completion'          — a member_assigned/assigned lifecycle event dated AFTER the
--                                            card's first CARD-LEVEL completion event (status_change to
--                                            done/review/archived, or archived/item_archived — NOT the
--                                            activity_completed/actual_completion activity-level noise),
--                                            performed by someone OTHER than the current assignee.
--   'completed_credit_from_non_leader_creator' — card is done/review/archived, the current assignee is
--                                            a leader/GP (manager|tribe_leader), but created_by is a
--                                            DIFFERENT, NON-leader person: a proxy for credit that sits
--                                            with a leader while a non-leader (likely the doer) created
--                                            it. Narrow by construction (a blanket "assigned to a leader"
--                                            flag is ~310 legitimate rows; this is the divergent subset).
--
-- Authority: manage_platform (or service_role/postgres for MCP/cron/tests). SECURITY DEFINER, read-only.

CREATE OR REPLACE FUNCTION public._audit_merit_transfer_on_completed_cards()
RETURNS TABLE(
  item_id uuid,
  board_id uuid,
  title text,
  status text,
  assignee_id uuid,
  assignee_name text,
  assignee_role text,
  flag text,
  detail jsonb
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT (
    current_setting('role', true) IN ('service_role', 'postgres')
    OR current_user IN ('postgres', 'supabase_admin')
    OR (auth.uid() IS NOT NULL
        AND public.can((SELECT p.id FROM public.persons p
                        JOIN public.members m ON m.id = p.legacy_member_id
                        WHERE m.auth_id = auth.uid()), 'manage_platform'))
  ) THEN
    RAISE EXCEPTION 'Unauthorized: _audit_merit_transfer_on_completed_cards requires manage_platform';
  END IF;

  RETURN QUERY
  WITH completion_evt AS (
    -- first CARD-LEVEL completion moment (excludes activity/forecast-level events)
    SELECT e.item_id, min(e.created_at) AS first_completed_at
    FROM public.board_lifecycle_events e
    WHERE (e.action = 'status_change' AND e.new_status IN ('done', 'review', 'archived'))
       OR e.action IN ('archived', 'item_archived')
    GROUP BY e.item_id
  ),
  reassigned AS (
    -- a (re)assignment after completion, by someone OTHER than the current assignee (drop self-touches)
    SELECT e.item_id,
           max(e.created_at) AS last_reassigned_at,
           (array_agg(e.actor_member_id ORDER BY e.created_at DESC))[1] AS reassigned_by
    FROM public.board_lifecycle_events e
    JOIN completion_evt ce ON ce.item_id = e.item_id
    JOIN public.board_items bi ON bi.id = e.item_id
    WHERE e.action IN ('member_assigned', 'assigned')
      AND e.created_at > ce.first_completed_at
      AND bi.status IN ('done', 'review', 'archived')
      AND e.actor_member_id IS DISTINCT FROM bi.assignee_id
    GROUP BY e.item_id
  )
  SELECT bi.id, bi.board_id, bi.title, bi.status,
         bi.assignee_id, am.name, am.operational_role,
         'reassigned_after_completion'::text,
         jsonb_build_object(
           'first_completed_at', ce.first_completed_at,
           'last_reassigned_at', r.last_reassigned_at,
           'reassigned_by', rb.name)
  FROM reassigned r
  JOIN public.board_items bi ON bi.id = r.item_id
  JOIN completion_evt ce ON ce.item_id = r.item_id
  LEFT JOIN public.members am ON am.id = bi.assignee_id
  LEFT JOIN public.members rb ON rb.id = r.reassigned_by

  UNION ALL

  SELECT bi.id, bi.board_id, bi.title, bi.status,
         bi.assignee_id, am.name, am.operational_role,
         'completed_credit_from_non_leader_creator'::text,
         jsonb_build_object('created_by', cb.name, 'created_by_role', cb.operational_role)
  FROM public.board_items bi
  JOIN public.members am ON am.id = bi.assignee_id
  LEFT JOIN public.members cb ON cb.id = bi.created_by
  WHERE bi.status IN ('done', 'review', 'archived')
    AND am.operational_role IN ('manager', 'tribe_leader')
    AND bi.created_by IS NOT NULL
    AND bi.created_by IS DISTINCT FROM bi.assignee_id
    AND (cb.operational_role IS NULL OR cb.operational_role NOT IN ('manager', 'tribe_leader'))

  ORDER BY 8, 3;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public._audit_merit_transfer_on_completed_cards() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public._audit_merit_transfer_on_completed_cards() TO authenticated, service_role;
