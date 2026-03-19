-- ============================================================
-- P1-5: Pilots CRUD RPCs + RLS write policies
-- ============================================================

-- 1. RLS write policies for admin
CREATE POLICY "Admins can insert pilots" ON public.pilots
  FOR INSERT TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid()
      AND (m.is_superadmin = true OR m.operational_role IN ('manager', 'deputy_manager')))
  );

CREATE POLICY "Admins can update pilots" ON public.pilots
  FOR UPDATE TO authenticated USING (
    EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid()
      AND (m.is_superadmin = true OR m.operational_role IN ('manager', 'deputy_manager')))
  );

CREATE POLICY "Admins can delete pilots" ON public.pilots
  FOR DELETE TO authenticated USING (
    EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid()
      AND (m.is_superadmin = true OR m.operational_role IN ('manager', 'deputy_manager')))
  );

-- 2. Create pilot RPC
CREATE OR REPLACE FUNCTION public.create_pilot(
  p_title text,
  p_hypothesis text DEFAULT NULL,
  p_problem_statement text DEFAULT NULL,
  p_scope text DEFAULT NULL,
  p_status text DEFAULT 'draft',
  p_tribe_id integer DEFAULT NULL,
  p_board_id uuid DEFAULT NULL,
  p_success_metrics jsonb DEFAULT '[]',
  p_team_member_ids uuid[] DEFAULT '{}'
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_caller_id uuid;
  v_next_number integer;
  v_new_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid()
    AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager'));
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Admin only'; END IF;

  SELECT COALESCE(MAX(pilot_number), 0) + 1 INTO v_next_number FROM pilots;

  INSERT INTO pilots (pilot_number, title, hypothesis, problem_statement, scope, status, tribe_id, board_id, success_metrics, team_member_ids, created_by, started_at)
  VALUES (v_next_number, p_title, p_hypothesis, p_problem_statement, p_scope, p_status, p_tribe_id, p_board_id, p_success_metrics, p_team_member_ids, v_caller_id,
    CASE WHEN p_status = 'active' THEN CURRENT_DATE ELSE NULL END)
  RETURNING id INTO v_new_id;

  RETURN jsonb_build_object('success', true, 'id', v_new_id, 'pilot_number', v_next_number);
END; $$;

-- 3. Update pilot RPC
CREATE OR REPLACE FUNCTION public.update_pilot(
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
  p_lessons_learned jsonb DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_caller_id uuid;
  v_old_status text;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid()
    AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager'));
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Admin only'; END IF;

  SELECT status INTO v_old_status FROM pilots WHERE id = p_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Pilot not found'); END IF;

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
      WHEN COALESCE(p_status, status) = 'active' AND started_at IS NULL THEN CURRENT_DATE
      ELSE started_at END,
    completed_at = CASE
      WHEN COALESCE(p_status, status) IN ('completed', 'cancelled') AND completed_at IS NULL THEN CURRENT_DATE
      ELSE completed_at END,
    updated_at = now()
  WHERE id = p_id;

  RETURN jsonb_build_object('success', true);
END; $$;

-- 4. Delete pilot RPC
CREATE OR REPLACE FUNCTION public.delete_pilot(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM members WHERE auth_id = auth.uid()
    AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager'))) THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  DELETE FROM pilots WHERE id = p_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Pilot not found'); END IF;

  RETURN jsonb_build_object('success', true);
END; $$;
