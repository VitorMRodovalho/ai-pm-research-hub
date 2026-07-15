-- #785: gate list_drive_discoveries to the initiatives the caller may see (+ fix a
-- pre-existing aggregate/pagination bug surfaced while gating it).
--
-- The function is gated by view_internal_analytics but listed drive-file discoveries for
-- any initiative regardless of its visibility. The prior structural containment ("the
-- confidential initiative has 0 drive links") no longer holds: initiative Drive
-- provisioning (#1376 / ADR-0124) created a drive link for the confidential committee,
-- so a file discovered under it would otherwise be listed without a visibility check.
--
-- Fix 1 (security): AND public.rls_can_see_initiative(l.initiative_id) into both the count
-- and the returned rows. rls_can_see_initiative returns true for non-confidential
-- initiatives and for engaged members / GP, so ordinary analytics viewers keep seeing all
-- non-confidential discoveries; only the confidential initiative is filtered from
-- non-engaged callers.
--
-- Fix 2 (pre-existing bug): the live body aggregated with jsonb_agg while applying
-- `ORDER BY d.discovered_at DESC LIMIT/OFFSET` at the OUTER level of that aggregate query
-- (no GROUP BY) -> "column d.discovered_at must appear in the GROUP BY clause". The
-- function errored on every call that reached the row aggregation (it was in the
-- never-called set, so this went unnoticed). Restructured to ORDER/LIMIT/OFFSET the rows
-- in a subquery and aggregate its output, preserving the same shape and ordering.
--
-- Apply + register + NOTIFY per Track Q-C / GC-097.

CREATE OR REPLACE FUNCTION public.list_drive_discoveries(p_initiative_id uuid DEFAULT NULL::uuid, p_status_filter text DEFAULT 'all'::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_rows jsonb;
  v_total integer;
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Not authorized: requires view_internal_analytics');
  END IF;
  IF p_status_filter NOT IN ('all', 'unmatched', 'unpromoted', 'promoted') THEN
    RETURN jsonb_build_object('error', 'Invalid status_filter. Use: all | unmatched | unpromoted | promoted');
  END IF;

  WITH base AS (
    SELECT d.id
    FROM public.drive_file_discoveries d
    INNER JOIN public.initiative_drive_links l ON l.id = d.initiative_drive_link_id
    WHERE (p_initiative_id IS NULL OR l.initiative_id = p_initiative_id)
      AND public.rls_can_see_initiative(l.initiative_id)
      AND (
        p_status_filter = 'all'
        OR (p_status_filter = 'unmatched' AND d.matched_event_id IS NULL)
        OR (p_status_filter = 'unpromoted' AND d.matched_event_id IS NOT NULL AND d.promoted_to_minutes_url = false)
        OR (p_status_filter = 'promoted' AND d.promoted_to_minutes_url = true)
      )
  )
  SELECT count(*) INTO v_total FROM base;

  SELECT coalesce(jsonb_agg(elem ORDER BY disc DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      jsonb_build_object(
        'id', d.id,
        'initiative_id', l.initiative_id,
        'initiative_title', i.title,
        'drive_folder_name', l.drive_folder_name,
        'drive_file_id', d.drive_file_id,
        'drive_file_url', d.drive_file_url,
        'filename', d.filename,
        'mime_type', d.mime_type,
        'size_bytes', d.size_bytes,
        'drive_modified_at', d.drive_modified_at,
        'discovered_at', d.discovered_at,
        'matched_event_id', d.matched_event_id,
        'matched_event_title', e.title,
        'matched_event_date', e.date,
        'match_strategy', d.match_strategy,
        'match_confidence', d.match_confidence,
        'promoted_to_minutes_url', d.promoted_to_minutes_url,
        'promoted_at', d.promoted_at,
        'promoted_by_name', m.name
      ) AS elem,
      d.discovered_at AS disc
    FROM public.drive_file_discoveries d
    INNER JOIN public.initiative_drive_links l ON l.id = d.initiative_drive_link_id
    LEFT JOIN public.initiatives i ON i.id = l.initiative_id
    LEFT JOIN public.events e ON e.id = d.matched_event_id
    LEFT JOIN public.members m ON m.id = d.promoted_by
    WHERE (p_initiative_id IS NULL OR l.initiative_id = p_initiative_id)
      AND public.rls_can_see_initiative(l.initiative_id)
      AND (
        p_status_filter = 'all'
        OR (p_status_filter = 'unmatched' AND d.matched_event_id IS NULL)
        OR (p_status_filter = 'unpromoted' AND d.matched_event_id IS NOT NULL AND d.promoted_to_minutes_url = false)
        OR (p_status_filter = 'promoted' AND d.promoted_to_minutes_url = true)
      )
    ORDER BY d.discovered_at DESC
    LIMIT v_limit OFFSET v_offset
  ) sub;

  RETURN jsonb_build_object(
    'total', v_total,
    'limit', v_limit,
    'offset', v_offset,
    'discoveries', v_rows,
    'fetched_at', now()
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
