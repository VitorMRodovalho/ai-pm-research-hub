-- COMMS_METRICS_V3 audit

-- A) columns on comms_metrics_daily
select column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'comms_metrics_daily'
  and column_name in ('published_at', 'published_by', 'publish_batch_id')
order by column_name;

-- B) publish log table + policy
select n.nspname as schema, c.relname as table_name, c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'comms_metrics_publish_log';

select schemaname, tablename, policyname, cmd, roles, qual
from pg_policies
where schemaname = 'public'
  and tablename = 'comms_metrics_publish_log';

-- C) publish RPC + grants
select n.nspname as schema, p.proname as function_name
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'publish_comms_metrics_batch';

select routine_schema, routine_name, privilege_type, grantee
from information_schema.routine_privileges
where routine_schema = 'public'
  and routine_name = 'publish_comms_metrics_batch'
order by grantee;

-- D) latest publish log
select batch_id, source, target_date, published_rows, created_at
from public.comms_metrics_publish_log
order by created_at desc
limit 10;
