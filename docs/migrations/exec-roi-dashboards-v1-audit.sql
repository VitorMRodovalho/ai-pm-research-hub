-- EXEC_ROI_DASHBOARDS_V1 audit

-- A) views presence
select table_schema, table_name
from information_schema.views
where table_schema = 'public'
  and table_name in ('vw_exec_funnel', 'vw_exec_cert_timeline', 'vw_exec_skills_radar')
order by table_name;

-- B) rpc presence
select n.nspname as schema, p.proname as function_name
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('exec_funnel_summary', 'exec_cert_timeline', 'exec_skills_radar')
order by p.proname;

-- C) rpc grants
select routine_schema, routine_name, privilege_type, grantee
from information_schema.routine_privileges
where routine_schema = 'public'
  and routine_name in ('exec_funnel_summary', 'exec_cert_timeline', 'exec_skills_radar')
order by routine_name, grantee;

-- D) smoke
select * from public.exec_funnel_summary();
select * from public.exec_cert_timeline(12);
select * from public.exec_skills_radar();
