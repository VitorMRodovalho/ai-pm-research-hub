-- Fix list_curation_board: remove references to non-existent suggested_tags column
-- and use suggest_tags() function instead (matching list_pending_curation pattern).

CREATE OR REPLACE FUNCTION public.list_curation_board(
  p_status TEXT DEFAULT NULL
)
RETURNS SETOF JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT row_to_json(r) FROM (
    SELECT
      a.id,
      a.title,
      a.type,
      a.url,
      a.description,
      COALESCE(a.status, 'draft') AS status,
      a.tribe_id,
      t.name AS tribe_name,
      m.name AS author_name,
      a.tags,
      a.submitted_at,
      a.reviewed_at,
      a.review_notes,
      'artifacts'::TEXT AS _table,
      COALESCE(a.source, 'manual') AS source,
      public.suggest_tags(a.title, a.type, a.cycle::TEXT) AS suggested_tags
    FROM artifacts a
    LEFT JOIN tribes t ON t.id = a.tribe_id
    LEFT JOIN members m ON m.id = a.member_id
    WHERE (p_status IS NULL OR a.status = p_status)
    ORDER BY a.submitted_at DESC NULLS LAST
  ) r

  UNION ALL

  SELECT row_to_json(r) FROM (
    SELECT
      hr.id,
      hr.title,
      hr.asset_type AS type,
      hr.url,
      hr.description,
      CASE WHEN hr.is_active THEN 'approved' ELSE 'pending' END AS status,
      hr.tribe_id,
      t.name AS tribe_name,
      m.name AS author_name,
      hr.tags,
      hr.created_at AS submitted_at,
      NULL::TIMESTAMPTZ AS reviewed_at,
      NULL::TEXT AS review_notes,
      'hub_resources'::TEXT AS _table,
      COALESCE(hr.source, 'manual') AS source,
      public.suggest_tags(hr.title, hr.asset_type, hr.cycle_code) AS suggested_tags
    FROM hub_resources hr
    LEFT JOIN tribes t ON t.id = hr.tribe_id
    LEFT JOIN members m ON m.id = hr.author_id
    WHERE (p_status IS NULL
           OR (p_status = 'approved' AND hr.is_active = true)
           OR (p_status = 'pending' AND hr.is_active = false))
    ORDER BY hr.created_at DESC NULLS LAST
  ) r;
END;
$$;
