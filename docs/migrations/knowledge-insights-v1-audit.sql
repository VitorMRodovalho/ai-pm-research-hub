-- KNOWLEDGE_INSIGHTS_V1 audit

-- A) table and indexes
select c.relname as table_name
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'knowledge_insights'
  and c.relkind = 'r';

select schemaname, tablename, indexname
from pg_indexes
where schemaname = 'public'
  and tablename = 'knowledge_insights'
order by indexname;

-- B) policies
select schemaname, tablename, policyname, cmd, roles
from pg_policies
where schemaname = 'public'
  and tablename = 'knowledge_insights'
order by policyname;

-- C) functions and grants
select p.proname as function_name
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('knowledge_insights_overview', 'knowledge_insights_backlog_candidates')
order by p.proname;

select routine_schema, routine_name, privilege_type, grantee
from information_schema.routine_privileges
where routine_schema = 'public'
  and routine_name in ('knowledge_insights_overview', 'knowledge_insights_backlog_candidates')
order by routine_name, grantee;

-- D) smoke (safe even with empty table)
select *
from public.knowledge_insights_overview('open', 30);

select *
from public.knowledge_insights_backlog_candidates('open', 10);
