-- =====================================================================================
-- #700 Agenda Viva [Foundation] — SLICE 2: reserve / read / update / cancel / reorder RPCs
--
-- Builds on slice 1 (tables event_agenda_blocks + agenda_block_formats + V4 action
-- reserve_agenda_block). All writes flow through these SECDEF RPCs (slice-1 RLS grants no
-- direct INSERT/UPDATE), so the 90-min capacity invariant is enforced under a row lock.
--
-- Scope of THIS slice:
--   1. reserve_agenda_block(...) — caller=auth.uid()→members (no p_member_id); gate
--      reserve_agenda_block; event ∈ next 2 upcoming `geral` + now<start; duration %5; capacity
--      ≤90 under SELECT ... FOR UPDATE on the event; one block/person (re-reserve reuses a
--      prior cancelled row); auto-publishes status='reserved'.
--   2. get_geral_agenda_viva(p_limit_events=2, p_member_id?) — anon-OK SECDEF. Next N upcoming
--      `geral` + their reserved/confirmed blocks + remaining capacity. Field visibility:
--      anon = owner FIRST name + title + format + duration (NO PII: no email/phone/member_id/
--      guest_name); authenticated adds is_mine + material_url; manage_event adds full detail
--      (owner_member_id, full name, guest_name, cancelled meta).
--   3. update_agenda_block / cancel_agenda_block — owner until the event starts; manage_event
--      anytime. Duration change re-checks capacity under the event lock.
--   4. reorder_event_blocks(p_event_id, p_ordered_ids[]) — manage_event.
--
-- NOT in scope: gamification pillar + XP crediting + confirm/revoke (slice 3); frontend.
--
-- LGPD: guest_name is third-party personal data — surfaced only to manage_event, never anon.
--   (Art. 18 erasure coverage for guest_name is tracked as a slice-2/3 follow-up gap.)
--
-- ROLLBACK:
--   DROP FUNCTION IF EXISTS public.reserve_agenda_block(uuid, text, text, integer, text, text, boolean);
--   DROP FUNCTION IF EXISTS public.get_geral_agenda_viva(integer, uuid);
--   DROP FUNCTION IF EXISTS public.update_agenda_block(uuid, text, text, integer, text, text, boolean);
--   DROP FUNCTION IF EXISTS public.cancel_agenda_block(uuid, text);
--   DROP FUNCTION IF EXISTS public.reorder_event_blocks(uuid, uuid[]);
-- =====================================================================================

