-- GC-101: Add p_started_at / p_completed_at params to update_pilot RPC
-- Allows manual date editing from the admin modal

DROP FUNCTION IF EXISTS update_pilot(uuid, text, text, text, text, text, integer, uuid, jsonb, uuid[], jsonb);
CREATE FUNCTION update_pilot(
  p_id uuid,
  p_title text DEFAULT NULL,
  p_hypothesis text DEFAULT NULL,
  p_problem_statement text DEFAULT NULL,
  p_scope text DEFAULT NULL,
  p_status text DEFAULT NULL,
  p_tribe_id integer DEFAULT NULL,
  p_board_id uuid DEFAULT NULL,
  p_success_metrics jsonb DEFAULT NULL,
  p_team_member_ids uuid[] DEFAULT NULL,
  p_lessons_learned jsonb DEFAULT NULL,
  p_started_at date DEFAULT NULL,
  p_completed_at date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid() AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager'));
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Admin only'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pilots WHERE id = p_id) THEN RETURN jsonb_build_object('success', false, 'error', 'Pilot not found'); END IF;
  UPDATE pilots SET
    title = COALESCE(p_title, title),
    hypothesis = COALESCE(p_hypothesis, hypothesis),
    problem_statement = COALESCE(p_problem_statement, problem_statement),
    scope = COALESCE(p_scope, scope),
    status = COALESCE(p_status, status),
    tribe_id = COALESCE(p_tribe_id, tribe_id),
    board_id = COALESCE(p_board_id, board_id),
    success_metrics = COALESCE(p_success_metrics, success_metrics),
    team_member_ids = COALESCE(p_team_member_ids, team_member_ids),
    lessons_learned = COALESCE(p_lessons_learned, lessons_learned),
    started_at = CASE
      WHEN p_started_at IS NOT NULL THEN p_started_at
      WHEN COALESCE(p_status, status) = 'active' AND started_at IS NULL THEN CURRENT_DATE
      ELSE started_at
    END,
    completed_at = CASE
      WHEN p_completed_at IS NOT NULL THEN p_completed_at
      WHEN COALESCE(p_status, status) IN ('completed', 'cancelled') AND completed_at IS NULL THEN CURRENT_DATE
      ELSE completed_at
    END,
    updated_at = now()
  WHERE id = p_id;
  RETURN jsonb_build_object('success', true);
END;
$$;

NOTIFY pgrst, 'reload schema';
