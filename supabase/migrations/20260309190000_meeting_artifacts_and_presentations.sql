-- ═══════════════════════════════════════════════════════════════════════════
-- S-PRES1: Meeting Artifacts + Presentation Snapshots
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- 1. meeting_artifacts: stores recording links, agendas, and presentation snapshots
create table if not exists public.meeting_artifacts (
  id             uuid primary key default gen_random_uuid(),
  event_id       uuid references public.events(id),
  title          text not null,
  meeting_date   date not null,
  recording_url  text,
  agenda_items   text[],
  page_data_snapshot jsonb,
  cycle_code     text default 'cycle_3',
  tribe_id       integer references public.tribes(id),
  created_by     uuid references public.members(id),
  is_published   boolean not null default false,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

alter table public.meeting_artifacts enable row level security;

create policy meeting_artifacts_select on public.meeting_artifacts
  for select to authenticated
  using (
    is_published = true
    or (select r.is_superadmin from public.get_my_member_record() r)
    or (select r.operational_role in ('manager', 'deputy_manager', 'tribe_leader')
        from public.get_my_member_record() r)
  );

create policy meeting_artifacts_manage on public.meeting_artifacts
  for all to authenticated
  using ((select r.is_superadmin from public.get_my_member_record() r)
    or (select r.operational_role in ('manager', 'deputy_manager')
        from public.get_my_member_record() r));

-- 2. RPC: list published meeting artifacts for the presentations page
create or replace function public.list_meeting_artifacts(
  p_limit integer default 20
)
returns setof public.meeting_artifacts
language sql security definer stable as $$
  select * from public.meeting_artifacts
  where is_published = true
  order by meeting_date desc
  limit p_limit;
$$;

grant execute on function public.list_meeting_artifacts(integer) to authenticated;
grant execute on function public.list_meeting_artifacts(integer) to anon;

-- 3. RPC: save presentation snapshot (admin+)
create or replace function public.save_presentation_snapshot(
  p_title text,
  p_meeting_date date,
  p_recording_url text default null,
  p_agenda_items text[] default '{}',
  p_snapshot jsonb default '{}'::jsonb,
  p_event_id uuid default null,
  p_tribe_id integer default null
)
returns uuid
language plpgsql security definer as $$
declare
  v_caller record;
  v_id uuid;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null or not (
    v_caller.is_superadmin
    or v_caller.operational_role in ('manager', 'deputy_manager')
  ) then
    raise exception 'Admin access required';
  end if;

  insert into public.meeting_artifacts
    (title, meeting_date, recording_url, agenda_items, page_data_snapshot,
     event_id, tribe_id, created_by, is_published)
  values
    (p_title, p_meeting_date, p_recording_url, p_agenda_items, p_snapshot,
     p_event_id, p_tribe_id, v_caller.id, false)
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.save_presentation_snapshot(text, date, text, text[], jsonb, uuid, integer) to authenticated;

commit;
