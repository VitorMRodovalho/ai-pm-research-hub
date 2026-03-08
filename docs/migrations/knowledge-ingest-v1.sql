-- KNOWLEDGE_INGEST_V1
-- Purpose: YouTube-first knowledge ingestion foundation for the AI & PM Hub.

create extension if not exists vector with schema extensions;

create or replace function public.can_manage_knowledge()
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1
    from public.members m
    where m.auth_id = auth.uid()
      and (
        coalesce(m.is_superadmin, false) = true
        or m.operational_role = any (array['manager','deputy_manager'])
      )
  );
$$;

revoke all on function public.can_manage_knowledge() from public;
grant execute on function public.can_manage_knowledge() to authenticated;

create table if not exists public.knowledge_assets (
  id uuid primary key default gen_random_uuid(),
  source text not null check (source in ('youtube','drive','linkedin','manual')),
  external_id text not null,
  source_url text,
  title text not null,
  summary text,
  tags text[] not null default '{}',
  language text not null default 'pt-BR',
  published_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_by uuid references public.members(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source, external_id)
);

create index if not exists idx_knowledge_assets_source_pub
  on public.knowledge_assets (source, published_at desc nulls last);

create index if not exists idx_knowledge_assets_tags
  on public.knowledge_assets using gin (tags);

create index if not exists idx_knowledge_assets_metadata
  on public.knowledge_assets using gin (metadata);

create table if not exists public.knowledge_chunks (
  id uuid primary key default gen_random_uuid(),
  asset_id uuid not null references public.knowledge_assets(id) on delete cascade,
  chunk_index integer not null,
  content text not null,
  token_estimate integer,
  embedding extensions.vector(1536),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (asset_id, chunk_index)
);

create index if not exists idx_knowledge_chunks_asset
  on public.knowledge_chunks (asset_id, chunk_index);

create index if not exists idx_knowledge_chunks_embedding
  on public.knowledge_chunks using ivfflat (embedding extensions.vector_cosine_ops)
  with (lists = 100);

create table if not exists public.knowledge_ingestion_runs (
  id uuid primary key default gen_random_uuid(),
  run_key text not null unique,
  source text not null,
  status text not null check (status in ('started','success','error','partial')),
  triggered_by text,
  rows_received integer not null default 0,
  rows_upserted integer not null default 0,
  rows_chunked integer not null default 0,
  error_message text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_knowledge_ingestion_runs_created
  on public.knowledge_ingestion_runs (created_at desc);

alter table public.knowledge_assets enable row level security;
alter table public.knowledge_chunks enable row level security;
alter table public.knowledge_ingestion_runs enable row level security;

-- Read for authenticated users, write for managers/superadmins.
drop policy if exists knowledge_assets_read on public.knowledge_assets;
create policy knowledge_assets_read
on public.knowledge_assets
for select
to authenticated
using (is_active = true);

drop policy if exists knowledge_assets_manage on public.knowledge_assets;
create policy knowledge_assets_manage
on public.knowledge_assets
for all
to authenticated
using (public.can_manage_knowledge())
with check (public.can_manage_knowledge());

drop policy if exists knowledge_chunks_read on public.knowledge_chunks;
create policy knowledge_chunks_read
on public.knowledge_chunks
for select
to authenticated
using (
  exists (
    select 1 from public.knowledge_assets a
    where a.id = knowledge_chunks.asset_id
      and a.is_active = true
  )
);

drop policy if exists knowledge_chunks_manage on public.knowledge_chunks;
create policy knowledge_chunks_manage
on public.knowledge_chunks
for all
to authenticated
using (public.can_manage_knowledge())
with check (public.can_manage_knowledge());

drop policy if exists knowledge_runs_read on public.knowledge_ingestion_runs;
create policy knowledge_runs_read
on public.knowledge_ingestion_runs
for select
to authenticated
using (public.can_manage_knowledge());

drop policy if exists knowledge_runs_manage on public.knowledge_ingestion_runs;
create policy knowledge_runs_manage
on public.knowledge_ingestion_runs
for all
to authenticated
using (public.can_manage_knowledge())
with check (public.can_manage_knowledge());

create or replace function public.set_knowledge_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_knowledge_assets_updated_at on public.knowledge_assets;
create trigger trg_knowledge_assets_updated_at
before update on public.knowledge_assets
for each row execute function public.set_knowledge_updated_at();

create or replace function public.knowledge_assets_latest(p_source text default null, p_limit integer default 100)
returns table (
  asset_id uuid,
  source text,
  external_id text,
  source_url text,
  title text,
  summary text,
  tags text[],
  language text,
  published_at timestamptz,
  chunk_count integer
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select
    a.id,
    a.source,
    a.external_id,
    a.source_url,
    a.title,
    a.summary,
    a.tags,
    a.language,
    a.published_at,
    coalesce(c.count_chunks, 0)::integer as chunk_count
  from public.knowledge_assets a
  left join (
    select asset_id, count(*) as count_chunks
    from public.knowledge_chunks
    group by asset_id
  ) c on c.asset_id = a.id
  where a.is_active = true
    and (p_source is null or a.source = p_source)
  order by a.published_at desc nulls last, a.created_at desc
  limit greatest(1, least(coalesce(p_limit, 100), 500));
$$;

revoke all on function public.knowledge_assets_latest(text, integer) from public;
grant execute on function public.knowledge_assets_latest(text, integer) to authenticated;

create or replace function public.knowledge_search(
  p_query_embedding extensions.vector(1536),
  p_match_count integer default 5,
  p_source text default null
)
returns table (
  asset_id uuid,
  chunk_id uuid,
  title text,
  source text,
  source_url text,
  snippet text,
  tags text[],
  similarity double precision
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select
    a.id,
    c.id,
    a.title,
    a.source,
    a.source_url,
    left(c.content, 400) as snippet,
    a.tags,
    1 - (c.embedding <=> p_query_embedding) as similarity
  from public.knowledge_chunks c
  join public.knowledge_assets a on a.id = c.asset_id
  where a.is_active = true
    and c.embedding is not null
    and (p_source is null or a.source = p_source)
  order by c.embedding <=> p_query_embedding
  limit greatest(1, least(coalesce(p_match_count, 5), 20));
$$;

revoke all on function public.knowledge_search(extensions.vector, integer, text) from public;
grant execute on function public.knowledge_search(extensions.vector, integer, text) to authenticated;
