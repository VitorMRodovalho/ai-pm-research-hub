-- EXEC_ROI_ACL_HARDENING_V1 audit

select routine_schema, routine_name, privilege_type, grantee
from information_schema.routine_privileges
where routine_schema = 'public'
  and routine_name in ('exec_funnel_summary', 'exec_cert_timeline', 'exec_skills_radar')
order by routine_name, grantee;
