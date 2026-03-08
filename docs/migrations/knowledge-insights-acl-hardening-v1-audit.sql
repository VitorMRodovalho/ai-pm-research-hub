-- KNOWLEDGE_INSIGHTS_ACL_HARDENING_V1 audit

select routine_schema, routine_name, privilege_type, grantee
from information_schema.routine_privileges
where routine_schema = 'public'
  and routine_name in ('knowledge_insights_overview', 'knowledge_insights_backlog_candidates')
order by routine_name, grantee;