-- ----------------------------------------------------------------------------
-- 1) reserve_agenda_block — self-service reservation with capacity lock.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reserve_agenda_block(
  p_event_id       uuid,
  p_format_slug    text,
  p_title          text,
  p_duration_min   integer,
  p_guest_name     text DEFAULT NULL,
  p_material_url   text DEFAULT NULL,
  p_external_guest boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_caller   uuid;
  v_event    record;
  v_rn       int;
  v_used     int;
  v_existing record;
  v_block_id uuid;
  v_sort     int;
BEGIN
  -- Caller resolves from the session; reservations are always self-scoped.
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller, 'reserve_agenda_block') THEN
    RETURN jsonb_build_object('error', 'access_denied', 'required', 'reserve_agenda_block');
  END IF;

  IF p_title IS NULL OR btrim(p_title) = '' THEN
    RETURN jsonb_build_object('error', 'title_required');
  END IF;
  IF p_duration_min IS NULL OR p_duration_min <= 0 OR p_duration_min % 5 <> 0 THEN
    RETURN jsonb_build_object('error', 'invalid_duration', 'detail', 'must be a positive multiple of 5');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.agenda_block_formats WHERE slug = p_format_slug AND active) THEN
    RETURN jsonb_build_object('error', 'invalid_format', 'received', p_format_slug);
  END IF;

  -- Lock the event row: serializes concurrent reservations for the capacity check.
  SELECT e.id, e.type, e.status, e.time_start,
         (e.date + COALESCE(e.time_start,'00:00'::time)) AT TIME ZONE COALESCE(e.timezone,'America/Sao_Paulo') AS start_at
    INTO v_event
    FROM public.events e
    WHERE e.id = p_event_id
    FOR UPDATE;
  IF v_event.id IS NULL OR v_event.type <> 'geral' OR v_event.status IS NOT DISTINCT FROM 'cancelled' THEN
    RETURN jsonb_build_object('error', 'event_not_reservable');
  END IF;
  -- Fail-close on unconfigured start time (the COALESCE-to-midnight fallback would silently
  -- close the window at 00:00 local on the event day); a geral event must have time_start set.
  IF v_event.time_start IS NULL THEN
    RETURN jsonb_build_object('error', 'event_not_reservable', 'detail', 'event time_start not configured');
  END IF;

  -- Must be one of the next 2 upcoming `geral` meetings (this also enforces now < start).
  SELECT rn INTO v_rn FROM (
    SELECT e.id,
           row_number() OVER (
             ORDER BY (e.date + COALESCE(e.time_start,'00:00'::time)) AT TIME ZONE COALESCE(e.timezone,'America/Sao_Paulo')
           ) AS rn
    FROM public.events e
    WHERE e.type = 'geral'
      AND e.status IS DISTINCT FROM 'cancelled'
      AND (e.date + COALESCE(e.time_start,'00:00'::time)) AT TIME ZONE COALESCE(e.timezone,'America/Sao_Paulo') > now()
  ) up WHERE up.id = p_event_id;
  IF v_rn IS NULL OR v_rn > 2 THEN
    RETURN jsonb_build_object('error', 'reservation_window_closed', 'detail', 'event is not among the next 2 open Reuniões Gerais');
  END IF;

  -- Capacity: reserved+confirmed must stay ≤ 90 min (the event is 90 min).
  SELECT COALESCE(SUM(duration_min), 0) INTO v_used
    FROM public.event_agenda_blocks
    WHERE event_id = p_event_id AND status IN ('reserved','confirmed');
  IF v_used + p_duration_min > 90 THEN
    RETURN jsonb_build_object('error', 'capacity_exceeded', 'used_min', v_used, 'requested_min', p_duration_min, 'cap_min', 90);
  END IF;

  -- One block per person per event. A prior cancelled row is reused (UNIQUE is unconditional).
  SELECT id, status INTO v_existing
    FROM public.event_agenda_blocks
    WHERE event_id = p_event_id AND owner_member_id = v_caller;
  -- Only a 'cancelled' row is reactivatable; reserved/confirmed/no_show all block a re-reserve.
  IF v_existing.id IS NOT NULL AND v_existing.status IN ('reserved','confirmed','no_show') THEN
    RETURN jsonb_build_object('error', 'already_reserved', 'block_id', v_existing.id, 'status', v_existing.status);
  END IF;

  SELECT COALESCE(MAX(sort_order), 0) + 1 INTO v_sort
    FROM public.event_agenda_blocks WHERE event_id = p_event_id;

  IF v_existing.id IS NOT NULL THEN
    -- Reactivate the cancelled row.
    UPDATE public.event_agenda_blocks
       SET format_slug = p_format_slug, title = p_title, duration_min = p_duration_min,
           guest_name = p_guest_name, material_url = p_material_url, external_guest = COALESCE(p_external_guest,false),
           status = 'reserved', reserved_at = now(), confirmed_at = NULL,
           cancelled_by = NULL, cancelled_reason = NULL, sort_order = v_sort, created_by = v_caller
     WHERE id = v_existing.id
     RETURNING id INTO v_block_id;
  ELSE
    INSERT INTO public.event_agenda_blocks (
      event_id, owner_member_id, format_slug, title, duration_min,
      guest_name, material_url, external_guest, sort_order, status, created_by
    ) VALUES (
      p_event_id, v_caller, p_format_slug, p_title, p_duration_min,
      p_guest_name, p_material_url, COALESCE(p_external_guest,false), v_sort, 'reserved', v_caller
    ) RETURNING id INTO v_block_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'block_id', v_block_id, 'event_id', p_event_id,
    'status', 'reserved', 'duration_min', p_duration_min,
    'capacity_used_min', v_used + p_duration_min, 'capacity_remaining_min', 90 - (v_used + p_duration_min)
  );
END
$function$;

