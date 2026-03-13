-- W111: Cycle management CRUD RPC
-- Allows superadmin to create, update, delete cycles and set current cycle

CREATE OR REPLACE FUNCTION admin_manage_cycle(
  p_action   TEXT,            -- 'create' | 'update' | 'delete' | 'set_current'
  p_cycle_code TEXT,
  p_label    TEXT DEFAULT NULL,
  p_abbr     TEXT DEFAULT NULL,
  p_start    DATE DEFAULT NULL,
  p_end      DATE DEFAULT NULL,
  p_color    TEXT DEFAULT NULL,
  p_sort     INT  DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_member  public.members%ROWTYPE;
  v_result  JSONB;
BEGIN
  -- ACL: superadmin only
  SELECT * INTO v_member FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND OR NOT v_member.is_superadmin THEN
    RAISE EXCEPTION 'access_denied';
  END IF;

  IF p_action = 'create' THEN
    INSERT INTO public.cycles (cycle_code, cycle_label, cycle_abbr, cycle_start, cycle_end, cycle_color, sort_order)
    VALUES (p_cycle_code, p_label, p_abbr, p_start, p_end, COALESCE(p_color, '#94A3B8'), COALESCE(p_sort, 0));

    v_result := jsonb_build_object('ok', true, 'action', 'created', 'cycle_code', p_cycle_code);

  ELSIF p_action = 'update' THEN
    UPDATE public.cycles SET
      cycle_label = COALESCE(p_label, cycle_label),
      cycle_abbr  = COALESCE(p_abbr, cycle_abbr),
      cycle_start = COALESCE(p_start, cycle_start),
      cycle_end   = COALESCE(p_end, cycle_end),
      cycle_color = COALESCE(p_color, cycle_color),
      sort_order  = COALESCE(p_sort, sort_order)
    WHERE cycle_code = p_cycle_code;

    IF NOT FOUND THEN RAISE EXCEPTION 'cycle_not_found'; END IF;
    v_result := jsonb_build_object('ok', true, 'action', 'updated', 'cycle_code', p_cycle_code);

  ELSIF p_action = 'delete' THEN
    -- Prevent deleting current cycle
    IF EXISTS (SELECT 1 FROM public.cycles WHERE cycle_code = p_cycle_code AND is_current = true) THEN
      RAISE EXCEPTION 'cannot_delete_current_cycle';
    END IF;
    DELETE FROM public.cycles WHERE cycle_code = p_cycle_code;
    IF NOT FOUND THEN RAISE EXCEPTION 'cycle_not_found'; END IF;
    v_result := jsonb_build_object('ok', true, 'action', 'deleted', 'cycle_code', p_cycle_code);

  ELSIF p_action = 'set_current' THEN
    -- Unset all, then set the target
    UPDATE public.cycles SET is_current = false WHERE is_current = true;
    UPDATE public.cycles SET is_current = true WHERE cycle_code = p_cycle_code;
    IF NOT FOUND THEN RAISE EXCEPTION 'cycle_not_found'; END IF;
    v_result := jsonb_build_object('ok', true, 'action', 'set_current', 'cycle_code', p_cycle_code);

  ELSE
    RAISE EXCEPTION 'invalid_action';
  END IF;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_manage_cycle TO authenticated;
