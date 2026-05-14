-- p158 #1: retrofit canonical onboarding for legacy-seeded approved members
--
-- Discovery (handoff p158 NEW gap from p157 #2 close): the post-#2 backfill survey showed that
-- 8 of 25 Active VEP approved candidates were missing ALL canonical onboarding rows (not just
-- vep_acceptance). Broader survey at p158 boot across all 33 distinct approved/converted
-- members:
--
--    canonical step      missing  present  (total approved pool)
--    code_of_conduct     14       19
--    volunteer_term      14       19
--    start_trail         12       21
--    meet_tribe           9       24
--    vep_acceptance       6       27       (was 14 pre-#2 — trigger backfill covered 8 here)
--    complete_profile     2       31
--    first_meeting        0       33       (all auto-completed by attendance pipeline)
--    ───────────────────────────
--    TOTAL INSERTs ≈      57
--
-- Root cause: members approved pre-#1 (≤2026-05-13) received the legacy 5-step XP-gamification
-- seed (create_account/setup_credly/explore_platform/read_blog/start_pmi_certs) which F2 p155
-- deleted but did NOT replace with canonical. Their canonical 7 stayed missing entirely (or,
-- for a few, partially present because the single-applicant inline flow had been patched at
-- different times — partial coverage). Result: onboarding dashboards showed 0% / wrong counts.
--
-- This migration: INSERTs missing canonical rows as 'pending' for each distinct approved or
-- converted member, keyed to that member's most recent application (DISTINCT ON ordered by
-- imported_at/created_at DESC). Idempotent via NOT EXISTS on (member_id, step_key) — safe to
-- re-run. Status='pending' so members must still complete in UI (no auto-credit beyond what
-- the auto-detect already gave them, e.g. first_meeting via attendance). vep_acceptance stays
-- consistent with #2 trigger: members already Active VEP have 'completed' rows (skipped by
-- NOT EXISTS); members not Active VEP get 'pending' here and will flip when VEP recruiter
-- accepts (trigger fires on next worker poll).
--
-- Notifications NOT sent: these are already-approved members long-since past the welcome
-- notification stage. Sending termo_due to 14 simultaneously would be confusing/spammy. They
-- will see the pending steps in their onboarding UI naturally on next visit.
--
-- Out of scope: rejected/waitlist applications (filter status IN ('approved','converted')).
-- Out of scope: check_pre_onboarding_auto_steps canonical (separate P2 carry-forward p155).

WITH latest_app AS (
  SELECT DISTINCT ON (m.id)
    m.id AS member_id,
    a.id AS application_id
  FROM   public.members m
  JOIN   public.selection_applications a ON lower(a.email) = lower(m.email)
  WHERE  a.status IN ('approved', 'converted')
  ORDER  BY m.id, COALESCE(a.imported_at, a.created_at) DESC
)
INSERT INTO public.onboarding_progress
  (application_id, member_id, step_key, status, metadata)
SELECT la.application_id, la.member_id, s.id, 'pending', '{}'::jsonb
FROM   latest_app la
CROSS  JOIN public.onboarding_steps s
WHERE  s.is_required = true
  AND  NOT EXISTS (
    SELECT 1 FROM public.onboarding_progress op
    WHERE op.member_id = la.member_id AND op.step_key = s.id
  );

NOTIFY pgrst, 'reload schema';
