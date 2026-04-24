-- =============================================================================
-- content_diff_json auto-populate trigger + immutability refinement
-- =============================================================================
-- Issue: p42 Track A smoke descobriu que content_diff_json column é sempre
--   NULL em prod — upsert_document_version nunca populated. get_version_diff
--   retorna pre_computed_diff=NULL sempre, forçando host a computar from scratch.
--
-- This migration:
--   1. Refines trg_document_version_immutable to exclude content_diff_json
--      from immutability (architectural correctness — it's a derived field,
--      not authored content).
--   2. Adds BEFORE INSERT OR UPDATE OF content_html trigger
--      `compute_document_version_diff` auto-populating NEW.content_diff_json.
--   3. Backfills existing 11 rows via direct UPDATE of content_diff_json.
--
-- Immutability refinement rationale: content_diff_json is derivable from
-- content_html (it's purely a function of NEW vs prev content_html). The
-- lock should protect AUTHORED content (content_html, content_markdown,
-- version_*, locked_at) — not derived metadata. Future algorithm changes
-- may require recomputation on locked rows; should not require dropping
-- the immutability trigger.
--
-- Diff algorithm v1: chars + line-level set diff via EXCEPT ALL. Pragmatic,
-- not LCS. ~200-300 bytes jsonb per row.
--
-- Rollback: re-add content_diff_json to immutability IS DISTINCT list + DROP
--   new trigger + UPDATE document_versions SET content_diff_json = NULL.
-- =============================================================================

-- 1. Refine immutability trigger — remove content_diff_json from protected set
CREATE OR REPLACE FUNCTION public.trg_document_version_immutable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
BEGIN
  IF OLD.locked_at IS NOT NULL THEN
    -- content_diff_json intentionally excluded — it's a derived field (see
    -- compute_document_version_diff trigger). Authored content fields remain locked.
    IF NEW.content_html IS DISTINCT FROM OLD.content_html
       OR NEW.content_markdown IS DISTINCT FROM OLD.content_markdown
       OR NEW.version_number IS DISTINCT FROM OLD.version_number
       OR NEW.version_label IS DISTINCT FROM OLD.version_label
       OR NEW.document_id IS DISTINCT FROM OLD.document_id
       OR NEW.locked_at IS DISTINCT FROM OLD.locked_at
    THEN
      RAISE EXCEPTION 'document_versions row locked at % is immutable (id=%, document=%)', OLD.locked_at, OLD.id, OLD.document_id
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  NEW.updated_at = now();
  RETURN NEW;
END;
$fn$;

-- 2. Auto-populate trigger function
CREATE OR REPLACE FUNCTION public.compute_document_version_diff()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_prev record;
  v_lines_prev int;
  v_lines_new int;
  v_lines_added int;
  v_lines_removed int;
BEGIN
  SELECT dv.id, dv.version_number, dv.content_html
  INTO v_prev
  FROM public.document_versions dv
  WHERE dv.document_id = NEW.document_id
    AND dv.version_number < NEW.version_number
  ORDER BY dv.version_number DESC
  LIMIT 1;

  IF v_prev.id IS NULL THEN
    NEW.content_diff_json := jsonb_build_object(
      'is_initial', true,
      'prev_version_id', NULL,
      'prev_version_number', NULL,
      'content_html_length_new', length(COALESCE(NEW.content_html, '')),
      'lines_new', COALESCE(array_length(regexp_split_to_array(COALESCE(NEW.content_html, ''), E'\n'), 1), 0),
      'computed_at', now()
    );
    RETURN NEW;
  END IF;

  v_lines_prev := COALESCE(array_length(regexp_split_to_array(v_prev.content_html, E'\n'), 1), 0);
  v_lines_new := COALESCE(array_length(regexp_split_to_array(COALESCE(NEW.content_html, ''), E'\n'), 1), 0);

  SELECT COUNT(*)::int INTO v_lines_added
  FROM (
    SELECT line FROM unnest(regexp_split_to_array(COALESCE(NEW.content_html, ''), E'\n')) AS t(line)
    EXCEPT ALL
    SELECT line FROM unnest(regexp_split_to_array(v_prev.content_html, E'\n')) AS t(line)
  ) s;

  SELECT COUNT(*)::int INTO v_lines_removed
  FROM (
    SELECT line FROM unnest(regexp_split_to_array(v_prev.content_html, E'\n')) AS t(line)
    EXCEPT ALL
    SELECT line FROM unnest(regexp_split_to_array(COALESCE(NEW.content_html, ''), E'\n')) AS t(line)
  ) s;

  NEW.content_diff_json := jsonb_build_object(
    'is_initial', false,
    'prev_version_id', v_prev.id,
    'prev_version_number', v_prev.version_number,
    'content_html_length_prev', length(v_prev.content_html),
    'content_html_length_new', length(COALESCE(NEW.content_html, '')),
    'chars_delta', length(COALESCE(NEW.content_html, '')) - length(v_prev.content_html),
    'lines_prev', v_lines_prev,
    'lines_new', v_lines_new,
    'lines_added', v_lines_added,
    'lines_removed', v_lines_removed,
    'computed_at', now()
  );

  RETURN NEW;
