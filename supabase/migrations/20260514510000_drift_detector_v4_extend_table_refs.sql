-- Issue #81 #4 v4: extend drift detector to catch table-level dead references.
-- v3 only checked column drops. Item 2 of handoff 2026-04-25 surfaced that
-- RPCs broken by table-level refs (cpmai_sessions, member_status_transitions)
-- needed a separate detection path.
--
-- This v4 adds:
-- - known_dropped_tables CTE (auto-verified via information_schema)
-- - pg_proc / pg_view scan for `public\.<dropped_table>` refs

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
  WITH
  known_dropped_cols_candidates AS (
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
  known_dropped_tables_candidates AS (
    SELECT * FROM (VALUES
      ('cpmai_sessions', 'never existed (Item 2 fix 2026-04-28)'),
      ('member_status_transitions', 'never existed (Item 2 fix 2026-04-28)'),
      ('member_role_changes', 'never existed (handoff suggestion outdated)')
    ) AS k(tbl, phase)
  ),
  known_dropped_tables AS (
    SELECT k.tbl, k.phase
    FROM known_dropped_tables_candidates k
    WHERE NOT EXISTS (
      SELECT 1 FROM information_schema.tables t
      WHERE t.table_schema = 'public' AND t.table_name = k.tbl
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
  pg_proc_col_hits AS (
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
  pg_proc_table_hits AS (
    SELECT
      'pg_proc'::text AS object_type,
      pc.proname::text AS object_name,
      pc.nspname::text AS schema_name,
      format('public.%s table ref', k.tbl) AS pattern_matched,
      k.tbl AS suspect_reference,
      format('Function still references public.%I (table %s)', k.tbl, k.phase) AS reason
    FROM pg_proc_clean pc
    CROSS JOIN known_dropped_tables k
    WHERE pc.clean_src ~ ('\m(public\.)?' || k.tbl || '\M')
  ),
  pg_view_col_hits AS (
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
  pg_view_table_hits AS (
    SELECT
      'pg_view'::text AS object_type,
      v.viewname::text AS object_name,
      v.schemaname::text AS schema_name,
      format('public.%s table ref', k.tbl) AS pattern_matched,
      k.tbl AS suspect_reference,
      format('View references public.%I (table %s)', k.tbl, k.phase) AS reason
    FROM pg_views v
    CROSS JOIN known_dropped_tables k
    WHERE v.schemaname = 'public'
      AND regexp_replace(
            regexp_replace(v.definition, '--[^\r\n]*', '', 'g'),
            '/\*[^*]*\*+([^/*][^*]*\*+)*/', '', 'g'
          ) ~ ('\m(public\.)?' || k.tbl || '\M')
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
  SELECT * FROM pg_proc_col_hits
  UNION ALL SELECT * FROM pg_proc_table_hits
  UNION ALL SELECT * FROM pg_view_col_hits
  UNION ALL SELECT * FROM pg_view_table_hits
  UNION ALL SELECT * FROM policy_hits
  ORDER BY object_type, object_name;
END;
$$;

COMMENT ON FUNCTION public.check_code_schema_drift() IS
'Issue #81 #4 v4: detects code references to dropped columns AND dropped tables. Auto-verifies via information_schema. Strips comments. Excludes self. Authority: view_internal_analytics. Catches drift from #79/#80 (column-level) + Item 2 handoff (table-level).';

NOTIFY pgrst, 'reload schema';
