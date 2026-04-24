-- content_diff_json v2 — word-level set diff + HTML tag stripping
-- =============================================================================
-- Issue: p44 Track M resolve. v1 (line-level EXCEPT ALL) is useless on
-- WYSIWYG output where content_html is single-line — produces lines_new=1,
-- lines_removed=N cardinality artifacts that carry no signal.
--
-- v2 algorithm:
--   1. keep line-level metrics for backward compat (algo_version='v2')
--   2. strip HTML tags via regexp_replace <[^>]+> → ' '
--   3. normalize whitespace + lowercase for word comparison
--   4. word-level EXCEPT ALL on cleaned text
--
-- New fields: algo_version, words_prev, words_new, words_added, words_removed.
-- Existing fields preserved: is_initial, prev_version_id, prev_version_number,
-- content_html_length_prev/new, chars_delta, lines_prev/new, lines_added/removed,
-- computed_at.
--
-- Limitations of v2:
--   - Still multiset diff (EXCEPT ALL), not ordered LCS. Rearrangement without
--     text change still not detected. Acceptable — true LCS is ~100 plpgsql
--     lines and review UX rarely needs it.
--   - Case-insensitive comparison (lowercase) — ignores case-only changes.
--     Acceptable for governance documents.
--
-- Rollback: DROP trigger, CREATE OR REPLACE back to v1 body (this file's
-- compute_document_version_diff body replaced by the v1 from migration
-- 20260510070000), re-run backfill.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.compute_document_version_diff()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_prev record;
  v_prev_text text;
  v_new_text text;
  v_new_content text := COALESCE(NEW.content_html, '');
  v_lines_prev int; v_lines_new int;
  v_lines_added int; v_lines_removed int;
  v_words_prev int; v_words_new int;
  v_words_added int; v_words_removed int;
