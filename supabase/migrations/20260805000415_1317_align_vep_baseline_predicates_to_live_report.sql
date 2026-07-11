-- #1317 — align VEP baseline snapshot predicates to the live actionable report.
-- capture_vep_baseline (INSERTed summary) and get_vep_baseline_history (live "current")
-- had drifted definitions for the 3 divergence buckets, counting compliant people as
-- divergent (measured 2026-07-11: onboarding 69 vs 1, active_members 9 vs 0).
-- SSOT for VEP<->Nucleo divergence semantics = public.get_vep_divergence_report.
-- These three predicate blocks MUST stay byte-equivalent to that function's buckets.

CREATE OR REPLACE FUNCTION public.capture_vep_baseline(p_label text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
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
      count(*) FILTER (WHERE a.vep_status_raw IS NOT NULL) AS vep_observed,
      max(c.created_at) AS c_created
    FROM public.selection_applications a
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    GROUP BY c.cycle_code, c.status
    ORDER BY max(c.created_at) DESC
  )
  SELECT jsonb_build_object(
    'captured_at', now(),
    -- #1317 — mirror get_vep_divergence_report selection_divergent (SSOT)
    'selection_divergent', (
      SELECT count(*) FROM public.selection_applications a
      JOIN public.selection_cycles c ON c.id = a.cycle_id
      WHERE a.vep_status_raw IN ('Withdrawn','Declined','OfferNotExtended')
        AND a.status IN ('submitted','screening','objective_eval','interview_pending','interview_scheduled','interview_done','final_eval')
        AND c.status = 'open'
        AND (a.vep_reconciled_at IS NULL OR a.vep_reconciled_at < a.vep_last_seen_at)
    ),
    -- #1317 — mirror get_vep_divergence_report onboarding_divergent (SSOT)
    'onboarding_divergent', (
      SELECT count(*) FROM public.selection_applications a
      WHERE a.status IN ('approved','converted')
        AND a.vep_status_raw IN ('Submitted','OfferExtended')
        AND (a.vep_reconciled_at IS NULL OR a.vep_reconciled_at < a.vep_last_seen_at)
    ),
    -- #1317 — mirror get_vep_divergence_report active_members_divergent (SSOT): member
    -- offboarded (is_active=false) but latest VEP app still Submitted/Active, not reconciled
    'active_members_divergent', (
      SELECT count(*) FROM public.members m
      JOIN LATERAL (
        SELECT sa.vep_status_raw, sa.vep_reconciled_at, sa.vep_last_seen_at
        FROM public.selection_applications sa
        WHERE lower(sa.email) = lower(m.email) AND sa.vep_status_raw IS NOT NULL
        ORDER BY sa.imported_at DESC NULLS LAST LIMIT 1
      ) a ON true
      WHERE m.is_active = false
        AND a.vep_status_raw IN ('Submitted','Active')
        AND (a.vep_reconciled_at IS NULL OR a.vep_reconciled_at < a.vep_last_seen_at)
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
      ) ORDER BY c_created DESC) FROM cycle_cov),
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

CREATE OR REPLACE FUNCTION public.get_vep_baseline_history(p_limit integer DEFAULT 10)
 RETURNS jsonb
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

  SELECT jsonb_build_object(
    -- #1317 — mirror get_vep_divergence_report selection_divergent (SSOT)
    'selection_divergent', (
      SELECT count(*) FROM public.selection_applications a
      JOIN public.selection_cycles c ON c.id = a.cycle_id
      WHERE a.vep_status_raw IN ('Withdrawn','Declined','OfferNotExtended')
        AND a.status IN ('submitted','screening','objective_eval','interview_pending','interview_scheduled','interview_done','final_eval')
        AND c.status = 'open'
        AND (a.vep_reconciled_at IS NULL OR a.vep_reconciled_at < a.vep_last_seen_at)
    ),
    -- #1317 — mirror get_vep_divergence_report onboarding_divergent (SSOT)
    'onboarding_divergent', (
      SELECT count(*) FROM public.selection_applications a
      WHERE a.status IN ('approved','converted')
        AND a.vep_status_raw IN ('Submitted','OfferExtended')
        AND (a.vep_reconciled_at IS NULL OR a.vep_reconciled_at < a.vep_last_seen_at)
    ),
    -- #1317 — mirror get_vep_divergence_report active_members_divergent (SSOT): member
    -- offboarded (is_active=false) but latest VEP app still Submitted/Active, not reconciled
    'active_members_divergent', (
      SELECT count(*) FROM public.members m
      JOIN LATERAL (
        SELECT sa.vep_status_raw, sa.vep_reconciled_at, sa.vep_last_seen_at
        FROM public.selection_applications sa
        WHERE lower(sa.email) = lower(m.email) AND sa.vep_status_raw IS NOT NULL
        ORDER BY sa.imported_at DESC NULLS LAST LIMIT 1
      ) a ON true
      WHERE m.is_active = false
        AND a.vep_status_raw IN ('Submitted','Active')
        AND (a.vep_reconciled_at IS NULL OR a.vep_reconciled_at < a.vep_last_seen_at)
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
