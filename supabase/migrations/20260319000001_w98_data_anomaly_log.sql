-- ═══════════════════════════════════════════════════════════════════════════
-- W98 — Data Sanity Remediation: Anomaly Detection + Auto-Fix
-- Date: 2026-03-12
-- Purpose: Automated detection and remediation of data inconsistencies
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ─── Table: data_anomaly_log ───
CREATE TABLE IF NOT EXISTS public.data_anomaly_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  anomaly_type text NOT NULL,
  severity text NOT NULL DEFAULT 'warning',
  member_id uuid REFERENCES public.members(id),
  description text NOT NULL,
  auto_fixable boolean DEFAULT false,
  auto_fixed boolean DEFAULT false,
  fixed_at timestamptz,
  fixed_by text,
  context jsonb DEFAULT '{}',
  detected_at timestamptz DEFAULT now(),
  CONSTRAINT chk_severity CHECK (severity IN ('critical', 'warning', 'info'))
);

CREATE INDEX IF NOT EXISTS idx_anomaly_type ON public.data_anomaly_log(anomaly_type);
CREATE INDEX IF NOT EXISTS idx_anomaly_severity ON public.data_anomaly_log(severity);
CREATE INDEX IF NOT EXISTS idx_anomaly_pending ON public.data_anomaly_log(auto_fixed) WHERE auto_fixed = false;

COMMENT ON TABLE public.data_anomaly_log IS 'Audit trail for detected data anomalies and their resolution status';

ALTER TABLE public.data_anomaly_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin_read_anomalies" ON public.data_anomaly_log
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND (m.is_superadmin = true OR m.operational_role IN ('manager', 'deputy_manager'))
    )
  );

CREATE POLICY "admin_write_anomalies" ON public.data_anomaly_log
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND (m.is_superadmin = true OR m.operational_role IN ('manager', 'deputy_manager'))
    )
  );

