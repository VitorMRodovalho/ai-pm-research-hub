-- Track Q-A Batch E — orphan recovery: knowledge surface (6 fns)
--
-- Captures live bodies as-of 2026-04-25 for the knowledge_assets/_chunks
-- search + insights surface. Bodies preserved verbatim from
-- `pg_get_functiondef` — no behavior change.
--
-- Notes:
-- - knowledge_search and knowledge_search_text use the `vector` type and
--   require `extensions` in search_path (pgvector operators live there).
-- - All 6 are STABLE SECURITY DEFINER. can_manage_knowledge gates writes via
--   manager / deputy_manager / is_superadmin (legacy role-list authority,
--   not V4 can_by_member — drift cleanup deferred to Phase B).
-- - knowledge_search returns vector similarity (1 - cosine distance) and
--   caps p_match_count at 20.
-- - knowledge_search_text uses ts_rank with plainto_tsquery('simple', …)
--   so it doesn't depend on a tsvector column existing on knowledge_chunks.

CREATE OR REPLACE FUNCTION public.can_manage_knowledge()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select exists (
    select 1
    from public.members m
    where m.auth_id = auth.uid()
      and (
        coalesce(m.is_superadmin, false) = true
        or m.operational_role = any (array['manager','deputy_manager'])
      )
  );
$function$;

CREATE OR REPLACE FUNCTION public.knowledge_assets_latest(p_source text DEFAULT NULL::text, p_limit integer DEFAULT 100)
 RETURNS TABLE(asset_id uuid, source text, external_id text, source_url text, title text, summary text, tags text[], language text, published_at timestamp with time zone, chunk_count integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select
    a.id,
    a.source,
    a.external_id,
    a.source_url,
    a.title,
    a.summary,
    a.tags,
    a.language,
    a.published_at,
    coalesce(c.count_chunks, 0)::integer as chunk_count
  from public.knowledge_assets a
  left join (
    select asset_id, count(*) as count_chunks
    from public.knowledge_chunks
    group by asset_id
  ) c on c.asset_id = a.id
  where a.is_active = true
    and (p_source is null or a.source = p_source)
  order by a.published_at desc nulls last, a.created_at desc
  limit greatest(1, least(coalesce(p_limit, 100), 500));
$function$;

CREATE OR REPLACE FUNCTION public.knowledge_insights_backlog_candidates(p_status text DEFAULT 'open'::text, p_limit integer DEFAULT 25)
 RETURNS TABLE(insight_id uuid, title text, taxonomy_area text, insight_type text, status text, impact_score integer, urgency_score integer, priority_score integer, confidence_score numeric, detected_at timestamp with time zone, evidence_url text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select
    i.id as insight_id,
    i.title,
    i.taxonomy_area,
    i.insight_type,
    i.status,
    i.impact_score,
    i.urgency_score,
    (i.impact_score * i.urgency_score) as priority_score,
    i.confidence_score,
    i.detected_at,
    i.evidence_url
  from public.knowledge_insights i
  where (p_status is null or i.status = p_status)
  order by priority_score desc, coalesce(i.confidence_score, 0) desc, i.detected_at desc
  limit greatest(1, least(coalesce(p_limit, 25), 200));
$function$;

CREATE OR REPLACE FUNCTION public.knowledge_insights_overview(p_status text DEFAULT 'open'::text, p_days integer DEFAULT 30)
 RETURNS TABLE(taxonomy_area text, insight_type text, items integer, avg_impact numeric, avg_urgency numeric, max_detected_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select
    i.taxonomy_area,
    i.insight_type,
    count(*)::integer as items,
    round(avg(i.impact_score)::numeric, 2) as avg_impact,
    round(avg(i.urgency_score)::numeric, 2) as avg_urgency,
    max(i.detected_at) as max_detected_at
  from public.knowledge_insights i
  where (p_status is null or i.status = p_status)
    and i.detected_at >= now() - make_interval(days => greatest(1, least(coalesce(p_days, 30), 365)))
  group by i.taxonomy_area, i.insight_type
  order by items desc, avg_impact desc, avg_urgency desc;
$function$;

CREATE OR REPLACE FUNCTION public.knowledge_search(p_query_embedding vector, p_match_count integer DEFAULT 5, p_source text DEFAULT NULL::text)
 RETURNS TABLE(asset_id uuid, chunk_id uuid, title text, source text, source_url text, snippet text, tags text[], similarity double precision)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select
    a.id,
    c.id,
    a.title,
    a.source,
    a.source_url,
    left(c.content, 400) as snippet,
    a.tags,
    1 - (c.embedding <=> p_query_embedding) as similarity
  from public.knowledge_chunks c
  join public.knowledge_assets a on a.id = c.asset_id
  where a.is_active = true
    and c.embedding is not null
    and (p_source is null or a.source = p_source)
  order by c.embedding <=> p_query_embedding
  limit greatest(1, least(coalesce(p_match_count, 5), 20));
$function$;

CREATE OR REPLACE FUNCTION public.knowledge_search_text(p_query text, p_source text DEFAULT NULL::text, p_match_count integer DEFAULT 8)
 RETURNS TABLE(asset_id uuid, chunk_id uuid, title text, source text, source_url text, snippet text, tags text[], rank real)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  with q as (
    select nullif(trim(p_query), '') as query_text
  ),
  ts as (
    select plainto_tsquery('simple', query_text) as query
    from q
    where query_text is not null
  )
  select
    a.id as asset_id,
    c.id as chunk_id,
    a.title,
    a.source,
    a.source_url,
    left(c.content, 500) as snippet,
    a.tags,
    ts_rank(to_tsvector('simple', c.content), ts.query)::real as rank
  from ts
  join public.knowledge_chunks c on to_tsvector('simple', c.content) @@ ts.query
  join public.knowledge_assets a on a.id = c.asset_id
  where a.is_active = true
    and (p_source is null or a.source = p_source)
  order by rank desc, a.published_at desc nulls last
  limit greatest(1, least(coalesce(p_match_count, 8), 20));
$function$;