BEGIN
  SELECT dv.id, dv.version_number, dv.content_html
  INTO v_prev
  FROM public.document_versions dv
  WHERE dv.document_id = NEW.document_id
    AND dv.version_number < NEW.version_number
  ORDER BY dv.version_number DESC
  LIMIT 1;

  -- Initial version: no predecessor to diff against
  IF v_prev.id IS NULL THEN
    v_new_text := lower(regexp_replace(v_new_content, '<[^>]+>', ' ', 'g'));
    v_words_new := COALESCE(array_length(
      array(SELECT word FROM unnest(regexp_split_to_array(v_new_text, '\s+')) AS t(word) WHERE word <> '')
    , 1), 0);
    NEW.content_diff_json := jsonb_build_object(
      'algo_version', 'v2-word-set-diff',
      'is_initial', true,
      'prev_version_id', NULL,
      'prev_version_number', NULL,
      'content_html_length_new', length(v_new_content),
      'lines_new', COALESCE(array_length(regexp_split_to_array(v_new_content, E'\n'), 1), 0),
      'words_new', v_words_new,
      'computed_at', now()
    );
    RETURN NEW;
  END IF;

  -- Line-level metrics (preserved from v1 for backward compat)
  v_lines_prev := COALESCE(array_length(regexp_split_to_array(v_prev.content_html, E'\n'), 1), 0);
  v_lines_new := COALESCE(array_length(regexp_split_to_array(v_new_content, E'\n'), 1), 0);

  SELECT COUNT(*)::int INTO v_lines_added FROM (
    SELECT line FROM unnest(regexp_split_to_array(v_new_content, E'\n')) AS t(line)
    EXCEPT ALL
    SELECT line FROM unnest(regexp_split_to_array(v_prev.content_html, E'\n')) AS t(line)
  ) s;

  SELECT COUNT(*)::int INTO v_lines_removed FROM (
    SELECT line FROM unnest(regexp_split_to_array(v_prev.content_html, E'\n')) AS t(line)
    EXCEPT ALL
    SELECT line FROM unnest(regexp_split_to_array(v_new_content, E'\n')) AS t(line)
  ) s;

  -- Word-level metrics (new in v2): strip tags, lowercase, split on whitespace, drop empties.
  v_prev_text := lower(regexp_replace(v_prev.content_html, '<[^>]+>', ' ', 'g'));
  v_new_text := lower(regexp_replace(v_new_content, '<[^>]+>', ' ', 'g'));

  v_words_prev := COALESCE(array_length(
    array(SELECT word FROM unnest(regexp_split_to_array(v_prev_text, '\s+')) AS t(word) WHERE word <> '')
  , 1), 0);
  v_words_new := COALESCE(array_length(
    array(SELECT word FROM unnest(regexp_split_to_array(v_new_text, '\s+')) AS t(word) WHERE word <> '')
  , 1), 0);

  SELECT COUNT(*)::int INTO v_words_added FROM (
    SELECT word FROM unnest(regexp_split_to_array(v_new_text, '\s+')) AS t(word) WHERE word <> ''
    EXCEPT ALL
    SELECT word FROM unnest(regexp_split_to_array(v_prev_text, '\s+')) AS t(word) WHERE word <> ''
  ) s;

  SELECT COUNT(*)::int INTO v_words_removed FROM (
    SELECT word FROM unnest(regexp_split_to_array(v_prev_text, '\s+')) AS t(word) WHERE word <> ''
    EXCEPT ALL
    SELECT word FROM unnest(regexp_split_to_array(v_new_text, '\s+')) AS t(word) WHERE word <> ''
  ) s;

  NEW.content_diff_json := jsonb_build_object(
    'algo_version', 'v2-word-set-diff',
    'is_initial', false,
    'prev_version_id', v_prev.id,
    'prev_version_number', v_prev.version_number,
    'content_html_length_prev', length(v_prev.content_html),
    'content_html_length_new', length(v_new_content),
    'chars_delta', length(v_new_content) - length(v_prev.content_html),
    'lines_prev', v_lines_prev,
    'lines_new', v_lines_new,
    'lines_added', v_lines_added,
    'lines_removed', v_lines_removed,
    'words_prev', v_words_prev,
    'words_new', v_words_new,
    'words_added', v_words_added,
    'words_removed', v_words_removed,
    'computed_at', now()
  );

  RETURN NEW;
END;
$fn$;

COMMENT ON FUNCTION public.compute_document_version_diff() IS
  'BEFORE INSERT OR UPDATE OF content_html trigger. Auto-populates document_versions.content_diff_json '
  'with diff stats vs previous version (N-1) of same document. v2 algorithm (p44 Track M): line-level '
  'metrics preserved for backward compat + word-level metrics (words_prev/new/added/removed) computed '
  'after HTML tag stripping + lowercase normalization. Uses EXCEPT ALL multiset diff, not true LCS — '
  'adequate for review UX.';

-- Backfill existing 16 rows with v2 diff (UPDATE of non-immutable column allowed)
DO $backfill$
DECLARE
  v_row record;
  v_prev record;
  v_prev_text text; v_new_text text;
  v_new_content text;
  v_lines_prev int; v_lines_new int;
  v_lines_added int; v_lines_removed int;
  v_words_prev int; v_words_new int;
  v_words_added int; v_words_removed int;
  v_diff jsonb;
