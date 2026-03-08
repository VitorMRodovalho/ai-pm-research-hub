-- S-KNW1: knowledge_assets table
-- Repositório central de recursos (cursos, referências, webinars) vinculados a tribo e autor.
-- Backlog: Wave 5 Knowledge Hub — "Create knowledge_assets table for courses, references, webinars"

begin;

create table if not exists public.knowledge_assets (
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

create index if not exists idx_knowledge_assets_tribe
  on public.knowledge_assets (tribe_id) where tribe_id is not null;

create index if not exists idx_knowledge_assets_author
  on public.knowledge_assets (author_id) where author_id is not null;

create index if not exists idx_knowledge_assets_type
  on public.knowledge_assets (asset_type);

create index if not exists idx_knowledge_assets_active_created
  on public.knowledge_assets (is_active, created_at desc) where is_active = true;

create or replace function public.set_knowledge_assets_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists tr_knowledge_assets_updated on public.knowledge_assets;
create trigger tr_knowledge_assets_updated
  before update on public.knowledge_assets
  for each row execute function public.set_knowledge_assets_updated_at();

alter table public.knowledge_assets enable row level security;

-- Leitura: usuários autenticados podem ver assets ativos
create policy knowledge_assets_select
  on public.knowledge_assets for select
  to authenticated
  using (is_active = true);

-- Inserção/atualização: usa can_manage_knowledge() (já existe no schema)
create policy knowledge_assets_insert
  on public.knowledge_assets for insert
  to authenticated
  with check (public.can_manage_knowledge());

create policy knowledge_assets_update
  on public.knowledge_assets for update
  to authenticated
  using (public.can_manage_knowledge())
  with check (public.can_manage_knowledge());

-- Delete físico: apenas superadmin (soft delete via is_active = false preferível)
create policy knowledge_assets_delete
  on public.knowledge_assets for delete
  to authenticated
  using (
    coalesce((select m.is_superadmin from public.members m where m.auth_id = auth.uid() limit 1), false) = true
  );

commit;
