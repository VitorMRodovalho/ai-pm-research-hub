-- KNOWLEDGE_INGEST_V1 rollback

revoke execute on function public.knowledge_search(extensions.vector, integer, text) from authenticated;
drop function if exists public.knowledge_search(extensions.vector, integer, text);

revoke execute on function public.knowledge_assets_latest(text, integer) from authenticated;
drop function if exists public.knowledge_assets_latest(text, integer);

drop trigger if exists trg_knowledge_assets_updated_at on public.knowledge_assets;
drop function if exists public.set_knowledge_updated_at();

drop policy if exists knowledge_runs_manage on public.knowledge_ingestion_runs;
drop policy if exists knowledge_runs_read on public.knowledge_ingestion_runs;
drop policy if exists knowledge_chunks_manage on public.knowledge_chunks;
drop policy if exists knowledge_chunks_read on public.knowledge_chunks;
drop policy if exists knowledge_assets_manage on public.knowledge_assets;
drop policy if exists knowledge_assets_read on public.knowledge_assets;

drop table if exists public.knowledge_ingestion_runs;
drop table if exists public.knowledge_chunks;
drop table if exists public.knowledge_assets;

revoke all on function public.can_manage_knowledge() from authenticated;
drop function if exists public.can_manage_knowledge();
