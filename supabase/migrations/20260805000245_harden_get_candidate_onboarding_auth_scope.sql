-- #877 (#872 review follow-up): harden authorization on get_candidate_onboarding_progress (GC-162).
--
-- Hardening (defense-in-depth, mirrors the nucleo-mcp tool gate):
--   (1) Resolve the authenticated caller; no caller -> 'Not authenticated'.
--   (2) The target defaults to the caller's own row; an explicit p_member_id may target another
--       member ONLY when the caller holds 'write' or 'manage_member' (the same gate the MCP
--       get_candidate_onboarding_progress tool enforces in the EF layer). Self-read stays open.
--   (3) REVOKE EXECUTE from anon — this is a member-onboarding RPC, never a public surface; only
--       get_public_* RPCs are anon-reachable (GC-162). The internal check_pre_onboarding_auto_steps
--       gate runs in the definer's context and therefore did not constrain this entrypoint.
-- The function body is otherwise unchanged from 20260805000244 (canonical onboarding aggregate).

CREATE OR REPLACE FUNCTION public.get_candidate_onboarding_progress(p_member_id uuid DEFAULT NULL::uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_mid uuid;
  v_caller uuid;
  v_result json;
BEGIN
  -- Resolve the authenticated caller (own member row).
  SELECT id INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated');
  END IF;

  -- Target defaults to self; an explicit p_member_id may address another member.
  v_mid := COALESCE(p_member_id, v_caller);

  -- Cross-member read requires write or manage_member (mirrors the nucleo-mcp tool gate).
  IF v_mid <> v_caller
     AND NOT public.can_by_member(v_caller, 'write', NULL, NULL)
     AND NOT public.can_by_member(v_caller, 'manage_member', NULL, NULL) THEN
    RETURN json_build_object('error', 'Unauthorized');
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

-- anon reached this RPC only via the default PUBLIC EXECUTE grant; revoke it so anon cannot
-- call a member-onboarding RPC at all (GC-162). authenticated + service_role keep explicit grants
-- (re-granted here for a clean fresh-apply). The in-body auth gate above is the primary control.
REVOKE EXECUTE ON FUNCTION public.get_candidate_onboarding_progress(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_candidate_onboarding_progress(uuid) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
