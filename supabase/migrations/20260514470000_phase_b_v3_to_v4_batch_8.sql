-- Phase B'' V3 → V4 batch 8: convert 3 functions from V3 auth patterns
-- (operational_role/designations direct checks) to V4 (can_by_member).
-- Auth surface preserved exactly via action mapping.
--
-- 1. get_tribe_member_contacts — view_pii (org admin) OR rls_can_for_tribe(write, tribe_id) (tribe leader)
-- 2. create_tag — manage_platform (administrative tier) / write (semantic tier)
-- 3. update_application_contact — manage_member (admin-only edit of candidate contact)

CREATE OR REPLACE FUNCTION public.get_tribe_member_contacts(p_tribe_id integer)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_can boolean;
  v_accessed_ids uuid[];
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN '{}'::json; END IF;

  v_can := public.can_by_member(v_caller_id, 'view_pii')
        OR public.rls_can_for_tribe('write'::text, p_tribe_id);
  IF NOT v_can THEN RETURN '{}'::json; END IF;

  SELECT array_agg(m.id) INTO v_accessed_ids
  FROM public.members m
  WHERE m.tribe_id = p_tribe_id AND m.current_cycle_active = true;

  PERFORM public.log_pii_access_batch(
    v_accessed_ids,
    ARRAY['email','phone']::text[],
    'get_tribe_member_contacts',
    'tribe ' || p_tribe_id
  );

  RETURN (
    SELECT coalesce(
      json_object_agg(m.id, json_build_object('email', m.email, 'phone', m.phone)),
      '{}'::json
    )
    FROM public.members m
    WHERE m.tribe_id = p_tribe_id AND m.current_cycle_active = true
  );
END;
$function$;

COMMENT ON FUNCTION public.get_tribe_member_contacts(integer) IS
'Phase B''V4: returns email+phone of active tribe members. Authority: view_pii (org admin) OR rls_can_for_tribe(write, tribe_id) (tribe leader). PII access logged.';

CREATE OR REPLACE FUNCTION public.create_tag(
  p_name text,
  p_label_pt text,
  p_color text DEFAULT '#6B7280'::text,
  p_tier text DEFAULT 'semantic'::text,
  p_domain text DEFAULT 'all'::text,
  p_description text DEFAULT NULL::text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_id uuid;
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF p_tier = 'system' THEN
    RAISE EXCEPTION 'System tags can only be created via migrations';
  ELSIF p_tier = 'administrative' THEN
    IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'Only admins/GP can create administrative tags';
    END IF;
  ELSIF p_tier = 'semantic' THEN
    IF NOT public.can_by_member(v_caller_id, 'write') THEN
      RAISE EXCEPTION 'Only admins/GP/tribe leaders can create semantic tags';
    END IF;
  END IF;

  INSERT INTO public.tags (name, label_pt, color, tier, domain, description, display_order, created_by)
  VALUES (
    p_name, p_label_pt, p_color, p_tier::tag_tier, p_domain::tag_domain, p_description,
    (SELECT COALESCE(MAX(display_order),0)+1 FROM public.tags),
    v_caller_id
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

COMMENT ON FUNCTION public.create_tag(text, text, text, text, text, text) IS
'Phase B''V4: tier-gated tag creation. Authority: manage_platform (administrative tier), write (semantic tier; covers tribe_leader). System tier blocked via migrations only.';

CREATE OR REPLACE FUNCTION public.update_application_contact(
  p_application_id uuid,
  p_phone text DEFAULT NULL::text,
  p_linkedin_url text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  UPDATE public.selection_applications SET
    phone = COALESCE(NULLIF(p_phone, ''), phone),
    linkedin_url = COALESCE(NULLIF(p_linkedin_url, ''), linkedin_url),
    updated_at = now()
  WHERE id = p_application_id;

  RETURN jsonb_build_object('success', true);
END;
$function$;

COMMENT ON FUNCTION public.update_application_contact(uuid, text, text) IS
'Phase B''V4: admin updates a candidate''s phone / linkedin_url on a selection application. Authority: manage_member.';

NOTIFY pgrst, 'reload schema';
