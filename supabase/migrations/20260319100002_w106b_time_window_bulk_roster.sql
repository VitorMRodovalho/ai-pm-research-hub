-- ═══════════════════════════════════════════════════════════════
-- W106 Sprint B — 24h check-in window + Bulk roster
-- Adds checked_in_at / marked_by columns to attendance,
-- enforces time window on self-check-in,
-- creates admin_bulk_mark_attendance RPC
-- ═══════════════════════════════════════════════════════════════

-- 1. Add columns to attendance
ALTER TABLE public.attendance
  ADD COLUMN IF NOT EXISTS checked_in_at timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS marked_by uuid;

-- 2. Replace register_own_presence with time-window enforcement
CREATE OR REPLACE FUNCTION public.register_own_presence(p_event_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_member_id uuid;
  v_role text;
  v_is_admin boolean;
  v_event_date date;
  v_event_ts timestamptz;
BEGIN
  -- Get caller
  SELECT id, operational_role, is_superadmin
  INTO v_member_id, v_role, v_is_admin
  FROM public.members WHERE auth_id = auth.uid();

  IF v_member_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  -- Get event date
  SELECT date INTO v_event_date FROM public.events WHERE id = p_event_id;

  IF v_event_date IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'event_not_found');
  END IF;

  -- Cast date to timestamptz (midnight of event day)
  v_event_ts := v_event_date::timestamptz;

  -- Check time window (admin/PM/DM bypass)
  IF NOT (v_is_admin IS TRUE OR v_role IN ('manager', 'deputy_manager')) THEN
    -- Can't check in more than 24h after event
    IF now() > v_event_ts + interval '24 hours' THEN
      RETURN json_build_object('success', false, 'error', 'checkin_window_expired',
        'message', 'O prazo de 24h para check-in expirou. Solicite ao gestor.');
    END IF;
    -- Can't check in more than 2h before event
    IF now() < v_event_ts - interval '2 hours' THEN
      RETURN json_build_object('success', false, 'error', 'checkin_too_early',
        'message', 'O check-in abre 2h antes do evento.');
    END IF;
  END IF;

  -- Register attendance
  INSERT INTO public.attendance (event_id, member_id, checked_in_at)
  VALUES (p_event_id, v_member_id, now())
  ON CONFLICT (event_id, member_id)
  DO UPDATE SET checked_in_at = now();

  RETURN json_build_object('success', true, 'member_id', v_member_id);
END;
$$;

-- 3. Bulk mark attendance RPC
CREATE OR REPLACE FUNCTION public.admin_bulk_mark_attendance(
  p_event_id   uuid,
  p_member_ids uuid[],
  p_present    boolean DEFAULT true
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_role text;
  v_is_admin boolean;
  v_count int := 0;
  v_mid uuid;
BEGIN
  -- Verify admin/leader permissions
  SELECT operational_role, is_superadmin
  INTO v_role, v_is_admin
  FROM public.members WHERE auth_id = auth.uid();

  IF NOT (v_is_admin IS TRUE OR v_role IN ('manager', 'deputy_manager', 'tribe_leader')) THEN
    RETURN json_build_object('success', false, 'error', 'permission_denied');
  END IF;

  IF p_present THEN
    FOREACH v_mid IN ARRAY p_member_ids LOOP
      INSERT INTO public.attendance (event_id, member_id, checked_in_at, marked_by)
      VALUES (p_event_id, v_mid, now(), auth.uid())
      ON CONFLICT (event_id, member_id)
      DO UPDATE SET checked_in_at = now(), marked_by = auth.uid();
      v_count := v_count + 1;
    END LOOP;
  ELSE
    FOREACH v_mid IN ARRAY p_member_ids LOOP
      DELETE FROM public.attendance
      WHERE event_id = p_event_id AND member_id = v_mid;
      v_count := v_count + 1;
    END LOOP;
  END IF;

  RETURN json_build_object('success', true, 'marked', v_count);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_bulk_mark_attendance(uuid, uuid[], boolean) TO authenticated;
