-- ═══════════════════════════════════════════════════════════════════════════
-- Analytics V2: internal readonly ACL + staged metric contracts
-- Date: 2026-03-12
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create or replace function public.can_read_internal_analytics()
returns boolean
language plpgsql
security definer
stable
as $$
declare
  v_caller record;
begin
  select * into v_caller from public.get_my_member_record();

  if v_caller is null then
    return false;
  end if;

  return v_caller.is_superadmin is true
    or v_caller.operational_role in ('manager', 'deputy_manager')
    or coalesce('co_gp' = any(v_caller.designations), false)
    or coalesce('sponsor' = any(v_caller.designations), false)
    or coalesce('chapter_liaison' = any(v_caller.designations), false)
    or coalesce('curator' = any(v_caller.designations), false);
end;
$$;

grant execute on function public.can_read_internal_analytics() to authenticated;

create or replace function public.analytics_role_bucket(
  p_operational_role text,
  p_designations text[]
)
returns text
language sql
immutable
as $$
  select case
    when p_operational_role = 'manager' then 'manager'
    when p_operational_role = 'deputy_manager' then 'deputy_manager'
    when p_operational_role = 'tribe_leader' then 'tribe_leader'
    when coalesce('ambassador' = any(p_designations), false) then 'ambassador'
    when coalesce('chapter_liaison' = any(p_designations), false) then 'chapter_liaison'
    when coalesce('sponsor' = any(p_designations), false) then 'sponsor'
    when p_operational_role in ('researcher', 'facilitator', 'communicator') then p_operational_role
    when p_operational_role is null or trim(p_operational_role) = '' or p_operational_role = 'none' then 'member'
    else p_operational_role
  end;
$$;

create or replace function public.analytics_is_leadership_role(
  p_operational_role text,
  p_designations text[]
)
returns boolean
language sql
immutable
as $$
  select
    p_operational_role in ('manager', 'deputy_manager', 'tribe_leader')
    or coalesce('ambassador' = any(p_designations), false)
    or coalesce('chapter_liaison' = any(p_designations), false)
    or coalesce('sponsor' = any(p_designations), false);
$$;

create or replace function public.analytics_member_scope(
  p_cycle_code text default null,
  p_tribe_id integer default null,
  p_chapter text default null
)
returns table (
  member_id uuid,
  cycle_code text,
  cycle_label text,
  cycle_start timestamptz,
  cycle_end timestamptz,
  chapter text,
  tribe_id integer,
  first_cycle_start timestamptz,
  first_cycle_code text,
  is_current boolean
)
language sql
security definer
stable
as $$
  with selected_cycle as (
    select
      c.cycle_code,
      c.cycle_label,
      c.cycle_start::timestamptz as cycle_start,
      c.cycle_end::timestamptz as cycle_end,
      c.is_current
    from public.cycles c
    where (p_cycle_code is null and c.is_current is true)
       or c.cycle_code = p_cycle_code
    order by c.is_current desc, c.sort_order desc
    limit 1
  ),
  history_scope as (
    select distinct
      mch.member_id,
      sc.cycle_code,
      sc.cycle_label,
      coalesce(mch.cycle_start::timestamptz, sc.cycle_start) as cycle_start,
      coalesce(mch.cycle_end::timestamptz, sc.cycle_end) as cycle_end,
      coalesce(mch.chapter, m.chapter) as chapter,
      coalesce(mch.tribe_id, m.tribe_id) as tribe_id
    from selected_cycle sc
    join public.member_cycle_history mch on mch.cycle_code = sc.cycle_code
    left join public.members m on m.id = mch.member_id
    where mch.member_id is not null
  ),
  current_fallback as (
    select
      m.id as member_id,
      sc.cycle_code,
      sc.cycle_label,
      sc.cycle_start,
      sc.cycle_end,
      m.chapter,
      m.tribe_id
    from selected_cycle sc
    join public.members m on sc.is_current is true and m.current_cycle_active is true
    left join public.member_cycle_history mch
      on mch.member_id = m.id
     and mch.cycle_code = sc.cycle_code
    where mch.id is null
  ),
  scoped_members as (
    select * from history_scope
    union all
    select * from current_fallback
  ),
  filtered_scope as (
    select distinct *
    from scoped_members
    where (p_tribe_id is null or tribe_id = p_tribe_id)
      and (p_chapter is null or chapter = p_chapter)
  ),
  first_history as (
    select distinct on (mch.member_id)
      mch.member_id,
      coalesce(mch.cycle_start::timestamptz, c.cycle_start::timestamptz, m.created_at) as first_cycle_start,
      coalesce(mch.cycle_code, c.cycle_code) as first_cycle_code
    from public.member_cycle_history mch
    left join public.cycles c on c.cycle_code = mch.cycle_code
    left join public.members m on m.id = mch.member_id
    where mch.member_id is not null
    order by
      mch.member_id,
      coalesce(mch.cycle_start::timestamptz, c.cycle_start::timestamptz, m.created_at),
      c.sort_order nulls last,
      mch.created_at nulls last
  )
  select
    fs.member_id,
    fs.cycle_code,
    fs.cycle_label,
    fs.cycle_start,
    fs.cycle_end,
    fs.chapter,
    fs.tribe_id,
    coalesce(fh.first_cycle_start, m.created_at, fs.cycle_start) as first_cycle_start,
    coalesce(fh.first_cycle_code, fs.cycle_code) as first_cycle_code,
    sc.is_current
  from filtered_scope fs
  cross join selected_cycle sc
  left join first_history fh on fh.member_id = fs.member_id
  left join public.members m on m.id = fs.member_id;