END;
$fn$;

COMMENT ON FUNCTION public.compute_document_version_diff() IS
  'BEFORE INSERT OR UPDATE OF content_html trigger. Auto-populates document_versions.content_diff_json '
  'with diff stats vs previous version (N-1) of same document. Used by get_version_diff RPC + MCP tool. '
  'Pragmatic v1 algorithm — chars + line-level set diff via EXCEPT ALL (unordered approximation, not LCS). '
  'Issue p42 Track C1 follow-up.';

DROP TRIGGER IF EXISTS trg_compute_document_version_diff ON public.document_versions;
CREATE TRIGGER trg_compute_document_version_diff
  BEFORE INSERT OR UPDATE OF content_html ON public.document_versions
  FOR EACH ROW EXECUTE FUNCTION public.compute_document_version_diff();

-- 3. Backfill existing rows — direct UPDATE of content_diff_json (now allowed
-- on locked rows after immutability refinement above).
DO $backfill$
DECLARE
  v_row record;
  v_prev record;
  v_lines_prev int;
  v_lines_new int;
  v_lines_added int;
  v_lines_removed int;
  v_diff jsonb;
BEGIN
  FOR v_row IN SELECT id, document_id, version_number, content_html FROM public.document_versions ORDER BY document_id, version_number LOOP
    v_prev := NULL;
    SELECT dv.id, dv.version_number, dv.content_html INTO v_prev
    FROM public.document_versions dv
    WHERE dv.document_id = v_row.document_id AND dv.version_number < v_row.version_number
    ORDER BY dv.version_number DESC LIMIT 1;

    IF v_prev.id IS NULL THEN
      v_diff := jsonb_build_object(
        'is_initial', true,
        'prev_version_id', NULL,
        'prev_version_number', NULL,
        'content_html_length_new', length(COALESCE(v_row.content_html, '')),
        'lines_new', COALESCE(array_length(regexp_split_to_array(COALESCE(v_row.content_html, ''), E'\n'), 1), 0),
        'computed_at', now()
      );
    ELSE
      v_lines_prev := COALESCE(array_length(regexp_split_to_array(v_prev.content_html, E'\n'), 1), 0);
      v_lines_new := COALESCE(array_length(regexp_split_to_array(COALESCE(v_row.content_html, ''), E'\n'), 1), 0);

      SELECT COUNT(*)::int INTO v_lines_added
      FROM (
        SELECT line FROM unnest(regexp_split_to_array(COALESCE(v_row.content_html, ''), E'\n')) AS t(line)
        EXCEPT ALL
        SELECT line FROM unnest(regexp_split_to_array(v_prev.content_html, E'\n')) AS t(line)
      ) s;

      SELECT COUNT(*)::int INTO v_lines_removed
      FROM (
        SELECT line FROM unnest(regexp_split_to_array(v_prev.content_html, E'\n')) AS t(line)
        EXCEPT ALL
        SELECT line FROM unnest(regexp_split_to_array(COALESCE(v_row.content_html, ''), E'\n')) AS t(line)
      ) s;

      v_diff := jsonb_build_object(
        'is_initial', false,
        'prev_version_id', v_prev.id,
        'prev_version_number', v_prev.version_number,
        'content_html_length_prev', length(v_prev.content_html),
        'content_html_length_new', length(COALESCE(v_row.content_html, '')),
        'chars_delta', length(COALESCE(v_row.content_html, '')) - length(v_prev.content_html),
        'lines_prev', v_lines_prev,
        'lines_new', v_lines_new,
        'lines_added', v_lines_added,
        'lines_removed', v_lines_removed,
        'computed_at', now()
      );
    END IF;

    UPDATE public.document_versions SET content_diff_json = v_diff WHERE id = v_row.id;
  END LOOP;
END;
$backfill$;
