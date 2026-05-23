-- ============================================================================
-- p234 — #322 close-review patch (PM 2026-05-23 post PR #327 review):
--   close Gap B re-entry vector via get_my_onboarding() auto-seed.
-- ADR: ADR-0006 (Person + Engagement) / ADR-0007 (Authority)
--
-- Purpose:
--   PM curator review of PR #327 surfaced an unguarded auto-seed path:
--   approve_selection_application gained a forward guard in
--   20260805000019 (skip volunteer_term seed when v_requires_agreement is
--   false), but get_my_onboarding() ALSO auto-seeds onboarding_progress
--   on first call — and was NOT guarded. Result: any member whose first
--   onboarding hit lands in get_my_onboarding() before
--   approve_selection_application has set their row (or whose engagement
--   kind doesn't have requires_agreement=true) gets volunteer_term=pending
--   created universally, reintroducing exactly Gap B.
--
--   This migration:
--   - CREATE OR REPLACE get_my_onboarding() with the mirror guard:
--     compute v_has_req_agreement_engagement via EXISTS on
--     engagements + engagement_kinds, then add
--     `AND NOT (s.id = 'volunteer_term' AND NOT v_has_req_agreement_engagement)`
--     to the auto-seed INSERT.
--   - The completed_steps + all_complete harmonization (skipped≡completed)
--     introduced in 20260805000019 is preserved verbatim.
--
-- Scope:
--   - ONLY get_my_onboarding(): the only auto-seed path that touched
--     volunteer_term universally. Audit of 6 auto-seed paths confirmed
--     (commit message has full table; PR #327 comment-4526761568).
--   - Per-step rendering still preserved verbatim — UI may render skipped
--     distinctly.
--
-- Out of scope:
--   - check_pre_onboarding_auto_steps(): only UPDATEs existing rows by
--     step_key, does not auto-seed catalog (safe).
--   - auto_detect_onboarding_completions(): only seeds complete_profile /
--     start_trail / first_meeting (safe).
--   - process_vep_acceptance_transition(): only touches vep_acceptance (safe).
--   - seed_pre_onboarding_steps(): only pre_onboarding steps (safe).
--   - complete_onboarding_step(): caller-driven; user explicitly clicks
--     "Mark complete" — not auto-seeding.
--   - approve_selection_application(): guarded in 20260805000019.
--
-- PM directive (2026-05-23 close-review):
--   "Do not auto-create volunteer_term unless the member has active
--   engagement with requires_agreement=true." — preserved as inline guard
--   in get_my_onboarding() auto-seed loop.
--
-- Rollback:
--   -- Revert get_my_onboarding() to 20260805000019 body (which already had
--   -- the skipped≡completed harmonization but no auto-seed guard).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_my_onboarding()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_has_req_agreement_engagement boolean;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;

  -- #322 close-review (p234, PM 2026-05-23 post PR #327 review): mirror the
  -- approve_selection_application forward guard here. Otherwise Gap B
  -- reintroduces — any member without an active requires_agreement=true
  -- engagement whose first onboarding hit lands in get_my_onboarding gets
  -- volunteer_term=pending auto-seeded, violating the goal metric.
  SELECT EXISTS (
    SELECT 1 FROM public.engagements e
    JOIN public.members m ON m.id = v_member_id
    JOIN public.engagement_kinds ek ON ek.slug = e.kind
    WHERE e.person_id = m.person_id
      AND e.status = 'active'
      AND ek.requires_agreement = true
  ) INTO v_has_req_agreement_engagement;

  -- Auto-generate progress rows (now guarded: volunteer_term only when the
  -- member has at least one active requires_agreement=true engagement)
  INSERT INTO onboarding_progress (member_id, step_key, status)
  SELECT v_member_id, s.id, 'pending'
  FROM onboarding_steps s
  WHERE NOT EXISTS (SELECT 1 FROM onboarding_progress op WHERE op.member_id = v_member_id AND op.step_key = s.id)
    AND NOT (s.id = 'volunteer_term' AND NOT v_has_req_agreement_engagement);

  SELECT jsonb_build_object(
    'member_id', v_member_id,
    'total_steps', (SELECT count(*) FROM onboarding_steps WHERE is_required),
    -- #322 (p234 / Gap B of #230): treat 'skipped' as terminal (≡ completed)
    -- for completion counting. Mirrors get_onboarding_status behavior. Required
    -- so backfilled rows with reason='no_requires_agreement_engagement' do not
    -- show as incomplete on the dashboard for the 4 active members in Gap B.
    'completed_steps', (SELECT count(*) FROM onboarding_progress WHERE member_id = v_member_id AND status IN ('completed', 'skipped') AND step_key IN (SELECT id FROM onboarding_steps)),
    'all_complete', (NOT EXISTS (
      SELECT 1 FROM onboarding_steps s
      JOIN onboarding_progress op ON op.step_key = s.id AND op.member_id = v_member_id
      WHERE s.is_required AND op.status NOT IN ('completed', 'skipped')
    )),
    'steps', (SELECT jsonb_agg(row_to_json(t) ORDER BY t.step_order) FROM (
      SELECT s.id AS step_id, s.step_order, s.label_pt, s.label_en, s.label_es,
        s.description_pt, s.description_en, s.description_es, s.icon, s.is_required,
        COALESCE(op.status, 'pending') AS status, op.completed_at, op.metadata
      FROM onboarding_steps s
      LEFT JOIN onboarding_progress op ON op.step_key = s.id AND op.member_id = v_member_id
      ORDER BY s.step_order
    ) t)
  ) INTO v_result;
  RETURN v_result;
END; $function$;

COMMENT ON FUNCTION public.get_my_onboarding() IS
  '#322 close-review (p234, PM 2026-05-23): mirrors approve_selection_application forward guard — does NOT auto-seed volunteer_term unless the member has an active engagement with requires_agreement=true. Also harmonizes status=skipped as terminal (≡ completed) for completed_steps + all_complete. Mirrors get_onboarding_status pattern. step rendering preserved verbatim — UI can render skipped distinctly if needed.';

NOTIFY pgrst, 'reload schema';
