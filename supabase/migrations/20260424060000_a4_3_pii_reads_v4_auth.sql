-- ============================================================
-- A4.3 — PII reads: V4 auth via can_by_member('view_pii') (ADR-0011)
--
-- RPCs refactored:
--   admin_list_members_with_pii  → view_pii
--   admin_get_member_details     → view_pii
--   export_audit_log_csv         → view_pii  (audit log surfaces PII-adjacent data)
--
-- Preserves: pii_access_log bulk logging, all return shapes.
-- ============================================================

-- ── admin_get_member_details ──
DROP FUNCTION IF EXISTS public.admin_get_member_details(uuid);

CREATE FUNCTION public.admin_get_member_details(p_member_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_pii') THEN
    RAISE EXCEPTION 'Access denied: requires view_pii permission (LGPD-sensitive data)';
  END IF;

  SELECT jsonb_build_object(
    'id', m.id, 'name', m.name, 'email', m.email, 'phone', m.phone,
    'photo_url', m.photo_url, 'tribe_id', m.tribe_id,
    'operational_role', m.operational_role, 'designations', m.designations,
    'is_superadmin', m.is_superadmin, 'is_active', m.is_active,
    'cycle_active', m.cycle_active, 'cycles', m.cycles,
    'created_at', m.created_at
  ) INTO v_result FROM public.members m WHERE m.id = p_member_id;

  RETURN v_result;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_get_member_details(uuid) TO authenticated;

-- ── admin_list_members_with_pii ──
DROP FUNCTION IF EXISTS public.admin_list_members_with_pii(integer);

CREATE FUNCTION public.admin_list_members_with_pii(p_tribe_id integer DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_accessed_ids uuid[];
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_pii') THEN
    RAISE EXCEPTION 'Access denied: requires view_pii permission (LGPD-sensitive data)';
  END IF;

  SELECT array_agg(m.id) INTO v_accessed_ids
  FROM public.members m
  WHERE (p_tribe_id IS NULL OR m.tribe_id = p_tribe_id) AND m.id != v_caller_id;

  IF v_accessed_ids IS NOT NULL THEN
    INSERT INTO public.pii_access_log (accessor_id, target_member_id, fields_accessed, context, reason)
    SELECT v_caller_id, unnest(v_accessed_ids),
      ARRAY['name','email','phone','role','designations']::text[],
      'admin_list_members_with_pii',
      CASE WHEN p_tribe_id IS NOT NULL THEN 'filtered by tribe ' || p_tribe_id ELSE 'all members' END;
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', m.id, 'name', m.name, 'email', m.email, 'phone', m.phone,
    'tribe_id', m.tribe_id, 'operational_role', m.operational_role,
    'designations', m.designations, 'is_active', m.is_active, 'cycle_active', m.cycle_active
  ) ORDER BY m.name), '[]'::jsonb) INTO v_result
  FROM public.members m
  WHERE (p_tribe_id IS NULL OR m.tribe_id = p_tribe_id);

  RETURN v_result;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_list_members_with_pii(integer) TO authenticated;

-- ── export_audit_log_csv ──
DROP FUNCTION IF EXISTS public.export_audit_log_csv(text, text, text);

CREATE FUNCTION public.export_audit_log_csv(
  p_category text DEFAULT 'all',
  p_actor_filter text DEFAULT NULL,
  p_search text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id uuid;
  v_csv text;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN 'Unauthorized'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_pii') THEN
    RETURN 'Unauthorized: requires view_pii permission';
  END IF;

  SELECT string_agg(
    category||','||to_char(event_date,'YYYY-MM-DD HH24:MI')||','||COALESCE(replace(actor_name,',',';'),'')||','||
    COALESCE(replace(action,',',';'),'')||','||COALESCE(replace(subject,',',';'),'')||','||
    COALESCE(replace(summary,',',';'),'')||','||COALESCE(replace(detail,',',';'),''), E'\n'
  ) INTO v_csv
  FROM (
    SELECT 'members' as category, mst.created_at as event_date, actor.name as actor_name,
           'status_change' as action, m.name as subject,
           mst.previous_status||' → '||mst.new_status as summary, mst.reason_detail as detail
    FROM public.member_status_transitions mst
    JOIN public.members m ON m.id = mst.member_id
    LEFT JOIN public.members actor ON actor.id = mst.actor_member_id
    WHERE (p_category='all' OR p_category='members')
    UNION ALL
    SELECT 'settings', psl.created_at, actor.name, 'setting_changed', psl.setting_key,
           psl.previous_value::text||' → '||psl.new_value::text, psl.reason
    FROM public.platform_settings_log psl
    LEFT JOIN public.members actor ON actor.id = psl.actor_member_id
    WHERE (p_category='all' OR p_category='settings')
    UNION ALL
    SELECT 'partnerships', pi.created_at, actor.name, pi.interaction_type, pe.name,
           pi.summary, pi.outcome
    FROM public.partner_interactions pi
    JOIN public.partner_entities pe ON pe.id = pi.partner_id
    LEFT JOIN public.members actor ON actor.id = pi.actor_member_id
    WHERE (p_category='all' OR p_category='partnerships')
    ORDER BY event_date DESC
  ) entries;

  RETURN 'Categoria,Data,Actor,Ação,Assunto,Resumo,Detalhe'||E'\n'||COALESCE(v_csv,'');
END;
$$;
GRANT EXECUTE ON FUNCTION public.export_audit_log_csv(text, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
