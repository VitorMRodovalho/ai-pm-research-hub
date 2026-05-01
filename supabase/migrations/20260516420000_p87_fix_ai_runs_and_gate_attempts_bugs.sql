-- ============================================================================
-- p87 BUG FIX — get_application_ai_analysis_runs + get_application_gate_attempts
-- ============================================================================
-- Bug 1: get_application_ai_analysis_runs references tv.ip + tv.ua but
--        selection_topic_views columns are ip_address + user_agent.
-- Bug 2: get_application_gate_attempts RETURNS TABLE (id uuid, ...) creates
--        PL/pgSQL OUT variable that conflicts with gate_attempts.id even
--        when qualified — PostgreSQL raises "column reference id is ambiguous"
--        in some plpgsql contexts. Fix: rename OUT 'id' → 'attempt_id'.
--        Frontend does not use the id field, so no UI breaking change.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_application_ai_analysis_runs(p_application_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_committee record;
  v_runs jsonb;
  v_topics_views jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id
    AND member_id = v_caller.id
    AND role IN ('lead','member');

  IF v_committee IS NULL
     AND NOT public.can_by_member(v_caller.id, 'manage_member'::text)
     AND NOT public.can_by_member(v_caller.id, 'view_internal_analytics'::text) THEN
    RAISE EXCEPTION 'Unauthorized: must be committee member or have manage_member/view_internal_analytics';
  END IF;

  SELECT jsonb_agg(
    jsonb_build_object(
      'id', r.id,
      'run_index', r.run_index,
      'triggered_by', r.triggered_by,
      'status', r.status,
      'ai_analysis_snapshot', r.ai_analysis_snapshot,
      'fields_changed', r.fields_changed,
      'model_version', r.model_version,
      'input_token_estimate', r.input_token_estimate,
      'output_token_estimate', r.output_token_estimate,
      'duration_ms', r.duration_ms,
      'error_message', r.error_message,
      'started_at', r.started_at,
      'completed_at', r.completed_at
    )
    ORDER BY r.run_index DESC
  ) INTO v_runs
  FROM public.ai_analysis_runs r
  WHERE r.application_id = p_application_id;

  SELECT jsonb_build_object(
    'count', count(*),
    'first_view_at', min(viewed_at),
    'last_view_at', max(viewed_at),
    'samples', (
      SELECT jsonb_agg(jsonb_build_object(
        'viewed_at', tv.viewed_at,
        'ip', tv.ip_address::text,
        'ua_excerpt', left(tv.user_agent, 60)
      ) ORDER BY tv.viewed_at DESC)
      FROM (
        SELECT viewed_at, ip_address, user_agent FROM public.selection_topic_views
        WHERE application_id = p_application_id
        ORDER BY viewed_at DESC LIMIT 5
      ) tv
    )
  ) INTO v_topics_views
  FROM public.selection_topic_views
  WHERE application_id = p_application_id;

  RETURN jsonb_build_object(
    'application_id', p_application_id,
    'enrichment_count', v_app.enrichment_count,
    'last_enrichment_at', v_app.last_enrichment_at,
    'runs', COALESCE(v_runs, '[]'::jsonb),
    'topics_views', v_topics_views
  );
END;
$function$;

DROP FUNCTION IF EXISTS public.get_application_gate_attempts(uuid);

CREATE OR REPLACE FUNCTION public.get_application_gate_attempts(
  p_application_id uuid
) RETURNS TABLE (
  attempt_id uuid,
  rpc_name text,
  caller_name text,
  gate_passed boolean,
  gate_failed_code text,
  gate_failed_reason text,
  bypass_requested boolean,
  bypass_granted boolean,
  payload jsonb,
  attempted_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_committee record;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;

  IF v_committee IS NULL
     AND NOT public.can_by_member(v_caller.id, 'manage_member'::text)
     AND NOT public.can_by_member(v_caller.id, 'view_internal_analytics'::text)
  THEN
    RAISE EXCEPTION 'Unauthorized: must be committee member or have manage_member/view_internal_analytics';
  END IF;

  RETURN QUERY
  SELECT ga.id AS attempt_id, ga.rpc_name,
         m.name AS caller_name,
         ga.gate_passed, ga.gate_failed_code, ga.gate_failed_reason,
         ga.bypass_requested, ga.bypass_granted,
         ga.payload, ga.attempted_at
  FROM public.gate_attempts ga
  LEFT JOIN public.members m ON m.id = ga.caller_id
  WHERE ga.application_id = p_application_id
  ORDER BY ga.attempted_at DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_application_gate_attempts(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_application_gate_attempts(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
