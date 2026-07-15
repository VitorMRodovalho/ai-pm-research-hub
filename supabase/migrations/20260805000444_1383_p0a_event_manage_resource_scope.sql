-- Scope event-management authority to the event's own initiative.
--
-- V4 authority (can() / can_by_member) grants organization/global scope
-- unconditionally and initiative scope for a matching initiative_id. Four event and
-- attendance write paths checked manage_event without passing the event's
-- initiative_id, so their authority check was not scoped to the event's initiative:
--   _can_manage_event, meeting_close, register_attendance_batch, mark_member_excused.
-- This migration routes all four through one shared helper,
-- _manage_event_scope_ok(caller, event), which passes the event's concrete
-- initiative_id. (Sibling bulk_mark_excused already scopes correctly.)
--
-- Org/global holders still pass (can() grants org scope unconditionally). Org-wide
-- events (no initiative_id) preserve prior behavior deliberately; tightening those is
-- a separate #1383 follow-up. p_resource_type is passed as 'initiative' (rationale in
-- the helper body).
--
-- Function bodies are the live definitions with only the authority line changed, so
-- the drift-gate captures them byte-for-byte (GC-097 / #965). Applied via
-- apply_migration, then registered + NOTIFY per Track Q-C.

-- ---------------------------------------------------------------------------
-- Shared helper: may the caller manage this specific event under V4 scoping?
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._manage_event_scope_ok(p_caller_id uuid, p_event_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_init uuid;
BEGIN
  SELECT initiative_id INTO v_init FROM public.events WHERE id = p_event_id;
  IF NOT FOUND THEN RETURN false; END IF;

  IF v_init IS NOT NULL THEN
    -- Initiative-linked event: org/global scope passes (can() grants it
    -- unconditionally); initiative-scoped grants pass ONLY for THIS initiative.
    -- Passing the concrete initiative_id defeats the resourceless NULL fallback.
    -- p_resource_type MUST be 'initiative' (not NULL): can() has a legacy branch
    --   OR (p_resource_type = 'tribe' AND ae.legacy_tribe_id = (p_resource_id::text)::integer)
    -- With a NULL resource_type, `NULL = 'tribe'` is NULL, so Postgres cannot
    -- short-circuit and evaluates `(p_resource_id::text)::integer` — which throws
    -- `invalid input syntax for type integer` for an initiative UUID on the
    -- cross-initiative path (the exact deny case this helper must return false for).
    -- A non-'tribe' resource_type makes that branch cleanly false; the UUID equality
    -- `ae.initiative_id = p_resource_id` still drives the initiative match.
    RETURN public.can_by_member(p_caller_id, 'manage_event', 'initiative', v_init);
  END IF;

  -- Org-wide event (no initiative_id, e.g. 'geral'/'kickoff'): preserve prior
  -- behavior — any manage_event holder. Tightening org-wide events to org/global
  -- scope only is a separate policy decision (#1383 follow-up), not the confirmed
  -- cross-initiative bypass this migration closes.
  RETURN public.can_by_member(p_caller_id, 'manage_event');
END;
$function$;

REVOKE EXECUTE ON FUNCTION public._manage_event_scope_ok(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._manage_event_scope_ok(uuid, uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- _can_manage_event: event lookup moved above the catalog check; resourceless
-- can_by_member replaced by the resource-scoped helper. Path Y unchanged.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._can_manage_event(p_event_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_event record;
  v_event_tribe_id int;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN false; END IF;

  SELECT * INTO v_event FROM public.events WHERE id = p_event_id;
  IF NOT FOUND THEN RETURN false; END IF;

  -- ADR-0042 + #1383: V4 catalog source-of-truth, now resource-scoped to the
  -- event's initiative (was a resourceless can_by_member(manage_event) that let any
  -- initiative-scoped leader manage events of any other initiative).
  IF public._manage_event_scope_ok(v_caller.id, p_event_id) THEN RETURN true; END IF;

  -- Path Y: tribe-scoped management (tribe_leader / researcher own-tribe events)
  -- and event-creator self-management — preserved from V3 body.
  v_event_tribe_id := public.resolve_tribe_id(v_event.initiative_id);

  IF v_caller.operational_role = 'tribe_leader' AND v_event_tribe_id = v_caller.tribe_id THEN RETURN true; END IF;
  IF v_caller.operational_role = 'researcher'   AND v_event_tribe_id = v_caller.tribe_id THEN RETURN true; END IF;
  IF v_event.created_by = v_caller.id THEN RETURN true; END IF;
  RETURN false;
END;
$function$;

-- ---------------------------------------------------------------------------
-- meeting_close: resourceless gate replaced by the resource-scoped helper.
-- Rest of the body is the live definition, unchanged.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.meeting_close(p_event_id uuid, p_summary text DEFAULT NULL::text, p_suggested_champion_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_org uuid;
  v_event record;
  v_already_closed boolean;
  v_action_count int;
  v_decision_count int;
  v_unresolved_count int;
  v_markdown_action_count int;
  v_structured_drift int;
  v_links_total int;
  v_showcase_count int;
  v_validated_suggestions uuid[];
  v_invalid_suggestions uuid[];
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id, organization_id INTO v_caller_id, v_caller_org
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  -- #1383: scope manage_event to this event's initiative (was resourceless).
  IF NOT public._manage_event_scope_ok(v_caller_id, p_event_id) THEN
    RAISE EXCEPTION 'Requires manage_event permission for this event';
  END IF;

  SELECT id, title, date, minutes_text, minutes_posted_at
  INTO v_event FROM public.events WHERE id = p_event_id;
  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('error', 'event_not_found');
  END IF;

  v_already_closed := v_event.minutes_posted_at IS NOT NULL;

  IF p_suggested_champion_ids IS NOT NULL AND cardinality(p_suggested_champion_ids) > 0 THEN
    IF cardinality(p_suggested_champion_ids) > 10 THEN
      RETURN jsonb_build_object('error', 'too_many_suggestions', 'detail', 'max 10 suggested member ids per meeting_close');
    END IF;

    SELECT array_agg(DISTINCT s ORDER BY s) INTO v_validated_suggestions
    FROM unnest(p_suggested_champion_ids) AS s
    WHERE EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.id = s AND m.organization_id = v_caller_org
    );

    SELECT array_agg(DISTINCT s) INTO v_invalid_suggestions
    FROM unnest(p_suggested_champion_ids) AS s
    WHERE NOT EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.id = s AND m.organization_id = v_caller_org
    );

    IF v_invalid_suggestions IS NOT NULL AND cardinality(v_invalid_suggestions) > 0 THEN
      RETURN jsonb_build_object(
        'error', 'invalid_suggestions',
        'detail', 'unknown or out-of-org member ids: ' || array_to_string(v_invalid_suggestions, ', ')
      );
    END IF;
  END IF;

  SELECT
    COUNT(*) FILTER (WHERE kind = 'action'),
    COUNT(*) FILTER (WHERE kind = 'decision'),
    COUNT(*) FILTER (WHERE kind IN ('action','followup') AND resolved_at IS NULL)
  INTO v_action_count, v_decision_count, v_unresolved_count
  FROM public.meeting_action_items WHERE event_id = p_event_id;

  v_markdown_action_count := COALESCE(
    (SELECT array_length(regexp_split_to_array(v_event.minutes_text, E'(^|\\n)\\s*-\\s*\\[\\s*\\]'), 1) - 1),
    0
  );
  v_markdown_action_count := GREATEST(0, v_markdown_action_count);
  v_structured_drift := GREATEST(0, v_markdown_action_count - v_action_count);

  SELECT COUNT(*) INTO v_links_total
  FROM public.board_item_event_links WHERE event_id = p_event_id;

  SELECT COUNT(*) INTO v_showcase_count
  FROM public.event_showcases WHERE event_id = p_event_id;

  IF NOT v_already_closed THEN
    UPDATE public.events
    SET minutes_posted_at = now(),
        minutes_posted_by = v_caller_id,
        notes = CASE
          WHEN p_summary IS NOT NULL AND length(trim(p_summary)) > 0
            THEN COALESCE(notes, '') ||
                 CASE WHEN COALESCE(notes, '') <> '' THEN E'\n\n' ELSE '' END ||
                 '## Meeting close summary (' || to_char(now(), 'YYYY-MM-DD HH24:MI') || ')' ||
                 E'\n' || trim(p_summary)
          ELSE notes
        END,
        suggested_champion_ids = COALESCE(v_validated_suggestions, suggested_champion_ids),
        updated_at = now()
    WHERE id = p_event_id;
  ELSE
    IF v_validated_suggestions IS NOT NULL THEN
      UPDATE public.events
      SET suggested_champion_ids = v_validated_suggestions,
          updated_at = now()
      WHERE id = p_event_id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'event_id', p_event_id,
    'event_title', v_event.title,
    'already_closed', v_already_closed,
    'closed_at', CASE WHEN v_already_closed THEN v_event.minutes_posted_at ELSE now() END,
    'action_count', v_action_count,
    'decision_count', v_decision_count,
    'unresolved_actions', v_unresolved_count,
    'markdown_action_count', v_markdown_action_count,
    'structured_drift', v_structured_drift,
    'links_total', v_links_total,
    'showcase_count', v_showcase_count,
    'drift_signal', v_structured_drift > 0,
    'summary_appended', p_summary IS NOT NULL AND length(trim(p_summary)) > 0 AND NOT v_already_closed,
    'suggestions_count', COALESCE(cardinality(v_validated_suggestions), 0),
    'suggestions_stored', v_validated_suggestions
  );
END;
$function$;

-- ---------------------------------------------------------------------------
-- register_attendance_batch: resourceless gate replaced by resource-scoped helper.
-- search_path is '' in the live body, so every reference stays public-qualified.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.register_attendance_batch(p_event_id uuid, p_member_ids uuid[], p_registered_by uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  inserted integer;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- #1383: scope manage_event to this event's initiative (was resourceless).
  IF NOT public._manage_event_scope_ok(v_caller_id, p_event_id) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event for this event';
  END IF;

  INSERT INTO public.attendance (event_id, member_id, present, registered_by)
  SELECT p_event_id, unnest(p_member_ids), true, v_caller_id
  ON CONFLICT (event_id, member_id)
  DO UPDATE SET present = true, registered_by = v_caller_id, updated_at = now();
  GET DIAGNOSTICS inserted = ROW_COUNT;
  RETURN inserted;
END;
$function$;

-- ---------------------------------------------------------------------------
-- mark_member_excused: resourceless gate replaced by resource-scoped helper
-- (scopes by the event's initiative, consistent with register_attendance_batch;
-- bulk_mark_excused scopes by target member because it has no single event).
-- search_path is '' in the live body — keep everything public-qualified.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mark_member_excused(p_event_id uuid, p_member_id uuid, p_excused boolean DEFAULT true, p_reason text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  -- #1383: scope manage_event to this event's initiative (was resourceless).
  IF NOT public._manage_event_scope_ok(v_caller_id, p_event_id) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event permission for this event';
  END IF;

  IF p_excused THEN
    INSERT INTO public.attendance (event_id, member_id, present, excused, excuse_reason)
    VALUES (p_event_id, p_member_id, false, true, p_reason)
    ON CONFLICT (event_id, member_id) DO UPDATE SET
      present = false,
      excused = true,
      excuse_reason = p_reason,
      updated_at = now();
  ELSE
    UPDATE public.attendance SET excused = false, excuse_reason = NULL, updated_at = now()
    WHERE event_id = p_event_id AND member_id = p_member_id;
  END IF;

  RETURN json_build_object('success', true, 'excused', p_excused);
END;
$function$;

NOTIFY pgrst, 'reload schema';
