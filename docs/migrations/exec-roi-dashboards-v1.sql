-- EXEC_ROI_DASHBOARDS_V1
-- Purpose: provide curated executive analytics models for /admin dashboards.

-- ── View 1: Funnel snapshot ─────────────────────────────────────────────
create or replace view public.vw_exec_funnel as
with base_members as (
  select
    m.id,
    coalesce(m.current_cycle_active, false) as current_cycle_active,
    coalesce(m.operational_role, 'guest') as operational_role,
    nullif(trim(coalesce(m.credly_url, '')), '') as credly_url
  from public.members m
  where coalesce(m.operational_role, 'guest') <> 'guest'
),
trail_progress as (
  select
    cp.member_id,
    count(*) filter (
      where cp.status = 'completed'
        and c.code in ('GENAI_OVERVIEW','DATA_LANDSCAPE','PROMPT_ENG','PRACTICAL_GENAI','CDBA_INTRO','CPMAI_INTRO','AI_INFRA','AI_AGILE')
    )::integer as core_completed
  from public.course_progress cp
  join public.courses c on c.id = cp.course_id
  group by cp.member_id
),
credly_points as (
  select gp.member_id,
         max(case when gp.points >= 25 then 1 else 0 end) as has_tier2_plus,
         max(case when gp.points >= 50 then 1 else 0 end) as has_tier1
  from public.gamification_points gp
  where gp.reason ilike 'Credly:%'
  group by gp.member_id
),
published_artifacts as (
  select a.member_id, count(*)::integer as qty
  from public.artifacts a
  where a.status = 'published'
  group by a.member_id
)
select
  now()::date as snapshot_date,
  count(*)::integer as total_members,
  count(*) filter (where bm.current_cycle_active)::integer as active_members,
  count(*) filter (where bm.credly_url is not null)::integer as members_with_credly_url,
  count(*) filter (where coalesce(cp.has_tier2_plus, 0) = 1)::integer as members_with_tier2_plus,
  count(*) filter (where coalesce(cp.has_tier1, 0) = 1)::integer as members_with_tier1,
  count(*) filter (where coalesce(tp.core_completed, 0) >= 8)::integer as members_with_full_core_trail,
  count(*) filter (where coalesce(pa.qty, 0) > 0)::integer as members_with_published_artifact,
  coalesce(sum(pa.qty), 0)::integer as total_published_artifacts
from base_members bm
left join trail_progress tp on tp.member_id = bm.id
left join credly_points cp on cp.member_id = bm.id
left join published_artifacts pa on pa.member_id = bm.id;

-- ── View 2: Certification timeline by cohort month ─────────────────────
create or replace view public.vw_exec_cert_timeline as
with cohort as (
  select
    m.id as member_id,
    date_trunc('month', coalesce(m.created_at, now()))::date as cohort_month,
    coalesce(m.created_at, now()) as joined_at
  from public.members m
  where coalesce(m.operational_role, 'guest') <> 'guest'
),
first_tier2 as (
  select gp.member_id, min(gp.created_at) as first_tier2_at
  from public.gamification_points gp
  where gp.reason ilike 'Credly:%'
    and gp.points >= 25
  group by gp.member_id
),
first_tier1 as (
  select gp.member_id, min(gp.created_at) as first_tier1_at
  from public.gamification_points gp
  where gp.reason ilike 'Credly:%'
    and gp.points >= 50
  group by gp.member_id
)
select
  c.cohort_month,
  count(*)::integer as members_in_cohort,
  count(*) filter (where t2.first_tier2_at is not null)::integer as members_with_tier2,
  count(*) filter (where t1.first_tier1_at is not null)::integer as members_with_tier1,
  round((100.0 * count(*) filter (where t2.first_tier2_at is not null) / nullif(count(*), 0))::numeric, 2) as pct_with_tier2,
  round((100.0 * count(*) filter (where t1.first_tier1_at is not null) / nullif(count(*), 0))::numeric, 2) as pct_with_tier1,
  round(avg(extract(epoch from (t2.first_tier2_at - c.joined_at)) / 86400.0) filter (where t2.first_tier2_at is not null)::numeric, 2) as avg_days_to_tier2,
  round(avg(extract(epoch from (t1.first_tier1_at - c.joined_at)) / 86400.0) filter (where t1.first_tier1_at is not null)::numeric, 2) as avg_days_to_tier1
