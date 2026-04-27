-- ADR-0026 EXTENSION (p66): manage_comms applied to 2 campaign fns
-- Phase B'' V3→V4 conversion of admin_get_campaign_stats + admin_preview_campaign.
-- See docs/adr/ADR-0026-manage-comms-v4-action.md (extension section).
--
-- Privilege expansion safety check (verified pre-apply):
--   V3 gate: is_superadmin OR manager/deputy_manager OR 'comms_team' designation
--   Note: 'comms_team' designation = 0 active members (dead code reference)
--   Effective V3 set: 2 (Vitor SA, Fabricio manager equiv → checked active)
--   V4 manage_comms grant: 2 (same)
--   would_gain = []  would_lose = []
--   Mayanna (comms_leader designation, no V4 engagement) — same drift as ADR-0026 batch 1.
--
-- Rationale for extension:
--   * Same gate semantics as admin_manage_comms_channel (already converted in p59)
--   * Both fns operate on campaign_sends/campaign_templates (comms domain)
--   * Zero new V4 ladder needed — reuses ADR-0026 grants
--   * Aligns with PM directive p66: "primeiro 1 depois 2" (this is item #1)

-- ============================================================
-- 1. Convert admin_get_campaign_stats
-- ============================================================
CREATE OR REPLACE FUNCTION public.admin_get_campaign_stats(p_send_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_member_id uuid;
  v_result jsonb;
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  -- V4 gate (replaces V3 mix of role + designation check)
  IF NOT public.can_by_member(v_caller_member_id, 'manage_comms') THEN
    RAISE EXCEPTION 'Forbidden: insufficient permissions';
  END IF;

  SELECT jsonb_build_object(
    'send_id', cs.id,
    'template_name', ct.name,
    'status', cs.status,
    'sent_at', cs.sent_at,
    'recipient_count', cs.recipient_count,
    'delivered_count', (SELECT COUNT(*) FROM public.campaign_recipients WHERE send_id = cs.id AND delivered = true),
    'open_count', (SELECT COUNT(*) FROM public.campaign_recipients WHERE send_id = cs.id AND opened = true),
    'unsubscribe_count', (SELECT COUNT(*) FROM public.campaign_recipients WHERE send_id = cs.id AND unsubscribed = true),
    'error_log', cs.error_log
  ) INTO v_result
  FROM public.campaign_sends cs
  JOIN public.campaign_templates ct ON ct.id = cs.template_id
  WHERE cs.id = p_send_id;
  IF v_result IS NULL THEN
    RAISE EXCEPTION 'Send not found';
  END IF;
  RETURN v_result;
END;
$$;
COMMENT ON FUNCTION public.admin_get_campaign_stats(uuid) IS
  'Phase B'' V4 conversion (ADR-0026 extension, p66): manage_comms gate via can_by_member. Was V3 (is_superadmin OR manager/deputy_manager OR designation comms_team — comms_team had 0 active members, was dead code).';

-- ============================================================
-- 2. Convert admin_preview_campaign
-- ============================================================
CREATE OR REPLACE FUNCTION public.admin_preview_campaign(p_template_id uuid, p_preview_member_id uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_member_id uuid;
  v_tmpl record;
  v_member record;
  v_html text;
  v_text text;
  v_subject text;
  v_lang text := 'pt';
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  -- V4 gate (replaces V3 mix of role + designation check)
  IF NOT public.can_by_member(v_caller_member_id, 'manage_comms') THEN
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
$$;
COMMENT ON FUNCTION public.admin_preview_campaign(uuid, uuid) IS
  'Phase B'' V4 conversion (ADR-0026 extension, p66): manage_comms gate via can_by_member. Was V3 (is_superadmin OR manager/deputy_manager OR designation comms_team — comms_team had 0 active members, was dead code).';

NOTIFY pgrst, 'reload schema';
