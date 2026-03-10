-- ═══════════════════════════════════════════════════════════════════════════
-- Wave 7: Volunteer Applications (Selection Process Data Pipeline)
-- Stores PMI volunteer application exports for analytics and member matching.
-- LGPD-sensitive: admin/superadmin access only.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS public.volunteer_applications (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id      TEXT NOT NULL,
  pmi_id              TEXT,
  first_name          TEXT NOT NULL,
  last_name           TEXT NOT NULL,
  email               TEXT NOT NULL,
  membership_status   TEXT,
  certifications      TEXT[] DEFAULT '{}',
  city                TEXT,
  state               TEXT,
  country             TEXT,
  app_status          TEXT,
  reason_for_applying TEXT,
  essay_answers       JSONB DEFAULT '{}'::JSONB,
  areas_of_interest   TEXT,
  label               TEXT,
  industry            TEXT,
  specialty           TEXT,
  resume_url          TEXT,
  cycle               INTEGER NOT NULL,
  opportunity_id      TEXT,
  snapshot_date       DATE NOT NULL,
  member_id           UUID REFERENCES public.members(id) ON DELETE SET NULL,
  is_existing_member  BOOLEAN NOT NULL DEFAULT FALSE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.volunteer_applications IS
  'PMI volunteer application data per cycle/snapshot. LGPD-sensitive -- admin only.';

CREATE INDEX idx_volunteer_apps_cycle ON public.volunteer_applications (cycle);
CREATE INDEX idx_volunteer_apps_email ON public.volunteer_applications (email);
CREATE INDEX idx_volunteer_apps_snapshot ON public.volunteer_applications (cycle, snapshot_date);
CREATE UNIQUE INDEX idx_volunteer_apps_dedup
  ON public.volunteer_applications (application_id, opportunity_id, snapshot_date);

ALTER TABLE public.volunteer_applications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "volunteer_applications_admin_read" ON public.volunteer_applications
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND (
          m.is_superadmin = TRUE
          OR m.operational_role IN ('manager','deputy_manager','co_gp')
        )
    )
  );

CREATE POLICY "volunteer_applications_superadmin_write" ON public.volunteer_applications
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid() AND m.is_superadmin = TRUE
    )
  );

-- ─── Analytics RPCs ───

CREATE OR REPLACE FUNCTION public.volunteer_funnel_summary(
  p_cycle INTEGER DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSON;
BEGIN
  IF NOT (SELECT is_superadmin OR operational_role IN ('manager','deputy_manager','co_gp')
          FROM members WHERE auth_id = auth.uid()) THEN
    RAISE EXCEPTION 'Insufficient permissions';
  END IF;

  SELECT json_build_object(
    'by_cycle', (
      SELECT json_agg(row_to_json(c)) FROM (
        SELECT
          cycle,
          COUNT(*) AS total_applications,
          COUNT(DISTINCT email) AS unique_applicants,
          COUNT(*) FILTER (WHERE is_existing_member) AS matched_members,
          COUNT(*) FILTER (WHERE app_status = 'Active') AS active_applications,
          MIN(snapshot_date) AS earliest_snapshot,
          MAX(snapshot_date) AS latest_snapshot
        FROM volunteer_applications
        WHERE (p_cycle IS NULL OR cycle = p_cycle)
        GROUP BY cycle ORDER BY cycle
      ) c
    ),
    'certifications', (
      SELECT json_agg(row_to_json(ct)) FROM (
        SELECT unnest(certifications) AS cert, COUNT(*) AS cnt
        FROM volunteer_applications
        WHERE (p_cycle IS NULL OR cycle = p_cycle)
        GROUP BY cert ORDER BY cnt DESC LIMIT 20
      ) ct
    ),
    'geography', (
      SELECT json_agg(row_to_json(g)) FROM (
        SELECT state, country, COUNT(*) AS cnt
        FROM volunteer_applications
        WHERE (p_cycle IS NULL OR cycle = p_cycle)
        GROUP BY state, country ORDER BY cnt DESC LIMIT 20
      ) g
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.volunteer_funnel_summary(INTEGER) TO authenticated;

COMMIT;
