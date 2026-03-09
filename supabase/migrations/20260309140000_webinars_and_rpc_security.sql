-- ═══════════════════════════════════════════════════════════════════════════
-- Wave 4 Expansion: Webinars schema + RPC security hardening
-- Date: 2026-03-09
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 1: Webinars table for chapter partnership calendar
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.webinars (
  id            uuid primary key default gen_random_uuid(),
  title         text not null,
  description   text,
  scheduled_at  timestamptz not null,
  duration_min  integer not null default 60,
  status        text not null default 'planned'
                  check (status in ('planned','confirmed','completed','cancelled')),
  chapter_code  text not null
                  check (chapter_code in ('CE','DF','GO','MG','RS','ALL')),
  tribe_id      integer references public.tribes(id),
  organizer_id  uuid references public.members(id),
  meeting_link  text,
  youtube_url   text,
  notes         text,
  created_by    uuid references auth.users(id) default auth.uid(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.webinars is 'Calendar of webinars/partnerships with PMI chapters (CE, DF, GO, MG, RS)';

create index if not exists idx_webinars_scheduled on public.webinars (scheduled_at desc);
create index if not exists idx_webinars_chapter   on public.webinars (chapter_code);
create index if not exists idx_webinars_status    on public.webinars (status);

alter table public.webinars enable row level security;

-- Authenticated users can view all webinars
create policy webinars_select on public.webinars
  for select to authenticated
  using (true);

-- Only admin+ can manage webinars
create policy webinars_insert on public.webinars
  for insert to authenticated
  with check (
    (select r.operational_role in ('manager','deputy_manager') or r.is_superadmin
     from public.get_my_member_record() r)
  );

create policy webinars_update on public.webinars
  for update to authenticated
  using (
    (select r.operational_role in ('manager','deputy_manager') or r.is_superadmin
     from public.get_my_member_record() r)
  );

create policy webinars_delete on public.webinars
  for delete to authenticated
  using (
    (select r.is_superadmin from public.get_my_member_record() r)
  );

-- Auto-update updated_at trigger
create or replace function public.webinars_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_webinars_updated_at on public.webinars;
create trigger trg_webinars_updated_at
  before update on public.webinars
  for each row execute function public.webinars_set_updated_at();

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 2: RPC for webinar CRUD (admin-only create/update)
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.list_webinars(p_status text default null)
returns setof public.webinars
language sql security definer stable as $$
  select * from public.webinars
  where (p_status is null or status = p_status)
  order by scheduled_at desc;
$$;

grant execute on function public.list_webinars(text) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 3: Dashboard RPCs for /admin/comms
-- ═══════════════════════════════════════════════════════════════════════════

-- Tribe engagement ranking: hours of impact per tribe
create or replace function public.tribe_impact_ranking()
returns table (
  tribe_id   integer,
  tribe_name text,
  total_events bigint,
  total_hours  numeric,
  avg_attendance numeric
) language sql security definer stable as $$
  select
    t.id as tribe_id,
    t.name as tribe_name,
    count(distinct e.id) as total_events,
    coalesce(sum(e.duration_minutes)::numeric / 60.0, 0) as total_hours,
    case when count(distinct e.id) = 0 then 0
         else (count(a.id)::numeric / count(distinct e.id))
    end as avg_attendance
  from public.tribes t
  left join public.events e on e.tribe_id = t.id
  left join public.attendance a on a.event_id = e.id and a.present = true
  group by t.id, t.name
  order by total_hours desc;
$$;

grant execute on function public.tribe_impact_ranking() to authenticated;

-- Broadcast history for a specific tribe (or all)
create or replace function public.broadcast_history(p_tribe_id integer default null, p_limit integer default 20)
returns table (
  id uuid,
  tribe_id integer,
  tribe_name text,
  subject text,
  recipient_count integer,
  sent_at timestamptz,
  sent_by_name text
) language sql security definer stable as $$
  select
    bl.id,
    bl.tribe_id,
    t.name as tribe_name,
    bl.subject,
    bl.recipient_count,
    bl.sent_at,
    m.name as sent_by_name
  from public.broadcast_log bl
  left join public.tribes t on t.id = bl.tribe_id
  left join public.members m on m.id = bl.sender_id
  where (p_tribe_id is null or bl.tribe_id = p_tribe_id)
  order by bl.sent_at desc
  limit p_limit;
$$;

grant execute on function public.broadcast_history(integer, integer) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 4: Security hardening for list_tribe_deliverables
-- ═══════════════════════════════════════════════════════════════════════════

-- Add auth check: caller must be tribe member, leader, or admin
drop function if exists public.list_tribe_deliverables(integer, text);

create or replace function public.list_tribe_deliverables(p_tribe_id integer, p_cycle_code text default null)
returns setof public.tribe_deliverables
language plpgsql security definer stable as $$
declare
  rec record;
begin
  select * into rec from public.get_my_member_record();
  if rec is null then
    raise exception 'Not authenticated';
  end if;

  -- Admin/SA can list any tribe's deliverables
  if rec.is_superadmin or rec.operational_role in ('manager','deputy_manager') then
    return query
      select * from public.tribe_deliverables
      where tribe_id = p_tribe_id
        and (p_cycle_code is null or cycle_code = p_cycle_code)
      order by due_date asc nulls last, created_at desc;
    return;
  end if;

  -- Tribe leaders can list their own tribe
  if rec.operational_role = 'tribe_leader' and rec.tribe_id = p_tribe_id then
    return query
      select * from public.tribe_deliverables
      where tribe_id = p_tribe_id
        and (p_cycle_code is null or cycle_code = p_cycle_code)
      order by due_date asc nulls last, created_at desc;
    return;
  end if;

  -- Regular members can only list their own tribe
  if rec.tribe_id = p_tribe_id then
    return query
      select * from public.tribe_deliverables
      where tribe_id = p_tribe_id
        and (p_cycle_code is null or cycle_code = p_cycle_code)
      order by due_date asc nulls last, created_at desc;
    return;
  end if;

  raise exception 'Access denied: not a member of tribe %', p_tribe_id;
end;
$$;

commit;
