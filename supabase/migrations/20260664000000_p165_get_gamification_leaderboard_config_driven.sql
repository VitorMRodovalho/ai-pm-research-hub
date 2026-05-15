-- p165 Item #1 — Reshape get_gamification_leaderboard config-driven via gamification_rules.pillar
-- Refs: ADR-0081 (config-driven + 6 pillars: presenca/trilha/certificacoes/producao/curadoria/champions)
-- Refs: handoff_p165 Tier A backlog item #1
--
-- Drift observed (live 2026-05-15):
--   - curation_ratification (50 pts, 2 rows) falling into bonus_points (slug pillar=curadoria, no bucket in RPC)
--   - specialization (1150 pts, 46 rows) falling into badge_points (slug pillar=trilha, RPC grouped with badge)
--   - 10 slugs (champion_*, curation_*, action_resolved, artifact_published, deliverable_completed) with no bucket → bonus_points
--   - artifact_points filter used literal 'artifact' which is not a slug; real slug is 'artifact_published' → bucket always 0
--
-- Approach:
--   1. LEFT JOIN gamification_rules on (organization_id, slug=category) → resolves pillar dynamically
--   2. Filters by gr.pillar (canonical) instead of literal category lists
--   3. Preserve 8 legacy column names (backward-compat with TribeGamificationTab + gamification.astro)
--   4. Add 3 new columns: producao_points, curadoria_points, champions_points (+ cycle mirrors)
--   5. Fix slug filter for artifact_points; specialization now correctly in learning_points
--   6. bonus_points defensive catch-all (rules.pillar CHECK enum means today this = 0)
--
-- Rollback: drop + recreate previous body (see prior migration touching this RPC).

DROP FUNCTION IF EXISTS public.get_gamification_leaderboard(integer, integer, text, text, text, uuid);

