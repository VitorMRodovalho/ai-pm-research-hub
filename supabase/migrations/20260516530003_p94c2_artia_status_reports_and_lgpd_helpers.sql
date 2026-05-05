-- p94 Phase C.2 Step 3: artia_status_reports cache + LGPD-safe helper RPCs for cron

-- 1. artia_status_reports table (idempotency cache for monthly cron)
CREATE TABLE IF NOT EXISTS artia_status_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_year INT NOT NULL,
  report_month DATE NOT NULL,
  body_md TEXT NOT NULL,
  metrics_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  generated_by_cron BOOLEAN DEFAULT true,
  artia_activity_id BIGINT,
  artia_synced_at TIMESTAMPTZ,
  UNIQUE(cycle_year, report_month)
);

CREATE INDEX IF NOT EXISTS idx_artia_status_reports_recent
  ON artia_status_reports(report_month DESC);

ALTER TABLE artia_status_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "v4_artia_status_reports_admin_read" ON artia_status_reports
  FOR SELECT USING (rls_can('manage_member') OR rls_can('view_internal_analytics'));

COMMENT ON TABLE artia_status_reports IS 'Phase C.2: monthly status report cache. Cron-generated 1st of each month. Idempotent: re-run same month overwrites. body_md ≤5KB Artia description limit. metrics_json for re-rendering.';

-- 2. LGPD-safe helper RPC: aggregated event summary
CREATE OR REPLACE FUNCTION _artia_safe_event_summary(
  p_start_date DATE,
  p_end_date DATE
) RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT jsonb_build_object(
    'period', jsonb_build_object('start', p_start_date, 'end', p_end_date),
    'total_events', COUNT(*),
    'by_type', jsonb_object_agg(COALESCE(type, 'other'), type_count),
    'total_duration_hours', COALESCE(ROUND(SUM(duration_minutes)::numeric / 60, 1), 0),
    'event_titles_sample', (
      SELECT jsonb_agg(title ORDER BY date DESC)
      FROM public.events
      WHERE date BETWEEN p_start_date AND p_end_date
      LIMIT 10
    )
  )
  FROM (
    SELECT type, duration_minutes, COUNT(*) OVER (PARTITION BY type) AS type_count
    FROM public.events
    WHERE date BETWEEN p_start_date AND p_end_date
  ) e;
$$;

GRANT EXECUTE ON FUNCTION _artia_safe_event_summary(DATE, DATE) TO authenticated;

COMMENT ON FUNCTION _artia_safe_event_summary IS 'LGPD-safe summary of events in date range. Returns counts + types + titles ONLY (no participant names). Used by sync-artia-rituals-weekly cron.';

-- 3. LGPD-safe helper RPC: aggregated platform metrics for monthly Status Report
CREATE OR REPLACE FUNCTION _artia_safe_monthly_metrics(
  p_year INT,
  p_month INT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
DECLARE
  v_start DATE := make_date(p_year, p_month, 1);
  v_end DATE := (make_date(p_year, p_month, 1) + interval '1 month - 1 day')::date;
  v_event_count INT;
  v_duration_h NUMERIC;
  v_active_volunteers INT;
  v_initiatives_count INT;
  v_publications INT;
  v_pilots_active INT;
BEGIN
  SELECT COUNT(*), COALESCE(ROUND(SUM(duration_minutes)::numeric / 60, 1), 0)
  INTO v_event_count, v_duration_h
  FROM public.events
  WHERE date BETWEEN v_start AND v_end;

  SELECT COUNT(DISTINCT m.id) INTO v_active_volunteers
  FROM public.members m
  WHERE m.status_active = true;

  SELECT COUNT(*) INTO v_initiatives_count
  FROM public.initiatives
  WHERE status = 'active';

  SELECT COUNT(*) INTO v_publications
  FROM public.board_items
  WHERE status = 'done' AND tags && ARRAY['publicacao']
    AND updated_at BETWEEN v_start AND v_end::timestamp;

  SELECT COUNT(*) INTO v_pilots_active
  FROM public.pilots
  WHERE status IN ('active','completed');

  RETURN jsonb_build_object(
    'period', jsonb_build_object('year', p_year, 'month', p_month, 'start', v_start, 'end', v_end),
    'events_in_month', v_event_count,
    'duration_hours_in_month', v_duration_h,
    'active_volunteers_total', v_active_volunteers,
    'initiatives_active_total', v_initiatives_count,
    'publications_done_in_month', v_publications,
    'pilots_active_total', v_pilots_active
  );
END;
$$;

GRANT EXECUTE ON FUNCTION _artia_safe_monthly_metrics(INT, INT) TO authenticated;

COMMENT ON FUNCTION _artia_safe_monthly_metrics IS 'LGPD-safe aggregated metrics for monthly status report. Returns counts only — no PII. Used by sync-artia-status-report-monthly cron.';

NOTIFY pgrst, 'reload schema';