$$;

create or replace function public.exec_funnel_v2(
  p_cycle_code text default null,
  p_tribe_id integer default null,
  p_chapter text default null
)
returns jsonb
language plpgsql
security definer
stable
as $$
declare
  v_result jsonb;
begin
  if not public.can_read_internal_analytics() then
    raise exception 'Internal analytics access required';
  end if;

  with scoped as (
    select * from public.analytics_member_scope(p_cycle_code, p_tribe_id, p_chapter)
  ),
  core_total as (
    select count(*)::integer as total_core_courses
    from public.courses
    where category = 'core'
  ),
  member_core_progress as (
    select
      s.member_id,
      count(distinct cp.course_id) filter (where cp.status = 'completed')::integer as completed_core_courses
    from scoped s
    left join public.course_progress cp on cp.member_id = s.member_id
    left join public.courses c on c.id = cp.course_id and c.category = 'core'
    group by s.member_id
  ),
  published_artifacts as (
    select distinct s.member_id
    from scoped s
    join public.artifacts a on a.member_id = s.member_id
    where a.status = 'published'
      and coalesce(a.published_at, a.created_at, now()) >= s.cycle_start
      and (
        s.cycle_end is null
        or coalesce(a.published_at, a.created_at, now()) < s.cycle_end + interval '1 day'
      )
  ),
  stage_rollup as (
    select
      count(distinct s.member_id)::integer as total_members,
      count(distinct s.member_id) filter (
        where coalesce(mcp.completed_core_courses, 0) >= coalesce((select total_core_courses from core_total), 0)
      )::integer as members_with_full_core_trail,
      count(distinct s.member_id) filter (where s.tribe_id is not null)::integer as members_allocated_to_tribe,
      count(distinct pa.member_id)::integer as members_with_published_artifact
    from scoped s
    left join member_core_progress mcp on mcp.member_id = s.member_id
    left join published_artifacts pa on pa.member_id = s.member_id
  )
  select jsonb_build_object(
    'cycle_code', (select max(cycle_code) from scoped),
    'cycle_label', (select max(cycle_label) from scoped),
    'filters', jsonb_build_object(
      'cycle_code', p_cycle_code,
      'tribe_id', p_tribe_id,
      'chapter', p_chapter
    ),
    'stages', jsonb_build_object(
      'total_members', coalesce((select total_members from stage_rollup), 0),
      'members_with_full_core_trail', coalesce((select members_with_full_core_trail from stage_rollup), 0),
      'members_allocated_to_tribe', coalesce((select members_allocated_to_tribe from stage_rollup), 0),
      'members_with_published_artifact', coalesce((select members_with_published_artifact from stage_rollup), 0)
    ),
    'breakdown_by_tribe', coalesce((
      select jsonb_agg(to_jsonb(t) order by t.tribe_id)
      from (
        select
          s.tribe_id,
          count(distinct s.member_id)::integer as total_members,
          count(distinct s.member_id) filter (
            where coalesce(mcp.completed_core_courses, 0) >= coalesce((select total_core_courses from core_total), 0)
          )::integer as members_with_full_core_trail,
          count(distinct s.member_id) filter (where s.tribe_id is not null)::integer as members_allocated_to_tribe,
          count(distinct pa.member_id)::integer as members_with_published_artifact
        from scoped s
        left join member_core_progress mcp on mcp.member_id = s.member_id
        left join published_artifacts pa on pa.member_id = s.member_id
        where s.tribe_id is not null
        group by s.tribe_id
      ) t
    ), '[]'::jsonb),
    'breakdown_by_chapter', coalesce((
      select jsonb_agg(to_jsonb(c) order by c.chapter)
      from (
        select
          s.chapter,
          count(distinct s.member_id)::integer as total_members,
          count(distinct s.member_id) filter (
            where coalesce(mcp.completed_core_courses, 0) >= coalesce((select total_core_courses from core_total), 0)
          )::integer as members_with_full_core_trail,
          count(distinct s.member_id) filter (where s.tribe_id is not null)::integer as members_allocated_to_tribe,
          count(distinct pa.member_id)::integer as members_with_published_artifact
        from scoped s
        left join member_core_progress mcp on mcp.member_id = s.member_id
        left join published_artifacts pa on pa.member_id = s.member_id
        where s.chapter is not null and trim(s.chapter) <> ''
        group by s.chapter
      ) c
    ), '[]'::jsonb)
  ) into v_result;

  return coalesce(v_result, jsonb_build_object(
    'cycle_code', p_cycle_code,
    'filters', jsonb_build_object('cycle_code', p_cycle_code, 'tribe_id', p_tribe_id, 'chapter', p_chapter),
    'stages', jsonb_build_object(
      'total_members', 0,
      'members_with_full_core_trail', 0,
      'members_allocated_to_tribe', 0,
      'members_with_published_artifact', 0
    ),
    'breakdown_by_tribe', '[]'::jsonb,
    'breakdown_by_chapter', '[]'::jsonb
  ));
