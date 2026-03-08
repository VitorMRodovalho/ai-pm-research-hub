-- KNOWLEDGE_ASSISTANT_V1
-- Purpose: add low-cost textual retrieval for /ai-assistant without realtime LLM dependency.

create index if not exists idx_knowledge_chunks_tsv_simple
  on public.knowledge_chunks
  using gin (to_tsvector('simple', content));

create or replace function public.knowledge_search_text(
  p_query text,
  p_source text default null,
  p_match_count integer default 8
)
returns table (
  asset_id uuid,
  chunk_id uuid,
  title text,
  source text,
  source_url text,
  snippet text,
  tags text[],
  rank real
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with q as (
    select nullif(trim(p_query), '') as query_text
  ),
  ts as (
    select plainto_tsquery('simple', query_text) as query
    from q
    where query_text is not null
  )
  select
    a.id as asset_id,
    c.id as chunk_id,
    a.title,
    a.source,
    a.source_url,
    left(c.content, 500) as snippet,
    a.tags,
    ts_rank(to_tsvector('simple', c.content), ts.query)::real as rank
  from ts
  join public.knowledge_chunks c on to_tsvector('simple', c.content) @@ ts.query
  join public.knowledge_assets a on a.id = c.asset_id
  where a.is_active = true
    and (p_source is null or a.source = p_source)
  order by rank desc, a.published_at desc nulls last
  limit greatest(1, least(coalesce(p_match_count, 8), 20));
$$;

revoke all on function public.knowledge_search_text(text, text, integer) from public;
grant execute on function public.knowledge_search_text(text, text, integer) to authenticated;
