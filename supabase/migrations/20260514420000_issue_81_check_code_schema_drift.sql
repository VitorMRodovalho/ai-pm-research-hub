-- Issue #81 #4: code-schema drift detector (v3 final)
-- Scans pg_proc / pg_view / pg_policy for references to dropped columns.
-- Surfaced by #79/#80: members.tribe_id Phase 3d drop left list_boards
-- silently broken for 6 days. This catches similar drift before deploy.
--
-- Design choices:
-- - Strips line + block comments before regex match (eliminates false positives
--   from `-- ADR-0015 Phase 3d: project_boards.tribe_id dropado` doc references)
-- - Auto-verifies dropped state via information_schema.columns (false positives
--   automatically filtered when column is re-added or never dropped)
-- - Excludes self-reference (this function's own VALUES list contains the
--   column names as string literals)
-- - Word-boundary regex `\m...\M` avoids substring false matches
--
-- Authority: can_by_member('view_internal_analytics').
-- Rollback: DROP FUNCTION public.check_code_schema_drift();

CREATE OR REPLACE FUNCTION public.check_code_schema_drift()
RETURNS TABLE(
  object_type text,
  object_name text,
  schema_name text,
  pattern_matched text,
  suspect_reference text,
  reason text
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_member_id uuid;
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();

  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT public.can_by_member(v_caller_member_id, 'view_internal_analytics') THEN
    RAISE EXCEPTION 'Not authorized: requires view_internal_analytics';
  END IF;

  RETURN QUERY
  WITH known_dropped_cols_candidates AS (
    -- Add (table, column, drop_phase) tuples here when you suspect drift.
    -- Auto-verified at runtime — false candidates filtered.
    SELECT * FROM (VALUES
      ('members', 'tribe_id', 'ADR-0015 Phase 3d (2026-04-15)'),
      ('events', 'tribe_id', 'ADR-0015 Phase 3d (2026-04-15)'),
      ('project_boards', 'tribe_id', 'ADR-0015 Phase 3d (2026-04-15)')
    ) AS k(tbl, col, phase)
  ),
  known_dropped_cols AS (
    SELECT k.tbl, k.col, k.phase
    FROM known_dropped_cols_candidates k
    WHERE NOT EXISTS (
      SELECT 1 FROM information_schema.columns c
      WHERE c.table_schema = 'public' AND c.table_name = k.tbl AND c.column_name = k.col
    )
  ),
  pg_proc_clean AS (
    SELECT
      p.proname,
      n.nspname,
      regexp_replace(
        regexp_replace(p.prosrc, '--[^\r\n]*', '', 'g'),
        '/\*[^*]*\*+([^/*][^*]*\*+)*/', '', 'g'
      ) AS clean_src
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname != 'check_code_schema_drift'
  ),
  pg_proc_hits AS (
    SELECT
      'pg_proc'::text AS object_type,
      pc.proname::text AS object_name,
      pc.nspname::text AS schema_name,
      format('%s.%s ref', k.tbl, k.col) AS pattern_matched,
      k.col AS suspect_reference,
      format('Function still references %I.%I (dropped in %s)', k.tbl, k.col, k.phase) AS reason
    FROM pg_proc_clean pc
    CROSS JOIN known_dropped_cols k
    WHERE pc.clean_src ~ ('\m' || k.tbl || '\.' || k.col || '\M')
  ),
  pg_view_hits AS (
    SELECT
      'pg_view'::text AS object_type,
      v.viewname::text AS object_name,
      v.schemaname::text AS schema_name,
      format('%s.%s ref', k.tbl, k.col) AS pattern_matched,
      k.col AS suspect_reference,
      format('View definition still references %I.%I (dropped in %s)', k.tbl, k.col, k.phase) AS reason
    FROM pg_views v
    CROSS JOIN known_dropped_cols k
    WHERE v.schemaname = 'public'
      AND regexp_replace(
            regexp_replace(v.definition, '--[^\r\n]*', '', 'g'),
            '/\*[^*]*\*+([^/*][^*]*\*+)*/', '', 'g'
          ) ~ ('\m' || k.tbl || '\.' || k.col || '\M')
  ),
  policy_hits AS (
    SELECT
      'pg_policy'::text AS object_type,
      pol.polname::text AS object_name,
      n.nspname::text AS schema_name,
      format('%s.%s ref', k.tbl, k.col) AS pattern_matched,
      k.col AS suspect_reference,
      format('RLS policy on %I.%I still references %I.%I (dropped in %s)', n.nspname, c.relname, k.tbl, k.col, k.phase) AS reason
    FROM pg_policy pol
    JOIN pg_class c ON c.oid = pol.polrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    CROSS JOIN known_dropped_cols k
    WHERE (
      coalesce(pg_get_expr(pol.polqual, pol.polrelid), '') ~ ('\m' || k.tbl || '\.' || k.col || '\M')
      OR coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), '') ~ ('\m' || k.tbl || '\.' || k.col || '\M')
    )
  )
  SELECT * FROM pg_proc_hits
  UNION ALL SELECT * FROM pg_view_hits
  UNION ALL SELECT * FROM policy_hits
  ORDER BY object_type, object_name;
END;
$$;

REVOKE ALL ON FUNCTION public.check_code_schema_drift() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_code_schema_drift() TO authenticated;

COMMENT ON FUNCTION public.check_code_schema_drift() IS
'Issue #81 #4: detects code references to dropped columns. Strips line + block comments. Auto-verifies dropped state via information_schema. Excludes self-reference. Authority: view_internal_analytics. Catches drift surfaced by #79/#80.';

NOTIFY pgrst, 'reload schema';