end;
$$;

grant execute on function public.exec_funnel_v2(text, integer, text) to authenticated;

create or replace function public.exec_impact_hours_v2(
  p_cycle_code text default null,
  p_tribe_id integer default null,
  p_chapter text default null
)
returns jsonb
language plpgsql
security definer
stable
as $$
declare
  v_result jsonb;
begin
  if not public.can_read_internal_analytics() then
    raise exception 'Internal analytics access required';
  end if;

  with scoped as (
    select * from public.analytics_member_scope(p_cycle_code, p_tribe_id, p_chapter)
  ),
  attendance_scope as (
    select
      s.member_id,
      coalesce(e.tribe_id, s.tribe_id) as tribe_id,
      s.chapter,
      e.id as event_id,
      greatest(coalesce(e.duration_actual, e.duration_minutes, 0), 0)::numeric / 60.0 as impact_hours
    from scoped s
    join public.attendance a on a.member_id = s.member_id and a.present is true
    join public.events e on e.id = a.event_id
    where e.date::timestamptz >= s.cycle_start
      and (
        s.cycle_end is null
        or e.date::timestamptz < s.cycle_end + interval '1 day'
      )
      and (p_tribe_id is null or coalesce(e.tribe_id, s.tribe_id) = p_tribe_id)
      and (p_chapter is null or s.chapter = p_chapter)
  ),
  totals as (
    select
      coalesce(round(sum(impact_hours), 1), 0)::numeric as total_impact_hours,
      count(*)::integer as total_attendances,
      count(distinct event_id)::integer as total_events
    from attendance_scope
  ),
  target_meta as (
    select coalesce(annual_target_hours, 1800)::numeric as annual_target_hours
    from public.impact_hours_total
    limit 1
  )
  select jsonb_build_object(
    'cycle_code', (select max(cycle_code) from scoped),
    'cycle_label', (select max(cycle_label) from scoped),
    'total_impact_hours', coalesce((select total_impact_hours from totals), 0),
    'total_attendances', coalesce((select total_attendances from totals), 0),
    'total_events', coalesce((select total_events from totals), 0),
    'annual_target_hours', coalesce((select annual_target_hours from target_meta), 1800),
    'percent_of_target', case
      when coalesce((select annual_target_hours from target_meta), 0) <= 0 then 0
      else round(
        coalesce((select total_impact_hours from totals), 0)
        * 100
        / nullif((select annual_target_hours from target_meta), 0),
        1
      )
    end,
    'breakdown_by_tribe', coalesce((
      select jsonb_agg(to_jsonb(t) order by t.impact_hours desc, t.tribe_id)
      from (
        select
          tribe_id,
          round(sum(impact_hours), 1)::numeric as impact_hours,
          count(*)::integer as total_attendances,
          count(distinct event_id)::integer as total_events
        from attendance_scope
        where tribe_id is not null
        group by tribe_id
      ) t
    ), '[]'::jsonb),
    'breakdown_by_chapter', coalesce((
      select jsonb_agg(to_jsonb(c) order by c.impact_hours desc, c.chapter)
      from (
        select
          chapter,
          round(sum(impact_hours), 1)::numeric as impact_hours,
          count(*)::integer as total_attendances,
          count(distinct event_id)::integer as total_events
        from attendance_scope
        where chapter is not null and trim(chapter) <> ''
        group by chapter
      ) c
    ), '[]'::jsonb)
  ) into v_result;

  return coalesce(v_result, jsonb_build_object(
    'cycle_code', p_cycle_code,
    'total_impact_hours', 0,
    'total_attendances', 0,
    'total_events', 0,
    'annual_target_hours', 1800,
    'percent_of_target', 0,
    'breakdown_by_tribe', '[]'::jsonb,
    'breakdown_by_chapter', '[]'::jsonb
  ));
