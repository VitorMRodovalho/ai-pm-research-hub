-- ============================================================================
-- #2427 — convite de acesso para membro criado FORA do funil
-- ============================================================================
--
-- WHAT: RPC admin_send_member_access(p_member_id) e template member_access_invite (pt/en/es).
--   A RPC valida, registra o pedido no audit e despacha send-portal-account-setup com SO o
--   member_id; a EF re-resolve tudo do zero (mesma regra do caminho do portal, #2273).
-- WHY: criar membro e liga-lo a uma iniciativa da AUTORIDADE, nao da CONTA. Os dois caminhos de
--   acesso que existiam nao alcancam quem nasce fora do funil: request_account_claim exige a
--   pessoa ja logada, e request_portal_account_setup exige o token do portal, que so existe para
--   candidatura aprovada. Medido em 23/09/2026: a pessoa que segue no baseline do detector 2427
--   nasceu por SQL/tela e recebeu o vinculo pelo MCP 9 s depois, sem nenhum convite.
-- REGRAS: so manage_member; recusa membro inativo e membro que ja tem login (convidar criaria
--   uma SEGUNDA identidade); destinatario = e-mail PRIMARIO do membro, resolvido no servidor,
--   nunca recebido por parametro; teto de 3 pedidos por hora por membro, contado no proprio audit;
--   o endereco nunca volta inteiro (so mascarado).
-- ROLLBACK: DROP FUNCTION public.admin_send_member_access(uuid); DELETE do template por slug.
-- CROSS-REF: #2427 · #2273 · #2421
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_send_member_access(p_member_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_caller uuid;
  v_member public.members%ROWTYPE;
  v_primary_email text;
  v_recent int;
  v_service_role_key text;
BEGIN
  SELECT m.id INTO v_caller
    FROM public.members m
   WHERE m.auth_id = auth.uid() AND m.is_active = true
   LIMIT 1;
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_caller, 'manage_member') THEN
    RAISE EXCEPTION 'Access denied: manage_member required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_member FROM public.members WHERE id = p_member_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'state', 'not_found');
  END IF;

  IF v_member.is_active IS NOT TRUE OR v_member.member_status IS DISTINCT FROM 'active' THEN
    RETURN jsonb_build_object('success', false, 'state', 'inactive');
  END IF;

  IF v_member.auth_id IS NOT NULL THEN
    -- Ja tem acesso: mandar link de criacao seria convidar a criar uma SEGUNDA identidade.
    RETURN jsonb_build_object(
      'success', false, 'state', 'already_linked',
      'masked_email', public._mask_email(v_member.email)
    );
  END IF;

  v_primary_email := COALESCE(
    (SELECT me.email::text FROM public.member_emails me
      WHERE me.member_id = v_member.id AND me.is_primary IS TRUE LIMIT 1),
    v_member.email
  );
  IF COALESCE(v_primary_email, '') = '' THEN
    RETURN jsonb_build_object('success', false, 'state', 'no_email');
  END IF;

  SELECT count(*) INTO v_recent
    FROM public.admin_audit_log
   WHERE action = 'member.access_invite_requested'
     AND target_id = v_member.id
     AND created_at > now() - interval '1 hour';
  IF v_recent >= 3 THEN
    RETURN jsonb_build_object('success', false, 'state', 'rate_limited');
  END IF;

  -- O registro do pedido e tambem a AUTORIZACAO que a EF confere antes de enviar: sem uma linha
  -- recente daqui, a EF recusa. Assim a EF nao envia convite a partir de qualquer chamada
  -- service_role, so a partir de um pedido que passou por este portao.
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller,
    'member.access_invite_requested',
    'member',
    v_member.id,
    jsonb_build_object('masked_email', public._mask_email(v_primary_email), 'resolved_via', 'primary_member_email'),
    jsonb_build_object('source', 'admin_send_member_access', 'issue', 2427)
  );

  BEGIN
    SELECT decrypted_secret INTO v_service_role_key
      FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
    IF v_service_role_key IS NOT NULL THEN
      PERFORM net.http_post(
        url     := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/send-portal-account-setup',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_service_role_key
        ),
        -- So o id. A EF re-resolve o endereco: destinatario escolhido fora do servidor e o que
        -- este caminho existe para impedir (mesma regra do #2273).
        body    := jsonb_build_object('member_id', v_member.id)
      );
    ELSE
      RAISE NOTICE 'admin_send_member_access: no service_role_key in vault, EF not dispatched';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'admin_send_member_access dispatch failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'state', 'sent',
    'masked_email', public._mask_email(v_primary_email)
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_send_member_access(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_send_member_access(uuid) TO authenticated;

COMMENT ON FUNCTION public.admin_send_member_access(uuid) IS
  '#2427 — convite de acesso para membro criado fora do funil. So manage_member; recusa inativo e quem ja tem login; destinatario e o primario do membro, resolvido no servidor; teto 3/hora; o pedido no audit e a autorizacao que a EF confere.';

INSERT INTO public.campaign_templates (name, slug, subject, body_html, body_text, category, variables)
VALUES (
  'Convite de acesso — membro cadastrado pelo GP',
  'member_access_invite',
  jsonb_build_object(
    'pt', 'Seu acesso à plataforma do Núcleo IA & GP',
    'en', 'Your access to the Núcleo IA & GP platform',
    'es', 'Su acceso a la plataforma del Núcleo IA & GP'
  ),
  jsonb_build_object(
    'pt', '<p>Olá <b>{{first_name}}</b>!</p><p>Você foi cadastrado(a) no Núcleo IA &amp; GP e já tem acesso à plataforma. Para entrar, use <b>este e-mail</b> em <a href="{{platform_url}}">nucleoia.pmigo.org.br</a>, com Google, LinkedIn ou código por e-mail.</p><p>Se preferir, o botão abaixo entra direto:</p><p><a href="{{access_url}}" style="background:#0066cc;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;">Entrar na plataforma</a></p><p><small>O botão vale por {{expires_in_minutes}} minutos. Depois disso, entre pelo site normalmente, com este mesmo e-mail.</small></p><p>Equipe GP</p>',
    'en', '<p>Hi <b>{{first_name}}</b>!</p><p>You have been registered at Núcleo IA &amp; GP and already have access to the platform. To sign in, use <b>this email</b> at <a href="{{platform_url}}">nucleoia.pmigo.org.br</a>, with Google, LinkedIn or an email code.</p><p>If you prefer, the button below signs you in directly:</p><p><a href="{{access_url}}" style="background:#0066cc;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;">Sign in</a></p><p><small>The button is valid for {{expires_in_minutes}} minutes. After that, sign in through the site as usual, with this same email.</small></p><p>GP Team</p>',
    'es', '<p>¡Hola <b>{{first_name}}</b>!</p><p>Usted fue registrado(a) en el Núcleo IA &amp; GP y ya tiene acceso a la plataforma. Para entrar, use <b>este correo</b> en <a href="{{platform_url}}">nucleoia.pmigo.org.br</a>, con Google, LinkedIn o código por correo.</p><p>Si lo prefiere, el botón de abajo entra directamente:</p><p><a href="{{access_url}}" style="background:#0066cc;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;">Entrar en la plataforma</a></p><p><small>El botón es válido por {{expires_in_minutes}} minutos. Después, entre por el sitio normalmente, con este mismo correo.</small></p><p>Equipo GP</p>'
  ),
  jsonb_build_object(
    'pt', 'Olá {{first_name}}!' || chr(10) || chr(10) || 'Você foi cadastrado(a) no Núcleo IA & GP e já tem acesso à plataforma. Entre com este e-mail em {{platform_url}} (Google, LinkedIn ou código por e-mail).' || chr(10) || chr(10) || 'Link direto (vale por {{expires_in_minutes}} minutos): {{access_url}}' || chr(10) || chr(10) || 'Equipe GP',
    'en', 'Hi {{first_name}}!' || chr(10) || chr(10) || 'You have been registered at Núcleo IA & GP and already have access to the platform. Sign in with this email at {{platform_url}} (Google, LinkedIn or email code).' || chr(10) || chr(10) || 'Direct link (valid for {{expires_in_minutes}} minutes): {{access_url}}' || chr(10) || chr(10) || 'GP Team',
    'es', '¡Hola {{first_name}}!' || chr(10) || chr(10) || 'Usted fue registrado(a) en el Núcleo IA & GP y ya tiene acceso a la plataforma. Entre con este correo en {{platform_url}} (Google, LinkedIn o código por correo).' || chr(10) || chr(10) || 'Enlace directo (válido por {{expires_in_minutes}} minutos): {{access_url}}' || chr(10) || chr(10) || 'Equipo GP'
  ),
  'onboarding',
  jsonb_build_object(
    'first_name',         jsonb_build_object('type', 'text',   'required', true),
    'access_url',         jsonb_build_object('type', 'text',   'required', true),
    'platform_url',       jsonb_build_object('type', 'text',   'required', true),
    'expires_in_minutes', jsonb_build_object('type', 'number', 'required', true)
  )
)
ON CONFLICT (slug) DO UPDATE
  SET subject    = EXCLUDED.subject,
      body_html  = EXCLUDED.body_html,
      body_text  = EXCLUDED.body_text,
      variables  = EXCLUDED.variables,
      updated_at = now();
