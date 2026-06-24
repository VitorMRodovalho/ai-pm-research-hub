-- #872 (#867 follow-up): pre-onboarding "0/0 passos" banner + purge ghost legacy step-keys
--
-- (1) get_candidate_onboarding_progress: add an `onboarding` aggregate that counts the member's
--     OWN canonical rows (step_key IN onboarding_steps), treating completed+skipped as done — mirrors
--     get_my_onboarding's completion semantics. The cockpit banner (OnboardingCockpitNudge) reads this
--     instead of `pre_onboarding`, whose phase='pre_onboarding' path has been dead since p155 F2
--     (2026-05-13) consolidated onboarding onto the canonical 7-step catalog → it always returns 0,
--     hence the "0/0 passos" symptom for the whole guest cohort.
--     This aggregate subquery is read-only (no auto-insert); the function's existing
--     check_pre_onboarding_auto_steps() side-effect (UPDATE pending→completed) is preserved unchanged.
--     `onboarding.total` is 0 for cohorts with no canonical rows (e.g. external_reviewer guests) → the
--     banner shows no count (not a misleading 0/0). `pre_onboarding` is kept intact (not removed) so the
--     deferred gamified-journey revival (#873) is not broken.
--
-- (2) Purge 5 off-catalog ghost step-keys (accept_terms, profile_complete, platform_access,
--     join_whatsapp, kick_off) — Cycle-3 w124/w130 seed residue. Footprint at apply: 31 members × 5 =
--     155 rows, ALL status='pending' (0 completed/0 skipped), outside onboarding_steps, with NO live
--     function dependency (references to "profile_complete" in check_schema_invariants / update_my_profile
--     / _trg_record_profile_complete_milestone are to the member_milestones milestone_key, not this step).
--     Current seeders only emit canonical steps, so these do not regenerate.

CREATE OR REPLACE FUNCTION public.get_candidate_onboarding_progress(p_member_id uuid DEFAULT NULL::uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_mid uuid;
  v_result json;
BEGIN
  -- Use provided member_id or resolve from auth
  v_mid := p_member_id;
  IF v_mid IS NULL THEN
    SELECT id INTO v_mid FROM members WHERE auth_id = auth.uid();
  END IF;

  IF v_mid IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated');
  END IF;

  -- First run auto-detection
  PERFORM check_pre_onboarding_auto_steps(v_mid);

  SELECT json_build_object(
    'member_id', v_mid,
    'steps', coalesce((
      SELECT json_agg(json_build_object(
        'step_key', op.step_key,
        'status', op.status,
        'completed_at', op.completed_at,
        'sla_deadline', op.sla_deadline,
        'xp', coalesce((op.metadata->>'xp')::int, 0),
        'phase', coalesce(op.metadata->>'phase', 'onboarding')
      ) ORDER BY
        CASE op.step_key
          WHEN 'create_account' THEN 1
          WHEN 'complete_profile' THEN 2
          WHEN 'setup_credly' THEN 3
          WHEN 'explore_platform' THEN 4
          WHEN 'read_blog' THEN 5
          WHEN 'start_pmi_certs' THEN 6
          WHEN 'code_of_conduct' THEN 7
          WHEN 'volunteer_term' THEN 8
          WHEN 'vep_acceptance' THEN 9
          WHEN 'first_meeting' THEN 10
          WHEN 'meet_tribe' THEN 11
          WHEN 'start_trail' THEN 12
          ELSE 99
        END
      )
      FROM onboarding_progress op
      WHERE op.member_id = v_mid
    ), '[]'::json),
    'pre_onboarding', json_build_object(
      'total', (SELECT count(*) FROM onboarding_progress WHERE member_id = v_mid AND metadata->>'phase' = 'pre_onboarding'),
      'completed', (SELECT count(*) FROM onboarding_progress WHERE member_id = v_mid AND metadata->>'phase' = 'pre_onboarding' AND status = 'completed'),
      'xp_earned', coalesce((SELECT sum((metadata->>'xp')::int) FROM onboarding_progress WHERE member_id = v_mid AND metadata->>'phase' = 'pre_onboarding' AND status = 'completed'), 0),
      'xp_total', coalesce((SELECT sum((metadata->>'xp')::int) FROM onboarding_progress WHERE member_id = v_mid AND metadata->>'phase' = 'pre_onboarding'), 0)
    ),
    'onboarding', json_build_object(
      'total', (SELECT count(*) FROM onboarding_progress WHERE member_id = v_mid AND step_key IN (SELECT id FROM onboarding_steps)),
      'completed', (SELECT count(*) FROM onboarding_progress WHERE member_id = v_mid AND step_key IN (SELECT id FROM onboarding_steps) AND status IN ('completed', 'skipped'))
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- (2) purge ghost legacy step-keys (see header)
DELETE FROM public.onboarding_progress
WHERE step_key IN ('accept_terms', 'profile_complete', 'platform_access', 'join_whatsapp', 'kick_off');

NOTIFY pgrst, 'reload schema';
