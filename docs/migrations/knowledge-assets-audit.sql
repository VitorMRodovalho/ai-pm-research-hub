-- S-KNW1: Audit knowledge_assets
-- Verificar se a tabela existe e quantos registros

select exists (
  select 1 from information_schema.tables
  where table_schema = 'public' and table_name = 'knowledge_assets'
) as table_exists;

select count(*) as asset_count from public.knowledge_assets;
