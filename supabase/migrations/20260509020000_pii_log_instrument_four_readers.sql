-- Migration: LGPD — instrument 4 PII-reading RPCs with log_pii_access/log_pii_access_batch
-- Issue: #85 Onda C — close PII access logging gap
-- Context: pii_access_log é 0 rows em produção. helper log_pii_access() já existe,
--          mas só admin_list_members_with_pii o utiliza (via inline INSERT equivalente).
--          Instrumenta: admin_get_member_details, get_tribe_member_contacts,
--          admin_preview_campaign, get_initiative_member_contacts.
--          Também refatora admin_list_members_with_pii para usar helper (consistência).
-- Rollback: CREATE OR REPLACE versões prévias (ver pg_get_functiondef antes de aplicar).
-- Invariantes preservados: zero mudança em gate/auth logic, zero mudança em payload retornado.

-- ============================================================================
-- 1. admin_list_members_with_pii — refactor inline INSERT → log_pii_access_batch
-- ============================================================================
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
    'cycle_active', m.cycle_active
  ) ORDER BY m.name), '[]'::jsonb) INTO v_result
  FROM public.members m
  WHERE (p_tribe_id IS NULL OR m.tribe_id = p_tribe_id);

  RETURN v_result;
END;
$function$;

-- ============================================================================
-- 2. admin_get_member_details — add log_pii_access (single-target)
-- ============================================================================
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
    'cycle_active', m.cycle_active,
    'cycles', m.cycles,
    'created_at', m.created_at
  ) INTO v_result
  FROM public.members m
  WHERE m.id = p_member_id;

  RETURN v_result;
END;
$function$;

-- ============================================================================
-- 3. get_tribe_member_contacts — add log_pii_access_batch
-- ============================================================================
-- Volatility note: original declared STABLE, but STABLE + INSERT (log_pii_access_batch)
-- is contradictory. Changed to VOLATILE (default) — zero caller dependency on STABLE cacheability
-- (RPC path via supabase-js treats all as volatile).
CREATE OR REPLACE FUNCTION public.get_tribe_member_contacts(p_tribe_id integer)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  caller record;
  is_tribe_leader boolean;
  is_admin boolean;
  v_accessed_ids uuid[];
begin
  select * into caller from public.get_my_member_record();
  if caller is null then
    return '{}';
  end if;

  is_admin := caller.is_superadmin = true
    or caller.operational_role in ('manager', 'deputy_manager');

  is_tribe_leader := caller.operational_role = 'tribe_leader'
    and caller.tribe_id = p_tribe_id;

  if not (is_admin or is_tribe_leader) then
    return '{}';
  end if;

  select array_agg(m.id)
  into v_accessed_ids
  from public.members m
  where m.tribe_id = p_tribe_id
    and m.current_cycle_active = true;

  perform public.log_pii_access_batch(
    v_accessed_ids,
    ARRAY['email','phone']::text[],
    'get_tribe_member_contacts',
    'tribe ' || p_tribe_id
  );

  return (
    select coalesce(
      json_object_agg(m.id, json_build_object('email', m.email, 'phone', m.phone)),
      '{}'::json
    )
    from public.members m
    where m.tribe_id = p_tribe_id
      and m.current_cycle_active = true
  );
end;
$function$;

