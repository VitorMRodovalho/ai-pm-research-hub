-- KNOWLEDGE_INSIGHTS_V1 rollback

revoke execute on function public.knowledge_insights_backlog_candidates(text, integer) from authenticated;
revoke execute on function public.knowledge_insights_overview(text, integer) from authenticated;

drop function if exists public.knowledge_insights_backlog_candidates(text, integer);
drop function if exists public.knowledge_insights_overview(text, integer);

drop trigger if exists trg_knowledge_insights_updated_at on public.knowledge_insights;
drop function if exists public.set_knowledge_insights_updated_at();

drop table if exists public.knowledge_insights;