-- ----------------------------------------------------------------------------
-- 2) get_geral_agenda_viva — anon-OK public agenda (no PII for anon).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_geral_agenda_viva(
  p_limit_events integer DEFAULT 2,
  p_member_id    uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_caller   uuid;
  v_is_admin boolean := false;
  v_limit    int := LEAST(GREATEST(COALESCE(p_limit_events, 2), 1), 6);
  v_result   jsonb;
BEGIN
  -- p_member_id is part of the spec signature, reserved for a future admin "view as member"
  -- mode (slice 3); the caller is always resolved from auth.uid() here (no impersonation yet).
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NOT NULL THEN
    v_is_admin := public.can_by_member(v_caller, 'manage_event');
  END IF;

  WITH upcoming AS (
    SELECT e.id, e.title, e.date, e.time_start, e.timezone,
           (e.date + COALESCE(e.time_start,'00:00'::time)) AT TIME ZONE COALESCE(e.timezone,'America/Sao_Paulo') AS start_at
    FROM public.events e
    WHERE e.type = 'geral'
      AND e.status IS DISTINCT FROM 'cancelled'
      AND (e.date + COALESCE(e.time_start,'00:00'::time)) AT TIME ZONE COALESCE(e.timezone,'America/Sao_Paulo') > now()
    ORDER BY start_at
    LIMIT v_limit
  ),
  blocks AS (
    SELECT b.event_id, b.id, b.format_slug, b.title, b.duration_min, b.status, b.sort_order,
           b.external_guest, b.owner_member_id, b.guest_name, b.material_url,
           split_part(m.name, ' ', 1) AS owner_first_name,
           m.name AS owner_full_name
    FROM public.event_agenda_blocks b
    JOIN public.members m ON m.id = b.owner_member_id
    WHERE b.event_id IN (SELECT id FROM upcoming)
      AND b.status IN ('reserved','confirmed')
  )
  SELECT jsonb_build_object(
    'viewer', jsonb_build_object('is_authenticated', v_caller IS NOT NULL, 'is_admin', v_is_admin),
    'events', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', u.id, 'title', u.title, 'date', u.date, 'time_start', u.time_start,
          'timezone', u.timezone, 'start_at', u.start_at,
          'capacity_total_min', 90,
          'capacity_used_min', COALESCE((SELECT SUM(duration_min) FROM blocks bk WHERE bk.event_id = u.id), 0),
          'capacity_remaining_min', 90 - COALESCE((SELECT SUM(duration_min) FROM blocks bk WHERE bk.event_id = u.id), 0),
          'blocks', COALESCE((
            SELECT jsonb_agg(
              jsonb_build_object(
                'id', bk.id, 'format_slug', bk.format_slug, 'title', bk.title,
                'duration_min', bk.duration_min, 'status', bk.status, 'sort_order', bk.sort_order,
                'external_guest', bk.external_guest,
                'owner_first_name', bk.owner_first_name,
                'is_mine', (v_caller IS NOT NULL AND bk.owner_member_id = v_caller)
              )
              -- authenticated (non-admin) additionally see the material link
              || CASE WHEN v_caller IS NOT NULL
                      THEN jsonb_build_object('material_url', bk.material_url)
                      ELSE '{}'::jsonb END
              -- manage_event sees full detail (owner id + full name + guest PII + raw fields)
              || CASE WHEN v_is_admin
                      THEN jsonb_build_object(
                             'owner_member_id', bk.owner_member_id,
                             'owner_full_name', bk.owner_full_name,
                             'guest_name', bk.guest_name)
                      ELSE '{}'::jsonb END
              ORDER BY bk.sort_order, bk.duration_min DESC
            ) FROM blocks bk WHERE bk.event_id = u.id
          ), '[]'::jsonb)
        ) ORDER BY u.start_at
      ) FROM upcoming u
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END
$function$;

