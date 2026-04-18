-- ============================================================================
-- ADR-0015 Phase 1 — Writers Batch A: dual-write initiative_id
--
-- Refactors 8 writer RPCs + 1 trigger function so they explicitly write BOTH
-- tribe_id and initiative_id. Removes writer-path dependency on dual-write
-- triggers (sync_initiative_from_tribe / sync_tribe_from_initiative), which
-- is the gating prerequisite for ADR-0015 Phase 2 (trigger drop).
--
-- Writers touched:
--   1. upsert_webinar                   (webinars)
--   2. link_webinar_event               (events)
--   3. save_presentation_snapshot       (meeting_artifacts)     [+ ADR-0011 V4 auth]
--   4. create_publication_submission    (publication_submissions) [+ ADR-0011 V4 auth]
--   5. admin_manage_publication         (public_publications — create path)
--   6. auto_publish_approved_article    (public_publications — via board_items trigger)
--   7. create_pilot                     (pilots)
--   8. update_pilot                     (pilots)
--
-- Strategy:
--   - Derive v_initiative_id := (SELECT id FROM initiatives WHERE legacy_tribe_id = p_tribe_id)
--   - Write BOTH columns in the INSERT/UPDATE column list
--   - Triggers remain active for now but become no-ops on these paths
--     (they only fire when one side is NULL)
--
-- Combined ADR-0011 V4 auth on 2 RPCs (session wrap lesson #6 — when touching
-- an auth-gated RPC, migrate to V4 authority instead of leaving tech debt):
--   - save_presentation_snapshot: gate via can_by_member('manage_event'),
--     admin exception preserved via can_by_member('manage_member')
--   - create_publication_submission: gate via can_by_member('write_board')
--     (semantic tightening vs. "any active member"; publications are
--     board-originated so write_board is the correct scope)
--
-- Signatures preserved verbatim, including all DEFAULT expressions. CREATE OR
-- REPLACE is used everywhere — no identity-argument changes.
--
-- Out of scope:
--   - V4 auth for the remaining 5 writers (upsert_webinar, link_webinar_event,
--     admin_manage_publication, create_pilot, update_pilot). Their exception
--     strings ('access_denied', 'auth_required', 'Admin only') slip past the
--     ADR-0011 contract test matcher; they remain tech debt pending a dedicated
--     sweep.
--   - Signature changes.
--   - Frontend direct writes (covered in Commit 3 of writer refactor plan).
--
-- Invariant held: F_initiative_legacy_tribe_orphan (count = 0 at migration time).
-- If an invalid p_tribe_id is passed that has no matching initiative, v_initiative_id
-- stays NULL and the row is still inserted — matches prior behavior. No NOT NULL
-- constraint added in this beat.
--
-- Rollback: revert migration (previous bodies restored via CREATE OR REPLACE).
-- ADR: ADR-0015 (primary), ADR-0011 (combined)
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. upsert_webinar (webinars)
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
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_rec record;
  v_member_id uuid;
  v_initiative_id uuid;
  v_result jsonb;
