-- p190 — calc_attendance_pct V4 data-filter: drop operational_role IN (...) for leader-flag
--
-- Replaces V3 cached enumeration `operational_role IN ('tribe_leader','manager','deputy_manager')`
-- (leader-flag for leadership_event expected calc) with V4 catalog-driven
-- `can_by_member(m.id, 'manage_event')` — same pattern as p189 bulk_mark_excused.
--
-- Empirical equivalence verified pre-apply (p190 boot, 2026-05-18):
--   V3 set (operational_role IN ('tribe_leader','manager','deputy_manager') + is_active): 8 members
--   V4 set (can_by_member(m.id,'manage_event') + is_active): 8 members
--   v3_only=0, v4_only=0 (zero inversions)
--   Parity check on AVG calc: V3 pct=65.9, V4 pct=65.9, delta=0.0
--
-- Future committee/workgroup leaders gaining 'manage_event' capability via
-- engagement_kind_permissions seed will auto-include — matches V4 model intent
-- (catalog-driven authority, ADR-0007 / ADR-0011).
--
-- Out-of-scope for this swap (separate sweep targets):
--   - `operational_role NOT IN ('sponsor','chapter_liaison','observer','candidate','visitor')`
--     (eligibility filter — V4 equivalent would inspect engagement kind/scope; distinct concern)
--
-- Single caller (verified via pg_proc.prosrc grep): get_annual_kpis(p_cycle, p_year)
-- analytics aggregator — function signature unchanged (no args, returns numeric).
--
-- Rollback: revert inner CASE in V4 line to V3 enumeration
--   `CASE WHEN m.operational_role IN ('tribe_leader','manager','deputy_manager') THEN ...`
-- (previous body captured in migration 20260428050000_adr0015_phase3e_events_drop_tribe_id.sql)

CREATE OR REPLACE FUNCTION public.calc_attendance_pct()
RETURNS numeric
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT ROUND(COALESCE(AVG(pct), 0)::numeric, 1)
  FROM (
    SELECT m.id,
      CASE WHEN expected > 0 THEN (attended::numeric / expected * 100) ELSE NULL END as pct
    FROM members m
    CROSS JOIN LATERAL (
      SELECT
        (
          (SELECT count(*) FROM events e WHERE e.type = 'geral' AND e.date >= '2026-01-01' AND e.date <= current_date)
          +
          (SELECT count(*) FROM events e JOIN initiatives i ON i.id = e.initiative_id
           WHERE e.type = 'tribo' AND i.legacy_tribe_id = m.tribe_id
             AND e.date >= '2026-01-01' AND e.date <= current_date)
          +
          (SELECT count(*) FROM attendance a JOIN events e ON e.id = a.event_id WHERE a.member_id = m.id AND e.type = '1on1' AND e.date >= '2026-01-01' AND e.date <= current_date)
          +
          -- V4 (p190): can_by_member('manage_event') replaces V3 operational_role IN (...)
          CASE WHEN public.can_by_member(m.id, 'manage_event') THEN
            (SELECT count(*) FROM events e WHERE e.type = 'lideranca' AND e.date >= '2026-01-01' AND e.date <= current_date)
          ELSE 0 END
        ) as expected,
        (SELECT count(*) FROM attendance a JOIN events e ON e.id = a.event_id
         WHERE a.member_id = m.id AND a.present = true
         AND e.type IN ('geral', 'tribo', '1on1', 'lideranca')
         AND e.date >= '2026-01-01' AND e.date <= current_date
        ) as attended
    ) stats
    WHERE m.is_active = true AND m.current_cycle_active = true
      AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'observer', 'candidate', 'visitor')
      AND stats.expected > 0
  ) sub
  WHERE pct IS NOT NULL;
$function$;

NOTIFY pgrst, 'reload schema';