BEGIN
  FOR v_row IN
    SELECT id, document_id, version_number, content_html
    FROM public.document_versions
    ORDER BY document_id, version_number
  LOOP
    v_new_content := COALESCE(v_row.content_html, '');
    v_prev := NULL;

    SELECT dv.id, dv.version_number, dv.content_html INTO v_prev
    FROM public.document_versions dv
    WHERE dv.document_id = v_row.document_id AND dv.version_number < v_row.version_number
    ORDER BY dv.version_number DESC LIMIT 1;

    IF v_prev.id IS NULL THEN
      v_new_text := lower(regexp_replace(v_new_content, '<[^>]+>', ' ', 'g'));
      v_words_new := COALESCE(array_length(
        array(SELECT word FROM unnest(regexp_split_to_array(v_new_text, '\s+')) AS t(word) WHERE word <> '')
      , 1), 0);
      v_diff := jsonb_build_object(
        'algo_version', 'v2-word-set-diff',
        'is_initial', true,
        'prev_version_id', NULL,
        'prev_version_number', NULL,
        'content_html_length_new', length(v_new_content),
        'lines_new', COALESCE(array_length(regexp_split_to_array(v_new_content, E'\n'), 1), 0),
        'words_new', v_words_new,
        'computed_at', now()
      );
    ELSE
      v_lines_prev := COALESCE(array_length(regexp_split_to_array(v_prev.content_html, E'\n'), 1), 0);
      v_lines_new := COALESCE(array_length(regexp_split_to_array(v_new_content, E'\n'), 1), 0);

      SELECT COUNT(*)::int INTO v_lines_added FROM (
        SELECT line FROM unnest(regexp_split_to_array(v_new_content, E'\n')) AS t(line)
        EXCEPT ALL
        SELECT line FROM unnest(regexp_split_to_array(v_prev.content_html, E'\n')) AS t(line)
      ) s;

      SELECT COUNT(*)::int INTO v_lines_removed FROM (
        SELECT line FROM unnest(regexp_split_to_array(v_prev.content_html, E'\n')) AS t(line)
        EXCEPT ALL
        SELECT line FROM unnest(regexp_split_to_array(v_new_content, E'\n')) AS t(line)
      ) s;

      v_prev_text := lower(regexp_replace(v_prev.content_html, '<[^>]+>', ' ', 'g'));
      v_new_text := lower(regexp_replace(v_new_content, '<[^>]+>', ' ', 'g'));

      v_words_prev := COALESCE(array_length(
        array(SELECT word FROM unnest(regexp_split_to_array(v_prev_text, '\s+')) AS t(word) WHERE word <> '')
      , 1), 0);
      v_words_new := COALESCE(array_length(
        array(SELECT word FROM unnest(regexp_split_to_array(v_new_text, '\s+')) AS t(word) WHERE word <> '')
      , 1), 0);

      SELECT COUNT(*)::int INTO v_words_added FROM (
        SELECT word FROM unnest(regexp_split_to_array(v_new_text, '\s+')) AS t(word) WHERE word <> ''
        EXCEPT ALL
        SELECT word FROM unnest(regexp_split_to_array(v_prev_text, '\s+')) AS t(word) WHERE word <> ''
      ) s;

      SELECT COUNT(*)::int INTO v_words_removed FROM (
        SELECT word FROM unnest(regexp_split_to_array(v_prev_text, '\s+')) AS t(word) WHERE word <> ''
        EXCEPT ALL
        SELECT word FROM unnest(regexp_split_to_array(v_new_text, '\s+')) AS t(word) WHERE word <> ''
      ) s;

      v_diff := jsonb_build_object(
        'algo_version', 'v2-word-set-diff',
        'is_initial', false,
        'prev_version_id', v_prev.id,
        'prev_version_number', v_prev.version_number,
        'content_html_length_prev', length(v_prev.content_html),
        'content_html_length_new', length(v_new_content),
        'chars_delta', length(v_new_content) - length(v_prev.content_html),
        'lines_prev', v_lines_prev,
        'lines_new', v_lines_new,
        'lines_added', v_lines_added,
        'lines_removed', v_lines_removed,
        'words_prev', v_words_prev,
        'words_new', v_words_new,
        'words_added', v_words_added,
        'words_removed', v_words_removed,
        'computed_at', now()
      );
    END IF;

    UPDATE public.document_versions SET content_diff_json = v_diff WHERE id = v_row.id;
  END LOOP;
END;
$backfill$;

NOTIFY pgrst, 'reload schema';
