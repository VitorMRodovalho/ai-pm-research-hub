-- ============================================================================
-- ADR-0011 V4 auth sweep — 5 legacy writers + link_webinar_event audience fix
--
-- Step 1 of pós-refactor cleanup. Motivado por:
--
--   1. Expanded `hasAuthGate` matcher em `rpc-v4-auth.test.mjs` (2026-04-17 p23)
--      agora captura `access_denied`, `auth_required`, `Admin only` nas RAISE
--      EXCEPTION — strings que os 5 writers V3 usavam e escapavam do matcher
--      anterior. Ajuste do matcher + LATEST-per-RPC tracking expõe eles.
--
--   2. Bug latente descoberto no smoke ADR-0015 Commit 1 (2026-04-17 p22):
--      `link_webinar_event` chamava `INSERT INTO events` com
--      `audience_level='general'`, violando a CHECK constraint que só aceita
--      `all|leadership|tribe|curators`. Qualquer call real ao RPC falharia.
--
-- RPCs refatorados (preservam signatures com DEFAULTs + retornos):
--   1. upsert_webinar             → can_by_member('manage_member') + organizer/co_manager bypass
--   2. link_webinar_event         → idem + audience_level derivation fix
--   3. admin_manage_publication   → can_by_member('write_board')
--   4. create_pilot               → can_by_member('manage_member')
--   5. update_pilot               → can_by_member('manage_member')
--
-- Auth mapping rationale:
--   - upsert_webinar + link_webinar_event: webinars historically admin-created
--     (GP); organizer/co_manager can edit their own. Mapped to `manage_member`
--     (admin-class gate) + legacy organizer/co_manager bypass preserved.
--   - admin_manage_publication: curators + admins manage public_publications.
--     `write_board` covers curator designation + manager/deputy_manager +
--     committee/study_group/workgroup leaders (via engagement_kind_permissions).
--   - create_pilot / update_pilot: pilots are strategic admin-only workspaces.
--     `manage_member` is the admin-class gate (same as event CRUD admin check).
--
-- audience_level fix (link_webinar_event):
--   Prior: `v_audience = 'general'` (always) — invalid enum value.
--   New: `CASE WHEN v_webinar.tribe_id IS NOT NULL THEN 'tribe' ELSE 'all' END`.
--   Preserves semantic intent (tribo webinars scoped to tribe, chapter-wide
--   webinars to 'all') and passes the CHECK.
--
-- Signatures preserved verbatim (incl. DEFAULTs). CREATE OR REPLACE only.
-- ADR: ADR-0011 (primary), ADR-0015 (link_webinar_event audience fix)
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. upsert_webinar
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.upsert_webinar(
  p_id uuid DEFAULT NULL::uuid,
  p_title text DEFAULT NULL::text,
  p_description text DEFAULT NULL::text,
  p_scheduled_at timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_duration_min integer DEFAULT 60,
  p_status text DEFAULT 'planned'::text,
  p_chapter_code text DEFAULT 'ALL'::text,
  p_tribe_id integer DEFAULT NULL::integer,
  p_organizer_id uuid DEFAULT NULL::uuid,
  p_co_manager_ids uuid[] DEFAULT '{}'::uuid[],
  p_meeting_link text DEFAULT NULL::text,
  p_youtube_url text DEFAULT NULL::text,
  p_notes text DEFAULT NULL::text,
  p_board_item_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_member_id uuid;
  v_initiative_id uuid;
  v_existing webinars%ROWTYPE;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM public.members
  WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: not authenticated';
  END IF;

  IF p_tribe_id IS NOT NULL THEN
    SELECT id INTO v_initiative_id FROM public.initiatives
    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  END IF;

  IF p_id IS NOT NULL THEN
    SELECT * INTO v_existing FROM public.webinars WHERE id = p_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'webinar_not_found';
    END IF;

    -- UPDATE: admin-class OR webinar organizer/co_manager
    IF NOT (
      public.can_by_member(v_member_id, 'manage_member')
      OR v_member_id = v_existing.organizer_id
      OR v_member_id = ANY(v_existing.co_manager_ids)
    ) THEN
      RAISE EXCEPTION 'Unauthorized: requires manage_member or organizer role';
    END IF;

    UPDATE public.webinars SET
      title = COALESCE(p_title, title),
      description = COALESCE(p_description, description),
      scheduled_at = COALESCE(p_scheduled_at, scheduled_at),
      duration_min = COALESCE(p_duration_min, duration_min),
      status = COALESCE(p_status, status),
      chapter_code = COALESCE(p_chapter_code, chapter_code),
      tribe_id = p_tribe_id,
      initiative_id = v_initiative_id,
      organizer_id = COALESCE(p_organizer_id, organizer_id),
      co_manager_ids = COALESCE(p_co_manager_ids, co_manager_ids),
      meeting_link = p_meeting_link,
      youtube_url = p_youtube_url,
      notes = p_notes,
      board_item_id = p_board_item_id
    WHERE id = p_id;

    SELECT row_to_json(w)::jsonb INTO v_result FROM public.webinars w WHERE w.id = p_id;
  ELSE
    -- CREATE: admin-class only
    IF NOT public.can_by_member(v_member_id, 'manage_member') THEN
      RAISE EXCEPTION 'Unauthorized: admin role required for webinar creation';
    END IF;

    INSERT INTO public.webinars (title, description, scheduled_at, duration_min, status,
      chapter_code, tribe_id, initiative_id, organizer_id, co_manager_ids, meeting_link,
      youtube_url, notes, board_item_id)
    VALUES (p_title, p_description, p_scheduled_at, p_duration_min, p_status,
      p_chapter_code, p_tribe_id, v_initiative_id, COALESCE(p_organizer_id, v_member_id),
      p_co_manager_ids, p_meeting_link, p_youtube_url, p_notes, p_board_item_id)
    RETURNING row_to_json(webinars)::jsonb INTO v_result;
  END IF;

  RETURN v_result;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. link_webinar_event — V4 auth + audience_level fix
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.link_webinar_event(
  p_webinar_id uuid,
  p_event_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_member_id uuid;
  v_event_id uuid;
  v_webinar webinars%ROWTYPE;
  v_event_initiative_id uuid;
  v_audience text;
BEGIN
  SELECT id INTO v_member_id FROM public.members
  WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: not authenticated';
  END IF;

  SELECT * INTO v_webinar FROM public.webinars WHERE id = p_webinar_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'webinar_not_found'; END IF;

  IF NOT (
    public.can_by_member(v_member_id, 'manage_member')
    OR v_member_id = v_webinar.organizer_id
    OR v_member_id = ANY(v_webinar.co_manager_ids)
  ) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member or organizer role';
  END IF;

  IF p_event_id IS NOT NULL THEN
    v_event_id := p_event_id;
  ELSE
    v_event_initiative_id := v_webinar.initiative_id;
    IF v_event_initiative_id IS NULL AND v_webinar.tribe_id IS NOT NULL THEN
      SELECT id INTO v_event_initiative_id FROM public.initiatives
      WHERE legacy_tribe_id = v_webinar.tribe_id LIMIT 1;
    END IF;

    -- Bug fix (17/Abr p22 smoke finding): events_audience_level_check allows
    -- only 'all'/'leadership'/'tribe'/'curators'. Prior 'general' value
    -- violated the constraint — any real call to this RPC's non-pre-existing-
    -- event path would fail. Derive from tribe scope instead.
    v_audience := CASE WHEN v_webinar.tribe_id IS NOT NULL THEN 'tribe' ELSE 'all' END;

    INSERT INTO public.events (title, type, date, duration_minutes, tribe_id, initiative_id,
      meeting_link, youtube_url, audience_level, created_by, source)
    VALUES (
      v_webinar.title, 'webinar', v_webinar.scheduled_at::date,
      v_webinar.duration_min, v_webinar.tribe_id, v_event_initiative_id,
      v_webinar.meeting_link, v_webinar.youtube_url, v_audience, auth.uid(),
      'webinar_governance'
    )
    RETURNING id INTO v_event_id;
  END IF;

  UPDATE public.webinars SET event_id = v_event_id WHERE id = p_webinar_id;

  INSERT INTO public.webinar_lifecycle_events (webinar_id, action, actor_id, metadata)
  VALUES (p_webinar_id, 'event_linked', v_member_id,
    jsonb_build_object('event_id', v_event_id));

  RETURN jsonb_build_object('ok', true, 'event_id', v_event_id, 'webinar_id', p_webinar_id);
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. admin_manage_publication — V4 auth (write_board)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_manage_publication(
  p_action text,
  p_data jsonb
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_member_id uuid;
  v_id uuid;
  v_tribe_id int;
  v_initiative_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM public.members
  WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: not authenticated';
  END IF;

  -- write_board covers: volunteer/curator designation, manager, deputy_manager,
  -- comms_leader, committee/study_group/workgroup leaders — i.e., everyone who
  -- previously had (is_superadmin OR manager OR deputy_manager OR curator).
  IF NOT public.can_by_member(v_member_id, 'write_board') THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission';
  END IF;

  IF p_action = 'create' THEN
    v_tribe_id := (p_data->>'tribe_id')::int;
    IF v_tribe_id IS NOT NULL THEN
      SELECT id INTO v_initiative_id FROM public.initiatives
      WHERE legacy_tribe_id = v_tribe_id LIMIT 1;
    END IF;

    INSERT INTO public.public_publications (
      title, abstract, authors, author_member_ids, publication_date, publication_type,
      external_url, external_platform, doi, keywords,
      tribe_id, initiative_id, cycle_code,
      language, thumbnail_url, pdf_url, is_featured, is_published
    ) VALUES (
      p_data->>'title', p_data->>'abstract',
      ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_data->'authors','[]'::jsonb))),
      ARRAY(SELECT (jsonb_array_elements_text(COALESCE(p_data->'author_member_ids','[]'::jsonb)))::uuid),
      (p_data->>'publication_date')::date, COALESCE(p_data->>'publication_type','article'),
      p_data->>'external_url', p_data->>'external_platform', p_data->>'doi',
      ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_data->'keywords','[]'::jsonb))),
      v_tribe_id, v_initiative_id, p_data->>'cycle_code',
      COALESCE(p_data->>'language','pt-BR'), p_data->>'thumbnail_url', p_data->>'pdf_url',
      COALESCE((p_data->>'is_featured')::boolean, false),
      COALESCE((p_data->>'is_published')::boolean, false)
    ) RETURNING id INTO v_id;
    RETURN jsonb_build_object('ok', true, 'id', v_id);

  ELSIF p_action = 'update' THEN
    v_id := (p_data->>'id')::uuid;
    UPDATE public.public_publications SET
      title = COALESCE(p_data->>'title', title),
      abstract = COALESCE(p_data->>'abstract', abstract),
      external_url = COALESCE(p_data->>'external_url', external_url),
      external_platform = COALESCE(p_data->>'external_platform', external_platform),
      doi = COALESCE(p_data->>'doi', doi),
      thumbnail_url = COALESCE(p_data->>'thumbnail_url', thumbnail_url),
      pdf_url = COALESCE(p_data->>'pdf_url', pdf_url),
      is_featured = COALESCE((p_data->>'is_featured')::boolean, is_featured),
      publication_date = COALESCE((p_data->>'publication_date')::date, publication_date),
      updated_at = now()
    WHERE id = v_id;
    RETURN jsonb_build_object('ok', true, 'id', v_id);

  ELSIF p_action = 'publish' THEN
    v_id := (p_data->>'id')::uuid;
    UPDATE public.public_publications SET is_published = true, updated_at = now() WHERE id = v_id;
    RETURN jsonb_build_object('ok', true, 'action', 'published');

  ELSIF p_action = 'unpublish' THEN
    v_id := (p_data->>'id')::uuid;
    UPDATE public.public_publications SET is_published = false, updated_at = now() WHERE id = v_id;
    RETURN jsonb_build_object('ok', true, 'action', 'unpublished');

  ELSIF p_action = 'delete' THEN
    v_id := (p_data->>'id')::uuid;
    DELETE FROM public.public_publications WHERE id = v_id;
    RETURN jsonb_build_object('ok', true, 'action', 'deleted');

  ELSE
    RAISE EXCEPTION 'invalid_action';
  END IF;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. create_pilot — V4 auth (manage_member)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.create_pilot(
  p_title text,
  p_hypothesis text DEFAULT NULL::text,
  p_problem_statement text DEFAULT NULL::text,
  p_scope text DEFAULT NULL::text,
  p_status text DEFAULT 'draft'::text,
  p_tribe_id integer DEFAULT NULL::integer,
  p_board_id uuid DEFAULT NULL::uuid,
  p_success_metrics jsonb DEFAULT '[]'::jsonb,
  p_team_member_ids uuid[] DEFAULT '{}'::uuid[]
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_caller_id uuid;
  v_next_number integer;
  v_new_id uuid;
  v_initiative_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members
  WHERE auth_id = auth.uid() LIMIT 1;
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: not authenticated';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member permission';
  END IF;

  SELECT COALESCE(MAX(pilot_number), 0) + 1 INTO v_next_number FROM public.pilots;

  IF p_tribe_id IS NOT NULL THEN
    SELECT id INTO v_initiative_id FROM public.initiatives
    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  END IF;

  INSERT INTO public.pilots (
    pilot_number, title, hypothesis, problem_statement, scope, status,
    tribe_id, initiative_id,
    board_id, success_metrics, team_member_ids, created_by, started_at
  )
  VALUES (
    v_next_number, p_title, p_hypothesis, p_problem_statement, p_scope, p_status,
    p_tribe_id, v_initiative_id,
    p_board_id, p_success_metrics, p_team_member_ids, v_caller_id,
    CASE WHEN p_status = 'active' THEN CURRENT_DATE ELSE NULL END
  )
  RETURNING id INTO v_new_id;

  RETURN jsonb_build_object('success', true, 'id', v_new_id, 'pilot_number', v_next_number);
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. update_pilot — V4 auth (manage_member)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.update_pilot(
  p_id uuid,
  p_title text DEFAULT NULL::text,
  p_hypothesis text DEFAULT NULL::text,
  p_problem_statement text DEFAULT NULL::text,
  p_scope text DEFAULT NULL::text,
  p_status text DEFAULT NULL::text,
  p_tribe_id integer DEFAULT NULL::integer,
  p_board_id uuid DEFAULT NULL::uuid,
  p_success_metrics jsonb DEFAULT NULL::jsonb,
  p_team_member_ids uuid[] DEFAULT NULL::uuid[],
  p_lessons_learned jsonb DEFAULT NULL::jsonb,
  p_started_at date DEFAULT NULL::date,
  p_completed_at date DEFAULT NULL::date
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_caller_id uuid;
  v_initiative_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members
  WHERE auth_id = auth.uid() LIMIT 1;
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: not authenticated';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member permission';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.pilots WHERE id = p_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Pilot not found');
  END IF;

  IF p_tribe_id IS NOT NULL THEN
    SELECT id INTO v_initiative_id FROM public.initiatives
    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  END IF;

  UPDATE public.pilots SET
    title = COALESCE(p_title, title),
    hypothesis = COALESCE(p_hypothesis, hypothesis),
    problem_statement = COALESCE(p_problem_statement, problem_statement),
    scope = COALESCE(p_scope, scope),
    status = COALESCE(p_status, status),
    tribe_id = COALESCE(p_tribe_id, tribe_id),
    initiative_id = CASE WHEN p_tribe_id IS NOT NULL THEN v_initiative_id ELSE initiative_id END,
    board_id = COALESCE(p_board_id, board_id),
    success_metrics = COALESCE(p_success_metrics, success_metrics),
    team_member_ids = COALESCE(p_team_member_ids, team_member_ids),
    lessons_learned = COALESCE(p_lessons_learned, lessons_learned),
    started_at = CASE
      WHEN p_started_at IS NOT NULL THEN p_started_at
      WHEN COALESCE(p_status, status) = 'active' AND started_at IS NULL THEN CURRENT_DATE
      ELSE started_at
    END,
    completed_at = CASE
      WHEN p_completed_at IS NOT NULL THEN p_completed_at
      WHEN COALESCE(p_status, status) IN ('completed', 'cancelled') AND completed_at IS NULL THEN CURRENT_DATE
      ELSE completed_at
    END,
    updated_at = now()
  WHERE id = p_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- Reload PostgREST cache so fresh signatures are served immediately
NOTIFY pgrst, 'reload schema';
