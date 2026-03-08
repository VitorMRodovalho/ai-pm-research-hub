-- KNOWLEDGE_ASSISTANT_V1 audit

-- A) tsvector index presence
select schemaname, tablename, indexname
from pg_indexes
where schemaname = 'public'
  and tablename = 'knowledge_chunks'
  and indexname = 'idx_knowledge_chunks_tsv_simple';

-- B) function presence
select p.proname as function_name
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'knowledge_search_text';

-- C) grant check
select routine_schema, routine_name, privilege_type, grantee
from information_schema.routine_privileges
where routine_schema = 'public'
  and routine_name = 'knowledge_search_text'
order by grantee;

-- D) smoke query
select *
from public.knowledge_search_text('ingestao conhecimento youtube', 'youtube', 8);