BEGIN
  SELECT id, operational_role, is_superadmin INTO v_rec FROM get_my_member_record();
  IF v_rec IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  v_member_id := v_rec.id;

  IF p_tribe_id IS NOT NULL THEN
    SELECT id INTO v_initiative_id FROM public.initiatives
    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  END IF;

  IF p_id IS NOT NULL THEN
    IF NOT (
      v_rec.is_superadmin
      OR v_rec.operational_role IN ('manager', 'deputy_manager')
      OR v_member_id = (SELECT organizer_id FROM webinars WHERE id = p_id)
      OR v_member_id = ANY((SELECT co_manager_ids FROM webinars WHERE id = p_id))
    ) THEN
      RAISE EXCEPTION 'access_denied';
    END IF;

    UPDATE webinars SET
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

    SELECT row_to_json(w)::jsonb INTO v_result FROM webinars w WHERE w.id = p_id;
  ELSE
    IF NOT (v_rec.is_superadmin OR v_rec.operational_role IN ('manager', 'deputy_manager')) THEN
      RAISE EXCEPTION 'access_denied: admin required for creation';
    END IF;

    INSERT INTO webinars (title, description, scheduled_at, duration_min, status,
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
-- 2. link_webinar_event (events)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.link_webinar_event(
  p_webinar_id uuid,
  p_event_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_rec record;
  v_member_id uuid;
  v_event_id uuid;
  v_webinar webinars%ROWTYPE;
  v_event_initiative_id uuid;
BEGIN
  SELECT id, operational_role, is_superadmin INTO v_rec FROM get_my_member_record();
  IF v_rec IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  v_member_id := v_rec.id;

  SELECT * INTO v_webinar FROM webinars WHERE id = p_webinar_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'webinar_not_found'; END IF;

  IF NOT (
    v_rec.is_superadmin
    OR v_rec.operational_role IN ('manager', 'deputy_manager')
    OR v_member_id = v_webinar.organizer_id
    OR v_member_id = ANY(v_webinar.co_manager_ids)
  ) THEN
    RAISE EXCEPTION 'access_denied';
  END IF;

  IF p_event_id IS NOT NULL THEN
    v_event_id := p_event_id;
  ELSE
    -- Prefer the webinar's already-synced initiative_id; fallback derives from
    -- tribe_id if for some reason the row predates the dual-write era.
    v_event_initiative_id := v_webinar.initiative_id;
    IF v_event_initiative_id IS NULL AND v_webinar.tribe_id IS NOT NULL THEN
      SELECT id INTO v_event_initiative_id FROM public.initiatives
      WHERE legacy_tribe_id = v_webinar.tribe_id LIMIT 1;
    END IF;

    INSERT INTO events (title, type, date, duration_minutes, tribe_id, initiative_id,
      meeting_link, youtube_url, audience_level, created_by, source)
    VALUES (
      v_webinar.title, 'webinar', v_webinar.scheduled_at::date,
      v_webinar.duration_min, v_webinar.tribe_id, v_event_initiative_id,
      v_webinar.meeting_link, v_webinar.youtube_url, 'general', auth.uid(),
      'webinar_governance'
    )
    RETURNING id INTO v_event_id;
  END IF;

  UPDATE webinars SET event_id = v_event_id WHERE id = p_webinar_id;

  INSERT INTO webinar_lifecycle_events (webinar_id, action, actor_id, metadata)
  VALUES (p_webinar_id, 'event_linked', v_member_id,
    jsonb_build_object('event_id', v_event_id));

  RETURN jsonb_build_object('ok', true, 'event_id', v_event_id, 'webinar_id', p_webinar_id);
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. save_presentation_snapshot (meeting_artifacts)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.save_presentation_snapshot(
  p_title text,
  p_meeting_date date,
  p_recording_url text DEFAULT NULL::text,
  p_agenda_items text[] DEFAULT '{}'::text[],
  p_snapshot jsonb DEFAULT '{}'::jsonb,
  p_event_id uuid DEFAULT NULL::uuid,
  p_tribe_id integer DEFAULT NULL::integer,
  p_deliberations text[] DEFAULT '{}'::text[],
  p_is_published boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_tribe_id integer;
  v_is_admin boolean;
  v_id uuid;
  v_initiative_id uuid;
BEGIN
  SELECT id, tribe_id INTO v_caller_id, v_caller_tribe_id
  FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Not authenticated';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event permission';
  END IF;

  -- Tribe scope: admin-class (manage_member) can save any scope;
  -- non-admin callers with manage_event (e.g., tribe leaders) are locked
  -- to their own tribe — preserves the prior business rule.
  v_is_admin := public.can_by_member(v_caller_id, 'manage_member');
  IF NOT v_is_admin THEN
    IF p_tribe_id IS NULL OR p_tribe_id != v_caller_tribe_id THEN
      RAISE EXCEPTION 'Leaders can only save snapshots for their own tribe';
    END IF;
  END IF;

  IF p_tribe_id IS NOT NULL THEN
    SELECT id INTO v_initiative_id FROM public.initiatives
    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  END IF;

  INSERT INTO public.meeting_artifacts
    (title, meeting_date, recording_url, agenda_items, page_data_snapshot,
     event_id, tribe_id, initiative_id, created_by, is_published, deliberations)
  VALUES
    (p_title, p_meeting_date, p_recording_url, p_agenda_items, p_snapshot,
     p_event_id, p_tribe_id, v_initiative_id, v_caller_id, p_is_published, p_deliberations)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. create_publication_submission (publication_submissions)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.create_publication_submission(
  p_title text,
  p_target_type submission_target_type,
  p_target_name text,
  p_primary_author_id uuid,
  p_tribe_id integer DEFAULT NULL::integer,
  p_board_item_id uuid DEFAULT NULL::uuid,
  p_abstract text DEFAULT NULL::text,
  p_target_url text DEFAULT NULL::text,
  p_estimated_cost_brl numeric DEFAULT 0
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_submission_id uuid;
  v_member_id uuid;
  v_initiative_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Not authenticated';
  END IF;

  SELECT id INTO v_member_id FROM public.members
  WHERE auth_id = auth.uid() AND is_active = true LIMIT 1;
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: not an active member';
  END IF;

  IF NOT public.can_by_member(v_member_id, 'write_board') THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission';
  END IF;

  IF p_tribe_id IS NOT NULL THEN
    SELECT id INTO v_initiative_id FROM public.initiatives
    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  END IF;

  INSERT INTO public.publication_submissions (
    title, target_type, target_name, primary_author_id,
    tribe_id, initiative_id,
    board_item_id, abstract, target_url, estimated_cost_brl, created_by
  )
  VALUES (
    p_title, p_target_type, p_target_name, p_primary_author_id,
    p_tribe_id, v_initiative_id,
    p_board_item_id, p_abstract, p_target_url, p_estimated_cost_brl, v_member_id
  )
  RETURNING id INTO v_submission_id;

  INSERT INTO public.publication_submission_authors (submission_id, member_id, author_order, is_corresponding)
  VALUES (v_submission_id, p_primary_author_id, 1, true);

  RETURN v_submission_id;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. admin_manage_publication (public_publications — create path)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_manage_publication(
  p_action text,
  p_data jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_member members%ROWTYPE;
  v_id uuid;
  v_tribe_id int;
  v_initiative_id uuid;
BEGIN
  SELECT * INTO v_member FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND OR NOT (
    v_member.is_superadmin
    OR v_member.operational_role IN ('manager','deputy_manager')
    OR v_member.designations && ARRAY['curator']
  ) THEN
    RAISE EXCEPTION 'access_denied';
  END IF;

  IF p_action = 'create' THEN
    v_tribe_id := (p_data->>'tribe_id')::int;
    IF v_tribe_id IS NOT NULL THEN
      SELECT id INTO v_initiative_id FROM public.initiatives
      WHERE legacy_tribe_id = v_tribe_id LIMIT 1;
    END IF;

    INSERT INTO public_publications (
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
    UPDATE public_publications SET
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
    UPDATE public_publications SET is_published = true, updated_at = now() WHERE id = v_id;
    RETURN jsonb_build_object('ok', true, 'action', 'published');

  ELSIF p_action = 'unpublish' THEN
    v_id := (p_data->>'id')::uuid;
    UPDATE public_publications SET is_published = false, updated_at = now() WHERE id = v_id;
    RETURN jsonb_build_object('ok', true, 'action', 'unpublished');

  ELSIF p_action = 'delete' THEN
    v_id := (p_data->>'id')::uuid;
    DELETE FROM public_publications WHERE id = v_id;
    RETURN jsonb_build_object('ok', true, 'action', 'deleted');

  ELSE
    RAISE EXCEPTION 'invalid_action';
  END IF;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. auto_publish_approved_article (public_publications — via board_items trigger)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.auto_publish_approved_article()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_authors text[];
  v_author_ids uuid[];
  v_tribe_id int;
  v_initiative_id uuid;
BEGIN
  -- Only fire when curation_status changes to 'approved'
  IF NEW.curation_status = 'approved'
    AND (OLD.curation_status IS DISTINCT FROM 'approved') THEN

    SELECT array_agg(m.name), array_agg(m.id)
    INTO v_authors, v_author_ids
    FROM board_item_assignments bia
    JOIN members m ON m.id = bia.member_id
    WHERE bia.item_id = NEW.id AND bia.role IN ('author','contributor');

    SELECT pb.tribe_id, pb.initiative_id
      INTO v_tribe_id, v_initiative_id
    FROM project_boards pb WHERE pb.id = NEW.board_id;

    INSERT INTO public_publications (
      title, abstract, authors, author_member_ids, publication_type,
      tribe_id, initiative_id, cycle_code, board_item_id, is_published
    ) VALUES (
      NEW.title,
      NEW.description,
      COALESCE(v_authors, ARRAY[NEW.title]),
      v_author_ids,
      'article',
      v_tribe_id,
      v_initiative_id,
      'cycle3-2026',
      NEW.id,
      false  -- GP/curator publishes manually after final review
    ) ON CONFLICT DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 7. create_pilot (pilots)
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
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_id uuid;
  v_next_number integer;
  v_new_id uuid;
  v_initiative_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM members
    WHERE auth_id = auth.uid()
      AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager'));
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Admin only'; END IF;

  SELECT COALESCE(MAX(pilot_number), 0) + 1 INTO v_next_number FROM pilots;

  IF p_tribe_id IS NOT NULL THEN
    SELECT id INTO v_initiative_id FROM public.initiatives
    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  END IF;

  INSERT INTO pilots (
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
-- 8. update_pilot (pilots)
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
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_id uuid;
  v_initiative_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM members
    WHERE auth_id = auth.uid()
      AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager'));
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Admin only'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pilots WHERE id = p_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Pilot not found');
  END IF;

  IF p_tribe_id IS NOT NULL THEN
    SELECT id INTO v_initiative_id FROM public.initiatives
    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  END IF;

  UPDATE pilots SET
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