CREATE OR REPLACE FUNCTION public.get_gamification_leaderboard(
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0,
  p_cycle_code text DEFAULT NULL,
  p_scope_kind text DEFAULT 'global',
  p_chapter_code text DEFAULT NULL,
  p_initiative_id uuid DEFAULT NULL
) RETURNS TABLE(
  member_id uuid,
  name text,
  chapter text,
  photo_url text,
  operational_role text,
  designations text[],
  total_points integer,
  attendance_points integer,
  learning_points integer,
  cert_points integer,
  badge_points integer,
  artifact_points integer,
  course_points integer,
  showcase_points integer,
  bonus_points integer,
  producao_points integer,
  curadoria_points integer,
  champions_points integer,
  cycle_points integer,
  cycle_attendance_points integer,
  cycle_course_points integer,
  cycle_artifact_points integer,
  cycle_showcase_points integer,
  cycle_bonus_points integer,
  cycle_learning_points integer,
  cycle_cert_points integer,
  cycle_badge_points integer,
  cycle_producao_points integer,
  cycle_curadoria_points integer,
  cycle_champions_points integer,
  total_count integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_start date;
  v_cycle_end date;
  v_total_count int;
  v_effective_limit int;
  v_effective_offset int;
  v_scope text;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_effective_limit := GREATEST(1, LEAST(COALESCE(p_limit, 50), 200));
  v_effective_offset := GREATEST(0, COALESCE(p_offset, 0));

  v_scope := COALESCE(NULLIF(trim(p_scope_kind), ''), 'global');
  IF v_scope NOT IN ('global', 'chapter', 'tribe') THEN
    RAISE EXCEPTION 'invalid_scope_kind: % (allowed: global|chapter|tribe)', v_scope
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_scope = 'chapter' AND (p_chapter_code IS NULL OR trim(p_chapter_code) = '') THEN
    RAISE EXCEPTION 'chapter_code_required: scope_kind=chapter requires p_chapter_code'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_scope = 'tribe' AND p_initiative_id IS NULL THEN
    RAISE EXCEPTION 'initiative_id_required: scope_kind=tribe requires p_initiative_id'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF p_cycle_code IS NOT NULL THEN
    SELECT c.cycle_start, c.cycle_end INTO v_cycle_start, v_cycle_end
    FROM public.cycles c WHERE c.cycle_code = p_cycle_code;
    IF v_cycle_start IS NULL THEN
      RAISE EXCEPTION 'cycle_not_found: %', p_cycle_code USING ERRCODE = 'no_data_found';
    END IF;
  ELSE
    SELECT c.cycle_start, c.cycle_end INTO v_cycle_start, v_cycle_end
    FROM public.cycles c WHERE c.is_current = true LIMIT 1;
  END IF;

  SELECT COUNT(*) INTO v_total_count
  FROM public.members m
  WHERE m.current_cycle_active = true
    AND m.gamification_opt_out = false
    AND (
      v_scope = 'global'
      OR (v_scope = 'chapter' AND m.chapter = p_chapter_code)
      OR (v_scope = 'tribe' AND EXISTS (
        SELECT 1 FROM public.persons p
        JOIN public.auth_engagements ae ON ae.person_id = p.id
        WHERE p.legacy_member_id = m.id
          AND ae.is_authoritative = true
          AND ae.initiative_id = p_initiative_id
      ))
    );

  RETURN QUERY
  SELECT
    m.id AS member_id,
    m.name,
    m.chapter,
    m.photo_url,
    m.operational_role,
    m.designations,
    COALESCE(sum(gp.points), 0::bigint)::integer AS total_points,
    -- Legacy 8 buckets (now pillar-driven via JOIN)
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'presenca'), 0::bigint)::integer AS attendance_points,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'trilha'), 0::bigint)::integer AS learning_points,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'certificacoes' AND gr.slug LIKE 'cert_%'), 0::bigint)::integer AS cert_points,
    COALESCE(sum(gp.points) FILTER (WHERE gr.slug = 'badge'), 0::bigint)::integer AS badge_points,
    COALESCE(sum(gp.points) FILTER (WHERE gr.slug = 'artifact_published'), 0::bigint)::integer AS artifact_points,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'trilha'), 0::bigint)::integer AS course_points,
    COALESCE(sum(gp.points) FILTER (WHERE gr.slug LIKE 'showcase%'), 0::bigint)::integer AS showcase_points,
    COALESCE(sum(gp.points) FILTER (
      WHERE gr.pillar IS NULL
         OR gr.pillar NOT IN ('presenca','trilha','certificacoes','producao','curadoria','champions')
    ), 0::bigint)::integer AS bonus_points,
    -- New 3 pillar buckets
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'producao' AND gr.slug <> 'artifact_published' AND gr.slug NOT LIKE 'showcase%'), 0::bigint)::integer AS producao_points,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'curadoria'), 0::bigint)::integer AS curadoria_points,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'champions'), 0::bigint)::integer AS champions_points,
    -- Cycle scalar
    COALESCE(sum(gp.points) FILTER (
      WHERE gp.created_at >= v_cycle_start
        AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))
    ), 0::bigint)::integer AS cycle_points,
    -- Cycle legacy buckets
    COALESCE(sum(gp.points) FILTER (
      WHERE gr.pillar = 'presenca'
        AND gp.created_at >= v_cycle_start
        AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))
    ), 0::bigint)::integer AS cycle_attendance_points,
    COALESCE(sum(gp.points) FILTER (
      WHERE gr.pillar = 'trilha'
        AND gp.created_at >= v_cycle_start
        AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))
    ), 0::bigint)::integer AS cycle_course_points,
    COALESCE(sum(gp.points) FILTER (
      WHERE gr.slug = 'artifact_published'
        AND gp.created_at >= v_cycle_start
        AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))
    ), 0::bigint)::integer AS cycle_artifact_points,
    COALESCE(sum(gp.points) FILTER (
      WHERE gr.slug LIKE 'showcase%'
        AND gp.created_at >= v_cycle_start
        AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))
    ), 0::bigint)::integer AS cycle_showcase_points,
    COALESCE(sum(gp.points) FILTER (
      WHERE (gr.pillar IS NULL OR gr.pillar NOT IN ('presenca','trilha','certificacoes','producao','curadoria','champions'))
        AND gp.created_at >= v_cycle_start
        AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))
    ), 0::bigint)::integer AS cycle_bonus_points,
    COALESCE(sum(gp.points) FILTER (
      WHERE gr.pillar = 'trilha'
        AND gp.created_at >= v_cycle_start
        AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))
    ), 0::bigint)::integer AS cycle_learning_points,
    COALESCE(sum(gp.points) FILTER (
      WHERE gr.pillar = 'certificacoes' AND gr.slug LIKE 'cert_%'
        AND gp.created_at >= v_cycle_start
        AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))
    ), 0::bigint)::integer AS cycle_cert_points,
    COALESCE(sum(gp.points) FILTER (
      WHERE gr.slug = 'badge'
        AND gp.created_at >= v_cycle_start
        AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))
    ), 0::bigint)::integer AS cycle_badge_points,
    -- Cycle new 3 pillar buckets
    COALESCE(sum(gp.points) FILTER (
      WHERE gr.pillar = 'producao' AND gr.slug <> 'artifact_published' AND gr.slug NOT LIKE 'showcase%'
        AND gp.created_at >= v_cycle_start
        AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))
    ), 0::bigint)::integer AS cycle_producao_points,
    COALESCE(sum(gp.points) FILTER (
      WHERE gr.pillar = 'curadoria'
        AND gp.created_at >= v_cycle_start
        AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))
    ), 0::bigint)::integer AS cycle_curadoria_points,
    COALESCE(sum(gp.points) FILTER (
      WHERE gr.pillar = 'champions'
        AND gp.created_at >= v_cycle_start
        AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))
    ), 0::bigint)::integer AS cycle_champions_points,
    v_total_count AS total_count
  FROM public.members m
    LEFT JOIN public.gamification_points gp ON gp.member_id = m.id
    LEFT JOIN public.gamification_rules gr
      ON gr.organization_id = gp.organization_id
     AND gr.slug = gp.category
  WHERE m.current_cycle_active = true
    AND m.gamification_opt_out = false
    AND (
      v_scope = 'global'
      OR (v_scope = 'chapter' AND m.chapter = p_chapter_code)
      OR (v_scope = 'tribe' AND EXISTS (
        SELECT 1 FROM public.persons p
        JOIN public.auth_engagements ae ON ae.person_id = p.id
        WHERE p.legacy_member_id = m.id
          AND ae.is_authoritative = true
          AND ae.initiative_id = p_initiative_id
      ))
    )
  GROUP BY m.id, m.name, m.chapter, m.photo_url, m.operational_role, m.designations
  ORDER BY total_points DESC, m.name ASC
  LIMIT v_effective_limit
  OFFSET v_effective_offset;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_gamification_leaderboard(integer, integer, text, text, text, uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
