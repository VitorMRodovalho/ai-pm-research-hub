-- C3 -> C4 roll-forward of member_cycle_history (runbook §4.3).
-- EXECUTED against PROD on 2026-07-05 via execute_sql during the early cycle
-- turnover (the DIA 9 opening meeting is the public kickoff; C3 had already
-- ended and pre-onboarding was underway, so the cycle was flipped ahead of the
-- meeting to end the "platform still says Ciclo 3" limbo). This file is the
-- repo/audit capture; it is idempotent (NOT EXISTS guard, date/cycle-scoped) so
-- it is a no-op on a fresh DB.
-- BEFORE (grounded 2026-07-05): 63 open cycle_3 rows, 0 cycle_4 rows, cohort=30.
-- AFTER:  0 open cycle_3 rows, 30 cycle_4 rows, invariants=0.

BEGIN;

-- 1) close all open C3 history rows (C3 ended 2026-07-08)
UPDATE public.member_cycle_history
SET cycle_end = DATE '2026-07-08'
WHERE cycle_code = 'cycle_3' AND cycle_end IS NULL;

-- 2) roll-forward continuers -> cycle_4 snapshot row.
--    Criterion: active member + C3 history + active volunteer engagement with
--    end_date NULL or >= 2026-12-01. Excludes Débora Moura (exit end_of_cycle).
WITH coorte AS (
  SELECT DISTINCT m.id, m.name, m.operational_role, m.designations, m.tribe_id, m.chapter
  FROM public.members m
  JOIN public.member_cycle_history h ON h.member_id = m.id AND h.cycle_code = 'cycle_3'
  JOIN public.persons p ON p.legacy_member_id = m.id
  JOIN public.engagements e ON e.person_id = p.id
    AND e.kind = 'volunteer' AND e.status = 'active' AND e.revoked_at IS NULL
    AND (e.end_date IS NULL OR e.end_date >= DATE '2026-12-01')
  WHERE m.is_active = true
    AND m.id <> 'a8c9af17-d9f8-4a0e-85bc-a0b13b0f8ad7'  -- Débora Moura
)
INSERT INTO public.member_cycle_history
  (member_id, member_name_snapshot, cycle_code, cycle_label, cycle_start, cycle_end,
   operational_role, designations, tribe_id, tribe_name, chapter, is_active, notes)
SELECT c.id, c.name, 'cycle_4', 'Ciclo 4 (2026/2)', DATE '2026-07-09', NULL,
       c.operational_role, c.designations, c.tribe_id, t.name, c.chapter, true,
       'roll-forward C3->C4 (runbook §4.3, executado 2026-07-05 na virada antecipada)'
FROM coorte c
LEFT JOIN public.tribes t ON t.id = c.tribe_id
WHERE NOT EXISTS (
  SELECT 1 FROM public.member_cycle_history h2
  WHERE h2.member_id = c.id AND h2.cycle_code = 'cycle_4'
);

COMMIT;
