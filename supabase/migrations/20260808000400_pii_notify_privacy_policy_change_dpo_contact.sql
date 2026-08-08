-- PII: o e-mail de mudanca de politica de privacidade e enviado a TODOS os titulares e dizia
-- "em caso de duvidas, entre em contato com o DPO" apontando para um endereco PESSOAL do
-- mantenedor. Medido em 08/08/2026: era a UNICA funcao viva de `public` com endereco em dominio
-- de e-mail pessoal, e a plataforma ja publica um canal proprio na pagina /privacy e nos 3
-- dicionarios de i18n. Um titular que quisesse exercer direito da LGPD lia um endereco que nao e
-- o canal declarado.
--
-- Decisao do PM (08/08/2026), e a fronteira importa: **dentro do site, o canal e o DPO**
-- (`dpo@pmigo.org.br`), que e o que a pagina /privacy e os 3 dicionarios de i18n ja publicam. O
-- endereco pessoal do mantenedor (`vitor@vitormr.dev`) e a superficie do GITHUB — contato de
-- seguranca do repositorio e valvula de sandbox das Edge Functions. Aqui quem le e o TITULAR, e
-- ele tem de encontrar o mesmo canal em qualquer superficie da plataforma.
--
-- ⚠️ Um placeholder aqui seria PIOR que o defeito: mandaria o titular escrever para um endereco
-- inexistente. Foi o mesmo raciocinio aplicado ao SECURITY.md no PR #1692, com a diferenca de
-- que la o leitor e um pesquisador de seguranca, e aqui e um titular exercendo direito da LGPD.
--
-- Corpo capturado VERBATIM de `pg_get_functiondef` (corpo VIVO, nao do arquivo de migration —
-- GC-097 / `reference-create-or-replace-base-on-live-body`). Unica diferenca: o endereco.
CREATE OR REPLACE FUNCTION public.notify_privacy_policy_change(p_version_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    || '<p>Em caso de dúvidas, entre em contato com o DPO: <a href="mailto:dpo@pmigo.org.br">dpo@pmigo.org.br</a></p>'
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
$function$;