-- ============================================================================
-- 4. get_initiative_member_contacts — add log_pii_access_batch
--    NOTE: caller é resolvido via persons, mas log_pii_access_batch resolve
--    via members.auth_id = auth.uid() — funciona igual (auth_id é shared).
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_initiative_member_contacts(p_initiative_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_person_id uuid;
  v_can_view_pii boolean;
  v_accessed_ids uuid[];
  v_result jsonb;
BEGIN
  SELECT p.id INTO v_caller_person_id
  FROM persons p WHERE p.auth_id = auth.uid();

  IF v_caller_person_id IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;

  v_can_view_pii := can(v_caller_person_id, 'view_pii', 'initiative', p_initiative_id);

  IF NOT v_can_view_pii THEN
    RETURN '{}'::jsonb;
  END IF;

  SELECT array_agg(m.id)
  INTO v_accessed_ids
  FROM engagements e
  JOIN persons p ON p.id = e.person_id
  JOIN members m ON m.id = p.legacy_member_id
  WHERE e.initiative_id = p_initiative_id
    AND e.status = 'active';

  PERFORM public.log_pii_access_batch(
    v_accessed_ids,
    ARRAY['email','phone','share_whatsapp']::text[],
    'get_initiative_member_contacts',
    'initiative ' || p_initiative_id::text
  );

  SELECT jsonb_object_agg(
    m.id::text,
    jsonb_build_object(
      'email', m.email,
      'phone', m.phone,
      'share_whatsapp', m.share_whatsapp
    )
  ) INTO v_result
  FROM engagements e
  JOIN persons p ON p.id = e.person_id
  JOIN members m ON m.id = p.legacy_member_id
  WHERE e.initiative_id = p_initiative_id
    AND e.status = 'active';

  RETURN coalesce(v_result, '{}'::jsonb);
END;
$function$;

-- ============================================================================
-- 5. admin_preview_campaign — add log_pii_access (single-target preview)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.admin_preview_campaign(p_template_id uuid, p_preview_member_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_tmpl record;
  v_member record;
  v_html text;
  v_text text;
  v_subject text;
  v_lang text := 'pt';
BEGIN
  -- Auth check: GP/DM/comms_team
  SELECT id INTO v_caller_id
  FROM public.members
  WHERE auth_id = auth.uid()
    AND (is_superadmin
         OR operational_role IN ('manager','deputy_manager')
         OR 'comms_team' = ANY(designations));
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: insufficient permissions';
  END IF;

  -- Load template
  SELECT * INTO v_tmpl FROM public.campaign_templates WHERE id = p_template_id;
  IF v_tmpl IS NULL THEN
    RAISE EXCEPTION 'Template not found';
  END IF;

  -- Load preview member (or first active member)
  IF p_preview_member_id IS NOT NULL THEN
    SELECT m.id, m.name, m.email, m.tribe_id, m.is_active, t.name AS tribe_name
    INTO v_member
    FROM public.members m
    LEFT JOIN public.tribes t ON t.id = m.tribe_id
    WHERE m.id = p_preview_member_id;
  ELSE
    SELECT m.id, m.name, m.email, m.tribe_id, m.is_active, t.name AS tribe_name
    INTO v_member
    FROM public.members m
    LEFT JOIN public.tribes t ON t.id = m.tribe_id
    WHERE m.is_active = true
    LIMIT 1;
  END IF;

  -- Log PII access (preview reads member.name + member.email)
  IF v_member.id IS NOT NULL THEN
    PERFORM public.log_pii_access(
      v_member.id,
      ARRAY['name','email']::text[],
      'admin_preview_campaign',
      'template ' || p_template_id::text
    );
  END IF;

  -- Render subject
  v_subject := COALESCE(v_tmpl.subject->>v_lang, v_tmpl.subject->>'pt', '');
  v_html := COALESCE(v_tmpl.body_html->>v_lang, v_tmpl.body_html->>'pt', '');
  v_text := COALESCE(v_tmpl.body_text->>v_lang, v_tmpl.body_text->>'pt', '');

  -- Replace variables
  v_subject := replace(v_subject, '{member.name}', COALESCE(v_member.name, 'Membro'));
  v_html := replace(v_html, '{member.name}', COALESCE(v_member.name, 'Membro'));
  v_html := replace(v_html, '{member.tribe}', COALESCE(v_member.tribe_name, ''));
  v_html := replace(v_html, '{member.chapter}', '');
  v_html := replace(v_html, '{platform.url}', 'https://ai-pm-research-hub.pages.dev');
  v_html := replace(v_html, '{unsubscribe_url}', 'https://ai-pm-research-hub.pages.dev/unsubscribe?token=preview');

  v_text := replace(v_text, '{member.name}', COALESCE(v_member.name, 'Membro'));
  v_text := replace(v_text, '{member.tribe}', COALESCE(v_member.tribe_name, ''));
  v_text := replace(v_text, '{member.chapter}', '');
  v_text := replace(v_text, '{platform.url}', 'https://ai-pm-research-hub.pages.dev');
  v_text := replace(v_text, '{unsubscribe_url}', 'https://ai-pm-research-hub.pages.dev/unsubscribe?token=preview');

  RETURN jsonb_build_object(
    'subject', v_subject,
    'html', v_html,
    'text', v_text,
    'member_name', v_member.name,
    'language', v_lang
  );
END;
$function$;

-- Reload PostgREST schema (OpenAPI cache)
NOTIFY pgrst, 'reload schema';
