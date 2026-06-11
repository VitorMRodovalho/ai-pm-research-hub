-- #625 C1 (instância trilha) — surfaced pelo M6 pós-offboarding 2026-06-11:
-- get_public_trail_ranking exibia NOMINALMENTE membro da coorte pré-onboarding
-- ciclo-4 (ativo, sem termo satisfeito, sem login) no ranking público de trilha.
-- Decisão PM #629: público = só operando-no-ciclo. Mesmo fix-pattern da mig 143
-- (get_public_platform_stats / get_homepage_stats): excluir via helper canônico
-- member_is_pre_onboarding (regra única, mig 143).
-- Efeito também converge as coortes de calc_trail_completion_pct (headline) e
-- deste ranking — o contrato M6 (home == ranking ± rounding) volta a ser estrutural.
-- Rollback: re-aplicar o corpo anterior sem a linha do helper (mig de origem do body:
-- ver capture anterior de get_public_trail_ranking).

CREATE OR REPLACE FUNCTION public.get_public_trail_ranking()
 RETURNS TABLE(member_name text, photo_url text, completed integer, in_progress integer, pct integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH trail_courses AS (
    SELECT id FROM courses WHERE is_trail = true
  ),
  trail_total AS (
    SELECT count(*)::int AS cnt FROM trail_courses
  ),
  eligible_members AS (
    SELECT DISTINCT m.id, m.name, m.photo_url
    FROM members m
    WHERE m.is_active AND m.current_cycle_active
      AND m.gamification_opt_out = false
      AND NOT public.member_is_pre_onboarding(m.person_id, m.member_status)
      AND (
        m.tribe_id IS NOT NULL
        OR EXISTS(
          SELECT 1 FROM engagements e
          WHERE e.person_id = m.person_id AND e.status = 'active'
            AND e.role IN ('leader', 'coordinator', 'manager', 'participant')
        )
      )
  ),
  progress AS (
    SELECT cp.member_id, cp.status
    FROM course_progress cp
    JOIN trail_courses tc ON tc.id = cp.course_id
  ),
  member_stats AS (
    SELECT
      p.member_id,
      COUNT(*) FILTER (WHERE p.status = 'completed') AS completed,
      COUNT(*) FILTER (WHERE p.status = 'in_progress') AS in_progress
    FROM progress p
    GROUP BY p.member_id
  )
  SELECT
    em.name,
    em.photo_url,
    COALESCE(ms.completed, 0)::int,
    COALESCE(ms.in_progress, 0)::int,
    CASE WHEN tt.cnt > 0 THEN ROUND(COALESCE(ms.completed, 0)::numeric / tt.cnt * 100)::int ELSE 0 END
  FROM eligible_members em
  CROSS JOIN trail_total tt
  LEFT JOIN member_stats ms ON ms.member_id = em.id
  ORDER BY COALESCE(ms.completed, 0) DESC, COALESCE(ms.in_progress, 0) DESC, em.name;
$function$;
