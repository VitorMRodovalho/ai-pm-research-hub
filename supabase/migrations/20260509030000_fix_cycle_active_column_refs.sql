-- Migration: fix pre-existing bug inherited by p41 instrumentation (20260509020000)
-- Issue: admin_get_member_details and admin_list_members_with_pii referenced
--        `m.cycle_active` but the actual column is `current_cycle_active`.
-- Root cause: bug pré-existente (não introduzido por 020000 — apenas copiado).
--             Smoke fired the error via `m.cycle_active does not exist` porque
--             o pre-instrumentation RPC tinha zero callers (grep em src/ retornou vazio)
--             e portanto nunca executou em produção.
-- Fix: both RPCs now reference `current_cycle_active`. Payload key `cycle_active`
--      preserved in JSON output para backward-compat com any future callers.
-- Rollback: não aplicável (conserta bug, não tem reversão útil).

CREATE OR REPLACE FUNCTION public.admin_get_member_details(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_pii') THEN
    RAISE EXCEPTION 'Access denied: requires view_pii permission (LGPD-sensitive data)';
  END IF;

  PERFORM public.log_pii_access(
    p_member_id,
    ARRAY['name','email','phone','photo_url','role','designations','is_active','cycles']::text[],
    'admin_get_member_details',
    NULL
  );

  SELECT jsonb_build_object(
    'id', m.id,
    'name', m.name,
    'email', m.email,
    'phone', m.phone,
    'photo_url', m.photo_url,
    'tribe_id', m.tribe_id,
    'operational_role', m.operational_role,
    'designations', m.designations,
    'is_superadmin', m.is_superadmin,
    'is_active', m.is_active,
    'cycle_active', m.current_cycle_active,
    'cycles', m.cycles,
    'created_at', m.created_at
  ) INTO v_result
  FROM public.members m
  WHERE m.id = p_member_id;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_list_members_with_pii(p_tribe_id integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_accessed_ids uuid[];
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_pii') THEN
    RAISE EXCEPTION 'Access denied: requires view_pii permission (LGPD-sensitive data)';
  END IF;

  SELECT array_agg(m.id) INTO v_accessed_ids
  FROM public.members m
  WHERE (p_tribe_id IS NULL OR m.tribe_id = p_tribe_id)
    AND m.id <> v_caller_id;

  PERFORM public.log_pii_access_batch(
    v_accessed_ids,
    ARRAY['name','email','phone','role','designations']::text[],
    'admin_list_members_with_pii',
    CASE WHEN p_tribe_id IS NOT NULL THEN 'filtered by tribe ' || p_tribe_id ELSE 'all members' END
  );

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', m.id,
    'name', m.name,
    'email', m.email,
    'phone', m.phone,
    'tribe_id', m.tribe_id,
    'operational_role', m.operational_role,
    'designations', m.designations,
    'is_active', m.is_active,
    'cycle_active', m.current_cycle_active
  ) ORDER BY m.name), '[]'::jsonb) INTO v_result
  FROM public.members m
  WHERE (p_tribe_id IS NULL OR m.tribe_id = p_tribe_id);

  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