end;
$$;

grant execute on function public.exec_impact_hours_v2(text, integer, text) to authenticated;

create or replace function public.exec_certification_delta(
  p_cycle_code text default null,
  p_tribe_id integer default null,
  p_chapter text default null
)
returns jsonb
language plpgsql
security definer
stable
as $$
declare
  v_result jsonb;
begin
  if not public.can_read_internal_analytics() then
    raise exception 'Internal analytics access required';
  end if;

  with scoped as (
    select * from public.analytics_member_scope(p_cycle_code, p_tribe_id, p_chapter)
  ),
  certificates_scoped as (
    select
      s.member_id,
      coalesce(nullif(trim(c.type), ''), nullif(trim(c.title), ''), 'Certification') as certification_type,
      c.title,
      c.issued_at::timestamptz as issued_at,
      case
        when c.issued_at is null then 'unknown'
        when c.issued_at::timestamptz < s.first_cycle_start then 'prior_background'
        else 'hub_impact'
      end as bucket
    from scoped s
    join public.certificates c on c.member_id = s.member_id
  )
  select jsonb_build_object(
    'cycle_code', (select max(cycle_code) from scoped),
    'cycle_label', (select max(cycle_label) from scoped),
    'summary', jsonb_build_object(
      'prior_background', coalesce((select count(*) from certificates_scoped where bucket = 'prior_background'), 0),
      'hub_impact', coalesce((select count(*) from certificates_scoped where bucket = 'hub_impact'), 0),
      'unknown_issue_date', coalesce((select count(*) from certificates_scoped where bucket = 'unknown'), 0),
      'members_in_scope', coalesce((select count(distinct member_id) from scoped), 0)
    ),
    'series', coalesce((
      select jsonb_agg(to_jsonb(s) order by s.certification_type)
      from (
        select
          certification_type,
          count(*) filter (where bucket = 'prior_background')::integer as prior_background,
          count(*) filter (where bucket = 'hub_impact')::integer as hub_impact,
          count(*) filter (where bucket = 'unknown')::integer as unknown_issue_date
        from certificates_scoped
        group by certification_type
        order by count(*) desc, certification_type
        limit 8
      ) s
    ), '[]'::jsonb)
  ) into v_result;

  return coalesce(v_result, jsonb_build_object(
    'cycle_code', p_cycle_code,
    'summary', jsonb_build_object(
      'prior_background', 0,
      'hub_impact', 0,
      'unknown_issue_date', 0,
      'members_in_scope', 0
    ),
    'series', '[]'::jsonb
  ));
end;
$$;

grant execute on function public.exec_certification_delta(text, integer, text) to authenticated;

create or replace function public.exec_chapter_roi(
  p_cycle_code text default null,
  p_tribe_id integer default null,
  p_chapter text default null
)
returns jsonb
language plpgsql
security definer
stable
as $$
declare
  v_result jsonb;
begin
  if not public.can_read_internal_analytics() then
    raise exception 'Internal analytics access required';
  end if;

  with scoped as (
    select * from public.analytics_member_scope(p_cycle_code, p_tribe_id, p_chapter)
  ),
  affiliation_scope as (
    select
      s.member_id,
      a.chapter_code,
      min(coalesce(a.affiliated_since, a.created_at)) as affiliated_since,
      bool_or(coalesce(a.is_current, false)) as is_current,
      min(s.first_cycle_start) as first_cycle_start
    from scoped s
    join public.member_chapter_affiliations a on a.member_id = s.member_id
    where (p_chapter is null or a.chapter_code = p_chapter)
    group by s.member_id, a.chapter_code
  )
  select jsonb_build_object(
    'cycle_code', (select max(cycle_code) from scoped),
    'cycle_label', (select max(cycle_label) from scoped),
    'attribution_window', jsonb_build_object('before_days', 30, 'after_days', 90),
    'chapters', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.attributed_conversions desc, r.chapter_code)
      from (
        select
          chapter_code,
          count(*)::integer as affiliated_members,
          count(*) filter (where is_current)::integer as current_active_affiliates,
          count(*) filter (
            where affiliated_since is not null
              and affiliated_since >= first_cycle_start - interval '30 days'
              and affiliated_since < first_cycle_start + interval '90 days'
          )::integer as attributed_conversions
        from affiliation_scope
        group by chapter_code
      ) r
    ), '[]'::jsonb)
  ) into v_result;

  return coalesce(v_result, jsonb_build_object(
    'cycle_code', p_cycle_code,
    'attribution_window', jsonb_build_object('before_days', 30, 'after_days', 90),
    'chapters', '[]'::jsonb
  ));
