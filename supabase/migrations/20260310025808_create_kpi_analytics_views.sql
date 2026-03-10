-- Executive KPI Dashboard RPC
-- Returns aggregated metrics for the admin Executive Overview panel.
-- Access: SECURITY DEFINER (bypasses RLS), called from admin panel only.

DROP FUNCTION IF EXISTS public.get_executive_kpis();

CREATE OR REPLACE FUNCTION public.get_executive_kpis()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_active    INT;
  v_total_verified  INT;
  v_multi_cycle     INT;
  v_retention_pct   NUMERIC;
  v_total_artifacts INT;
  v_total_tribes    INT;
  v_avg_per_tribe   NUMERIC;
  v_chapters        INT;
BEGIN
  -- Active members (current_cycle_active = true OR is_active = true)
  SELECT COUNT(*) INTO v_total_active
  FROM members
  WHERE COALESCE(current_cycle_active, is_active, false) = true;

  -- Members with verified PMI ID
  SELECT COUNT(*) INTO v_total_verified
  FROM members
  WHERE pmi_id_verified = true
    AND COALESCE(current_cycle_active, is_active, false) = true;

  -- Members present in more than one cycle (retention proxy)
  SELECT COUNT(*) INTO v_multi_cycle
  FROM members
  WHERE COALESCE(current_cycle_active, is_active, false) = true
    AND array_length(cycles, 1) > 1;

  -- Retention percentage
  IF v_total_active > 0 THEN
    v_retention_pct := ROUND((v_multi_cycle::NUMERIC / v_total_active) * 100, 1);
  ELSE
    v_retention_pct := 0;
  END IF;

  -- Published artifacts
  SELECT COUNT(*) INTO v_total_artifacts
  FROM artifacts
  WHERE status = 'published';

  -- Active tribes
  SELECT COUNT(*) INTO v_total_tribes
  FROM tribes
  WHERE is_active = true;

  -- Average members per tribe
  IF v_total_tribes > 0 THEN
    SELECT ROUND(AVG(cnt), 1) INTO v_avg_per_tribe
    FROM (
      SELECT COUNT(*) AS cnt
      FROM members
      WHERE tribe_id IS NOT NULL
        AND COALESCE(current_cycle_active, is_active, false) = true
      GROUP BY tribe_id
    ) sub;
  ELSE
    v_avg_per_tribe := 0;
  END IF;

  -- Distinct chapters
  SELECT COUNT(DISTINCT chapter) INTO v_chapters
  FROM members
  WHERE chapter IS NOT NULL
    AND COALESCE(current_cycle_active, is_active, false) = true;

  RETURN json_build_object(
    'total_active',       v_total_active,
    'pmi_verified',       v_total_verified,
    'multi_cycle',        v_multi_cycle,
    'retention_pct',      v_retention_pct,
    'published_artifacts', v_total_artifacts,
    'active_tribes',      v_total_tribes,
    'avg_per_tribe',      v_avg_per_tribe,
    'chapters',           v_chapters
  );
END;
$$;

COMMENT ON FUNCTION public.get_executive_kpis() IS
  'Returns aggregated executive KPIs: active members, PMI verified, retention rate, artifacts, tribes.';