-- ─── RPC: admin_detect_data_anomalies ───
CREATE OR REPLACE FUNCTION public.admin_detect_data_anomalies(p_auto_fix boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller record;
  v_fixed jsonb[] := '{}';
  v_pending jsonb[] := '{}';
  v_rec record;
  v_anomaly_id uuid;
  v_current_cycle text;
  v_counts jsonb;
BEGIN
  -- Admin check
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND OR (v_caller.is_superadmin IS NOT TRUE AND v_caller.operational_role NOT IN ('manager', 'deputy_manager')) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- Get current cycle code
  SELECT code INTO v_current_cycle FROM public.cycles WHERE is_current = true LIMIT 1;
  IF v_current_cycle IS NULL THEN
    v_current_cycle := 'cycle3-2026';
  END IF;

  -- ─── 1. tribe_selection_drift ───
  FOR v_rec IN
    SELECT m.id AS member_id, m.name, m.tribe_id AS member_tribe, ts.tribe_id AS selection_tribe
    FROM public.members m
    JOIN public.tribe_selections ts ON ts.member_id = m.id
    WHERE m.tribe_id IS DISTINCT FROM ts.tribe_id
      AND m.current_cycle_active = true
  LOOP
    v_anomaly_id := gen_random_uuid();
    INSERT INTO public.data_anomaly_log (id, anomaly_type, severity, member_id, description, auto_fixable, context)
    VALUES (v_anomaly_id, 'tribe_selection_drift', 'warning', v_rec.member_id,
      format('Member %s: members.tribe_id=%s differs from tribe_selections.tribe_id=%s',
        v_rec.name, v_rec.member_tribe, v_rec.selection_tribe),
      true,
      jsonb_build_object('member_tribe_id', v_rec.member_tribe, 'selection_tribe_id', v_rec.selection_tribe));

    IF p_auto_fix THEN
      UPDATE public.members SET tribe_id = v_rec.selection_tribe, updated_at = now()
      WHERE id = v_rec.member_id;
      UPDATE public.data_anomaly_log SET auto_fixed = true, fixed_at = now(), fixed_by = 'auto'
      WHERE id = v_anomaly_id;
      v_fixed := v_fixed || jsonb_build_object('type', 'tribe_selection_drift', 'member_id', v_rec.member_id);
    ELSE
      v_pending := v_pending || jsonb_build_object('type', 'tribe_selection_drift', 'member_id', v_rec.member_id);
    END IF;
  END LOOP;

  -- ─── 2. active_flag_inconsistency ───
  FOR v_rec IN
    SELECT m.id AS member_id, m.name, m.is_active, m.current_cycle_active, m.operational_role
    FROM public.members m
    WHERE m.is_active = false AND m.current_cycle_active = true
      AND (m.operational_role IS NULL OR m.operational_role = 'none' OR m.operational_role = '')
  LOOP
    v_anomaly_id := gen_random_uuid();
    INSERT INTO public.data_anomaly_log (id, anomaly_type, severity, member_id, description, auto_fixable, context)
    VALUES (v_anomaly_id, 'active_flag_inconsistency', 'warning', v_rec.member_id,
      format('Member %s: is_active=false but current_cycle_active=true with no operational role', v_rec.name),
      true,
      jsonb_build_object('is_active', v_rec.is_active, 'current_cycle_active', v_rec.current_cycle_active));

    IF p_auto_fix THEN
      UPDATE public.members SET current_cycle_active = false, updated_at = now()
      WHERE id = v_rec.member_id;
      UPDATE public.data_anomaly_log SET auto_fixed = true, fixed_at = now(), fixed_by = 'auto'
      WHERE id = v_anomaly_id;
      v_fixed := v_fixed || jsonb_build_object('type', 'active_flag_inconsistency', 'member_id', v_rec.member_id);
    ELSE
      v_pending := v_pending || jsonb_build_object('type', 'active_flag_inconsistency', 'member_id', v_rec.member_id);
    END IF;
  END LOOP;

  -- ─── 3. role_designation_mismatch (info, NOT auto-fixable) ───
  FOR v_rec IN
    SELECT m.id AS member_id, m.name, m.operational_role, m.designations
    FROM public.members m
    WHERE (m.operational_role IS NULL OR m.operational_role = 'none' OR m.operational_role = '')
      AND m.designations IS NOT NULL
      AND m.designations::text != '[]'
      AND m.designations::text != 'null'
      AND jsonb_array_length(m.designations) > 0
      AND m.current_cycle_active = true
  LOOP
    INSERT INTO public.data_anomaly_log (anomaly_type, severity, member_id, description, auto_fixable, context)
    VALUES ('role_designation_mismatch', 'info', v_rec.member_id,
      format('Member %s: operational_role is none but has designations %s', v_rec.name, v_rec.designations),
      false,
      jsonb_build_object('operational_role', v_rec.operational_role, 'designations', v_rec.designations));
    v_pending := v_pending || jsonb_build_object('type', 'role_designation_mismatch', 'member_id', v_rec.member_id);
  END LOOP;

  -- ─── 4. orphan_active_no_tribe (NOT auto-fixable) ───
  FOR v_rec IN
    SELECT m.id AS member_id, m.name, m.created_at
    FROM public.members m
    WHERE m.current_cycle_active = true
      AND m.tribe_id IS NULL
      AND m.created_at < (now() - interval '30 days')
  LOOP
    INSERT INTO public.data_anomaly_log (anomaly_type, severity, member_id, description, auto_fixable, context)
    VALUES ('orphan_active_no_tribe', 'warning', v_rec.member_id,
      format('Member %s: active with no tribe for over 30 days', v_rec.name),
      false,
      jsonb_build_object('created_at', v_rec.created_at));
    v_pending := v_pending || jsonb_build_object('type', 'orphan_active_no_tribe', 'member_id', v_rec.member_id);
  END LOOP;

  -- ─── 5. cycle_array_stale ───
  FOR v_rec IN
    SELECT m.id AS member_id, m.name, m.cycles
    FROM public.members m
    WHERE m.current_cycle_active = true
      AND m.cycles IS NOT NULL
      AND NOT (m.cycles ? v_current_cycle)
  LOOP
    v_anomaly_id := gen_random_uuid();
    INSERT INTO public.data_anomaly_log (id, anomaly_type, severity, member_id, description, auto_fixable, context)
    VALUES (v_anomaly_id, 'cycle_array_stale', 'info', v_rec.member_id,
      format('Member %s: current_cycle_active=true but cycles array does not include %s', v_rec.name, v_current_cycle),
      true,
      jsonb_build_object('cycles', v_rec.cycles, 'expected_cycle', v_current_cycle));

    IF p_auto_fix THEN
      UPDATE public.members
      SET cycles = CASE
        WHEN cycles IS NULL THEN jsonb_build_array(v_current_cycle)
        ELSE cycles || to_jsonb(v_current_cycle)
      END, updated_at = now()
      WHERE id = v_rec.member_id;
      UPDATE public.data_anomaly_log SET auto_fixed = true, fixed_at = now(), fixed_by = 'auto'
      WHERE id = v_anomaly_id;
      v_fixed := v_fixed || jsonb_build_object('type', 'cycle_array_stale', 'member_id', v_rec.member_id);
    ELSE
      v_pending := v_pending || jsonb_build_object('type', 'cycle_array_stale', 'member_id', v_rec.member_id);
    END IF;
  END LOOP;

  -- ─── 6. duplicate_email (critical, NOT auto-fixable) ───
  FOR v_rec IN
    SELECT m.email, array_agg(m.id) AS member_ids, count(*) AS cnt
    FROM public.members m
    WHERE m.email IS NOT NULL AND m.email != ''
    GROUP BY m.email
    HAVING count(*) > 1
  LOOP
    INSERT INTO public.data_anomaly_log (anomaly_type, severity, description, auto_fixable, context)
    VALUES ('duplicate_email', 'critical',
      format('Duplicate email %s found in %s members', v_rec.email, v_rec.cnt),
      false,
      jsonb_build_object('email', v_rec.email, 'member_ids', to_jsonb(v_rec.member_ids), 'count', v_rec.cnt));
    v_pending := v_pending || jsonb_build_object('type', 'duplicate_email', 'email', v_rec.email);
  END LOOP;

  -- ─── 7. never_logged_in (info, NOT auto-fixable) ───
  FOR v_rec IN
    SELECT m.id AS member_id, m.name, m.created_at
    FROM public.members m
    WHERE m.auth_id IS NULL
      AND m.created_at < (now() - interval '60 days')
      AND m.current_cycle_active = true
  LOOP
    INSERT INTO public.data_anomaly_log (anomaly_type, severity, member_id, description, auto_fixable, context)
    VALUES ('never_logged_in', 'info', v_rec.member_id,
      format('Member %s: created over 60 days ago but never logged in', v_rec.name),
      false,
      jsonb_build_object('created_at', v_rec.created_at));
    v_pending := v_pending || jsonb_build_object('type', 'never_logged_in', 'member_id', v_rec.member_id);
  END LOOP;

  -- ─── 8. assignment_orphan ───
  FOR v_rec IN
    SELECT bia.id AS assignment_id, bia.member_id, bia.item_id, m.name
    FROM public.board_item_assignments bia
    JOIN public.members m ON m.id = bia.member_id
    WHERE m.is_active = false
  LOOP
    v_anomaly_id := gen_random_uuid();
    INSERT INTO public.data_anomaly_log (id, anomaly_type, severity, member_id, description, auto_fixable, context)
    VALUES (v_anomaly_id, 'assignment_orphan', 'warning', v_rec.member_id,
      format('Inactive member %s still assigned to board item %s', v_rec.name, v_rec.item_id),
      true,
      jsonb_build_object('assignment_id', v_rec.assignment_id, 'item_id', v_rec.item_id));

    IF p_auto_fix THEN
      DELETE FROM public.board_item_assignments WHERE id = v_rec.assignment_id;
      UPDATE public.data_anomaly_log SET auto_fixed = true, fixed_at = now(), fixed_by = 'auto'
      WHERE id = v_anomaly_id;
      v_fixed := v_fixed || jsonb_build_object('type', 'assignment_orphan', 'member_id', v_rec.member_id);
    ELSE
      v_pending := v_pending || jsonb_build_object('type', 'assignment_orphan', 'member_id', v_rec.member_id);
    END IF;
  END LOOP;

  -- ─── 9. sla_config_missing ───
  FOR v_rec IN
    SELECT pb.id AS board_id, pb.title
    FROM public.project_boards pb
    WHERE pb.is_active = true
      AND NOT EXISTS (SELECT 1 FROM public.board_sla_config bsc WHERE bsc.board_id = pb.id)
  LOOP
    v_anomaly_id := gen_random_uuid();
    INSERT INTO public.data_anomaly_log (id, anomaly_type, severity, description, auto_fixable, context)
    VALUES (v_anomaly_id, 'sla_config_missing', 'warning',
      format('Active board "%s" has no SLA configuration', v_rec.title),
      true,
      jsonb_build_object('board_id', v_rec.board_id, 'board_title', v_rec.title));

    IF p_auto_fix THEN
      INSERT INTO public.board_sla_config (board_id) VALUES (v_rec.board_id)
      ON CONFLICT (board_id) DO NOTHING;
      UPDATE public.data_anomaly_log SET auto_fixed = true, fixed_at = now(), fixed_by = 'auto'
      WHERE id = v_anomaly_id;
      v_fixed := v_fixed || jsonb_build_object('type', 'sla_config_missing', 'board_id', v_rec.board_id);
    ELSE
      v_pending := v_pending || jsonb_build_object('type', 'sla_config_missing', 'board_id', v_rec.board_id);
    END IF;
  END LOOP;

  -- Build summary
  v_counts := jsonb_build_object(
    'total', array_length(v_fixed, 1) + array_length(v_pending, 1),
    'fixed', array_length(v_fixed, 1),
    'pending', array_length(v_pending, 1),
    'by_severity', (
      SELECT jsonb_build_object(
        'critical', count(*) FILTER (WHERE severity = 'critical'),
        'warning', count(*) FILTER (WHERE severity = 'warning'),
        'info', count(*) FILTER (WHERE severity = 'info')
      )
      FROM public.data_anomaly_log
      WHERE auto_fixed = false
    )
  );

  RETURN jsonb_build_object(
    'fixed', to_jsonb(v_fixed),
    'pending', to_jsonb(v_pending),
    'summary', v_counts
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_detect_data_anomalies(boolean) TO authenticated;

-- ─── RPC: admin_get_anomaly_report ───
CREATE OR REPLACE FUNCTION public.admin_get_anomaly_report()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller record;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND OR (v_caller.is_superadmin IS NOT TRUE AND v_caller.operational_role NOT IN ('manager', 'deputy_manager')) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT jsonb_build_object(
    'pending', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', d.id,
          'anomaly_type', d.anomaly_type,
          'severity', d.severity,
          'member_id', d.member_id,
          'description', d.description,
          'auto_fixable', d.auto_fixable,
          'context', d.context,
          'detected_at', d.detected_at
        ) ORDER BY
          CASE d.severity WHEN 'critical' THEN 0 WHEN 'warning' THEN 1 ELSE 2 END,
          d.detected_at DESC
      )
      FROM public.data_anomaly_log d
      WHERE d.auto_fixed = false
    ), '[]'::jsonb),
    'history', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', d.id,
          'anomaly_type', d.anomaly_type,
          'severity', d.severity,
          'description', d.description,
          'fixed_at', d.fixed_at,
          'fixed_by', d.fixed_by
        ) ORDER BY d.fixed_at DESC
      )
      FROM public.data_anomaly_log d
      WHERE d.auto_fixed = true
      LIMIT 50
    ), '[]'::jsonb),
    'summary', jsonb_build_object(
      'total_pending', (SELECT count(*) FROM public.data_anomaly_log WHERE auto_fixed = false),
      'total_fixed', (SELECT count(*) FROM public.data_anomaly_log WHERE auto_fixed = true),
      'by_type', COALESCE((
        SELECT jsonb_object_agg(anomaly_type, cnt)
        FROM (
          SELECT anomaly_type, count(*) AS cnt
          FROM public.data_anomaly_log
          WHERE auto_fixed = false
          GROUP BY anomaly_type
        ) sub
      ), '{}'::jsonb),
      'by_severity', COALESCE((
        SELECT jsonb_object_agg(severity, cnt)
        FROM (
          SELECT severity, count(*) AS cnt
          FROM public.data_anomaly_log
          WHERE auto_fixed = false
          GROUP BY severity
        ) sub
      ), '{}'::jsonb)
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_anomaly_report() TO authenticated;

-- ─── RPC: admin_resolve_anomaly (manual resolution) ───
CREATE OR REPLACE FUNCTION public.admin_resolve_anomaly(p_anomaly_id uuid, p_notes text DEFAULT '')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller record;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND OR (v_caller.is_superadmin IS NOT TRUE AND v_caller.operational_role NOT IN ('manager', 'deputy_manager')) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  UPDATE public.data_anomaly_log
  SET auto_fixed = true,
      fixed_at = now(),
      fixed_by = v_caller.name,
      context = context || jsonb_build_object('resolution_notes', p_notes)
  WHERE id = p_anomaly_id AND auto_fixed = false;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Anomaly not found or already resolved');
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_resolve_anomaly(uuid, text) TO authenticated;

COMMIT;
