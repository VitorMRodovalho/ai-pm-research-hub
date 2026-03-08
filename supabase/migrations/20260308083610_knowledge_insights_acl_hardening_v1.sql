-- KNOWLEDGE_INSIGHTS_ACL_HARDENING_V1
-- Purpose: remove anonymous/public execute on insight RPCs.

revoke execute on function public.knowledge_insights_overview(text, integer) from anon;
revoke execute on function public.knowledge_insights_overview(text, integer) from public;

grant execute on function public.knowledge_insights_overview(text, integer) to authenticated;

revoke execute on function public.knowledge_insights_backlog_candidates(text, integer) from anon;
revoke execute on function public.knowledge_insights_backlog_candidates(text, integer) from public;

grant execute on function public.knowledge_insights_backlog_candidates(text, integer) to authenticated;
