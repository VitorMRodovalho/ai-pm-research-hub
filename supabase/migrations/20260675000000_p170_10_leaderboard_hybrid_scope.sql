-- p170 #10 — Leaderboard hybrid scope: include alumni with XP in current cycle
--
-- PM ratified Option C: WHERE current_cycle_active=true OR EXISTS gamification_points
-- in current cycle. Captura (a) members ativos hoje, (b) alumni que contribuíram
-- antes do offboarding. Members 100% inativos sem histórico não aparecem.
--
-- Modificações: replace WHERE clauses no COUNT + main SELECT da get_gamification_leaderboard.
--
-- Rollback: re-CREATE FUNCTION sem o OR EXISTS predicado (volta a current_cycle_active=true only).

CREATE OR REPLACE FUNCTION public.get_gamification_leaderboard(
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0,
  p_cycle_code text DEFAULT NULL::text,
  p_scope_kind text DEFAULT 'global'::text,
  p_chapter_code text DEFAULT NULL::text,
  p_initiative_id uuid DEFAULT NULL::uuid
)
RETURNS TABLE(member_id uuid, name text, chapter text, photo_url text, operational_role text, designations text[],
              total_points integer, attendance_points integer, learning_points integer, cert_points integer,
              badge_points integer, artifact_points integer, course_points integer, showcase_points integer,
              bonus_points integer, producao_points integer, curadoria_points integer, champions_points integer,
              cycle_points integer, cycle_attendance_points integer, cycle_course_points integer,
              cycle_artifact_points integer, cycle_showcase_points integer, cycle_bonus_points integer,
              cycle_learning_points integer, cycle_cert_points integer, cycle_badge_points integer,
              cycle_producao_points integer, cycle_curadoria_points integer, cycle_champions_points integer,
              total_count integer)
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
    RAISE EXCEPTION 'chapter_code_required' USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_scope = 'tribe' AND p_initiative_id IS NULL THEN
    RAISE EXCEPTION 'initiative_id_required' USING ERRCODE = 'invalid_parameter_value';
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

  -- p170 #10: hybrid scope — current_cycle_active OR has XP in current cycle
  SELECT COUNT(*) INTO v_total_count
  FROM public.members m
  WHERE m.gamification_opt_out = false
    AND (
      m.current_cycle_active = true
      OR EXISTS (
        SELECT 1 FROM public.gamification_points gp_check
        WHERE gp_check.member_id = m.id
          AND gp_check.created_at >= v_cycle_start
          AND (v_cycle_end IS NULL OR gp_check.created_at < (v_cycle_end + INTERVAL '1 day'))
      )
    )
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
    m.id AS member_id, m.name, m.chapter, m.photo_url, m.operational_role, m.designations,
    COALESCE(sum(gp.points), 0::bigint)::integer AS total_points,
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
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'producao' AND gr.slug <> 'artifact_published' AND gr.slug NOT LIKE 'showcase%'), 0::bigint)::integer AS producao_points,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'curadoria'), 0::bigint)::integer AS curadoria_points,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'champions'), 0::bigint)::integer AS champions_points,
    COALESCE(sum(gp.points) FILTER (
      WHERE gp.created_at >= v_cycle_start
        AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))
    ), 0::bigint)::integer AS cycle_points,
    COALESCE(sum(gp.points) FILTER (
      WHERE gr.pillar = 'presenca' AND gp.created_at >= v_cycle_start
        AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))
    ), 0::bigint)::integer AS cycle_attendance_points,
    COALESCE(sum(gp.points) FILTER (
      WHERE gr.pillar = 'trilha' AND gp.created_at >= v_cycle_start
        AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))
    ), 0::bigint)::integer AS cycle_course_points,
    COALESCE(sum(gp.points) FILTER (
      WHERE gr.slug = 'artifact_published' AND gp.created_at >= v_cycle_start
        AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))
    ), 0::bigint)::integer AS cycle_artifact_points,
    COALESCE(sum(gp.points) FILTER (
      WHERE gr.slug LIKE 'showcase%' AND gp.created_at >= v_cycle_start
        AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))
    ), 0::bigint)::integer AS cycle_showcase_points,
    COALESCE(sum(gp.points) FILTER (
      WHERE (gr.pillar IS NULL OR gr.pillar NOT IN ('presenca','trilha','certificacoes','producao','curadoria','champions'))
        AND gp.created_at >= v_cycle_start
        AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))
    ), 0::bigint)::integer AS cycle_bonus_points,
    COALESCE(sum(gp.points) FILTER (
      WHERE gr.pillar = 'trilha' AND gp.created_at >= v_cycle_start
        AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))
    ), 0::bigint)::integer AS cycle_learning_points,
    COALESCE(sum(gp.points) FILTER (
      WHERE gr.pillar = 'certificacoes' AND gr.slug LIKE 'cert_%'
        AND gp.created_at >= v_cycle_start
        AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))
    ), 0::bigint)::integer AS cycle_cert_points,
    COALESCE(sum(gp.points) FILTER (
      WHERE gr.slug = 'badge' AND gp.created_at >= v_cycle_start
        AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))
    ), 0::bigint)::integer AS cycle_badge_points,
    COALESCE(sum(gp.points) FILTER (
      WHERE gr.pillar = 'producao' AND gr.slug <> 'artifact_published' AND gr.slug NOT LIKE 'showcase%'
        AND gp.created_at >= v_cycle_start
        AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))
    ), 0::bigint)::integer AS cycle_producao_points,
    COALESCE(sum(gp.points) FILTER (
      WHERE gr.pillar = 'curadoria' AND gp.created_at >= v_cycle_start
        AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))
    ), 0::bigint)::integer AS cycle_curadoria_points,
    COALESCE(sum(gp.points) FILTER (
      WHERE gr.pillar = 'champions' AND gp.created_at >= v_cycle_start
        AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))
    ), 0::bigint)::integer AS cycle_champions_points,
    v_total_count AS total_count
  FROM public.members m
    LEFT JOIN public.gamification_points gp ON gp.member_id = m.id
    LEFT JOIN public.gamification_rules gr
      ON gr.organization_id = gp.organization_id
     AND gr.slug = gp.category
  WHERE m.gamification_opt_out = false
    AND (
      m.current_cycle_active = true
      OR EXISTS (
        SELECT 1 FROM public.gamification_points gp_check
        WHERE gp_check.member_id = m.id
          AND gp_check.created_at >= v_cycle_start
          AND (v_cycle_end IS NULL OR gp_check.created_at < (v_cycle_end + INTERVAL '1 day'))
      )
    )
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

COMMENT ON FUNCTION public.get_gamification_leaderboard(integer, integer, text, text, text, uuid) IS
  'p170 #10 — hybrid scope: includes current_cycle_active OR alumni com XP no cycle atual. Resolve desaparecimento de alumni mid-cycle / offboarding-in-flight. PM ratified Option C 2026-05-16.';

NOTIFY pgrst, 'reload schema';
