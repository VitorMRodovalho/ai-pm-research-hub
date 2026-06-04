-- #419 Bucket-B "M5 / D1" — fix get_member_cycle_xp rank to match the displayed cycle XP.
--
-- PROBLEM (live-grounded 2026-06-04, cycle_3 start 2026-03-01):
--   get_member_cycle_xp DISPLAYS each member's cycle XP (points since cycle_start)
--   but computed rank_position by LIFETIME XP (ROW_NUMBER() OVER (ORDER BY SUM(points) DESC),
--   no cycle filter, no tiebreak). So the #1 cycle earner (Hayala Curto, 435 cycle XP)
--   surfaced at rank #12 (her all-time total), and tied cycle scores (31 of 60 members
--   share a cycle-XP value) ranked non-deterministically.
--
-- FIX (body-only, same signature get_member_cycle_xp(p_member_id uuid) RETURNS json):
--   1. rank by cycle XP: COALESCE(SUM(points) FILTER (WHERE created_at >= cycle_start_date), 0)
--   2. deterministic member_id tiebreak in the ROW_NUMBER ORDER BY
--   3. remove the dead hardcoded January-1 literal fallback (the cycle window now comes solely
--      from the current cycle; the literal could only ever have produced a wrong window if it fired)
--   The self-or-view_pii auth gate, SECURITY DEFINER, search_path, and every displayed field
--   (lifetime_points, cycle_*, cycle_code/label, total_ranked) are UNCHANGED.
--
-- Sole consumers of rank_position are the MCP/chat tools (get_my_xp_and_ranking,
-- get_member_cycle_xp, get_in_dashboard composite). No web surface renders rank_position
-- (profile.astro reads only points). get_public_leaderboard stays lifetime-by-design.
--
-- ROLLBACK: re-apply the prior body captured in
--   20260805000055_p276_bucket_a_lgpd_auth_hardening.sql. Same-signature CREATE OR REPLACE; no DROP.

CREATE OR REPLACE FUNCTION public.get_member_cycle_xp(p_member_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  cycle_start_date date;
  v_rank int;
  v_total int;
  result json;
  v_caller_id uuid;
begin
  -- XP gate: SECDEF + authenticated-grant allowed enumerating any member's XP/rank by id.
  select id into v_caller_id from public.members where auth_id = auth.uid() and is_active = true;
  if v_caller_id is null then
    raise exception 'Not authenticated' using errcode = 'insufficient_privilege';
  end if;
  if p_member_id <> v_caller_id and not public.can_by_member(v_caller_id, 'view_pii') then
    raise exception 'Unauthorized' using errcode = 'insufficient_privilege';
  end if;

  -- Cycle window comes solely from the current cycle (the prior hardcoded literal fallback was removed).
  select cycle_start into cycle_start_date
  from public.cycles where is_current = true limit 1;

  -- M5 (#419 D1): rank by THIS cycle's XP (matches the displayed cycle_points), with a
  -- deterministic member_id tiebreak. Previously ranked on lifetime SUM(points), which
  -- contradicted the cycle_points shown and reshuffled ties non-deterministically.
  WITH ranked AS (
    SELECT member_id,
           COALESCE(SUM(points) FILTER (WHERE created_at >= cycle_start_date), 0) as cycle_pts,
           ROW_NUMBER() OVER (
             ORDER BY COALESCE(SUM(points) FILTER (WHERE created_at >= cycle_start_date), 0) DESC,
                      member_id
           ) as pos
    FROM public.gamification_points
    GROUP BY member_id
  )
  SELECT pos, (SELECT COUNT(DISTINCT member_id) FROM public.gamification_points)
  INTO v_rank, v_total
  FROM ranked WHERE member_id = p_member_id;

  select json_build_object(
    'lifetime_points', coalesce(sum(points), 0)::int,
    'cycle_points', coalesce(sum(points) filter (where created_at >= cycle_start_date), 0)::int,
    'cycle_attendance', coalesce(sum(points) filter (where category = 'attendance' and created_at >= cycle_start_date), 0)::int,
    'cycle_learning', coalesce(sum(points) filter (where category in ('trail', 'course', 'knowledge_ai_pm') and created_at >= cycle_start_date), 0)::int,
    'cycle_certs', coalesce(sum(points) filter (where category in ('cert_pmi_senior', 'cert_cpmai', 'cert_pmi_mid', 'cert_pmi_practitioner', 'cert_pmi_entry') and created_at >= cycle_start_date), 0)::int,
    'cycle_courses', coalesce(sum(points) filter (where category in ('trail', 'course', 'knowledge_ai_pm') and created_at >= cycle_start_date), 0)::int,
    'cycle_artifacts', coalesce(sum(points) filter (where category = 'artifact' and created_at >= cycle_start_date), 0)::int,
    'cycle_showcase', coalesce(sum(points) filter (where category = 'showcase' and created_at >= cycle_start_date), 0)::int,
    'cycle_bonus', coalesce(sum(points) filter (where category not in ('attendance','trail','course','knowledge_ai_pm','cert_pmi_senior','cert_cpmai','cert_pmi_mid','cert_pmi_practitioner','cert_pmi_entry','artifact','badge','specialization','showcase') and created_at >= cycle_start_date), 0)::int,
    'cycle_code', (select cycle_code from public.cycles where is_current = true limit 1),
    'cycle_label', (select cycle_label from public.cycles where is_current = true limit 1),
    'rank_position', coalesce(v_rank, 0),
    'total_ranked', coalesce(v_total, 0)
  ) into result
  from public.gamification_points
  where member_id = p_member_id;

  return coalesce(result, '{}');
end;
$function$;

NOTIFY pgrst, 'reload schema';