end;
$$;

grant execute on function public.exec_chapter_roi(text, integer, text) to authenticated;

create or replace function public.exec_role_transitions(
  p_cycle_code text default null,
  p_tribe_id integer default null,
  p_chapter text default null
)
returns jsonb
language plpgsql
security definer
stable
as $$
declare
  v_result jsonb;
begin
  if not public.can_read_internal_analytics() then
    raise exception 'Internal analytics access required';
  end if;

  with history_rows as (
    select
      mch.member_id,
      mch.cycle_code,
      coalesce(mch.cycle_label, c.cycle_label, mch.cycle_code) as cycle_label,
      coalesce(c.sort_order, 9999) as sort_order,
      coalesce(mch.chapter, m.chapter) as chapter,
      coalesce(mch.tribe_id, m.tribe_id) as tribe_id,
      public.analytics_role_bucket(mch.operational_role, mch.designations) as role_bucket,
      public.analytics_is_leadership_role(mch.operational_role, mch.designations) as is_leadership
    from public.member_cycle_history mch
    left join public.cycles c on c.cycle_code = mch.cycle_code
    left join public.members m on m.id = mch.member_id
    where mch.member_id is not null
  ),
  ordered_transitions as (
    select
      hr.*,
      lag(hr.cycle_code) over (partition by hr.member_id order by hr.sort_order, hr.cycle_code) as from_cycle_code,
      lag(hr.cycle_label) over (partition by hr.member_id order by hr.sort_order, hr.cycle_code) as from_cycle_label,
      lag(hr.role_bucket) over (partition by hr.member_id order by hr.sort_order, hr.cycle_code) as from_role_bucket,
      lag(hr.is_leadership) over (partition by hr.member_id order by hr.sort_order, hr.cycle_code) as from_is_leadership
    from history_rows hr
  ),
  filtered_transitions as (
    select *
    from ordered_transitions
    where from_cycle_code is not null
      and (p_cycle_code is null or cycle_code = p_cycle_code)
      and (p_tribe_id is null or tribe_id = p_tribe_id)
      and (p_chapter is null or chapter = p_chapter)
  ),
  conversion_cycles as (
    select
      cycle_code,
      max(cycle_label) as cycle_label,
      count(distinct member_id)::integer as promoted_members
    from filtered_transitions
    where coalesce(from_is_leadership, false) is false
      and is_leadership is true
    group by cycle_code
  )
  select jsonb_build_object(
    'cycle_code', p_cycle_code,
    'summary', jsonb_build_object(
      'tracked_transitions', coalesce((select count(*) from filtered_transitions), 0),
      'promoted_members', coalesce((
        select sum(promoted_members)::integer from conversion_cycles
      ), 0),
      'leadership_roles', jsonb_build_array(
        'tribe_leader',
        'ambassador',
        'manager',
        'deputy_manager',
        'chapter_liaison',
        'sponsor'
      )
    ),
    'conversions_by_cycle', coalesce((
      select jsonb_agg(to_jsonb(c) order by c.cycle_code)
      from conversion_cycles c
    ), '[]'::jsonb),
    'transition_matrix', coalesce((
      select jsonb_agg(to_jsonb(m) order by m.transitions desc, m.from_role_bucket, m.to_role_bucket)
      from (
        select
          from_role_bucket,
          role_bucket as to_role_bucket,
          count(*)::integer as transitions
        from filtered_transitions
        group by from_role_bucket, role_bucket
      ) m
    ), '[]'::jsonb)
  ) into v_result;

  return coalesce(v_result, jsonb_build_object(
    'cycle_code', p_cycle_code,
    'summary', jsonb_build_object(
      'tracked_transitions', 0,
      'promoted_members', 0,
      'leadership_roles', jsonb_build_array(
        'tribe_leader',
        'ambassador',
        'manager',
        'deputy_manager',
        'chapter_liaison',
        'sponsor'
      )
    ),
    'conversions_by_cycle', '[]'::jsonb,
    'transition_matrix', '[]'::jsonb
  ));
end;
$$;

grant execute on function public.exec_role_transitions(text, integer, text) to authenticated;

commit;
