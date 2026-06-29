-- #963: webinars_pending_comms() was SECURITY DEFINER with NO permission check and
-- EXECUTE granted to `authenticated`, returning meeting_link (live Zoom/Meet/Teams
-- conference URLs) for confirmed/completed webinars. Any authenticated member — incl.
-- via the get_comms_pending_webinars MCP tool, which only checks authentication — could
-- read the meeting links. Gate behind can_view_comms_analytics() (same model as #961/#883).
-- Body-only CREATE OR REPLACE; grant unchanged. Denied → '[]' (the function's natural
-- empty shape; the comms-ops page hides the section on empty, no frontend change needed).
--
-- Two-sided live verification (2026-06-29):
--   * Mayanna (comms_leader)            → 3 webinars, meeting_link present
--   * Ana Carla (tribe_leader, no comms) → [] (was leaking meeting_link before)
--   * no-JWT / anon                      → []
--
-- The in-body RPC gate is the boundary (ADR-0106); the MCP tool get_comms_pending_webinars
-- is protected transitively (it calls this RPC with the user-scoped client), so no EF change.
CREATE OR REPLACE FUNCTION public.webinars_pending_comms()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_result jsonb;
BEGIN
  -- #963: meeting_link is a live access credential — restrict the comms worklist to the
  -- comms-analytics tier (comms team / managers / governance), same gate as the siblings.
  IF NOT public.can_view_comms_analytics() THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.scheduled_at), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      w.id, w.title, w.scheduled_at, w.status, w.chapter_code,
      w.meeting_link, w.youtube_url,
      i.legacy_tribe_id AS tribe_id,
      i.title AS tribe_name,
      m.name AS organizer_name,
      CASE
        WHEN w.status = 'confirmed' AND w.scheduled_at > now() THEN 'invite'
        WHEN w.status = 'confirmed' AND w.scheduled_at <= now() THEN 'followup'
        WHEN w.status = 'completed' AND w.youtube_url IS NULL THEN 'awaiting_replay'
        WHEN w.status = 'completed' AND w.youtube_url IS NOT NULL THEN 'replay_ready'
        ELSE 'info'
      END AS comms_action,
      CASE
        WHEN w.status = 'confirmed' AND w.scheduled_at > now() THEN 'Preparar convite e lembretes'
        WHEN w.status = 'confirmed' AND w.scheduled_at <= now() THEN 'Preparar follow-up pós-evento'
        WHEN w.status = 'completed' AND w.youtube_url IS NULL THEN 'Aguardando replay para divulgar'
        WHEN w.status = 'completed' AND w.youtube_url IS NOT NULL THEN 'Divulgar replay e materiais'
        ELSE 'Acompanhar'
      END AS comms_label
    FROM public.webinars w
    LEFT JOIN public.initiatives i ON i.id = w.initiative_id
    LEFT JOIN public.members m ON m.id = w.organizer_id
    WHERE w.status IN ('confirmed', 'completed')
    ORDER BY w.scheduled_at
  ) r;
  RETURN v_result;
END; $function$;
