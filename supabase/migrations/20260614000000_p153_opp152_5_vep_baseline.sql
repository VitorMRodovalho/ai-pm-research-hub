-- p153 OPP-152.5 — VEP reconciliation calibration baseline
--
-- Snapshots divergence buckets + status distribution + per-cycle coverage at a
-- point in time so the PM can detect drift between Apply UI C rounds. Without
-- a baseline, "is this divergence count normal?" has no anchor.
--
-- Schema:
--   vep_reconciliation_baselines  — append-only audit table (RLS gated by
--                                   view_internal_analytics, multi-tenant via
--                                   organization_id).
--   capture_vep_baseline()        — SECDEF RPC that computes current divergence
--                                   shape and persists it. Returns the captured row.
--   get_vep_baseline_history()    — returns last N baselines + the current
--                                   divergence snapshot for client-side diff.

-- ─── 1) Table ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.vep_reconciliation_baselines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  captured_at timestamptz NOT NULL DEFAULT now(),
  captured_by uuid REFERENCES public.members(id),
  label text NOT NULL,
  notes text,
  summary jsonb NOT NULL,
  organization_id uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid REFERENCES public.organizations(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_vep_baselines_captured_at
  ON public.vep_reconciliation_baselines(captured_at DESC);

CREATE INDEX IF NOT EXISTS idx_vep_baselines_org
  ON public.vep_reconciliation_baselines(organization_id, captured_at DESC);

ALTER TABLE public.vep_reconciliation_baselines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS vep_baselines_read ON public.vep_reconciliation_baselines;
CREATE POLICY vep_baselines_read ON public.vep_reconciliation_baselines
  FOR SELECT TO authenticated
  USING (
    organization_id = public.auth_org()
    AND public.rls_can('view_internal_analytics')
  );

-- No INSERT/UPDATE/DELETE policy — only SECDEF capture_vep_baseline can write.
COMMENT ON TABLE public.vep_reconciliation_baselines IS
  'p153 OPP-152.5 — append-only snapshots of VEP↔Núcleo divergence shape. Written exclusively by capture_vep_baseline() SECDEF RPC. Used by /admin/vep-reconciliation to detect drift between Apply UI C rounds.';

-- ─── 2) capture_vep_baseline RPC ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.capture_vep_baseline(
  p_label text,
  p_notes text DEFAULT NULL
) RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_baseline_id uuid;
  v_org_id uuid;
  v_summary jsonb;
BEGIN
  SELECT id, organization_id INTO v_caller_id, v_org_id
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RAISE EXCEPTION 'Forbidden: view_internal_analytics required';
  END IF;
  IF p_label IS NULL OR length(trim(p_label)) = 0 THEN
    RAISE EXCEPTION 'label is required';
  END IF;

  -- Compute the snapshot. Same buckets as get_vep_divergence_report but
  -- aggregated to counts (no per-row PII) so the baseline is safe to surface
  -- in dashboards. Extra dimensions captured for drift forensics.
  WITH vep_status_dist AS (
    SELECT vep_status_raw, count(*) AS n
    FROM public.selection_applications
    WHERE vep_status_raw IS NOT NULL
    GROUP BY vep_status_raw
  ),
  cycle_cov AS (
    SELECT
      c.cycle_code,
      c.status AS cycle_status,
      count(*) AS apps,
      count(*) FILTER (WHERE a.vep_status_raw IS NOT NULL) AS vep_observed
    FROM public.selection_applications a
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    GROUP BY c.cycle_code, c.status, c.created_at
    ORDER BY c.created_at DESC
  )
  SELECT jsonb_build_object(
    'captured_at', now(),
    'selection_divergent', (
      SELECT count(*) FROM public.selection_applications a
      WHERE a.vep_status_raw IN ('Withdrawn','Declined','OfferNotExtended','Expired')
        AND a.status NOT IN ('rejected','withdrawn','cancelled')
        AND COALESCE(a.vep_reconciled_at < a.vep_last_seen_at, true)
    ),
    'onboarding_divergent', (
      SELECT count(*) FROM public.selection_applications a
      WHERE a.status IN ('approved','converted')
        AND a.vep_status_raw IN ('Submitted','Active')
        AND COALESCE(a.vep_reconciled_at < a.vep_last_seen_at, true)
    ),
    'active_members_divergent', (
      SELECT count(*) FROM public.selection_applications a
      WHERE a.vep_status_raw IS NOT NULL
        AND a.vep_status_raw NOT IN ('Active')
        AND EXISTS (
          SELECT 1 FROM public.members m
          WHERE m.is_active = true
            AND lower(m.email) = lower(a.email)
        )
    ),
    'total_observed', (
      SELECT count(*) FROM public.selection_applications WHERE vep_status_raw IS NOT NULL
    ),
    'total_apps', (
      SELECT count(*) FROM public.selection_applications
    ),
    'latest_ingest_at', (
      SELECT max(vep_last_seen_at) FROM public.selection_applications
    ),
    'missing_from_latest_vep', (
      -- Apps with vep_last_seen_at older than the most-recent ingest run
      -- = PMI removed them from the recruiter dashboard between rounds.
      SELECT count(*) FROM public.selection_applications a
      WHERE a.vep_status_raw IS NOT NULL
        AND a.vep_last_seen_at < (
          SELECT max(vep_last_seen_at) - interval '5 minutes'
          FROM public.selection_applications
        )
    ),
    'vep_status_distribution', COALESCE(
      (SELECT jsonb_object_agg(vep_status_raw, n) FROM vep_status_dist),
      '{}'::jsonb
    ),
    'cycle_coverage', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'cycle_code', cycle_code,
        'cycle_status', cycle_status,
        'apps', apps,
        'vep_observed', vep_observed,
        'pct', CASE WHEN apps > 0 THEN round((vep_observed::numeric / apps) * 100, 1) ELSE 0 END
      )) FROM cycle_cov),
      '[]'::jsonb
    )
  ) INTO v_summary;

  INSERT INTO public.vep_reconciliation_baselines
    (captured_by, label, notes, summary, organization_id)
  VALUES
    (v_caller_id, trim(p_label), p_notes, v_summary, v_org_id)
  RETURNING id INTO v_baseline_id;

  RETURN jsonb_build_object(
    'id', v_baseline_id,
    'captured_at', v_summary->>'captured_at',
    'label', trim(p_label),
    'summary', v_summary
  );