-- ----------------------------------------------------------------------------
-- 3) update_agenda_block — owner until start; manage_event anytime.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_agenda_block(
  p_block_id       uuid,
  p_title          text DEFAULT NULL,
  p_format_slug    text DEFAULT NULL,
  p_duration_min   integer DEFAULT NULL,
  p_guest_name     text DEFAULT NULL,
  p_material_url   text DEFAULT NULL,
  p_external_guest boolean DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_caller   uuid;
  v_is_admin boolean;
  v_block    record;
  v_start    timestamptz;
  v_used     int;
  v_new_dur  int;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  v_is_admin := public.can_by_member(v_caller, 'manage_event');

  SELECT b.*, (e.date + COALESCE(e.time_start,'00:00'::time)) AT TIME ZONE COALESCE(e.timezone,'America/Sao_Paulo') AS start_at
    INTO v_block
    FROM public.event_agenda_blocks b JOIN public.events e ON e.id = b.event_id
    WHERE b.id = p_block_id
    FOR UPDATE OF b;
  IF v_block.id IS NULL THEN RETURN jsonb_build_object('error', 'block_not_found'); END IF;

  IF NOT v_is_admin THEN
    IF v_block.owner_member_id <> v_caller THEN RETURN jsonb_build_object('error', 'access_denied'); END IF;
    IF now() >= v_block.start_at THEN RETURN jsonb_build_object('error', 'edit_window_closed'); END IF;
  END IF;
  IF v_block.status NOT IN ('reserved','confirmed') THEN
    RETURN jsonb_build_object('error', 'block_not_editable', 'status', v_block.status);
  END IF;

  v_new_dur := COALESCE(p_duration_min, v_block.duration_min);
  IF v_new_dur <= 0 OR v_new_dur % 5 <> 0 THEN
    RETURN jsonb_build_object('error', 'invalid_duration', 'detail', 'must be a positive multiple of 5');
  END IF;
  IF p_format_slug IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.agenda_block_formats WHERE slug = p_format_slug AND active) THEN
    RETURN jsonb_build_object('error', 'invalid_format', 'received', p_format_slug);
  END IF;

  -- Re-check capacity when duration grows (exclude this block's current contribution).
  IF v_new_dur <> v_block.duration_min THEN
    -- Acquire the event-row lock first, the same lock reserve_agenda_block holds, so the
    -- capacity SUM cannot race a concurrent reservation on the same event.
    PERFORM 1 FROM public.events WHERE id = v_block.event_id FOR UPDATE;
    SELECT COALESCE(SUM(duration_min), 0) INTO v_used
      FROM public.event_agenda_blocks
      WHERE event_id = v_block.event_id AND status IN ('reserved','confirmed') AND id <> p_block_id;
    IF v_used + v_new_dur > 90 THEN
      RETURN jsonb_build_object('error', 'capacity_exceeded', 'used_min', v_used, 'requested_min', v_new_dur, 'cap_min', 90);
    END IF;
  END IF;

  UPDATE public.event_agenda_blocks
     SET title          = COALESCE(p_title, title),
         format_slug    = COALESCE(p_format_slug, format_slug),
         duration_min   = v_new_dur,
         guest_name     = COALESCE(p_guest_name, guest_name),
         material_url   = COALESCE(p_material_url, material_url),
         external_guest = COALESCE(p_external_guest, external_guest)
   WHERE id = p_block_id;

  RETURN jsonb_build_object('success', true, 'block_id', p_block_id);
END
$function$;

-- ----------------------------------------------------------------------------
-- 4) cancel_agenda_block — owner until start; manage_event anytime.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancel_agenda_block(
  p_block_id uuid,
  p_reason   text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_caller   uuid;
  v_is_admin boolean;
  v_block    record;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  v_is_admin := public.can_by_member(v_caller, 'manage_event');

  SELECT b.*, (e.date + COALESCE(e.time_start,'00:00'::time)) AT TIME ZONE COALESCE(e.timezone,'America/Sao_Paulo') AS start_at
    INTO v_block
    FROM public.event_agenda_blocks b JOIN public.events e ON e.id = b.event_id
    WHERE b.id = p_block_id
    FOR UPDATE OF b;
  IF v_block.id IS NULL THEN RETURN jsonb_build_object('error', 'block_not_found'); END IF;
  IF v_block.status = 'cancelled' THEN RETURN jsonb_build_object('success', true, 'block_id', p_block_id, 'already', true); END IF;

  IF NOT v_is_admin THEN
    IF v_block.owner_member_id <> v_caller THEN RETURN jsonb_build_object('error', 'access_denied'); END IF;
    IF now() >= v_block.start_at THEN RETURN jsonb_build_object('error', 'cancel_window_closed'); END IF;
  END IF;

  UPDATE public.event_agenda_blocks
     SET status = 'cancelled', cancelled_by = v_caller, cancelled_reason = p_reason
   WHERE id = p_block_id;

  RETURN jsonb_build_object('success', true, 'block_id', p_block_id, 'status', 'cancelled');
END
$function$;

-- ----------------------------------------------------------------------------
-- 5) reorder_event_blocks — coordination only (manage_event).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reorder_event_blocks(
  p_event_id    uuid,
  p_ordered_ids uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_caller  uuid;
  v_updated int := 0;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT public.can_by_member(v_caller, 'manage_event') THEN
    RETURN jsonb_build_object('error', 'access_denied', 'required', 'manage_event');
  END IF;
  IF p_ordered_ids IS NULL OR array_length(p_ordered_ids, 1) IS NULL THEN
    RETURN jsonb_build_object('error', 'empty_order');
  END IF;

  UPDATE public.event_agenda_blocks b
     SET sort_order = ord.pos
    FROM (SELECT id, row_number() OVER () AS pos FROM unnest(p_ordered_ids) WITH ORDINALITY AS t(id, pos)) ord
   WHERE b.id = ord.id AND b.event_id = p_event_id;
  GET DIAGNOSTICS v_updated = ROW_COUNT;

  RETURN jsonb_build_object('success', true, 'event_id', p_event_id, 'reordered', v_updated);
END
$function$;

-- ----------------------------------------------------------------------------
-- 6) Grants: writes are authenticated-only; the public agenda RPC is anon-OK.
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.reserve_agenda_block(uuid, text, text, integer, text, text, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_agenda_block(uuid, text, text, integer, text, text, boolean)   FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cancel_agenda_block(uuid, text)                                        FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reorder_event_blocks(uuid, uuid[])                                     FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reserve_agenda_block(uuid, text, text, integer, text, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_agenda_block(uuid, text, text, integer, text, text, boolean)   TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_agenda_block(uuid, text)                                        TO authenticated;
GRANT EXECUTE ON FUNCTION public.reorder_event_blocks(uuid, uuid[])                                     TO authenticated;

REVOKE ALL ON FUNCTION public.get_geral_agenda_viva(integer, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_geral_agenda_viva(integer, uuid) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