from cohort c
left join first_tier2 t2 on t2.member_id = c.member_id
left join first_tier1 t1 on t1.member_id = c.member_id
group by c.cohort_month
order by c.cohort_month desc;

-- ── View 3: Skills radar by badge signal taxonomy ──────────────────────
create or replace view public.vw_exec_skills_radar as
with raw as (
  select
    gp.member_id,
    gp.points,
    lower(gp.reason) as reason_lc,
    case
      when gp.reason ilike '%pmp%' or gp.reason ilike '%capm%' or gp.reason ilike '%project management%' then 'pm_core'
      when gp.reason ilike '%scrum%' or gp.reason ilike '%agile%' or gp.reason ilike '%safe%' then 'agile_delivery'
      when gp.reason ilike '%data%' or gp.reason ilike '%business intelligence%' or gp.reason ilike '%ai%' or gp.reason ilike '%genai%' then 'data_ai'
      when gp.reason ilike '%governan%' or gp.reason ilike '%itil%' or gp.reason ilike '%togaf%' or gp.reason ilike '%cobit%' then 'governance'
      when gp.reason ilike '%change%' or gp.reason ilike '%prosci%' then 'change_leadership'
      else 'other'
    end as radar_axis
  from public.gamification_points gp
  where gp.reason ilike 'Credly:%'
),
agg as (
  select
    radar_axis,
    count(distinct member_id)::integer as members_with_signal,
    count(*)::integer as badges_count,
    coalesce(sum(points), 0)::integer as total_points,
    round(avg(points)::numeric, 2) as avg_points
  from raw
  group by radar_axis
)
select
  radar_axis,
  members_with_signal,
  badges_count,
  total_points,
  avg_points
from agg
order by total_points desc, members_with_signal desc;

-- ── RPC wrappers with admin+ gate ───────────────────────────────────────
create or replace function public.exec_funnel_summary()
returns table (
  snapshot_date date,
  total_members integer,
  active_members integer,
  members_with_credly_url integer,
  members_with_tier2_plus integer,
  members_with_tier1 integer,
  members_with_full_core_trail integer,
  members_with_published_artifact integer,
  total_published_artifacts integer
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not public.has_min_tier(4) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;

  return query
  select
    v.snapshot_date,
    v.total_members,
    v.active_members,
    v.members_with_credly_url,
    v.members_with_tier2_plus,
    v.members_with_tier1,
    v.members_with_full_core_trail,
    v.members_with_published_artifact,
    v.total_published_artifacts
  from public.vw_exec_funnel v;
end;
$$;

revoke all on function public.exec_funnel_summary() from public;
grant execute on function public.exec_funnel_summary() to authenticated;

create or replace function public.exec_cert_timeline(p_months integer default 12)
returns table (
  cohort_month date,
  members_in_cohort integer,
  members_with_tier2 integer,
  members_with_tier1 integer,
  pct_with_tier2 numeric,
  pct_with_tier1 numeric,
  avg_days_to_tier2 numeric,
  avg_days_to_tier1 numeric
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not public.has_min_tier(4) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;

  return query
  select
    v.cohort_month,
    v.members_in_cohort,
    v.members_with_tier2,
    v.members_with_tier1,
    v.pct_with_tier2,
    v.pct_with_tier1,
    v.avg_days_to_tier2,
    v.avg_days_to_tier1
  from public.vw_exec_cert_timeline v
  where v.cohort_month >= (date_trunc('month', now())::date - make_interval(months => greatest(1, least(coalesce(p_months, 12), 60))))
  order by v.cohort_month desc;
end;
$$;

revoke all on function public.exec_cert_timeline(integer) from public;
grant execute on function public.exec_cert_timeline(integer) to authenticated;

create or replace function public.exec_skills_radar()
returns table (
  radar_axis text,
  members_with_signal integer,
  badges_count integer,
  total_points integer,
  avg_points numeric
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not public.has_min_tier(4) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;

  return query
  select
    v.radar_axis,
    v.members_with_signal,
    v.badges_count,
    v.total_points,
    v.avg_points
  from public.vw_exec_skills_radar v
  order by v.total_points desc, v.members_with_signal desc;
end;
$$;

revoke all on function public.exec_skills_radar() from public;
grant execute on function public.exec_skills_radar() to authenticated;
