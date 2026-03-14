-- ============================================================================
-- W125: Security & LGPD Hardening
-- Hardening only — zero new features
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- P0-A: EXPLICIT RLS POLICIES ON TABLES ACCESSED ONLY VIA RPCs
-- Pattern A — deny-all direct access, all operations through SECURITY DEFINER
-- ─────────────────────────────────────────────────────────────────────────────

-- selection_cycles
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'selection_cycles' AND policyname = 'rpc_only_deny_all') THEN
    CREATE POLICY "rpc_only_deny_all" ON public.selection_cycles FOR ALL USING (false);
  END IF;
END $$;

-- selection_committee
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'selection_committee' AND policyname = 'rpc_only_deny_all') THEN
    CREATE POLICY "rpc_only_deny_all" ON public.selection_committee FOR ALL USING (false);
  END IF;
END $$;

-- selection_applications
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'selection_applications' AND policyname = 'rpc_only_deny_all') THEN
    CREATE POLICY "rpc_only_deny_all" ON public.selection_applications FOR ALL USING (false);
  END IF;
END $$;

-- selection_evaluations
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'selection_evaluations' AND policyname = 'rpc_only_deny_all') THEN
    CREATE POLICY "rpc_only_deny_all" ON public.selection_evaluations FOR ALL USING (false);
  END IF;
END $$;

-- selection_interviews
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'selection_interviews' AND policyname = 'rpc_only_deny_all') THEN
    CREATE POLICY "rpc_only_deny_all" ON public.selection_interviews FOR ALL USING (false);
  END IF;
END $$;

-- selection_diversity_snapshots
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'selection_diversity_snapshots' AND policyname = 'rpc_only_deny_all') THEN
    CREATE POLICY "rpc_only_deny_all" ON public.selection_diversity_snapshots FOR ALL USING (false);
  END IF;
END $$;

-- onboarding_progress
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'onboarding_progress' AND policyname = 'rpc_only_deny_all') THEN
    CREATE POLICY "rpc_only_deny_all" ON public.onboarding_progress FOR ALL USING (false);
  END IF;
END $$;

-- Additional tables discovered without RLS
ALTER TABLE IF EXISTS public.board_source_tribe_map ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.board_taxonomy_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.knowledge_insights_ingestion_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.member_chapter_affiliations ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.member_cycle_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.portfolio_data_sanity_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.publication_submission_events ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'board_source_tribe_map' AND policyname = 'rpc_only_deny_all') THEN
    CREATE POLICY "rpc_only_deny_all" ON public.board_source_tribe_map FOR ALL USING (false);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'board_taxonomy_alerts' AND policyname = 'rpc_only_deny_all') THEN
    CREATE POLICY "rpc_only_deny_all" ON public.board_taxonomy_alerts FOR ALL USING (false);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'knowledge_insights_ingestion_log' AND policyname = 'rpc_only_deny_all') THEN
    CREATE POLICY "rpc_only_deny_all" ON public.knowledge_insights_ingestion_log FOR ALL USING (false);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'member_chapter_affiliations' AND policyname = 'rpc_only_deny_all') THEN
    CREATE POLICY "rpc_only_deny_all" ON public.member_chapter_affiliations FOR ALL USING (false);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'member_cycle_history' AND policyname = 'rpc_only_deny_all') THEN
    CREATE POLICY "rpc_only_deny_all" ON public.member_cycle_history FOR ALL USING (false);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'portfolio_data_sanity_runs' AND policyname = 'rpc_only_deny_all') THEN
    CREATE POLICY "rpc_only_deny_all" ON public.portfolio_data_sanity_runs FOR ALL USING (false);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'publication_submission_events' AND policyname = 'rpc_only_deny_all') THEN
    CREATE POLICY "rpc_only_deny_all" ON public.publication_submission_events FOR ALL USING (false);
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- P0-B: SECURITY DEFINER AUTH FIXES — create_event
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.create_event(text, text, date, int, uuid, text);

