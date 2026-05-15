-- p162 Fase A.2 — RPC get_member_xp_pillars
-- Refs: ADR-0081 + p162 transparency UI ratificada PM
-- Returns 6-pillar XP breakdown per member per cycle, with rules drilldown.
-- Always returns ALL 6 pillars (zero-pts incluído) para empty-state UX.

CREATE OR REPLACE FUNCTION public.get_member_xp_pillars(
  p_member_id uuid DEFAULT NULL,
  p_cycle_code text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_caller members%ROWTYPE;
  v_target_id uuid;
  v_target members%ROWTYPE;
  v_is_self boolean;
  v_can_view_pii boolean;
  v_cycle_code text;
  v_cycle_start timestamptz;
  v_cycle_end timestamptz;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;

  v_target_id := COALESCE(p_member_id, v_caller.id);
  v_is_self := (v_target_id = v_caller.id);

  SELECT * INTO v_target FROM members WHERE id = v_target_id;
  IF v_target.id IS NULL THEN
    RETURN jsonb_build_object('error','member_not_found');
  END IF;
  IF v_target.organization_id != v_caller.organization_id THEN
    RETURN jsonb_build_object('error','member_not_in_org');
  END IF;

  IF NOT v_is_self THEN
    v_can_view_pii := public.can_by_member(v_caller.id, 'view_pii'::text);
    IF NOT v_can_view_pii AND COALESCE(v_target.gamification_opt_out, false) THEN
      RETURN jsonb_build_object('error','member_opted_out_from_public');
    END IF;
  END IF;

  IF p_cycle_code IS NULL THEN
    SELECT cycle_code, cycle_start::timestamptz, cycle_end::timestamptz
      INTO v_cycle_code, v_cycle_start, v_cycle_end
    FROM cycles WHERE is_current = true LIMIT 1;
  ELSE
    SELECT cycle_code, cycle_start::timestamptz, cycle_end::timestamptz
      INTO v_cycle_code, v_cycle_start, v_cycle_end
    FROM cycles WHERE cycle_code = p_cycle_code LIMIT 1;
    IF v_cycle_code IS NULL THEN
      RETURN jsonb_build_object('error','cycle_not_found');
    END IF;
  END IF;

  WITH points_in_cycle AS (
    SELECT gp.category, gp.points
    FROM gamification_points gp
    WHERE gp.member_id = v_target_id
      AND gp.organization_id = v_caller.organization_id
      AND gp.created_at >= v_cycle_start
      AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + interval '1 day'))
  ),
  rule_breakdown AS (
    SELECT
      r.pillar,
      r.slug,
      r.display_name_i18n,
      r.base_points,
      r.cap_points,
      COALESCE(SUM(p.points), 0)::int AS pts,
      COUNT(p.points)::int AS earned_count
    FROM gamification_rules r
    LEFT JOIN points_in_cycle p ON p.category = r.slug
    WHERE r.organization_id = v_caller.organization_id
      AND r.active = true
    GROUP BY r.pillar, r.slug, r.display_name_i18n, r.base_points, r.cap_points
  ),
  pillar_agg AS (
    SELECT
      pillar,
      SUM(pts)::int AS total_pts,
      SUM(earned_count)::int AS earned_count,
      jsonb_agg(
        jsonb_build_object(
          'slug', slug,
          'display_name_i18n', display_name_i18n,
          'base_points', base_points,
          'cap_points', cap_points,
          'pts', pts,
          'count', earned_count
        ) ORDER BY pts DESC, slug
      ) AS rules
    FROM rule_breakdown
    GROUP BY pillar
  )
  SELECT jsonb_build_object(
    'member_id', v_target_id,
    'member_name', v_target.name,
    'is_self', v_is_self,
    'cycle_code', v_cycle_code,
    'cycle_start', v_cycle_start,
    'cycle_end', v_cycle_end,
    'total_pts', COALESCE((SELECT SUM(total_pts)::int FROM pillar_agg), 0),
    'pillars', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'pillar', pillar,
          'total_pts', total_pts,
          'earned_count', earned_count,
          'rules', rules
        )
        ORDER BY CASE pillar
          WHEN 'presenca' THEN 1
          WHEN 'trilha' THEN 2
          WHEN 'certificacoes' THEN 3
          WHEN 'producao' THEN 4
          WHEN 'curadoria' THEN 5
          WHEN 'champions' THEN 6
        END
      ) FROM pillar_agg
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_member_xp_pillars(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_member_xp_pillars(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_member_xp_pillars(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.get_member_xp_pillars(uuid, text) IS
'XP breakdown per pillar (6 buckets) for a member, current or specified cycle. Self-view always allowed; cross-member requires view_pii OR target not opted-out. Returns ALL 6 pillars even if zero-pts (empty-state UX). NULL-safe cycle_end (ADR-0062). Ver ADR-0081 + SEMANTIC_TAXONOMY.md.';

NOTIFY pgrst, 'reload schema';

-- Rollback:
-- DROP FUNCTION IF EXISTS public.get_member_xp_pillars(uuid, text);
