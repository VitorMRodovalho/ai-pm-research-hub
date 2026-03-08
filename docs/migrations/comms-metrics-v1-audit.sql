-- COMMS_METRICS_V1 audit
-- Run after applying comms-metrics-v1.sql

-- 1) table + RLS
select
  n.nspname as schema,
  c.relname as table_name,
  c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'comms_metrics_daily';

-- 2) indexes
select schemaname, tablename, indexname, indexdef
from pg_indexes
where schemaname = 'public'
  and tablename = 'comms_metrics_daily'
order by indexname;

-- 3) policies
select schemaname, tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'comms_metrics_daily'
order by policyname;

-- 4) function exists + grants
select n.nspname as schema, p.proname as function_name
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'comms_metrics_latest';

select routine_schema, routine_name, privilege_type, grantee
from information_schema.routine_privileges
where routine_schema = 'public'
  and routine_name = 'comms_metrics_latest'
order by grantee;

-- 5) smoke payload
select * from public.comms_metrics_latest();
