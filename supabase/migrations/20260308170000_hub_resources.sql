-- S-KNW2: hub_resources table (curated resources for Knowledge Hub)
-- Separate from knowledge_assets (sync/embeddings). Manual CRUD for courses, refs, webinars.
-- Backlog: Wave 5 Knowledge Hub

begin;

create table if not exists public.hub_resources (
  id uuid primary key default gen_random_uuid(),
  asset_type text not null check (asset_type in ('course', 'reference', 'webinar', 'other')),
  title text not null,
  description text,
  url text,
  tribe_id integer references public.tribes(id) on delete set null,
  author_id uuid references public.members(id) on delete set null,
  course_id integer references public.courses(id) on delete set null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_hub_resources_tribe
  on public.hub_resources (tribe_id) where tribe_id is not null;

create index if not exists idx_hub_resources_author
  on public.hub_resources (author_id) where author_id is not null;

create index if not exists idx_hub_resources_type
  on public.hub_resources (asset_type);

create index if not exists idx_hub_resources_active_created
  on public.hub_resources (is_active, created_at desc) where is_active = true;

create or replace function public.set_hub_resources_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists tr_hub_resources_updated on public.hub_resources;
create trigger tr_hub_resources_updated
  before update on public.hub_resources
  for each row execute function public.set_hub_resources_updated_at();

alter table public.hub_resources enable row level security;

create policy hub_resources_select
  on public.hub_resources for select
  to authenticated
  using (is_active = true);

create policy hub_resources_select_manage
  on public.hub_resources for select
  to authenticated
  using (public.can_manage_knowledge());

create policy hub_resources_insert
  on public.hub_resources for insert
  to authenticated
  with check (public.can_manage_knowledge());

create policy hub_resources_update
  on public.hub_resources for update
  to authenticated
  using (public.can_manage_knowledge())
  with check (public.can_manage_knowledge());

create policy hub_resources_delete
  on public.hub_resources for delete
  to authenticated
  using (
    coalesce((select m.is_superadmin from public.members m where m.auth_id = auth.uid() limit 1), false) = true
  );

commit;
