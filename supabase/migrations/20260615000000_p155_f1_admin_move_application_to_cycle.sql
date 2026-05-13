-- p155 F1: RPC admin_move_application_to_cycle
-- Purpose: move a selection_application from one cycle to another, preserving children (evaluations,
-- interviews, AI runs etc which FK by application_id) but clearing rankings (recomputed at target).
-- Driver: PM directive p155 (2026-05-13) — Luciana Carpes Pranke cycle3-2026-b2 → cycle4-2026 pool.
-- Gate: manage_platform (V4 can_by_member). Audit: data_anomaly_log (same pattern as admin_update_application).
-- Rollback: SELECT admin_move_application_to_cycle(<app_id>, <prior_cycle_id>, 'rollback');

CREATE OR REPLACE FUNCTION public.admin_move_application_to_cycle(
  p_application_id uuid,
  p_target_cycle_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_name text;
  v_app record;
  v_target_cycle record;
  v_old_cycle_code text;
BEGIN
  SELECT id, name INTO v_caller_id, v_caller_name FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN json_build_object('error', 'Unauthorized');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN json_build_object('error', 'Unauthorized');
  END IF;

  SELECT * INTO v_app FROM selection_applications WHERE id = p_application_id;
  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Application not found');
  END IF;

  SELECT * INTO v_target_cycle FROM selection_cycles WHERE id = p_target_cycle_id;
  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Target cycle not found');
  END IF;
  IF v_target_cycle.status <> 'open' THEN
    RETURN json_build_object('error', 'Target cycle is not open: ' || v_target_cycle.status);
  END IF;
  IF v_app.cycle_id = p_target_cycle_id THEN
    RETURN json_build_object('error', 'Application already in target cycle (no-op)');
  END IF;

  SELECT cycle_code INTO v_old_cycle_code FROM selection_cycles WHERE id = v_app.cycle_id;

  UPDATE selection_applications SET
    cycle_id        = p_target_cycle_id,
    rank_chapter    = NULL,
    rank_overall    = NULL,
    rank_researcher = NULL,
    rank_leader     = NULL,
    updated_at      = now()
  WHERE id = p_application_id;

  INSERT INTO data_anomaly_log (anomaly_type, severity, description, context)
  VALUES (
    'application_cycle_move',
    'info',
    'Application ' || v_app.applicant_name || ' moved: ' || coalesce(v_old_cycle_code, '?') || ' → ' || v_target_cycle.cycle_code,
    jsonb_build_object(
      'application_id', p_application_id,
      'old_cycle_id',   v_app.cycle_id,
      'old_cycle_code', v_old_cycle_code,
      'new_cycle_id',   p_target_cycle_id,
      'new_cycle_code', v_target_cycle.cycle_code,
      'reason',         coalesce(p_reason, '(no reason given)'),
      'actor',          v_caller_name,
      'children_preserved', jsonb_build_object(
        'evaluations',  (SELECT count(*) FROM selection_evaluations WHERE application_id = p_application_id),
        'interviews',   (SELECT count(*) FROM selection_interviews  WHERE application_id = p_application_id),
        'ai_runs',      (SELECT count(*) FROM ai_analysis_runs      WHERE application_id = p_application_id)
      )
    )
  );

  RETURN json_build_object(
    'success',        true,
    'application_id', p_application_id,
    'applicant_name', v_app.applicant_name,
    'old_cycle_code', v_old_cycle_code,
    'new_cycle_code', v_target_cycle.cycle_code,
    'note',           'Rankings cleared; run recalculate_cycle_rankings + calculate_rankings on both source and target cycles'
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.admin_move_application_to_cycle(uuid, uuid, text) FROM PUBLIC, anon;

COMMENT ON FUNCTION public.admin_move_application_to_cycle(uuid, uuid, text) IS
  'Move a selection_application from one open cycle to another. Children (evaluations, interviews, AI runs) preserved via FK on application_id. Rankings cleared (must run recalculate_cycle_rankings + calculate_rankings on both cycles after). Gated by manage_platform. Audit in data_anomaly_log. p155 F1 (2026-05-13) for Luciana Carpes Pranke cycle3-2026-b2 → cycle4-2026.';
