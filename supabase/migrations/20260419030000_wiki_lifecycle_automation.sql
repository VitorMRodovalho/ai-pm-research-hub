-- Wiki Lifecycle Automation (Phase 5)
-- Staleness detection, PII scan, metadata completeness
-- Rollback: DROP FUNCTION IF EXISTS public.wiki_health_report();

CREATE OR REPLACE FUNCTION public.wiki_health_report()
RETURNS TABLE(
  check_type text,
  severity text,
  path text,
  title text,
  detail text
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT r.check_type, r.severity, r.path, r.title, r.detail
  FROM (
    -- Stale pages: not updated in >90 days
    SELECT
      'stale'::text AS check_type,
      CASE
        WHEN now() - w.updated_at > interval '180 days' THEN 'high'
        ELSE 'medium'
      END AS severity,
      w.path,
      w.title,
      'Last updated ' || to_char(w.updated_at, 'YYYY-MM-DD') ||
        ' (' || extract(day FROM now() - w.updated_at)::int || ' days ago)' AS detail
    FROM wiki_pages w
    WHERE now() - w.updated_at > interval '90 days'

    UNION ALL

    -- PII: email patterns
    SELECT 'pii_warning'::text, 'high'::text, w.path, w.title,
      'Content may contain email address(es)' AS detail
    FROM wiki_pages w
    WHERE w.content ~* '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'

    UNION ALL

    -- PII: phone patterns (BR)
    SELECT 'pii_warning'::text, 'high'::text, w.path, w.title,
      'Content may contain phone number(s)' AS detail
    FROM wiki_pages w
    WHERE w.content ~ '\+?55\s?\d{2}\s?\d{4,5}[\s-]?\d{4}'

    UNION ALL

    -- PII: CPF patterns
    SELECT 'pii_warning'::text, 'high'::text, w.path, w.title,
      'Content may contain CPF number(s)' AS detail
    FROM wiki_pages w
    WHERE w.content ~ '\d{3}\.\d{3}\.\d{3}-\d{2}'

    UNION ALL

    -- Missing summary
    SELECT 'incomplete'::text, 'low'::text, w.path, w.title,
      'Missing summary' AS detail
    FROM wiki_pages w
    WHERE w.summary IS NULL OR w.summary = ''

    UNION ALL

    -- Missing tags
    SELECT 'incomplete'::text, 'low'::text, w.path, w.title,
      'Missing tags' AS detail
    FROM wiki_pages w
    WHERE w.tags = '{}'

    UNION ALL

    -- Missing license
    SELECT 'incomplete'::text, 'low'::text, w.path, w.title,
      'Missing license' AS detail
    FROM wiki_pages w
    WHERE w.license IS NULL OR w.license = ''
  ) r
  ORDER BY
    CASE r.check_type
      WHEN 'pii_warning' THEN 1
      WHEN 'stale' THEN 2
      WHEN 'incomplete' THEN 3
    END,
    r.severity,
    r.path;
$$;

GRANT EXECUTE ON FUNCTION public.wiki_health_report() TO authenticated;

COMMENT ON FUNCTION public.wiki_health_report IS 'Wiki lifecycle health report: staleness (>90d), PII detection (email/phone/CPF), metadata completeness.';
