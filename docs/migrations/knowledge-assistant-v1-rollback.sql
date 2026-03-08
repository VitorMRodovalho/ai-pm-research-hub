-- KNOWLEDGE_ASSISTANT_V1 rollback

revoke execute on function public.knowledge_search_text(text, text, integer) from authenticated;
drop function if exists public.knowledge_search_text(text, text, integer);

drop index if exists public.idx_knowledge_chunks_tsv_simple;
