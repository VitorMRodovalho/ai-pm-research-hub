-- p95 #131 — comms self-service: pipeline view + asset patcher
-- Spinoff from #89 Frente 4 split per PM decision 3A.
-- Mayanna não consegue responder via plataforma: template divulgação, Sympla cadastrar, briefing materials.
-- Build sobre #129 (cols briefing_doc_url + sympla_event_url + promo_kit_url + comms_kickoff_at já em prod).
-- Rollback:
--   DROP FUNCTION IF EXISTS public.get_comms_pipeline();
--   DROP FUNCTION IF EXISTS public.update_webinar_comms_assets(uuid,text,text,text,boolean);

-- ============================================================
-- get_comms_pipeline — read view
-- Distinct from webinars_pending_comms (status-driven actions).
-- This one: ALL upcoming webinars (planned + confirmed) with PROMO ASSET readiness.
-- Mayanna's perspective: "what's the pipeline of webinars I need to prep promo for".
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_comms_pipeline()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_now timestamptz := now();
  v_urgent_count int;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT (
    public.can_by_member(v_caller_id, 'write_board') OR
    public.can_by_member(v_caller_id, 'manage_event') OR
    public.can_by_member(v_caller_id, 'manage_member')
  ) THEN
    RAISE EXCEPTION 'Unauthorized: requires comms/board/admin authority';
  END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.scheduled_at), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      w.id AS webinar_id,
      w.title,
      w.scheduled_at,
      w.status,
      w.chapter_code,
      w.format_type,
      w.series_id,
      COALESCE(ps.title_i18n->>'pt-BR', ps.slug) AS series_title,
      ps.slug AS series_slug,
      w.series_position,
      w.tribe_anchors,
      i.title AS initiative_title,
      m.name AS organizer_name,
      w.briefing_doc_url,
      w.sympla_event_url,
      w.promo_kit_url,
      w.comms_kickoff_at,
      (w.briefing_doc_url IS NOT NULL) AS has_briefing,
      (w.sympla_event_url IS NOT NULL) AS has_sympla,
      (w.promo_kit_url IS NOT NULL) AS has_promo_kit,
      (w.comms_kickoff_at IS NOT NULL) AS comms_kickoff_logged,
      (w.scheduled_at - interval '30 days') AS d30_due_at,
      EXTRACT(EPOCH FROM (w.scheduled_at - v_now))::bigint / 86400 AS days_until,
      CASE
        WHEN w.briefing_doc_url IS NOT NULL
         AND w.sympla_event_url IS NOT NULL
         AND w.promo_kit_url IS NOT NULL THEN 'ready'
        WHEN w.briefing_doc_url IS NULL
         AND w.sympla_event_url IS NULL
         AND w.promo_kit_url IS NULL THEN 'not_started'
        ELSE 'in_progress'
      END AS readiness,
      (
        w.scheduled_at <= v_now + interval '30 days'
        AND w.scheduled_at > v_now
        AND (w.briefing_doc_url IS NULL OR w.sympla_event_url IS NULL OR w.promo_kit_url IS NULL)
      ) AS urgent
    FROM public.webinars w
    LEFT JOIN public.initiatives i ON i.id = w.initiative_id
    LEFT JOIN public.members m ON m.id = w.organizer_id
    LEFT JOIN public.publication_series ps ON ps.id = w.series_id
    WHERE w.status IN ('planned', 'confirmed')
      AND w.scheduled_at >= v_now - interval '7 days'
    ORDER BY w.scheduled_at
  ) r;

  SELECT COUNT(*) INTO v_urgent_count
  FROM public.webinars w
  WHERE w.status IN ('planned', 'confirmed')
    AND w.scheduled_at <= v_now + interval '30 days'
    AND w.scheduled_at > v_now
    AND (w.briefing_doc_url IS NULL OR w.sympla_event_url IS NULL OR w.promo_kit_url IS NULL);

  RETURN jsonb_build_object(
    'webinars', v_result,
    'count', jsonb_array_length(v_result),
    'urgent_count', v_urgent_count,
    'generated_at', v_now
  );
END; $function$;

GRANT EXECUTE ON FUNCTION public.get_comms_pipeline() TO authenticated;

