-- ═══════════════════════════════════════════════════════════════
-- Sprint 1 (Wave 3): Cycle-aware Gamification Leaderboard
-- Rebuilds gamification_leaderboard with cycle_points column
-- and adds helper RPCs for profile cycle XP.
-- ═══════════════════════════════════════════════════════════════

begin;

-- ───────────────────────────────────────────────────────────────
-- 1. Recreate gamification_leaderboard VIEW
--    total_points = lifetime (all rows)
--    cycle_points = points earned since current cycle start
-- ───────────────────────────────────────────────────────────────

drop view if exists public.gamification_leaderboard cascade;

create or replace view public.gamification_leaderboard as
with current_cycle as (
  select cycle_start from public.cycles where is_current = true limit 1
)
select
  m.id as member_id,
  m.name,
  m.chapter,
  m.photo_url,
  m.operational_role,
  m.role,
  m.designations,
  coalesce(sum(gp.points), 0)::int as total_points,
  coalesce(sum(gp.points) filter (where gp.category = 'attendance'), 0)::int as attendance_points,
  coalesce(sum(gp.points) filter (where gp.category = 'course'), 0)::int as course_points,
  coalesce(sum(gp.points) filter (where gp.category = 'artifact'), 0)::int as artifact_points,
  coalesce(sum(gp.points) filter (where gp.category not in ('attendance','course','artifact')), 0)::int as bonus_points,
  coalesce(sum(gp.points) filter (where gp.created_at >= (select cycle_start from current_cycle)), 0)::int as cycle_points,
  coalesce(sum(gp.points) filter (where gp.category = 'attendance' and gp.created_at >= (select cycle_start from current_cycle)), 0)::int as cycle_attendance_points,
  coalesce(sum(gp.points) filter (where gp.category = 'course' and gp.created_at >= (select cycle_start from current_cycle)), 0)::int as cycle_course_points,
  coalesce(sum(gp.points) filter (where gp.category = 'artifact' and gp.created_at >= (select cycle_start from current_cycle)), 0)::int as cycle_artifact_points,
  coalesce(sum(gp.points) filter (
    where gp.category not in ('attendance','course','artifact')
      and gp.created_at >= (select cycle_start from current_cycle)
  ), 0)::int as cycle_bonus_points
from public.members m
left join public.gamification_points gp on gp.member_id = m.id
where m.current_cycle_active = true
group by m.id, m.name, m.chapter, m.photo_url, m.operational_role, m.designations, m.role;

-- ───────────────────────────────────────────────────────────────
-- 2. RPC: get_member_cycle_xp
--    Returns cycle vs lifetime XP breakdown for a specific member.
--    Used by profile.astro Dashboard section.
-- ───────────────────────────────────────────────────────────────

drop function if exists public.get_member_cycle_xp(uuid);

create or replace function public.get_member_cycle_xp(p_member_id uuid)
returns json
language plpgsql security definer stable as $$
declare
  cycle_start_date date;
  result json;
begin
  select cycle_start into cycle_start_date
  from public.cycles where is_current = true limit 1;

  if cycle_start_date is null then
    cycle_start_date := '2026-01-01';
  end if;

  select json_build_object(
    'lifetime_points', coalesce(sum(points), 0)::int,
    'cycle_points', coalesce(sum(points) filter (where created_at >= cycle_start_date), 0)::int,
    'cycle_attendance', coalesce(sum(points) filter (where category = 'attendance' and created_at >= cycle_start_date), 0)::int,
    'cycle_courses', coalesce(sum(points) filter (where category = 'course' and created_at >= cycle_start_date), 0)::int,
    'cycle_artifacts', coalesce(sum(points) filter (where category = 'artifact' and created_at >= cycle_start_date), 0)::int,
    'cycle_bonus', coalesce(sum(points) filter (where category not in ('attendance','course','artifact') and created_at >= cycle_start_date), 0)::int,
    'cycle_code', (select cycle_code from public.cycles where is_current = true limit 1),
    'cycle_label', (select cycle_label from public.cycles where is_current = true limit 1)
  ) into result
  from public.gamification_points
  where member_id = p_member_id;

  return coalesce(result, '{}');
end;
$$;

grant execute on function public.get_member_cycle_xp(uuid) to authenticated;

commit;
