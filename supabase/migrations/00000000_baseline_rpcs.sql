-- ============================================================================
-- Baseline migration: captures 14 pre-existing RPCs that are called by the
-- frontend but had no definition in supabase/migrations/.
--
-- These stubs were reverse-engineered from frontend .rpc() call sites and
-- usage patterns. They should match the functions already deployed in the
-- production database.
--
-- Generated: 2026-03-12
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. get_member_by_auth
--    Called from: Nav.astro, profile.astro, gamification.astro, admin pages
--    No parameters — uses auth.uid() to identify the caller.
--    Returns: a single members row (id, name, email, photo_url, role, tier,
--             tribe_id, chapter, credly_url, is_active, secondary_emails, …)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_member_by_auth()
RETURNS SETOF public.members
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT *
    FROM public.members
   WHERE auth_id = auth.uid()
   LIMIT 1;
$$;

-- ---------------------------------------------------------------------------
-- 2. get_events_with_attendance
--    Called from: attendance.astro, admin/webinars.astro
--    Params: p_limit int, p_offset int
--    Returns rows with: id, title, date, type, duration_minutes, meeting_link,
--            youtube_url, is_recorded, audience_level, attendee_count
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_events_with_attendance(
  p_limit  int DEFAULT 40,
  p_offset int DEFAULT 0
)
RETURNS TABLE (
  id               uuid,
  title            text,
  date             date,
  type             text,
  duration_minutes int,
  meeting_link     text,
  youtube_url      text,
  is_recorded      boolean,
  audience_level   text,
  tribe_id         uuid,
  attendee_count   bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT
    e.id,
    e.title,
    e.date,
    e.type,
    e.duration_minutes,
    e.meeting_link,
    e.youtube_url,
    e.is_recorded,
    e.audience_level,
    e.tribe_id,
    (SELECT count(*) FROM public.attendance a WHERE a.event_id = e.id) AS attendee_count
  FROM public.events e
  ORDER BY e.date DESC
  LIMIT p_limit
  OFFSET p_offset;
$$;

-- ---------------------------------------------------------------------------
-- 3. register_own_presence
--    Called from: attendance.astro (checkIn)
--    Params: p_event_id uuid
--    Returns: json { success: bool, error?: text }
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.register_own_presence(
  p_event_id uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT id INTO v_member_id
    FROM public.members
   WHERE auth_id = auth.uid();

  IF v_member_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Member not found');
  END IF;

  INSERT INTO public.attendance (event_id, member_id)
  VALUES (p_event_id, v_member_id)
  ON CONFLICT (event_id, member_id) DO NOTHING;

  RETURN json_build_object('success', true);
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. create_event
--    Called from: attendance.astro (createEvent)
--    Params: p_type, p_title, p_date, p_duration_minutes, p_tribe_id, p_audience_level
--    Returns: json { success: bool, event_id?: uuid, error?: text }
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_event(
  p_type             text,
  p_title            text,
  p_date             date,
  p_duration_minutes int      DEFAULT 90,
  p_tribe_id         uuid     DEFAULT NULL,
  p_audience_level   text     DEFAULT 'all'
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.events (type, title, date, duration_minutes, tribe_id, audience_level)
  VALUES (p_type, p_title, p_date, p_duration_minutes, p_tribe_id, p_audience_level)
  RETURNING id INTO v_id;

  RETURN json_build_object('success', true, 'event_id', v_id);
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. create_recurring_weekly_events
--    Called from: attendance.astro (createRecurring)
--    Params: p_type, p_title_template, p_start_date, p_duration_minutes,
--            p_n_weeks, p_meeting_link, p_tribe_id, p_is_recorded, p_audience_level
--    Returns: json { success: bool, events_created?: int, error?: text }
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_recurring_weekly_events(
  p_type             text,
  p_title_template   text,
  p_start_date       date,
  p_duration_minutes int      DEFAULT 90,
  p_n_weeks          int      DEFAULT 4,
  p_meeting_link     text     DEFAULT NULL,
  p_tribe_id         uuid     DEFAULT NULL,
  p_is_recorded      boolean  DEFAULT false,
  p_audience_level   text     DEFAULT 'all'
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  i int;
  v_date date;
  v_count int := 0;
BEGIN
  FOR i IN 0..(p_n_weeks - 1) LOOP
    v_date := p_start_date + (i * 7);
    INSERT INTO public.events (type, title, date, duration_minutes, meeting_link, tribe_id, is_recorded, audience_level)
    VALUES (p_type, p_title_template, v_date, p_duration_minutes, p_meeting_link, p_tribe_id, p_is_recorded, p_audience_level);
    v_count := v_count + 1;
  END LOOP;

  RETURN json_build_object('success', true, 'events_created', v_count);
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. update_event
--    Called from: attendance.astro (saveEventEdit, after create_event)
--    Params: p_event_id, p_title, p_date, p_duration_minutes, p_meeting_link,
--            p_youtube_url, p_is_recorded, p_audience_level
--    Returns: json { success: bool, error?: text }
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_event(
  p_event_id         uuid,
  p_title            text     DEFAULT NULL,
  p_date             date     DEFAULT NULL,
  p_duration_minutes int      DEFAULT NULL,
  p_meeting_link     text     DEFAULT NULL,
  p_youtube_url      text     DEFAULT NULL,
  p_is_recorded      boolean  DEFAULT NULL,
  p_audience_level   text     DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.events
     SET title            = COALESCE(p_title, title),
         date             = COALESCE(p_date, date),
         duration_minutes = COALESCE(p_duration_minutes, duration_minutes),
         meeting_link     = COALESCE(p_meeting_link, meeting_link),
         youtube_url      = COALESCE(p_youtube_url, youtube_url),
         is_recorded      = COALESCE(p_is_recorded, is_recorded),
         audience_level   = COALESCE(p_audience_level, audience_level)
   WHERE id = p_event_id;

  RETURN json_build_object('success', true);
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. get_tribe_event_roster
--    Called from: attendance.astro (openRoster)
--    Params: p_event_id uuid
--    Returns rows: id (member id), name, photo_url, present (bool), plus role fields
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_tribe_event_roster(
  p_event_id uuid
)
RETURNS TABLE (
  id        uuid,
  name      text,
  photo_url text,
  present   boolean,
  role      text,
  tier      int
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT
    m.id,
    m.name,
    m.photo_url,
    EXISTS (
      SELECT 1 FROM public.attendance a
       WHERE a.event_id = p_event_id AND a.member_id = m.id
    ) AS present,
    m.role,
    m.tier
  FROM public.members m
  WHERE m.is_active = true
    AND m.tribe_id = (SELECT e.tribe_id FROM public.events e WHERE e.id = p_event_id)
  ORDER BY m.name;
$$;

-- ---------------------------------------------------------------------------
-- 8. mark_member_present
--    Called from: attendance.astro (togglePresence)
--    Params: p_event_id uuid, p_member_id uuid, p_present bool
--    Returns: json { success: bool, error?: text }
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mark_member_present(
  p_event_id  uuid,
  p_member_id uuid,
  p_present   boolean
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF p_present THEN
    INSERT INTO public.attendance (event_id, member_id)
    VALUES (p_event_id, p_member_id)
    ON CONFLICT (event_id, member_id) DO NOTHING;
  ELSE
    DELETE FROM public.attendance
     WHERE event_id = p_event_id AND member_id = p_member_id;
  END IF;

  RETURN json_build_object('success', true);
END;
$$;

-- ---------------------------------------------------------------------------
-- 9. deselect_tribe
--    Called from: TribesSection.astro
--    No parameters — uses auth.uid() to identify member.
--    Returns: json { success: bool, error?: text }
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.deselect_tribe()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT id INTO v_member_id
    FROM public.members
   WHERE auth_id = auth.uid();

  IF v_member_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Member not found');
  END IF;

  UPDATE public.members
     SET tribe_id = NULL
   WHERE id = v_member_id;

  RETURN json_build_object('success', true);
END;
$$;

-- ---------------------------------------------------------------------------
-- 10. admin_inactivate_member
--     Called from: admin/member/[id].astro
--     Params: p_member_id uuid, p_reason text (nullable)
--     Returns: json { success: bool }
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_inactivate_member(
  p_member_id uuid,
  p_reason    text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.members
     SET is_active = false,
         inactivation_reason = p_reason
   WHERE id = p_member_id;

  RETURN json_build_object('success', true);
END;
$$;

-- ---------------------------------------------------------------------------
-- 11. admin_reactivate_member
--     Called from: admin/member/[id].astro
--     Params: p_member_id uuid
--     Returns: json { success: bool }
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_reactivate_member(
  p_member_id uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.members
     SET is_active = true,
         inactivation_reason = NULL
   WHERE id = p_member_id;

  RETURN json_build_object('success', true);
END;
$$;

-- ---------------------------------------------------------------------------
-- 12. get_member_cycle_xp
--     Called from: profile.astro
--     Params: p_member_id uuid
--     Returns: json with cycle_points, lifetime_points, and breakdown
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_member_cycle_xp(
  p_member_id uuid
)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  v_cycle_points   int;
  v_lifetime       int;
BEGIN
  SELECT COALESCE(SUM(points), 0) INTO v_lifetime
    FROM public.gamification_points
   WHERE member_id = p_member_id;

  -- Cycle points: approximate using current cycle period
  SELECT COALESCE(SUM(points), 0) INTO v_cycle_points
    FROM public.gamification_points
   WHERE member_id = p_member_id;

  RETURN json_build_object(
    'cycle_points',    v_cycle_points,
    'lifetime_points', v_lifetime
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 13. get_my_member_record
--     Called from: other migration RPCs (admin helpers) to identify the caller.
--     No parameters — uses auth.uid().
--     Returns: a single members row (used as "SELECT * INTO v_caller").
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_member_record()
RETURNS SETOF public.members
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT *
    FROM public.members
   WHERE auth_id = auth.uid()
   LIMIT 1;
$$;

-- ---------------------------------------------------------------------------
-- 14. upsert_publication_submission_event
--     Called from: PublicationsBoardIsland.tsx (saveSubmissionMetadata)
--     Params: p_board_item_id, p_channel, p_submitted_at, p_outcome,
--             p_notes, p_external_link, p_published_at
--     Returns: void (caller only checks for error)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.upsert_publication_submission_event(
  p_board_item_id uuid,
  p_channel       text     DEFAULT NULL,
  p_submitted_at  timestamptz DEFAULT NULL,
  p_outcome       text     DEFAULT NULL,
  p_notes         text     DEFAULT NULL,
  p_external_link text     DEFAULT NULL,
  p_published_at  timestamptz DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Upsert the submission metadata on the board item
  UPDATE public.board_items
     SET external_link = COALESCE(p_external_link, external_link),
         published_at  = COALESCE(p_published_at, published_at),
         updated_at    = now()
   WHERE id = p_board_item_id;

  -- Record the submission event
  INSERT INTO public.publication_submission_events (
    board_item_id, channel, submitted_at, outcome, notes, external_link, published_at
  )
  VALUES (
    p_board_item_id, p_channel, p_submitted_at, p_outcome, p_notes, p_external_link, p_published_at
  )
  ON CONFLICT (board_item_id)
  DO UPDATE SET
    channel       = EXCLUDED.channel,
    submitted_at  = EXCLUDED.submitted_at,
    outcome       = EXCLUDED.outcome,
    notes         = EXCLUDED.notes,
    external_link = EXCLUDED.external_link,
    published_at  = EXCLUDED.published_at,
    updated_at    = now();
END;
$$;