COMMENT ON FUNCTION public.get_comms_pipeline() IS
  'Returns webinars pipeline with promo asset readiness (briefing_doc / sympla_event / promo_kit / comms_kickoff). Spinoff #131 from #89 Frente 4. Build sobre #129 cols.';

-- ============================================================
-- update_webinar_comms_assets — patcher
-- Mayanna fills briefing/sympla/promo_kit URLs without DB access.
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_webinar_comms_assets(
  p_webinar_id uuid,
  p_briefing_doc_url text DEFAULT NULL,
  p_sympla_event_url text DEFAULT NULL,
  p_promo_kit_url text DEFAULT NULL,
  p_mark_kickoff boolean DEFAULT FALSE
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_webinar_exists boolean := false;
  v_updated text[] := '{}';
  v_old_record jsonb;
  v_new_record jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT (
    public.can_by_member(v_caller_id, 'write_board') OR
    public.can_by_member(v_caller_id, 'manage_event') OR
    public.can_by_member(v_caller_id, 'manage_member')
  ) THEN
    RAISE EXCEPTION 'Unauthorized: requires comms/board/admin authority';
  END IF;

  SELECT
    jsonb_build_object(
      'briefing_doc_url', briefing_doc_url,
      'sympla_event_url', sympla_event_url,
      'promo_kit_url', promo_kit_url,
      'comms_kickoff_at', comms_kickoff_at
    ),
    true
  INTO v_old_record, v_webinar_exists
  FROM public.webinars WHERE id = p_webinar_id;

  IF NOT v_webinar_exists THEN
    RAISE EXCEPTION 'Webinar not found: %', p_webinar_id;
  END IF;

  IF p_briefing_doc_url IS NOT NULL THEN
    UPDATE public.webinars SET briefing_doc_url = p_briefing_doc_url, updated_at = now() WHERE id = p_webinar_id;
    v_updated := array_append(v_updated, 'briefing_doc_url');
  END IF;
  IF p_sympla_event_url IS NOT NULL THEN
    UPDATE public.webinars SET sympla_event_url = p_sympla_event_url, updated_at = now() WHERE id = p_webinar_id;
    v_updated := array_append(v_updated, 'sympla_event_url');
  END IF;
  IF p_promo_kit_url IS NOT NULL THEN
    UPDATE public.webinars SET promo_kit_url = p_promo_kit_url, updated_at = now() WHERE id = p_webinar_id;
    v_updated := array_append(v_updated, 'promo_kit_url');
  END IF;
  IF p_mark_kickoff THEN
    UPDATE public.webinars SET comms_kickoff_at = now(), updated_at = now()
    WHERE id = p_webinar_id AND comms_kickoff_at IS NULL;
    IF FOUND THEN v_updated := array_append(v_updated, 'comms_kickoff_at'); END IF;
  END IF;

  IF array_length(v_updated, 1) IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'webinar_id', p_webinar_id,
      'message', 'no fields provided'
    );
  END IF;

  SELECT jsonb_build_object(
    'briefing_doc_url', briefing_doc_url,
    'sympla_event_url', sympla_event_url,
    'promo_kit_url', promo_kit_url,
    'comms_kickoff_at', comms_kickoff_at
  )
  INTO v_new_record
  FROM public.webinars WHERE id = p_webinar_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller_id,
    'update_webinar_comms_assets',
    'webinar',
    p_webinar_id,
    jsonb_build_object(
      'before', v_old_record,
      'after',  v_new_record,
      'updated_fields', to_jsonb(v_updated)
    ),
    jsonb_build_object('source', 'mcp', 'issue', '#131')
  );

  RETURN jsonb_build_object(
    'success', true,
    'webinar_id', p_webinar_id,
    'updated_fields', to_jsonb(v_updated)
  );
END; $function$;

GRANT EXECUTE ON FUNCTION public.update_webinar_comms_assets(uuid, text, text, text, boolean) TO authenticated;

COMMENT ON FUNCTION public.update_webinar_comms_assets(uuid, text, text, text, boolean) IS
  'Patches webinars promo asset URLs (briefing_doc / sympla / promo_kit / comms_kickoff_at). Spinoff #131 from #89 Frente 4. Audit log via admin_audit_log.';