CREATE OR REPLACE FUNCTION public.create_event(
  p_type             text,
  p_title            text,
  p_date             date,
  p_duration_minutes int      DEFAULT 90,
  p_tribe_id         uuid     DEFAULT NULL,
  p_audience_level   text     DEFAULT 'all'
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_is_admin boolean;
  v_id uuid;
BEGIN
  -- Auth check
  SELECT id, operational_role, is_superadmin
  INTO v_caller_id, v_caller_role, v_is_admin
  FROM public.members WHERE auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Only admin, manager, deputy_manager, or tribe_leader can create events
  IF NOT (v_is_admin = true OR v_caller_role IN ('manager', 'deputy_manager', 'tribe_leader')) THEN
    RAISE EXCEPTION 'Unauthorized: insufficient role to create events';
  END IF;

  INSERT INTO public.events (type, title, date, duration_minutes, tribe_id, audience_level)
  VALUES (p_type, p_title, p_date, p_duration_minutes, p_tribe_id, p_audience_level)
  RETURNING id INTO v_id;

  RETURN json_build_object('success', true, 'event_id', v_id);
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- P0-B: SECURITY DEFINER AUTH FIXES — mark_member_present
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.mark_member_present(uuid, uuid, boolean);

CREATE OR REPLACE FUNCTION public.mark_member_present(
  p_event_id  uuid,
  p_member_id uuid,
  p_present   boolean
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_is_admin boolean;
BEGIN
  -- Auth check
  SELECT id, operational_role, is_superadmin
  INTO v_caller_id, v_caller_role, v_is_admin
  FROM public.members WHERE auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Caller must be the member themselves, or admin/manager
  IF NOT (v_caller_id = p_member_id OR v_is_admin = true OR v_caller_role IN ('manager', 'deputy_manager')) THEN
    RAISE EXCEPTION 'Unauthorized: can only mark own presence or requires admin role';
  END IF;

  IF p_present THEN
    INSERT INTO public.attendance (event_id, member_id)
    VALUES (p_event_id, p_member_id)
    ON CONFLICT (event_id, member_id) DO NOTHING;
  ELSE
    DELETE FROM public.attendance
     WHERE event_id = p_event_id AND member_id = p_member_id;
  END IF;

  RETURN json_build_object('success', true);
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- P0-B: SECURITY DEFINER AUTH FIXES — get_member_attendance_hours
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.get_member_attendance_hours(uuid, text);

CREATE OR REPLACE FUNCTION public.get_member_attendance_hours(
  p_member_id  uuid,
  p_cycle_code text DEFAULT 'cycle_3'
)
RETURNS TABLE(total_hours numeric, total_events int, avg_hours_per_event numeric, current_streak int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_is_admin boolean;
  v_cycle_start date;
  v_streak int := 0;
  v_rec record;
BEGIN
  -- Auth check
  SELECT id, operational_role, is_superadmin
  INTO v_caller_id, v_caller_role, v_is_admin
  FROM public.members WHERE auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Caller must be the member themselves, or admin/manager
  IF NOT (v_caller_id = p_member_id OR v_is_admin = true OR v_caller_role IN ('manager', 'deputy_manager', 'tribe_leader')) THEN
    RAISE EXCEPTION 'Unauthorized: can only view own attendance or requires admin role';
  END IF;

  SELECT cycle_start INTO v_cycle_start
  FROM public.cycles WHERE cycle_code = p_cycle_code;

  IF v_cycle_start IS NULL THEN
    RETURN QUERY SELECT 0::numeric, 0::int, 0::numeric, 0::int;
    RETURN;
  END IF;

  FOR v_rec IN
    SELECT e.id,
           EXISTS(SELECT 1 FROM public.attendance a WHERE a.event_id = e.id AND a.member_id = p_member_id) AS was_present
    FROM public.events e
    WHERE e.date >= v_cycle_start
      AND e.date <= current_date
      AND (e.tribe_id IS NULL
           OR e.tribe_id = (SELECT m.tribe_id FROM public.members m WHERE m.id = p_member_id))
    ORDER BY e.date DESC
  LOOP
    IF v_rec.was_present THEN
      v_streak := v_streak + 1;
    ELSE
      EXIT;
    END IF;
  END LOOP;

  RETURN QUERY
  SELECT
    COALESCE(SUM(e.duration_minutes / 60.0), 0)::numeric          AS total_hours,
    COUNT(DISTINCT a.event_id)::int                                AS total_events,
    CASE WHEN COUNT(DISTINCT a.event_id) > 0
      THEN (COALESCE(SUM(e.duration_minutes / 60.0), 0) / COUNT(DISTINCT a.event_id))::numeric
      ELSE 0::numeric
    END                                                            AS avg_hours_per_event,
    v_streak                                                       AS current_streak
  FROM public.attendance a
  JOIN public.events e ON e.id = a.event_id
  WHERE a.member_id = p_member_id
    AND e.date >= v_cycle_start;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- P1-A: LGPD DATA EXPORT — export_my_data()
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.export_my_data()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_member_id uuid;
  v_member_email text;
  v_result jsonb;
BEGIN
  SELECT id, email INTO v_member_id, v_member_email
  FROM public.members WHERE auth_id = auth.uid();

  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT jsonb_build_object(
    'profile', (SELECT row_to_json(m)::jsonb FROM public.members m WHERE m.id = v_member_id),
    'attendance', COALESCE((SELECT jsonb_agg(row_to_json(a)::jsonb) FROM public.attendance a WHERE a.member_id = v_member_id), '[]'::jsonb),
    'gamification', COALESCE((SELECT jsonb_agg(row_to_json(g)::jsonb) FROM public.gamification_points g WHERE g.member_id = v_member_id), '[]'::jsonb),
    'notifications', COALESCE((SELECT jsonb_agg(row_to_json(n)::jsonb) FROM public.notifications n WHERE n.member_id = v_member_id), '[]'::jsonb),
    'board_assignments', COALESCE((SELECT jsonb_agg(row_to_json(ba)::jsonb) FROM public.board_item_assignments ba WHERE ba.member_id = v_member_id), '[]'::jsonb),
    'cycle_history', COALESCE((SELECT jsonb_agg(row_to_json(mch)::jsonb) FROM public.member_cycle_history mch WHERE mch.member_id = v_member_id), '[]'::jsonb),
    'selection_applications', COALESCE((SELECT jsonb_agg(row_to_json(sa)::jsonb) FROM public.selection_applications sa WHERE sa.email = v_member_email), '[]'::jsonb),
    'onboarding', COALESCE((SELECT jsonb_agg(row_to_json(op)::jsonb) FROM public.onboarding_progress op WHERE op.member_id = v_member_id), '[]'::jsonb),
    'exported_at', now()
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.export_my_data() TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- P1-B: LGPD DATA ERASURE — admin_anonymize_member()
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.members ADD COLUMN IF NOT EXISTS anonymized_at timestamptz;
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS anonymized_by uuid REFERENCES public.members(id);

CREATE OR REPLACE FUNCTION public.admin_anonymize_member(p_member_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_id uuid;
  v_target_email text;
BEGIN
  -- Only superadmin can anonymize
  SELECT id INTO v_caller_id FROM public.members
  WHERE auth_id = auth.uid() AND is_superadmin = true;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: only superadmin can anonymize members';
  END IF;

  -- Get target email before anonymization (for selection_applications)
  SELECT email INTO v_target_email FROM public.members WHERE id = p_member_id;

  IF v_target_email IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;

  -- Anonymize PII but preserve aggregate data
  UPDATE public.members SET
    full_name = 'Membro Anonimizado #' || SUBSTR(p_member_id::text, 1, 8),
    email = 'anon_' || SUBSTR(p_member_id::text, 1, 8) || '@removed.local',
    phone = NULL,
    linkedin_url = NULL,
    avatar_url = NULL,
    pmi_id = NULL,
    bio = NULL,
    auth_id = NULL,
    is_active = false,
    anonymized_at = now(),
    anonymized_by = v_caller_id
  WHERE id = p_member_id;

  -- Delete notifications (personal)
  DELETE FROM public.notifications WHERE member_id = p_member_id;

  -- Delete notification preferences
  DELETE FROM public.notification_preferences WHERE member_id = p_member_id;

  -- Anonymize selection applications
  UPDATE public.selection_applications SET
    applicant_name = 'Candidato Anonimizado',
    email = 'anon@removed.local',
    phone = NULL,
    linkedin_url = NULL,
    resume_url = NULL,
    motivation_letter = NULL
  WHERE email = v_target_email;

  RETURN jsonb_build_object('anonymized', true, 'member_id', p_member_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_anonymize_member(uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- P1-C: DATA RETENTION POLICY TABLE + CLEANUP RPC
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.data_retention_policy (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  table_name text NOT NULL,
  retention_days int NOT NULL,
  cleanup_type text NOT NULL CHECK (cleanup_type IN ('delete', 'anonymize', 'archive')),
  description text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.data_retention_policy ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'data_retention_policy' AND policyname = 'admin_only_retention') THEN
    CREATE POLICY "admin_only_retention" ON public.data_retention_policy FOR ALL USING (
      EXISTS (SELECT 1 FROM public.members m WHERE m.auth_id = auth.uid()
        AND (m.is_superadmin = true OR m.operational_role IN ('manager', 'deputy_manager')))
    );
  END IF;
END $$;

-- Seed retention policies
INSERT INTO public.data_retention_policy (table_name, retention_days, cleanup_type, description) VALUES
  ('notifications', 180, 'delete', 'Notificações lidas com mais de 6 meses'),
  ('data_anomaly_log', 365, 'delete', 'Logs de anomalia com mais de 1 ano'),
  ('board_lifecycle_events', 730, 'archive', 'Eventos de lifecycle com mais de 2 anos'),
  ('attendance', 1095, 'archive', 'Registros de presença com mais de 3 anos'),
  ('selection_applications', 1095, 'anonymize', 'Candidaturas com mais de 3 anos (manter agregado)')
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.admin_run_retention_cleanup()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_id uuid;
  v_policy record;
  v_affected int;
  v_results jsonb := '[]'::jsonb;
  v_cutoff_date date;
BEGIN
  -- Only superadmin/manager can run cleanup
  SELECT id INTO v_caller_id FROM public.members
  WHERE auth_id = auth.uid() AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager'));

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: admin only';
  END IF;

  FOR v_policy IN SELECT * FROM public.data_retention_policy WHERE is_active = true LOOP
    v_cutoff_date := current_date - (v_policy.retention_days || ' days')::interval;
    v_affected := 0;

    IF v_policy.cleanup_type = 'delete' THEN
      IF v_policy.table_name = 'notifications' THEN
        DELETE FROM public.notifications
        WHERE created_at < v_cutoff_date AND read = true;
        GET DIAGNOSTICS v_affected = ROW_COUNT;
      ELSIF v_policy.table_name = 'data_anomaly_log' THEN
        DELETE FROM public.data_anomaly_log
        WHERE detected_at < v_cutoff_date AND status = 'resolved';
        GET DIAGNOSTICS v_affected = ROW_COUNT;
      END IF;

    ELSIF v_policy.cleanup_type = 'anonymize' THEN
      IF v_policy.table_name = 'selection_applications' THEN
        UPDATE public.selection_applications SET
          applicant_name = 'Candidato Anonimizado',
          email = 'anon_' || SUBSTR(id::text, 1, 8) || '@removed.local',
          phone = NULL,
          linkedin_url = NULL,
          resume_url = NULL,
          motivation_letter = NULL
        WHERE applied_at < v_cutoff_date
          AND applicant_name != 'Candidato Anonimizado';
        GET DIAGNOSTICS v_affected = ROW_COUNT;
      END IF;

    ELSIF v_policy.cleanup_type = 'archive' THEN
      -- Archive = soft-mark for now (actual archive table creation is future work)
      v_affected := 0;
    END IF;

    v_results := v_results || jsonb_build_object(
      'table', v_policy.table_name,
      'type', v_policy.cleanup_type,
      'affected', v_affected,
      'cutoff', v_cutoff_date
    );
  END LOOP;

  RETURN jsonb_build_object('results', v_results, 'executed_by', v_caller_id, 'executed_at', now());
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_run_retention_cleanup() TO authenticated;
