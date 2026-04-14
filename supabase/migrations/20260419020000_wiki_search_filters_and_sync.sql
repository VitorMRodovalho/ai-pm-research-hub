-- ============================================================================
-- Enhanced wiki search with domain/tag filters
-- Purpose: Add optional p_domain and p_tag filters to search_wiki_pages RPC
--          to support refined MCP search_wiki tool.
-- Rollback: Re-create search_wiki_pages without p_domain/p_tag params
-- ============================================================================

-- Must DROP first since we're adding parameters
DROP FUNCTION IF EXISTS search_wiki_pages(text, int);

CREATE OR REPLACE FUNCTION search_wiki_pages(
  p_query text,
  p_limit int DEFAULT 10,
  p_domain text DEFAULT NULL,
  p_tag text DEFAULT NULL
)
RETURNS TABLE(
  id uuid,
  path text,
  title text,
  domain text,
  summary text,
  tags text[],
  license text,
  ip_track text,
  rank real,
  headline text
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    w.id, w.path, w.title, w.domain, w.summary, w.tags,
    w.license, w.ip_track,
    ts_rank(w.fts, websearch_to_tsquery('portuguese', p_query)) AS rank,
    ts_headline('portuguese', w.content, websearch_to_tsquery('portuguese', p_query),
      'MaxWords=60, MinWords=20, StartSel=**, StopSel=**') AS headline
  FROM wiki_pages w
  WHERE w.fts @@ websearch_to_tsquery('portuguese', p_query)
    AND (p_domain IS NULL OR w.domain = p_domain)
    AND (p_tag IS NULL OR p_tag = ANY(w.tags))
  ORDER BY rank DESC
  LIMIT p_limit;
$$;
