-- KNOWLEDGE_INGEST_V1 audit

-- A) tables exist
select n.nspname as schema_name, c.relname as table_name
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where c.relkind = 'r'
  and n.nspname = 'public'
  and c.relname in ('knowledge_assets', 'knowledge_chunks', 'knowledge_ingestion_runs')
order by c.relname;

-- B) critical indexes
select schemaname, tablename, indexname
from pg_indexes
where schemaname = 'public'
  and tablename in ('knowledge_assets', 'knowledge_chunks', 'knowledge_ingestion_runs')
order by tablename, indexname;

-- C) rls policies
select schemaname, tablename, policyname, cmd, roles
from pg_policies
where schemaname = 'public'
  and tablename in ('knowledge_assets', 'knowledge_chunks', 'knowledge_ingestion_runs')
order by tablename, policyname;

-- D) rpc presence
select p.proname as function_name
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('can_manage_knowledge', 'knowledge_assets_latest', 'knowledge_search')
order by p.proname;

-- E) rpc grants
select routine_schema, routine_name, privilege_type, grantee
from information_schema.routine_privileges
where routine_schema = 'public'
  and routine_name in ('can_manage_knowledge', 'knowledge_assets_latest', 'knowledge_search')
order by routine_name, grantee;

-- F) smoke query
select * from public.knowledge_assets_latest('youtube', 20);