END;
$function$;

COMMENT ON FUNCTION public.capture_vep_baseline(text, text) IS
  'p153 OPP-152.5 — captures a VEP reconciliation baseline snapshot. Gated by view_internal_analytics. Returns the persisted summary.';

-- ─── 3) get_vep_baseline_history RPC ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_vep_baseline_history(
  p_limit int DEFAULT 10
) RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_org_id uuid;
  v_baselines jsonb;
  v_current jsonb;
BEGIN
  SELECT id, organization_id INTO v_caller_id, v_org_id
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RAISE EXCEPTION 'Forbidden: view_internal_analytics required';
  END IF;

  -- History list
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', id,
    'captured_at', captured_at,
    'captured_by_name', (SELECT m.name FROM public.members m WHERE m.id = captured_by),
    'label', label,
    'notes', notes,
    'selection_divergent', (summary->>'selection_divergent')::int,
    'onboarding_divergent', (summary->>'onboarding_divergent')::int,
    'active_members_divergent', (summary->>'active_members_divergent')::int,
    'total_observed', (summary->>'total_observed')::int,
    'total_apps', (summary->>'total_apps')::int,
    'missing_from_latest_vep', (summary->>'missing_from_latest_vep')::int,
    'summary', summary
  ) ORDER BY captured_at DESC), '[]'::jsonb)
  INTO v_baselines
  FROM (
    SELECT id, captured_at, captured_by, label, notes, summary
    FROM public.vep_reconciliation_baselines
    WHERE organization_id = v_org_id
    ORDER BY captured_at DESC
    LIMIT GREATEST(1, LEAST(p_limit, 50))
  ) b;

  -- Current snapshot (same shape as capture, but not persisted — for live diff vs baselines)
  SELECT jsonb_build_object(
    'selection_divergent', (
      SELECT count(*) FROM public.selection_applications a
      WHERE a.vep_status_raw IN ('Withdrawn','Declined','OfferNotExtended','Expired')
        AND a.status NOT IN ('rejected','withdrawn','cancelled')
        AND COALESCE(a.vep_reconciled_at < a.vep_last_seen_at, true)
    ),
    'onboarding_divergent', (
      SELECT count(*) FROM public.selection_applications a
      WHERE a.status IN ('approved','converted')
        AND a.vep_status_raw IN ('Submitted','Active')
        AND COALESCE(a.vep_reconciled_at < a.vep_last_seen_at, true)
    ),
    'active_members_divergent', (
      SELECT count(*) FROM public.selection_applications a
      WHERE a.vep_status_raw IS NOT NULL
        AND a.vep_status_raw NOT IN ('Active')
        AND EXISTS (
          SELECT 1 FROM public.members m
          WHERE m.is_active = true
            AND lower(m.email) = lower(a.email)
        )
    ),
    'total_observed', (SELECT count(*) FROM public.selection_applications WHERE vep_status_raw IS NOT NULL),
    'total_apps', (SELECT count(*) FROM public.selection_applications),
    'latest_ingest_at', (SELECT max(vep_last_seen_at) FROM public.selection_applications),
    'missing_from_latest_vep', (
      SELECT count(*) FROM public.selection_applications a
      WHERE a.vep_status_raw IS NOT NULL
        AND a.vep_last_seen_at < (
          SELECT max(vep_last_seen_at) - interval '5 minutes' FROM public.selection_applications
        )
    )
  ) INTO v_current;

  RETURN jsonb_build_object(
    'current', v_current,
    'baselines', v_baselines
  );
END;
$function$;

COMMENT ON FUNCTION public.get_vep_baseline_history(int) IS
  'p153 OPP-152.5 — returns historical VEP baselines + current divergence snapshot for drift comparison. Gated by view_internal_analytics.';
