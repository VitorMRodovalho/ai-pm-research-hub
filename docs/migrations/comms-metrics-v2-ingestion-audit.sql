-- COMMS_METRICS_V2 audit

-- A) ingestion table + rls
select n.nspname as schema, c.relname as table_name, c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'comms_metrics_ingestion_log';

-- B) ingestion indexes
select schemaname, tablename, indexname, indexdef
from pg_indexes
where schemaname = 'public'
  and tablename = 'comms_metrics_ingestion_log'
order by indexname;

-- C) ingestion policies
select schemaname, tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'comms_metrics_ingestion_log'
order by policyname;

-- D) functions + grants
select n.nspname as schema, p.proname as function_name
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('can_manage_comms_metrics', 'comms_metrics_latest_by_channel')
order by p.proname;

select routine_schema, routine_name, privilege_type, grantee
from information_schema.routine_privileges
where routine_schema = 'public'
  and routine_name in ('can_manage_comms_metrics', 'comms_metrics_latest_by_channel')
order by routine_name, grantee;

-- E) smoke
select * from public.comms_metrics_latest_by_channel(7) limit 20;
select run_key, source, status, fetched_rows, upserted_rows, invalid_rows, created_at, finished_at
from public.comms_metrics_ingestion_log
order by created_at desc
limit 5;
