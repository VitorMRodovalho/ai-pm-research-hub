-- P1-7: Fix mark_member_present to include tribe_leader role
-- Tribe leaders can mark attendance for events belonging to their own tribe.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.mark_member_present(
  p_event_id  uuid,
  p_member_id uuid,
  p_present   boolean
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_is_admin boolean;
BEGIN
  -- Auth check
  SELECT id, operational_role, is_superadmin
  INTO v_caller_id, v_caller_role, v_is_admin
  FROM public.members WHERE auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Allow: self, admin, manager, deputy_manager, or tribe_leader (own tribe events only)
  IF v_caller_id = p_member_id THEN
    -- Self-marking: always allowed
    NULL;
  ELSIF v_is_admin = true OR v_caller_role IN ('manager', 'deputy_manager') THEN
    -- Admin/GP: always allowed
    NULL;
  ELSIF v_caller_role = 'tribe_leader' THEN
    -- Tribe leader: only for events in their tribe
    IF NOT EXISTS (
      SELECT 1 FROM events e
      JOIN members m ON m.auth_id = auth.uid()
      WHERE e.id = p_event_id AND e.tribe_id = m.tribe_id
    ) THEN
      RAISE EXCEPTION 'Tribe leaders can only mark attendance for their own tribe events';
    END IF;
  ELSE
    RAISE EXCEPTION 'Unauthorized: can only mark own presence or requires admin/leader role';
  END IF;

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
