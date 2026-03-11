-- ============================================================================
-- W90: RPC search_knowledge — Global Search / Command Palette
-- Full-Text Search em knowledge_chunks, retorno padronizado para UI
-- Date: 2026-03-15
-- ============================================================================

create or replace function public.search_knowledge(search_term text)
returns table (
  chunk_id uuid,
  content_snippet text,
  asset_id uuid,
  artifact_id text,
  tribe_name text,
  theme_title text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_term text;
begin
  v_term := coalesce(trim(search_term), '');
  if length(v_term) < 2 then
    return;
  end if;
  v_term := '%' || v_term || '%';

  return query
  select
    kc.id::uuid as chunk_id,
    left(kc.content, 100) as content_snippet,
    kc.asset_id,
    coalesce(ka.metadata->>'artifact_id', ka.source_url, '')::text as artifact_id,
    coalesce(ka.metadata->>'tribe_name', '')::text as tribe_name,
    coalesce(ka.title, '')::text as theme_title
  from public.knowledge_chunks kc
  join public.knowledge_assets ka on ka.id = kc.asset_id
  where ka.is_active = true
    and (kc.content ilike v_term or ka.title ilike v_term or ka.summary ilike v_term)
  order by
    case when ka.title ilike v_term then 0 else 1 end,
    kc.chunk_index,
    kc.created_at desc
  limit 10;
end;
$$;

comment on function public.search_knowledge(text) is
  'W90: Busca global em knowledge_chunks — usado pela Command Palette (Cmd+K).';

grant execute on function public.search_knowledge(text) to authenticated;
