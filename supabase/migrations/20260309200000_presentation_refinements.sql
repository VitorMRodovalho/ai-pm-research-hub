-- ═══════════════════════════════════════════════════════════════════════════
-- S-PRES1 Refinements + Tribe Counter Fix (P0)
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ─── P0: Tribe Counter Fix ─────────────────────────────────────────────────
-- tribe_selections may have RLS that blocks anon reads, causing 0/6 on home.
-- Create a SECURITY DEFINER RPC that returns counts safely for any caller.

create or replace function public.count_tribe_slots()
returns json
language sql security definer stable as $$
  select coalesce(
    json_object_agg(tribe_id, cnt),
    '{}'::json
  )
  from (
    select tribe_id, count(*)::int as cnt
    from public.tribe_selections
    group by tribe_id
  ) sub;
$$;

grant execute on function public.count_tribe_slots() to authenticated;
grant execute on function public.count_tribe_slots() to anon;

-- ─── Presentation Refinements ──────────────────────────────────────────────

-- 1. Add deliberations column
do $$ begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'meeting_artifacts' and column_name = 'deliberations'
  ) then
    alter table public.meeting_artifacts add column deliberations text[] default '{}';
  end if;
end $$;

-- 2. Allow anon to read published artifacts
grant select on public.meeting_artifacts to anon;

-- 3. Drop + recreate save_presentation_snapshot to allow tribe leaders
drop function if exists public.save_presentation_snapshot(text, date, text, text[], jsonb, uuid, integer);
drop function if exists public.save_presentation_snapshot(text, date, text, text[], jsonb, uuid, integer, text[]);

create or replace function public.save_presentation_snapshot(
  p_title text,
  p_meeting_date date,
  p_recording_url text default null,
  p_agenda_items text[] default '{}',
  p_snapshot jsonb default '{}'::jsonb,
  p_event_id uuid default null,
  p_tribe_id integer default null,
  p_deliberations text[] default '{}',
  p_is_published boolean default false
)
returns uuid
language plpgsql security definer as $$
declare
  v_caller record;
  v_id uuid;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null then
    raise exception 'Not authenticated';
  end if;

  if v_caller.is_superadmin or v_caller.operational_role in ('manager', 'deputy_manager') then
    null; -- admin+ can save any scope
  elsif v_caller.operational_role = 'tribe_leader' then
    if p_tribe_id is null or p_tribe_id != v_caller.tribe_id then
      raise exception 'Leaders can only save snapshots for their own tribe';
    end if;
  else
    raise exception 'Insufficient permissions';
  end if;

  insert into public.meeting_artifacts
    (title, meeting_date, recording_url, agenda_items, page_data_snapshot,
     event_id, tribe_id, created_by, is_published, deliberations)
  values
    (p_title, p_meeting_date, p_recording_url, p_agenda_items, p_snapshot,
     p_event_id, p_tribe_id, v_caller.id, p_is_published, p_deliberations)
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.save_presentation_snapshot(text, date, text, text[], jsonb, uuid, integer, text[], boolean) to authenticated;

-- 4. Drop + recreate list_meeting_artifacts with optional tribe filter
drop function if exists public.list_meeting_artifacts(integer);
drop function if exists public.list_meeting_artifacts(integer, integer);

create or replace function public.list_meeting_artifacts(
  p_limit integer default 20,
  p_tribe_id integer default null
)
returns setof public.meeting_artifacts
language sql security definer stable as $$
  select * from public.meeting_artifacts
  where is_published = true
    and (p_tribe_id is null or tribe_id = p_tribe_id or tribe_id is null)
  order by meeting_date desc
  limit p_limit;
$$;

grant execute on function public.list_meeting_artifacts(integer, integer) to authenticated;
grant execute on function public.list_meeting_artifacts(integer, integer) to anon;

-- 5. Update manage policy for tribe_leader scoped access
drop policy if exists meeting_artifacts_manage on public.meeting_artifacts;

create policy meeting_artifacts_manage on public.meeting_artifacts
  for all to authenticated
  using (
    (select r.is_superadmin from public.get_my_member_record() r)
    or (select r.operational_role in ('manager', 'deputy_manager')
        from public.get_my_member_record() r)
    or (
      (select r.operational_role from public.get_my_member_record() r) = 'tribe_leader'
      and tribe_id = (select r.tribe_id from public.get_my_member_record() r)
    )
  );

commit;
