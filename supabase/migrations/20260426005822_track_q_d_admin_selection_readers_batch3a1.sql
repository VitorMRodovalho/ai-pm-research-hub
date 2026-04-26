-- Track Q-D — admin selection readers hardening (batch 3a.1)
--
-- Council-validated reshape of original 6-fn proposal. After
-- platform-guardian + security-engineer callsite analysis:
--
-- - 1 fn truly dead (no callers in src/ or supabase/functions/) → REVOKE only.
-- - 2 fns have CRITICAL PII risk (LGPD Art. 5/6/46) per security-engineer:
--   admin frontend caller exists; PostgREST direct call bypasses UI gate.
--   Treatment: REVOKE FROM PUBLIC + anon (keep `authenticated` for admin
--   UI), ADD internal `can_by_member('manage_platform')` gate.
-- - 3 fns deferred for PM tier clarification: get_attendance_panel
--   (homepage caller!), get_meeting_notes_compliance, count_tribe_slots.
--
-- Batch shape (3 of original 6):
--
-- (a) Dead-code REVOKE-only:
-- - get_executive_kpis() — admin executive aggregate stats. NO callers
--   in src/ or supabase/functions/. Per security-engineer: not
--   public-by-design per ADR-0024; aggregate-only but admin-shape.
--
-- (b) PII gate + REVOKE-from-public:
-- - get_application_interviews(uuid) — selection eval reader exposing
--   interview notes + interviewer_ids per applicant. Caller:
--   /admin/selection.astro:1553 (admin-only flow). LGPD Art. 5/6 PII.
-- - get_application_onboarding_pct(uuid) — onboarding progress %
--   per application. Caller: /admin/selection.astro:443. Aggregates
--   onboarding state for an applicant; selection-admin only.
--
-- Privilege expansion analysis (verified live data 2026-04-25):
--   manage_platform safety check: legacy_count=2 (Vitor SA, Fabricio SA),
--   v4_count=2, would_gain=null. Zero authorization change in production.
--
-- Bodies preserved verbatim except added gate at top.
--
-- log_pii_access integration deferred — log_pii_access expects
-- target_member_id but selection_applications.id ≠ members.id (applicants
-- are pre-member). Future audit doc improvement: extend log_pii_access
-- to support application-id targets, then retrofit gates.
--
-- DEFERRED to batch 3a.2 (PM tier input needed):
-- - get_attendance_panel — called from HomepageHero (member tier?
--   anon?), AttendanceDashboard, attendance.astro, MCP tool.
-- - get_meeting_notes_compliance — called from MeetingsPage.
-- - count_tribe_slots — called from TribesSection (homepage tier?).

-- ========================================================================
-- (a) Dead-code REVOKE-only
-- ========================================================================

REVOKE EXECUTE ON FUNCTION public.get_executive_kpis() FROM PUBLIC, anon, authenticated;

-- ========================================================================
-- (b) PII gate + REVOKE-from-public (keep authenticated for admin UI)
-- ========================================================================

CREATE OR REPLACE FUNCTION public.get_application_interviews(p_application_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform permission';
  END IF;

  RETURN (
    SELECT coalesce(json_agg(json_build_object(
      'id', si.id, 'scheduled_at', si.scheduled_at, 'duration_minutes', si.duration_minutes,
      'status', si.status, 'conducted_at', si.conducted_at, 'theme_of_interest', si.theme_of_interest,
      'notes', si.notes, 'interviewer_ids', si.interviewer_ids
    ) ORDER BY si.created_at DESC), '[]'::json)
    FROM selection_interviews si
    WHERE si.application_id = p_application_id
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_application_interviews(uuid) FROM PUBLIC, anon;

CREATE OR REPLACE FUNCTION public.get_application_onboarding_pct(p_application_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result integer;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform permission';
  END IF;

  SELECT CASE
    WHEN count(*) = 0 THEN -1
    ELSE round(100.0 * count(*) FILTER (WHERE status = 'completed') / count(*))::int
  END INTO v_result
  FROM onboarding_progress
  WHERE application_id = p_application_id
  AND metadata->>'phase' = 'pre_onboarding';

  RETURN v_result;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_application_onboarding_pct(uuid) FROM PUBLIC, anon;

NOTIFY pgrst, 'reload schema';
