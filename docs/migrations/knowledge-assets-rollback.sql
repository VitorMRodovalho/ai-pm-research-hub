-- S-KNW1: Rollback knowledge_assets
-- Executar apenas se necessário reverter. Perde dados da tabela.

begin;
drop policy if exists knowledge_assets_delete on public.knowledge_assets;
drop policy if exists knowledge_assets_update on public.knowledge_assets;
drop policy if exists knowledge_assets_insert on public.knowledge_assets;
drop policy if exists knowledge_assets_select on public.knowledge_assets;
drop trigger if exists tr_knowledge_assets_updated on public.knowledge_assets;
drop function if exists public.set_knowledge_assets_updated_at();
drop table if exists public.knowledge_assets;
commit;
