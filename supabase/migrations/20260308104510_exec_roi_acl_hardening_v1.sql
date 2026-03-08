-- EXEC_ROI_ACL_HARDENING_V1
-- Purpose: remove anonymous/public execute from executive RPCs.

revoke execute on function public.exec_funnel_summary() from anon;
revoke execute on function public.exec_funnel_summary() from public;
grant execute on function public.exec_funnel_summary() to authenticated;

revoke execute on function public.exec_cert_timeline(integer) from anon;
revoke execute on function public.exec_cert_timeline(integer) from public;
grant execute on function public.exec_cert_timeline(integer) to authenticated;

revoke execute on function public.exec_skills_radar() from anon;
revoke execute on function public.exec_skills_radar() from public;
grant execute on function public.exec_skills_radar() to authenticated;
