-- Phase B' / Drift signal #1 resolution — fix broken admin tribe selection RPCs
--
-- p52 Q-A capture (`20260425143237_qa_orphan_recovery_selection_application.sql`)
-- preserved the live bodies of `admin_force_tribe_selection` and
-- `admin_remove_tribe_selection` verbatim, including a critical bug:
--
--   IF NOT EXISTS (
--     SELECT 1 FROM members
--     WHERE auth_id = auth.uid()
--     AND (is_superadmin = true OR role = 'manager')
--   )
--
-- The `members.role` column does NOT exist in the V4 schema (only
-- `operational_role` exists). Any call to these RPCs hits a "column does
-- not exist" error from PostgreSQL, making them silently broken in prod.
--
-- These are dead code — `database.gen.ts` types them but no call site uses
-- them. Still, capture-and-fix here so that:
--   1. Future re-deploys don't reproduce the broken state.
--   2. If anyone later hooks them up to a UI, they actually work.
--   3. ADR-0011 V4 auth pattern is applied (closes Phase B' for these 2).
--
-- Replacement: V4 `can_by_member(v_caller_id, 'manage_member')`.

CREATE OR REPLACE FUNCTION public.admin_force_tribe_selection(p_member_id uuid, p_tribe_id integer)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_current_count INTEGER;
  v_max_slots INTEGER := 6;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RETURN json_build_object('error', 'Unauthorized: requires manage_member permission');
  END IF;

  -- Check slot availability
  SELECT COUNT(*) INTO v_current_count
  FROM public.tribe_selections WHERE tribe_id = p_tribe_id;

  IF v_current_count >= v_max_slots THEN
    RETURN json_build_object('error', 'Tribo lotada (' || v_current_count || '/' || v_max_slots || ')');
  END IF;

  -- Remove existing selection if any
  DELETE FROM public.tribe_selections WHERE member_id = p_member_id;

  -- Insert new selection
  INSERT INTO public.tribe_selections (member_id, tribe_id, selected_at)
  VALUES (p_member_id, p_tribe_id, now());

  RETURN json_build_object('success', true, 'tribe_id', p_tribe_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_remove_tribe_selection(p_member_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RETURN json_build_object('error', 'Unauthorized: requires manage_member permission');
  END IF;

  DELETE FROM public.tribe_selections WHERE member_id = p_member_id;
  RETURN json_build_object('success', true);
END;
$$;
