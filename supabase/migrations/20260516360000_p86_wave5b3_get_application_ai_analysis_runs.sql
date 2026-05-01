-- p86 Wave 5b-3: RPC supports admin diff UI in modal admin/selection.
-- Returns timeline of ai_analysis_runs + topics-viewed audit count for one application.
-- V4 authority: committee (lead/member) OR manage_member OR view_internal_analytics.

DROP FUNCTION IF EXISTS public.get_application_ai_analysis_runs(uuid);
CREATE FUNCTION public.get_application_ai_analysis_runs(p_application_id uuid)
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

  -- Topics-viewed audit (informational only — non-penalizing)
  SELECT jsonb_build_object(
    'count', count(*),
    'first_view_at', min(viewed_at),
    'last_view_at', max(viewed_at),
    'samples', (
      SELECT jsonb_agg(jsonb_build_object(
        'viewed_at', tv.viewed_at,
        'ip', tv.ip::text,
        'ua_excerpt', left(tv.ua, 60)
      ) ORDER BY tv.viewed_at DESC)
      FROM (
        SELECT viewed_at, ip, ua FROM public.selection_topic_views
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

GRANT EXECUTE ON FUNCTION public.get_application_ai_analysis_runs(uuid) TO authenticated;

COMMENT ON FUNCTION public.get_application_ai_analysis_runs(uuid) IS
  'p86 Wave 5b-3: returns ai_analysis_runs timeline + topics-viewed audit for committee admin diff UI. V4 manage_member or view_internal_analytics or committee member.';

NOTIFY pgrst, 'reload schema';
