-- ═══════════════════════════════════════════════════════════════════════════
-- Wave 4 Expansion: Legacy Ingestion + Admin Governance Links
-- Date: 2026-03-09
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 1: Admin Governance Links (Tier 4+ only)
-- Stores sensitive administrative links (Drive folders, governance docs, etc.)
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.admin_links (
  id          serial primary key,
  category    text not null check (category in ('governance','finance','legal','operations','templates','other')),
  title       text not null,
  description text,
  url         text not null,
  icon        text default 'folder',
  sort_order  integer default 0,
  is_active   boolean not null default true,
  created_by  uuid references auth.users(id) default auth.uid(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.admin_links is 'Administrative links visible only to Tier 4 (Admin) and Tier 5 (Superadmin). Contains governance docs, Drive folders, financial reports.';

alter table public.admin_links enable row level security;

create policy admin_links_select on public.admin_links
  for select to authenticated
  using (
    (select r.is_superadmin or r.operational_role in ('manager','deputy_manager','co_gp')
     from public.get_my_member_record() r)
  );

create policy admin_links_insert on public.admin_links
  for insert to authenticated
  with check (
    (select r.is_superadmin from public.get_my_member_record() r)
  );

create policy admin_links_update on public.admin_links
  for update to authenticated
  using (
    (select r.is_superadmin from public.get_my_member_record() r)
  );

create policy admin_links_delete on public.admin_links
  for delete to authenticated
  using (
    (select r.is_superadmin from public.get_my_member_record() r)
  );

-- Seed initial governance link
insert into public.admin_links (category, title, description, url, icon, sort_order)
values (
  'governance',
  'Pasta Administrativa (Governança/Atas)',
  'Pasta oficial do Google Drive contendo atas de reuniões, documentos de governança e templates administrativos do Núcleo.',
  'https://drive.google.com/drive/folders/PLACEHOLDER_ADMIN_FOLDER',
  'folder-lock',
  1
);

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 2: Trello Import Tracking
-- Tracks imports from Trello legacy boards
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.trello_import_log (
  id            serial primary key,
  board_name    text not null,
  board_source  text not null check (board_source in ('articles_c1','articles_c2','comms_c3','social_media','other')),
  cards_total   integer not null default 0,
  cards_mapped  integer not null default 0,
  cards_skipped integer not null default 0,
  target_table  text not null,
  imported_by   uuid references auth.users(id) default auth.uid(),
  imported_at   timestamptz not null default now(),
  notes         text
);

comment on table public.trello_import_log is 'Audit log for Trello board imports. Each row = one import batch.';

alter table public.trello_import_log enable row level security;

create policy trello_import_log_admin on public.trello_import_log
  for all to authenticated
  using (
    (select r.is_superadmin or r.operational_role in ('manager','deputy_manager')
     from public.get_my_member_record() r)
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 3: Extend hub_resources for Trello/Comms ingestion
-- Add source tracking and cycle code for imported resources
-- ═══════════════════════════════════════════════════════════════════════════

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'hub_resources' and column_name = 'source'
  ) then
    alter table public.hub_resources add column source text default 'manual';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'hub_resources' and column_name = 'cycle_code'
  ) then
    alter table public.hub_resources add column cycle_code text;
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'hub_resources' and column_name = 'trello_card_id'
  ) then
    alter table public.hub_resources add column trello_card_id text;
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'hub_resources' and column_name = 'tags'
  ) then
    alter table public.hub_resources add column tags text[] default '{}';
  end if;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 4: Extend artifacts for Trello legacy data
-- ═══════════════════════════════════════════════════════════════════════════

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'artifacts' and column_name = 'source'
  ) then
    alter table public.artifacts add column source text default 'manual';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'artifacts' and column_name = 'trello_card_id'
  ) then
    alter table public.artifacts add column trello_card_id text;
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'artifacts' and column_name = 'tags'
  ) then
    alter table public.artifacts add column tags text[] default '{}';
  end if;
end $$;

-- Unique constraint to prevent duplicate Trello imports
create unique index if not exists idx_artifacts_trello_card
  on public.artifacts (trello_card_id) where trello_card_id is not null;

create unique index if not exists idx_hub_resources_trello_card
  on public.hub_resources (trello_card_id) where trello_card_id is not null;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 5: Extend events for legacy import source tracking
-- ═══════════════════════════════════════════════════════════════════════════

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'events' and column_name = 'source'
  ) then
    alter table public.events add column source text default 'manual';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'events' and column_name = 'calendar_event_id'
  ) then
    alter table public.events add column calendar_event_id text;
  end if;
end $$;

create unique index if not exists idx_events_calendar_id
  on public.events (calendar_event_id) where calendar_event_id is not null;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 6: RPC to list admin links (admin-only)
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.list_admin_links()
returns setof public.admin_links
language sql security definer stable as $$
  select * from public.admin_links
  where is_active = true
  order by sort_order asc, created_at desc;
$$;

grant execute on function public.list_admin_links() to authenticated;

commit;
