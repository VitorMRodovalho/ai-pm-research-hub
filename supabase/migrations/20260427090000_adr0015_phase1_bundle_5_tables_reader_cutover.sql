-- ============================================================================
-- ADR-0015 Phase 1 — Bundled reader cutover (5 C3 tables)
--
-- Scope: refactor 4 reader RPCs covering hub_resources, pilots, and
-- public_publications. announcements + ia_pilots have no dedicated
-- readers with tribe_id filters/joins (consumed only via SELECT * or
-- count aggregates).
--
-- Dual-write reality check (17/Abr):
--   hub_resources      : 330 rows — 157 both + 173 neither (many globals)
--   ia_pilots          : 1 row  — neither
--   pilots             : 1 row  — neither
--   announcements      : 1 row  — neither
--   public_publications: 7 rows — all neither (global articles)
--
-- Conclusion: low-risk cutover. Only hub_resources has substantive scoped
-- rows. All other readers will preserve their effective behaviour (LEFT
-- JOIN NULL or filter returning 0 when p_tribe_id is non-null).
--
-- Refactored:
--   1. list_curation_board      — hub_resources block: JOIN initiatives
--   2. list_pending_curation    — hub_resources block: JOIN initiatives
--   3. get_pilots_summary       — LEFT JOIN initiatives for tribe_name
--   4. get_public_publications  — filter via i.legacy_tribe_id
--
-- NOT refactored (no JOIN/filter needing change):
--   - search_hub_resources   — outputs tribe_id column only; no JOIN
--   - get_publication_detail — outputs tribe_id column; no JOIN, no filter
--   - get_public_impact_data — doesn't touch these 5 tables' tribe_id
--     (only uses tribes C1 permanent + members.tribe_id C4 deferred)
--
-- NOT refactored (writers — dual-write triggers handle sync):
--   - curate_item, create_pilot, update_pilot,
--     admin_manage_publication, auto_publish_approved_article
--
-- Note on list_curation_board + list_pending_curation: they also reference
-- artifacts (NOT a C3 table — classified C2 in ADR-0015). The artifacts
-- block is left unchanged; only the hub_resources block is refactored.
--
-- ADR: ADR-0015 Phase 1
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. list_curation_board — hub_resources block uses initiatives
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.list_curation_board(
  p_status text DEFAULT NULL
)
RETURNS SETOF json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
BEGIN
  RETURN QUERY
  SELECT row_to_json(r) FROM (
    SELECT
      a.id, a.title, a.type, a.url, a.description,
      COALESCE(a.status, 'draft') AS status,
      a.tribe_id,
      t.name AS tribe_name,  -- artifacts is C2 (not C3) — still JOIN tribes
      m.name AS author_name,
      a.tags, a.submitted_at, a.reviewed_at, a.review_notes,
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
      hr.id, hr.title, hr.asset_type AS type, hr.url, hr.description,
      CASE WHEN hr.is_active THEN 'approved' ELSE 'pending' END AS status,
      hr.tribe_id,
      i.title AS tribe_name,  -- ADR-0015 Phase 1: derive from initiative
      m.name AS author_name,
      hr.tags, hr.created_at AS submitted_at,
      NULL::TIMESTAMPTZ AS reviewed_at,
      NULL::TEXT AS review_notes,
      'hub_resources'::TEXT AS _table,
      COALESCE(hr.source, 'manual') AS source,
      public.suggest_tags(hr.title, hr.asset_type, hr.cycle_code) AS suggested_tags
    FROM hub_resources hr
    LEFT JOIN initiatives i ON i.id = hr.initiative_id  -- ADR-0015 Phase 1
    LEFT JOIN members m ON m.id = hr.author_id
    WHERE (p_status IS NULL
           OR (p_status = 'approved' AND hr.is_active = true)
           OR (p_status = 'pending' AND hr.is_active = false))
    ORDER BY hr.created_at DESC NULLS LAST
  ) r;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. list_pending_curation — hub_resources block uses initiatives
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.list_pending_curation(
  p_table text DEFAULT 'all'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_member_id uuid;
  v_result jsonb := '[]'::jsonb;
  v_artifacts jsonb;
  v_resources jsonb;
BEGIN
  -- ADR-0011 V4 auth pattern: resolve member_id + can_by_member() gate
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.can_by_member(v_member_id, 'write') THEN
    RAISE EXCEPTION 'Insufficient permissions';
  END IF;

  IF p_table IN ('all', 'artifacts') THEN
    SELECT COALESCE(jsonb_agg(row_to_json(r)), '[]'::jsonb) INTO v_artifacts
    FROM (
      SELECT a.id, a.title, a.url, a.type, a.status, a.source, a.tags,
             a.curation_status, a.trello_card_id, a.cycle,
             a.created_at, m.name AS author_name,
             t.name AS tribe_name,  -- artifacts C2, still JOIN tribes
             'artifacts' AS _table,
             public.suggest_tags(a.title, a.type, a.cycle) AS suggested_tags
      FROM public.artifacts a
      LEFT JOIN public.members m ON m.id = a.member_id
      LEFT JOIN public.tribes t ON t.id = a.tribe_id
      WHERE a.source IS DISTINCT FROM 'manual'
        AND a.curation_status IN ('draft','pending_review')
      ORDER BY a.created_at DESC
      LIMIT 200
    ) r;
    v_result := v_result || COALESCE(v_artifacts, '[]'::jsonb);
  END IF;

  IF p_table IN ('all', 'hub_resources') THEN
    SELECT COALESCE(jsonb_agg(row_to_json(r)), '[]'::jsonb) INTO v_resources
    FROM (
      SELECT h.id, h.title, h.url, h.asset_type AS type, h.source, h.tags,
             h.curation_status, h.trello_card_id, h.cycle_code AS cycle,
             h.created_at, NULL::text AS author_name,
             i.title AS tribe_name,  -- ADR-0015 Phase 1
             'hub_resources' AS _table,
             public.suggest_tags(h.title, h.asset_type, h.cycle_code) AS suggested_tags
      FROM public.hub_resources h
      LEFT JOIN public.initiatives i ON i.id = h.initiative_id  -- ADR-0015 Phase 1
      WHERE h.source IS DISTINCT FROM 'manual'
        AND h.curation_status IN ('draft','pending_review')
      ORDER BY h.created_at DESC
      LIMIT 200
    ) r;
    v_result := v_result || COALESCE(v_resources, '[]'::jsonb);
  END IF;

  RETURN v_result;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. get_pilots_summary — LEFT JOIN initiatives for tribe_name
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_pilots_summary()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_agg(jsonb_build_object(
    'id', p.id,
    'pilot_number', p.pilot_number,
    'title', p.title,
    'status', p.status,
    'started_at', p.started_at,
    'completed_at', p.completed_at,
    'hypothesis', p.hypothesis,
    'problem_statement', p.problem_statement,
    'scope', p.scope,
    'tribe_name', i.title,  -- ADR-0015 Phase 1: derive from initiative
    'board_id', p.board_id,
    'days_active', CASE WHEN p.started_at IS NOT NULL
      THEN CURRENT_DATE - p.started_at ELSE 0 END,
    'success_metrics', COALESCE(p.success_metrics, '[]'::jsonb),
    'metrics_count', jsonb_array_length(COALESCE(p.success_metrics, '[]'::jsonb)),
    'team_count', COALESCE(array_length(p.team_member_ids, 1), 0)
  ) ORDER BY p.pilot_number)
  INTO v_result
  FROM public.pilots p
  LEFT JOIN public.initiatives i ON i.id = p.initiative_id;  -- ADR-0015 Phase 1

  RETURN jsonb_build_object(
    'pilots', COALESCE(v_result, '[]'::jsonb),
    'total', (SELECT count(*) FROM public.pilots),
    'active', (SELECT count(*) FROM public.pilots WHERE status = 'active'),
    'target', 3,
    'progress_pct', ROUND((SELECT count(*) FROM public.pilots WHERE status IN ('active','completed'))::numeric / 3 * 100, 0)
  );
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. get_public_publications — filter via i.legacy_tribe_id
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_public_publications(
  p_type text DEFAULT NULL,
  p_tribe_id integer DEFAULT NULL,
  p_cycle text DEFAULT NULL,
  p_search text DEFAULT NULL,
  p_limit integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_agg(row_to_json(r) ORDER BY r.is_featured DESC, r.publication_date DESC NULLS LAST)
  INTO v_result
  FROM (
    SELECT pp.id, pp.title, pp.abstract, pp.authors, pp.publication_date, pp.publication_type,
           pp.external_url, pp.external_platform, pp.doi, pp.keywords, pp.tribe_id, pp.cycle_code,
           pp.language, pp.citation_count, pp.view_count, pp.thumbnail_url, pp.pdf_url, pp.is_featured
    FROM public.public_publications pp
    LEFT JOIN public.initiatives i ON i.id = pp.initiative_id  -- ADR-0015 Phase 1
    WHERE pp.is_published = true
      AND (p_type IS NULL OR pp.publication_type = p_type)
      AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)  -- ADR-0015 Phase 1
      AND (p_cycle IS NULL OR pp.cycle_code = p_cycle)
      AND (p_search IS NULL OR pp.title ILIKE '%' || p_search || '%'
           OR pp.abstract ILIKE '%' || p_search || '%'
           OR EXISTS (SELECT 1 FROM unnest(pp.keywords) k WHERE k ILIKE '%' || p_search || '%'))
    ORDER BY pp.is_featured DESC, pp.publication_date DESC NULLS LAST
    LIMIT p_limit
  ) r;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;
