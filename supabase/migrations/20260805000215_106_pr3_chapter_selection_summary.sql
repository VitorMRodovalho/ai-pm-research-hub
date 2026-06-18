-- #106 PR3 — chapter selection pipeline (Bloco 3): a SEPARATE lazy-loaded RPC (data-architect:
-- do NOT inflate the get_chapter_dashboard monolith). Same V4 own-chapter gate.
--
-- Filters by selection_cycles.contracting_chapter = v_chapter (NOT selection_applications.chapter,
-- which is an arbitrary order-dependent guess for multi-chapter members — mig 20260805000189).
-- Returns the most-recent OPEN cycle for the chapter (live data) + a 'last' fallback for the
-- graceful empty-state (ux R2) when no cycle is open.

CREATE OR REPLACE FUNCTION public.get_chapter_selection_summary(p_chapter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_chapter text;
  v_chapter text;
BEGIN
  SELECT m.id, m.chapter INTO v_caller_id, v_caller_chapter
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- V4 gate (mirrors get_chapter_dashboard): cross-chapter for view_internal_analytics, else own.
  IF public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    v_chapter := COALESCE(p_chapter, v_caller_chapter);
  ELSIF p_chapter IS NULL OR p_chapter = v_caller_chapter THEN
    v_chapter := v_caller_chapter;
  ELSE
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  IF v_chapter IS NULL THEN
    RETURN jsonb_build_object('error', 'No chapter specified');
  END IF;

  RETURN jsonb_build_object(
    'open', (
      SELECT jsonb_build_object(
        'cycle_code', sc.cycle_code,
        'title', sc.title,
        'close_date', sc.close_date,
        'booking_url', sc.interview_booking_url,
        'open_apps', (SELECT count(*) FROM public.selection_applications sa WHERE sa.cycle_id = sc.id)
      )
      FROM public.selection_cycles sc
      WHERE sc.contracting_chapter = v_chapter AND sc.status = 'open'
      ORDER BY sc.created_at DESC LIMIT 1
    ),
    'last', (
      SELECT jsonb_build_object('title', sc.title, 'close_date', sc.close_date)
      FROM public.selection_cycles sc
      WHERE sc.contracting_chapter = v_chapter
      ORDER BY sc.created_at DESC LIMIT 1
    )
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_chapter_selection_summary(text) FROM public;
GRANT EXECUTE ON FUNCTION public.get_chapter_selection_summary(text) TO authenticated;

-- ROLLBACK: DROP FUNCTION public.get_chapter_selection_summary(text);
