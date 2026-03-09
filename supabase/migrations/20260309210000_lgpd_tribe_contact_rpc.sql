-- P2.2: Secure RPC for tribe leaders/admins to see member contact info
-- Regular members see public_members (no PII). This RPC provides
-- email + phone only to the tribe leader (own tribe) or admin+.

create or replace function public.get_tribe_member_contacts(p_tribe_id integer)
returns json
language plpgsql security definer stable as $$
declare
  caller record;
  is_tribe_leader boolean;
  is_admin boolean;
begin
  select * into caller from public.get_my_member_record();
  if caller is null then
    return '{}';
  end if;

  is_admin := caller.is_superadmin = true
    or caller.operational_role in ('manager', 'deputy_manager');

  is_tribe_leader := caller.operational_role = 'tribe_leader'
    and caller.tribe_id = p_tribe_id;

  if not (is_admin or is_tribe_leader) then
    return '{}';
  end if;

  return (
    select coalesce(
      json_object_agg(m.id, json_build_object('email', m.email, 'phone', m.phone)),
      '{}'::json
    )
    from public.members m
    where m.tribe_id = p_tribe_id
      and m.current_cycle_active = true
  );
end;
$$;

grant execute on function public.get_tribe_member_contacts(integer) to authenticated;

-- Analytics helper RPCs (P2.3)
-- exec_funnel_summary: returns member funnel stages
drop function if exists public.exec_funnel_summary();
create or replace function public.exec_funnel_summary()
returns json
language plpgsql security definer stable as $$
declare
  caller record;
  result json;
begin
  select * into caller from public.get_my_member_record();
  if caller is null or (
    caller.is_superadmin is not true
    and caller.operational_role not in ('manager', 'deputy_manager')
  ) then
    return '{}';
  end if;

  select json_build_object(
    'total_members', (select count(*) from members where current_cycle_active = true),
    'with_tribe', (select count(*) from members where current_cycle_active = true and tribe_id is not null),
    'with_credly', (select count(*) from members where current_cycle_active = true and credly_profile_url is not null and credly_profile_url != ''),
    'with_photo', (select count(*) from members where current_cycle_active = true and photo_url is not null and photo_url != ''),
    'with_linkedin', (select count(*) from members where current_cycle_active = true and linkedin is not null and linkedin != ''),
    'tribe_leaders', (select count(*) from members where current_cycle_active = true and operational_role = 'tribe_leader'),
    'total_artifacts', (select count(*) from artifacts where status = 'published'),
    'total_events', (select count(*) from events),
    'total_broadcasts', (select count(*) from broadcast_log)
  ) into result;

  return result;
end;
$$;

grant execute on function public.exec_funnel_summary() to authenticated;

-- exec_skills_radar: returns skill distribution across tribes
drop function if exists public.exec_skills_radar();
create or replace function public.exec_skills_radar()
returns json
language plpgsql security definer stable as $$
declare
  caller record;
  result json;
begin
  select * into caller from public.get_my_member_record();
  if caller is null or (
    caller.is_superadmin is not true
    and caller.operational_role not in ('manager', 'deputy_manager')
  ) then
    return '{}';
  end if;

  select coalesce(json_agg(row_to_json(t)), '[]'::json)
  into result
  from (
    select
      tr.id as tribe_id,
      tr.name as tribe_name,
      count(m.id) as member_count,
      count(case when m.credly_profile_url is not null and m.credly_profile_url != '' then 1 end) as credly_count,
      count(case when m.photo_url is not null and m.photo_url != '' then 1 end) as photo_count,
      count(case when m.linkedin is not null and m.linkedin != '' then 1 end) as linkedin_count,
      coalesce((
        select count(*)::int from artifacts a where a.status = 'published'
        and exists(select 1 from members am where am.id = a.member_id and am.tribe_id = tr.id)
      ), 0) as artifacts_count
    from tribes tr
    left join members m on m.tribe_id = tr.id and m.current_cycle_active = true
    where tr.is_active = true
    group by tr.id, tr.name
    order by tr.id
  ) t;

  return result;
end;
$$;

grant execute on function public.exec_skills_radar() to authenticated;
