-- Fix: get_diversity_dashboard ORDER BY was outside jsonb_agg causing
-- "column sds.created_at must appear in the GROUP BY clause" error
-- Solution: move ORDER BY inside jsonb_agg()

DROP FUNCTION IF EXISTS get_diversity_dashboard(uuid);
CREATE OR REPLACE FUNCTION get_diversity_dashboard(p_cycle_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_caller record;
  v_cycle_id uuid;
  v_by_gender jsonb;
  v_by_chapter jsonb;
  v_by_sector jsonb;
  v_by_seniority jsonb;
  v_by_region jsonb;
  v_applicants_total int;
  v_approved_total int;
  v_snapshots jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Unauthorized: member not found'; END IF;

  IF v_caller.is_superadmin IS NOT TRUE
    AND v_caller.operational_role NOT IN ('manager', 'deputy_manager')
    AND NOT (v_caller.designations && ARRAY['sponsor', 'chapter_liaison']::text[]) THEN
    RAISE EXCEPTION 'Unauthorized: admin or sponsor required';
  END IF;

  IF p_cycle_id IS NOT NULL THEN v_cycle_id := p_cycle_id;
  ELSE SELECT id INTO v_cycle_id FROM public.selection_cycles ORDER BY created_at DESC LIMIT 1;
  END IF;
  IF v_cycle_id IS NULL THEN RETURN jsonb_build_object('error', 'no_cycle_found'); END IF;

  SELECT COUNT(*) INTO v_applicants_total FROM public.selection_applications WHERE cycle_id = v_cycle_id;
  SELECT COUNT(*) INTO v_approved_total FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status IN ('approved', 'converted');

  SELECT jsonb_agg(jsonb_build_object('gender', COALESCE(gender, 'Não informado'), 'applicants', applicants, 'approved', approved))
  INTO v_by_gender FROM (
    SELECT sa.gender, COUNT(*) AS applicants, COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa WHERE sa.cycle_id = v_cycle_id GROUP BY sa.gender ORDER BY applicants DESC
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('chapter', COALESCE(chapter, 'Não informado'), 'applicants', applicants, 'approved', approved))
  INTO v_by_chapter FROM (
    SELECT sa.chapter, COUNT(*) AS applicants, COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa WHERE sa.cycle_id = v_cycle_id GROUP BY sa.chapter ORDER BY applicants DESC
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('sector', COALESCE(sector, 'Não informado'), 'applicants', applicants, 'approved', approved))
  INTO v_by_sector FROM (
    SELECT sa.sector, COUNT(*) AS applicants, COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa WHERE sa.cycle_id = v_cycle_id GROUP BY sa.sector ORDER BY applicants DESC
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('band', band, 'applicants', applicants, 'approved', approved))
  INTO v_by_seniority FROM (
    SELECT
      CASE WHEN sa.seniority_years IS NULL THEN 'Não informado'
        WHEN sa.seniority_years < 3 THEN '0-2 anos' WHEN sa.seniority_years < 6 THEN '3-5 anos'
        WHEN sa.seniority_years < 11 THEN '6-10 anos' WHEN sa.seniority_years < 16 THEN '11-15 anos'
        ELSE '16+ anos' END AS band,
      COUNT(*) AS applicants, COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa WHERE sa.cycle_id = v_cycle_id GROUP BY band ORDER BY band
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('region', COALESCE(region, 'Não informado'), 'applicants', applicants, 'approved', approved))
  INTO v_by_region FROM (
    SELECT COALESCE(sa.state, sa.country) AS region, COUNT(*) AS applicants,
      COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa WHERE sa.cycle_id = v_cycle_id GROUP BY region ORDER BY applicants DESC
  ) sub;

  SELECT jsonb_agg(
    jsonb_build_object('snapshot_type', sds.snapshot_type, 'metrics', sds.metrics, 'created_at', sds.created_at)
    ORDER BY sds.created_at DESC
  ) INTO v_snapshots
  FROM public.selection_diversity_snapshots sds
  WHERE sds.cycle_id = v_cycle_id;

  RETURN jsonb_build_object(
    'cycle_id', v_cycle_id,
    'applicants_total', v_applicants_total,
    'approved_total', v_approved_total,
    'by_gender', COALESCE(v_by_gender, '[]'::jsonb),
    'by_chapter', COALESCE(v_by_chapter, '[]'::jsonb),
    'by_sector', COALESCE(v_by_sector, '[]'::jsonb),
    'by_seniority', COALESCE(v_by_seniority, '[]'::jsonb),
    'by_region', COALESCE(v_by_region, '[]'::jsonb),
    'snapshots', COALESCE(v_snapshots, '[]'::jsonb)
  );
END;
$$;
