-- Phase B'' batch 12 (p79): notify_privacy_policy_change V3 (is_superadmin only) → V4 manage_platform.
-- Surfaced by V3 pattern scan. Single-action, no business logic change.
-- LGPD ART. 7º — privacy policy notification campaign creation. Only platform-admin should trigger.

CREATE OR REPLACE FUNCTION public.notify_privacy_policy_change(p_version_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_auth uuid := auth.uid();
  v_caller_id uuid;
  v_version record;
  v_template_id uuid;
  v_send_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = v_caller_auth;
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform permission';
  END IF;

  SELECT * INTO v_version FROM public.privacy_policy_versions WHERE id = p_version_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Version not found';
  END IF;

  IF v_version.notification_campaign_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'status', 'already_notified',
      'campaign_id', v_version.notification_campaign_id
    );
  END IF;

  INSERT INTO public.campaign_templates (name, subject, body_html, category, created_by)
  VALUES (
    'Atualização da Política de Privacidade ' || v_version.version,
    'Atualização da Política de Privacidade — ' || v_version.version,
    '<p>Prezado(a) membro,</p>'
    || '<p>Informamos que a Política de Privacidade do Núcleo IA &amp; GP foi atualizada para a versão <strong>' || v_version.version || '</strong>, '
    || 'com vigência a partir de ' || to_char(v_version.effective_at, 'DD/MM/YYYY') || '.</p>'
    || '<p><strong>Resumo das alterações:</strong></p>'
    || '<p>' || COALESCE(v_version.summary_pt, 'Consulte a política atualizada no site.') || '</p>'
    || '<p>A política completa pode ser consultada em: '
    || '<a href="https://nucleoia.vitormr.dev/privacy">nucleoia.vitormr.dev/privacy</a></p>'
    || '<p>Em caso de dúvidas, entre em contato com o DPO: <a href="mailto:vitor.rodovalho@outlook.com">vitor.rodovalho@outlook.com</a></p>'
    || '<p>Atenciosamente,<br/>Núcleo IA &amp; GP</p>',
    'lgpd',
    v_caller_auth
  )
  RETURNING id INTO v_template_id;

  INSERT INTO public.campaign_sends (template_id, status, created_by)
  VALUES (v_template_id, 'draft', v_caller_auth)
  RETURNING id INTO v_send_id;

  UPDATE public.privacy_policy_versions SET
    notification_campaign_id = v_send_id,
    notification_created_at = now()
  WHERE id = p_version_id;

  RETURN jsonb_build_object(
    'status', 'draft_created',
    'campaign_send_id', v_send_id,
    'template_id', v_template_id,
    'note', 'Campaign created in DRAFT status. Review and send via admin_send_campaign.'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.notify_privacy_policy_change(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.notify_privacy_policy_change(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
