-- p158 F2: admin_decide_dual_track — cross-role decision RPC for dual_track pairs
--
-- Problem (PM directive 2026-05-14): when a candidate has 2 linked applications in a cycle
-- (promotion_path='dual_track', both rows mutually linked via F1 backfill+trigger), the existing
-- admin_update_application RPC only accepts a decision for ONE application at a time. PM cannot
-- in a single gesture "reject as leader + approve as researcher" — has to open 2 modals, and
-- the unscored sibling (typically researcher when only the leader interview happened) has NULL
-- objective_score_avg / interview_score, blocking the standard flow.
--
-- This RPC:
-- (1) Resolves the pair from either application_id input
-- (2) Auto-copies role-agnostic raw scores (objective_score_avg + interview_score) from the
--     scored app to the unscored app — these criteria are identical across researcher and
--     leader tracks (e.g. ai_knowledge, gp_knowledge, communication, teamwork). leader_extra
--     is NOT copied — that's role-specific (5 leader-only criteria).
-- (3) Applies each per-role decision via admin_update_application (internal call), preserving
--     all existing side-effects: onboarding seed on approved, operational_role promotion on
--     reactivation (Op B), notification, audit log entry per app.
-- (4) Returns both per-role results for UI display.
-- (5) Logs a cross-decision audit entry in data_anomaly_log (separable from per-app audits
--     done by admin_update_application).
--
-- Gated by manage_platform (caller check — internal admin_update_application also enforces).
-- Single transaction (PG default), so both decisions roll back together if any sub-step errors.

CREATE OR REPLACE FUNCTION public.admin_decide_dual_track(
  p_application_id      uuid,
  p_researcher_decision text,
  p_leader_decision     text,
  p_feedback            text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id          uuid;
  v_app                record;
  v_sibling_app        record;
  v_researcher_app_id  uuid;
  v_leader_app_id      uuid;
  v_scored             record;
  v_unscored_id        uuid;
  v_researcher_result  json;
  v_leader_result      json;
  v_copied_scores      boolean := false;
  v_allowed_decisions  text[] := ARRAY['approved','rejected','waitlist'];
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN json_build_object('error', 'Unauthorized'); END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN json_build_object('error', 'Unauthorized');
  END IF;

  IF NOT (p_researcher_decision = ANY(v_allowed_decisions)) THEN
    RETURN json_build_object('error', 'Invalid researcher_decision: ' || p_researcher_decision);
  END IF;
  IF NOT (p_leader_decision = ANY(v_allowed_decisions)) THEN
    RETURN json_build_object('error', 'Invalid leader_decision: ' || p_leader_decision);
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF NOT FOUND THEN RETURN json_build_object('error', 'Application not found'); END IF;

  IF v_app.promotion_path IS DISTINCT FROM 'dual_track' OR v_app.linked_application_id IS NULL THEN
    RETURN json_build_object('error', 'Application is not part of a dual_track pair');
  END IF;

  SELECT * INTO v_sibling_app FROM public.selection_applications WHERE id = v_app.linked_application_id;
  IF NOT FOUND THEN RETURN json_build_object('error', 'Sibling application not found'); END IF;

  IF v_app.role_applied = 'researcher' AND v_sibling_app.role_applied = 'leader' THEN
    v_researcher_app_id := v_app.id;
    v_leader_app_id     := v_sibling_app.id;
  ELSIF v_app.role_applied = 'leader' AND v_sibling_app.role_applied = 'researcher' THEN
    v_researcher_app_id := v_sibling_app.id;
    v_leader_app_id     := v_app.id;
  ELSE
    RETURN json_build_object('error', 'Pair roles are not researcher+leader (' || v_app.role_applied || ' + ' || v_sibling_app.role_applied || ')');
  END IF;

  -- Auto-copy role-agnostic scores BEFORE applying decisions
  SELECT id, objective_score_avg, interview_score INTO v_scored
  FROM   public.selection_applications
  WHERE  id IN (v_researcher_app_id, v_leader_app_id)
    AND  objective_score_avg IS NOT NULL
  ORDER BY (CASE WHEN id = v_leader_app_id THEN 0 ELSE 1 END)
  LIMIT 1;

  IF FOUND THEN
    v_unscored_id := CASE WHEN v_scored.id = v_researcher_app_id THEN v_leader_app_id ELSE v_researcher_app_id END;

    UPDATE public.selection_applications
    SET    objective_score_avg = COALESCE(objective_score_avg, v_scored.objective_score_avg),
           interview_score     = COALESCE(interview_score,     v_scored.interview_score),
           updated_at          = now()
    WHERE  id = v_unscored_id
      AND  (objective_score_avg IS NULL OR interview_score IS NULL);

    IF FOUND THEN v_copied_scores := true; END IF;
  END IF;

  v_researcher_result := public.admin_update_application(
    v_researcher_app_id,
    jsonb_build_object(
      'status',   p_researcher_decision,
      'feedback', COALESCE(p_feedback, '')
    )
  );

  v_leader_result := public.admin_update_application(
    v_leader_app_id,
    jsonb_build_object(
      'status',   p_leader_decision,
      'feedback', COALESCE(p_feedback, '')
    )
  );

  INSERT INTO public.data_anomaly_log (anomaly_type, severity, description, context)
  VALUES (
    'selection_dual_track_decision',
    'info',
    v_app.applicant_name || ': researcher=' || p_researcher_decision || ', leader=' || p_leader_decision,
    jsonb_build_object(
      'researcher_app_id',  v_researcher_app_id,
      'leader_app_id',      v_leader_app_id,
      'researcher_decision', p_researcher_decision,
      'leader_decision',    p_leader_decision,
      'scores_copied',      v_copied_scores,
      'feedback',           p_feedback,
      'caller_id',          v_caller_id
    )
  );

  RETURN json_build_object(
    'success',             true,
    'researcher_app_id',   v_researcher_app_id,
    'leader_app_id',       v_leader_app_id,
    'researcher_decision', p_researcher_decision,
    'leader_decision',     p_leader_decision,
    'scores_copied',       v_copied_scores,
    'researcher_result',   v_researcher_result,
    'leader_result',       v_leader_result
  );
END;
$function$;

COMMENT ON FUNCTION public.admin_decide_dual_track(uuid, text, text, text) IS
  'Cross-role decision for dual_track candidate pairs. Resolves pair from either application_id, auto-copies role-agnostic scores (objective + interview), then applies each per-role decision via admin_update_application (preserving onboarding seed, Op B promote, notification, audit). Single transaction. p158 F2 (2026-05-14).';

GRANT EXECUTE ON FUNCTION public.admin_decide_dual_track(uuid, text, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
