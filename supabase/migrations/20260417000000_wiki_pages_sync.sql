-- ============================================================================
-- Wiki Pages Sync Table + Search RPCs
-- Purpose: Supabase search index for the Núcleo wiki (GitHub markdown vault).
--          Enables full-text search via MCP tools (search_wiki, get_wiki_page,
--          get_decision_log). Content synced from nucleo-ia-gp/wiki repo.
-- Rollback: DROP FUNCTION IF EXISTS search_wiki_pages(text, int);
--           DROP FUNCTION IF EXISTS get_wiki_page(text);
--           DROP FUNCTION IF EXISTS get_decision_log(text);
--           DROP TABLE IF EXISTS wiki_pages;
-- ============================================================================

-- ═══ PART 1: wiki_pages table ═══

CREATE TABLE wiki_pages (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  path        text NOT NULL UNIQUE,          -- e.g. "governance/manual.md"
  title       text NOT NULL,
  domain      text NOT NULL CHECK (domain IN ('research', 'governance', 'tribes', 'partnerships', 'platform', 'onboarding')),
  content     text NOT NULL DEFAULT '',
  summary     text,                          -- optional short summary
  tags        text[] DEFAULT '{}',
  authors     text[] DEFAULT '{}',           -- contributor names
  license     text CHECK (license IN ('CC-BY-4.0', 'CC-BY-SA-4.0', 'MIT', 'proprietary')),
  ip_track    text CHECK (ip_track IN ('A', 'B', 'C')),
  source_repo text NOT NULL DEFAULT 'nucleo-ia-gp/wiki',
  source_sha  text,                          -- git commit SHA of last sync
  synced_at   timestamptz DEFAULT now(),
  created_at  timestamptz DEFAULT now(),
  updated_at  timestamptz DEFAULT now(),
  -- full-text search vector
  fts         tsvector GENERATED ALWAYS AS (
    setweight(to_tsvector('portuguese', coalesce(title, '')), 'A') ||
    setweight(to_tsvector('portuguese', coalesce(summary, '')), 'B') ||
    setweight(to_tsvector('portuguese', coalesce(content, '')), 'C')
  ) STORED
);

CREATE INDEX idx_wiki_pages_fts ON wiki_pages USING gin(fts);
CREATE INDEX idx_wiki_pages_domain ON wiki_pages(domain);
CREATE INDEX idx_wiki_pages_tags ON wiki_pages USING gin(tags);
CREATE INDEX idx_wiki_pages_path ON wiki_pages(path);

-- RLS: authenticated can read, service_role can write (sync)
ALTER TABLE wiki_pages ENABLE ROW LEVEL SECURITY;

CREATE POLICY wiki_pages_read ON wiki_pages
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY wiki_pages_service_write ON wiki_pages
  FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);

-- ═══ PART 2: search_wiki_pages RPC ═══

CREATE OR REPLACE FUNCTION search_wiki_pages(
  p_query text,
  p_limit int DEFAULT 10
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
  ORDER BY rank DESC
  LIMIT p_limit;
$$;

-- ═══ PART 3: get_wiki_page RPC (by path) ═══

CREATE OR REPLACE FUNCTION get_wiki_page(p_path text)
RETURNS TABLE(
  id uuid,
  path text,
  title text,
  domain text,
  content text,
  summary text,
  tags text[],
  authors text[],
  license text,
  ip_track text,
  source_sha text,
  synced_at timestamptz,
  updated_at timestamptz
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    w.id, w.path, w.title, w.domain, w.content, w.summary,
    w.tags, w.authors, w.license, w.ip_track,
    w.source_sha, w.synced_at, w.updated_at
  FROM wiki_pages w
  WHERE w.path = p_path;
$$;

-- ═══ PART 4: get_decision_log RPC (ADRs filter) ═══

CREATE OR REPLACE FUNCTION get_decision_log(p_filter text DEFAULT NULL)
RETURNS TABLE(
  id uuid,
  path text,
  title text,
  summary text,
  tags text[],
  updated_at timestamptz
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    w.id, w.path, w.title, w.summary, w.tags, w.updated_at
  FROM wiki_pages w
  WHERE w.domain = 'governance'
    AND w.path LIKE 'governance/adr/%'
    AND (p_filter IS NULL OR w.fts @@ websearch_to_tsquery('portuguese', p_filter))
  ORDER BY w.path;
$$;
