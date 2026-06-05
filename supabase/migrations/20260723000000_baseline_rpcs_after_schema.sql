-- ============================================================================
-- Baseline RPCs (after-schema variant)
--
-- This file contains the 14 RPCs originally in `00000000_baseline_rpcs.sql`,
-- moved to a later timestamp so they run AFTER the schema migrations have
-- created the underlying tables (`members`, `events`, `attendance`,
-- `gamification_points`, `board_items`, `publication_submission_events`).
--
-- Why this exists (issue #164, p202 path C — 2026-05-19):
--   `supabase start` aborted at `00000000_baseline_rpcs.sql` with
--   `ERROR: type "public.members" does not exist (SQLSTATE 42704)` because
--   the timestamp 0 placed it before any schema migration. Production was
--   never affected (these are idempotent CREATE OR REPLACE FUNCTION calls;
--   they ran once at original apply, and the migration is recorded in
--   `supabase_migrations.schema_migrations`).
--
-- All bodies below WERE byte-identical to the original baseline at first
-- introduction (p202, 2026-05-19). Production impact = zero on reapply
-- (CREATE OR REPLACE is idempotent and the live RPCs already match). Local
-- stack impact = supabase start no longer fails on the baseline ordering,
-- provided the schema has been seeded first (see `docs/operations/LOCAL_QA.md`).
--
-- 00000000_baseline_rpcs.sql is retained as a marker file pointing to this
-- one — modifying it (rather than deleting) preserves the migration history
-- record without breaking idempotent reapply.
--
-- 2026-05-21 (issue #220 / BUG-203.A): functions 4 (create_event) and
-- 8 (mark_member_present) were REMOVED from this baseline because their
-- bare pre-W125 bodies (no auth gate) conflicted with the hardened bodies
-- defined in earlier-timestamp migrations (W125 + p149 + p174 + p178).
-- The static `security-lgpd` test takes the LAST CREATE OR REPLACE FUNCTION
-- block per name as canonical, and lex order placed this file last → 8
-- false-fail assertions on auth gates the live prod body has. See inline
-- comments below at slots 4 and 8 for full rationale.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. get_member_by_auth
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
-- 4. create_event — REMOVED from baseline 2026-05-21 (issue #220 / BUG-203.A)
-- ---------------------------------------------------------------------------
-- Original baseline body had NO auth gate (bare SECURITY DEFINER INSERT).
-- The hardened body lives in `20260319100029_w125_security_lgpd_hardening.sql`
-- and was further refined in `20260524000000_p149_*` and the canonical
-- `20260684000000_p178_phase_b_drift_capture_*` (14-param signature, full
-- `auth.uid()` + `can_by_member` + `Unauthorized` gates). Keeping the bare
-- body here caused `tests/contracts/security-lgpd.test.mjs` to take THIS
-- block as canonical (lex order LAST), generating 4 false-fail assertions on
-- auth checks that the live prod body actually has. Removal makes the test
-- pick up the p178 hardened body instead. Production state unaffected — this
-- migration is not in `supabase_migrations.schema_migrations` (local-stack
-- ordering fix only; verified 2026-05-21 via MCP). Local `supabase start`
-- still works because the W125 + p149 + p178 migrations CREATE OR REPLACE
-- this function at earlier timestamps with the hardened body.

-- ---------------------------------------------------------------------------
-- 5. create_recurring_weekly_events
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
-- 8. mark_member_present — REMOVED 2026-05-21 (issue #220 / BUG-203.A)
-- ---------------------------------------------------------------------------
-- Original baseline body had NO auth gate (bare INSERT/DELETE). The hardened
-- body lives in `20260319100029_w125_security_lgpd_hardening.sql` (W125) and
-- was refined in `20260514490000_item_10_*` and the canonical
-- `20260679000000_p174_qb_drift_correction_*` (full `auth.uid()` + caller
-- self-check `v_caller_id = p_member_id` + `can_by_member(_, 'manage_event')`
-- + `RAISE EXCEPTION 'Not authenticated'` / `'Unauthorized: ...'`). Same lex-
-- ordering conflict as create_event above caused 4 false-fail test assertions.
-- See create_event note for full context.

-- ---------------------------------------------------------------------------
-- 9. deselect_tribe
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
