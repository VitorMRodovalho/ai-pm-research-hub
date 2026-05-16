-- p170 ATT-2 — Admin RPCs to list/link orphan interview events
--
-- Context: p169 backfill (20260673700000) linked 15/35 entrevista events to applications via
-- title regex `\(Nome\)`. 20 ficaram órfãs (parsing falhou — nomes parciais, prefixos diferentes).
-- ATT-2 entrega admin UI pra linkar manualmente.
--
-- Two RPCs:
--   • list_orphan_interview_events() — list events com type='entrevista' AND selection_application_id IS NULL
--   • link_interview_event(p_event_id, p_application_id) — admin link com audit log
--
-- Authority: manage_member OR manage_platform (Selection Committee leads + GP). Fail-closed.

-- ============================================================
-- RPC 1: list orphan interview events
-- ============================================================
CREATE OR REPLACE FUNCTION public.list_orphan_interview_events()
RETURNS TABLE(
  event_id          uuid,
  title             text,
  event_date        date,
  time_start        time,
  duration_minutes  int,
  calendar_event_id text,
  source            text,
  status            text,
  -- Suggested applications via fuzzy match on title (limit 3)
  suggested_applications jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  IF NOT (
    public.can_by_member(v_caller.id, 'manage_member'::text)
    OR public.can_by_member(v_caller.id, 'manage_platform'::text)
  ) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member or manage_platform';
  END IF;

  RETURN QUERY
  SELECT
    e.id AS event_id,
    e.title,
    e.date AS event_date,
    e.time_start,
    e.duration_minutes,
    e.calendar_event_id,
    e.source,
    e.status,
    -- Suggested apps: fuzzy match on applicant_name vs parenthetical content of title
    (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'application_id', sa.id,
        'applicant_name', sa.applicant_name,
        'email', sa.email,
        'chapter', sa.chapter,
        'status', sa.status,
        'cycle_code', sc.cycle_code,
        'similarity_score', similarity(LOWER(sa.applicant_name), LOWER(COALESCE(substring(e.title FROM '\(([^)]+)\)'), '')))
      ) ORDER BY similarity(LOWER(sa.applicant_name), LOWER(COALESCE(substring(e.title FROM '\(([^)]+)\)'), ''))) DESC), '[]'::jsonb)
      FROM public.selection_applications sa
      JOIN public.selection_cycles sc ON sc.id = sa.cycle_id
      WHERE e.title ~ '\([^)]+\)'
        AND similarity(LOWER(sa.applicant_name), LOWER(substring(e.title FROM '\(([^)]+)\)'))) > 0.3
      LIMIT 3
    ) AS suggested_applications
  FROM public.events e
  WHERE e.type = 'entrevista'
    AND e.selection_application_id IS NULL
  ORDER BY e.date DESC NULLS LAST, e.time_start DESC NULLS LAST;
END;
$function$;

COMMENT ON FUNCTION public.list_orphan_interview_events() IS
  'p170 ATT-2 — list events entrevista sem selection_application_id linked. Returns suggested_applications via pg_trgm similarity (threshold 0.3). Admin-only (manage_member OR manage_platform).';

GRANT EXECUTE ON FUNCTION public.list_orphan_interview_events() TO authenticated;

-- ============================================================
-- RPC 2: link orphan interview event to application
-- ============================================================
CREATE OR REPLACE FUNCTION public.link_interview_event(
  p_event_id uuid,
  p_application_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_event record;
  v_app record;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  IF NOT (
    public.can_by_member(v_caller.id, 'manage_member'::text)
    OR public.can_by_member(v_caller.id, 'manage_platform'::text)
  ) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member or manage_platform';
  END IF;

  SELECT * INTO v_event FROM public.events WHERE id = p_event_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Event not found: %', p_event_id;
  END IF;

  IF v_event.type <> 'entrevista' THEN
    RAISE EXCEPTION 'Event is not entrevista type (got %)', v_event.type;
  END IF;

  IF v_event.selection_application_id IS NOT NULL THEN
    RAISE EXCEPTION 'Event already linked to application: %', v_event.selection_application_id;
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Application not found: %', p_application_id;
  END IF;

  -- Perform the link
  UPDATE public.events
     SET selection_application_id = p_application_id,
         updated_at = now()
   WHERE id = p_event_id;

  -- Audit log
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller.id,
    'link_interview_event',
    'event',
    p_event_id,
    jsonb_build_object(
      'before', jsonb_build_object('selection_application_id', NULL),
      'after',  jsonb_build_object('selection_application_id', p_application_id)
    ),
    jsonb_build_object(
      'applicant_name', v_app.applicant_name,
      'event_title', v_event.title,
      'event_date', v_event.date,
      'method', 'manual_admin_link'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'event_id', p_event_id,
    'application_id', p_application_id,
    'applicant_name', v_app.applicant_name,
    'linked_by', v_caller.id,
    'linked_at', now()
  );
END;
$function$;

COMMENT ON FUNCTION public.link_interview_event(uuid, uuid) IS
  'p170 ATT-2 — admin manual link de events.selection_application_id. Audit em admin_audit_log. Falha se já linked. Admin-only (manage_member OR manage_platform).';

GRANT EXECUTE ON FUNCTION public.link_interview_event(uuid, uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
