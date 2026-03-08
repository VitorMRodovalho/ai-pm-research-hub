-- EXEC_ROI_DASHBOARDS_V1 rollback

revoke execute on function public.exec_skills_radar() from authenticated;
revoke execute on function public.exec_cert_timeline(integer) from authenticated;
revoke execute on function public.exec_funnel_summary() from authenticated;

drop function if exists public.exec_skills_radar();
drop function if exists public.exec_cert_timeline(integer);
drop function if exists public.exec_funnel_summary();

drop view if exists public.vw_exec_skills_radar;
drop view if exists public.vw_exec_cert_timeline;
drop view if exists public.vw_exec_funnel;
