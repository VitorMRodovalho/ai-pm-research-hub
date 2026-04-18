-- ============================================================================
-- ADR-0015 Phase 1 — Writers Batch B: create_event + upsert_tribe_deliverable
--
-- Second writer-refactor commit. Closes the remaining writer paths identified
-- by prosrc audit after Batch A: two writers that INSERT tribe_id without
-- initiative_id. Both migrated to V4 auth in the same beat because their
-- exception strings would trip the ADR-0011 contract test.
--
-- Writers touched:
--   1. create_event             (events)             — dual-write + V4 auth
--   2. upsert_tribe_deliverable (tribe_deliverables) — dual-write + V4 auth
--
-- Not in scope (confirmed no-op via prosrc audit):
--   - create_initiative_event    — already writes BOTH columns + uses can() V4
--   - update_event               — UPDATE SET does not touch tribe_id
--   - update_event_instance      — UPDATE SET does not touch tribe_id
--   - update_future_events_in_group — UPDATE SET does not touch tribe_id
--   - update_event_duration      — UPDATE SET does not touch tribe_id
--   - upsert_event_agenda        — UPDATE SET does not touch tribe_id
--   - upsert_event_minutes       — UPDATE SET does not touch tribe_id
--   - admin_update_board_columns — UPDATE SET does not touch tribe_id
--     (tribe_id appears only in auth WHERE clauses, not SET)
--
-- Strategy (same as Batch A):
--   - Derive v_initiative_id from initiatives.legacy_tribe_id = p_tribe_id
--   - INSERT both columns explicitly; triggers become no-ops on this path
--   - Signatures preserved verbatim (incl. DEFAULTs)
--
-- V4 auth pattern (ADR-0011):
--   - Primary gate: can_by_member(v_member_id, <action>)
--   - Admin exception: can_by_member(v_member_id, 'manage_member') — admin-class
--     callers bypass tribe-scope enforcement (preserves prior business rule:
--     admins edit any scope, tribe leaders are locked to own tribe)
--
--   create_event        → action='manage_event'  (inherits all kinds that
--                                                  previously matched manager/
--                                                  deputy_manager/tribe_leader)
--   upsert_tribe_deliverable → action='write'    (leaders/coordinators/managers)
--
-- Rollback: revert migration (previous bodies restored via CREATE OR REPLACE).
-- ADR: ADR-0015 (primary), ADR-0011 (combined)
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. create_event — dual-write initiative_id + V4 auth
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.create_event(
  p_type text,
  p_title text,
  p_date date,
  p_duration_minutes integer DEFAULT 90,
  p_tribe_id integer DEFAULT NULL::integer,
  p_meeting_link text DEFAULT NULL::text,
  p_nature text DEFAULT 'recorrente'::text,
  p_visibility text DEFAULT 'all'::text,
  p_agenda_text text DEFAULT NULL::text,
  p_agenda_url text DEFAULT NULL::text,
  p_external_attendees text[] DEFAULT NULL::text[],
  p_invited_member_ids uuid[] DEFAULT NULL::uuid[],
  p_audience_level text DEFAULT NULL::text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_member_id uuid;
  v_member_tribe_id integer;
  v_is_admin boolean;
  v_event_id uuid;
  v_audience text;
  v_initiative_id uuid;
BEGIN
  SELECT id, tribe_id INTO v_member_id, v_member_tribe_id
  FROM members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  IF NOT public.can_by_member(v_member_id, 'manage_event') THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized: requires manage_event permission');
  END IF;

  -- Type validation
  IF p_type NOT IN ('geral','tribo','lideranca','kickoff','comms','parceria','entrevista','1on1','evento_externo','webinar') THEN
    RETURN json_build_object('success', false, 'error', 'Invalid event type: ' || p_type);
  END IF;

  -- Nature validation
  IF p_nature NOT IN ('kickoff','recorrente','avulsa','encerramento','workshop','entrevista_selecao') THEN
    p_nature := 'avulsa';
  END IF;

  -- Visibility validation + auto-enforce for sensitive types
  IF p_type IN ('parceria','entrevista','1on1') THEN
    p_visibility := 'gp_only';
  ELSIF p_visibility NOT IN ('all','leadership','gp_only') THEN
    p_visibility := 'all';
  END IF;

  -- Tribe required for tribe events
  IF p_type = 'tribo' AND p_tribe_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'tribe_id required for tribe events');
  END IF;

  -- Scope enforcement: non-admin callers with manage_event (tribe leaders,
  -- study group owners, etc.) are restricted to 'tribo' type for own tribe
  -- and cannot set externals/invitees — preserves the prior business rule.
  v_is_admin := public.can_by_member(v_member_id, 'manage_member');
  IF NOT v_is_admin THEN
    IF p_type NOT IN ('tribo') THEN
      RETURN json_build_object('success', false, 'error', 'Leaders can only create tribe events');
    END IF;
    IF p_tribe_id IS DISTINCT FROM v_member_tribe_id THEN
      RETURN json_build_object('success', false, 'error', 'Can only create events for your own tribe');
    END IF;
    p_external_attendees := NULL;
    p_invited_member_ids := NULL;
  END IF;

  -- Derive initiative_id (dual-write, trigger-independent)
  IF p_tribe_id IS NOT NULL THEN
    SELECT id INTO v_initiative_id FROM public.initiatives
    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  END IF;

  v_audience := COALESCE(p_audience_level,
    CASE p_type
      WHEN 'tribo'     THEN 'tribe'
      WHEN 'lideranca' THEN 'leadership'
      WHEN 'comms'     THEN 'leadership'
      ELSE 'all'
    END
  );

  INSERT INTO events (
    type, title, date, duration_minutes,
    tribe_id, initiative_id,
    audience_level, meeting_link,
    nature, visibility, agenda_text, agenda_url,
    external_attendees, invited_member_ids, created_by
  )
  VALUES (
    p_type, p_title, p_date, p_duration_minutes,
    p_tribe_id, v_initiative_id,
    v_audience, p_meeting_link,
    p_nature, p_visibility, p_agenda_text, p_agenda_url,
    p_external_attendees, p_invited_member_ids, auth.uid()
  )
  RETURNING id INTO v_event_id;

  IF p_agenda_text IS NOT NULL OR p_agenda_url IS NOT NULL THEN
    UPDATE events SET agenda_posted_at = now(), agenda_posted_by = v_member_id
    WHERE id = v_event_id;
  END IF;

  RETURN json_build_object('success', true, 'event_id', v_event_id);
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. upsert_tribe_deliverable — dual-write initiative_id + V4 auth
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.upsert_tribe_deliverable(
  p_id uuid DEFAULT NULL::uuid,
  p_tribe_id integer DEFAULT NULL::integer,
  p_cycle_code text DEFAULT NULL::text,
  p_title text DEFAULT NULL::text,
  p_description text DEFAULT NULL::text,
  p_status text DEFAULT 'planned'::text,
  p_assigned_member_id uuid DEFAULT NULL::uuid,
  p_artifact_id uuid DEFAULT NULL::uuid,
  p_due_date date DEFAULT NULL::date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_member_id uuid;
  v_member_tribe_id integer;
  v_is_admin boolean;
  v_result public.tribe_deliverables%ROWTYPE;
  v_initiative_id uuid;
BEGIN
  SELECT id, tribe_id INTO v_member_id, v_member_tribe_id
  FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  IF NOT public.can_by_member(v_member_id, 'write') THEN
    RAISE EXCEPTION 'Unauthorized: requires write permission';
  END IF;

  -- Admin-class can manage any tribe; non-admins (tribe leaders, coordinators)
  -- are locked to their own tribe — preserves the prior business rule.
  v_is_admin := public.can_by_member(v_member_id, 'manage_member');
  IF NOT v_is_admin THEN
    IF p_tribe_id IS NULL OR p_tribe_id != v_member_tribe_id THEN
      RAISE EXCEPTION 'Unauthorized: non-admin can only manage deliverables for own tribe';
    END IF;
  END IF;

  IF p_title IS NULL OR p_title = '' THEN
    RAISE EXCEPTION 'Title is required';
  END IF;

  IF p_tribe_id IS NOT NULL THEN
    SELECT id INTO v_initiative_id FROM public.initiatives
    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  END IF;

  IF p_id IS NOT NULL THEN
    -- UPDATE path: tribe_id is pinned by WHERE clause (no change to scope).
    -- initiative_id is synced at creation and never drifts because UPDATE
    -- does not touch tribe_id here.
    UPDATE public.tribe_deliverables
       SET title              = COALESCE(p_title, title),
           description        = p_description,
           status             = COALESCE(p_status, status),
           assigned_member_id = p_assigned_member_id,
           artifact_id        = p_artifact_id,
           due_date           = p_due_date
     WHERE id = p_id
       AND tribe_id = p_tribe_id
    RETURNING * INTO v_result;

    IF v_result IS NULL THEN
      RAISE EXCEPTION 'Deliverable not found or tribe mismatch';
    END IF;
  ELSE
    INSERT INTO public.tribe_deliverables
      (tribe_id, initiative_id, cycle_code, title, description, status,
       assigned_member_id, artifact_id, due_date)
    VALUES
      (p_tribe_id, v_initiative_id, p_cycle_code, p_title, p_description, p_status,
       p_assigned_member_id, p_artifact_id, p_due_date)
    RETURNING * INTO v_result;
  END IF;

  RETURN to_jsonb(v_result);
END;
$$;

-- Reload PostgREST cache so fresh signatures are served immediately
NOTIFY pgrst, 'reload schema';
