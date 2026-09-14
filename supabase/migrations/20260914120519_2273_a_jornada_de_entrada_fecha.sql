-- #2273 — a jornada de entrada FECHA: o portal do token passa a falar a lingua do catalogo,
-- e passa a ter um caminho para dentro da plataforma em vez de um botao para tras de um login.
--
-- O QUE A MEDICAO DE 14/09 MOSTROU, e que muda o desenho que a #2273 propunha:
--
--   * 137 membros, 111 com conta. Na janela de 150 dias: 66, com 10 sem conta. Mas SEIS desses
--     dez sao `chapter_liaison` ou `guest` criados administrativamente — nunca tiveram
--     candidatura nem token, e a jornada de entrada nao passa por eles. Sobram QUATRO.
--   * A jornada NAO parou de funcionar. `members.auth_id.first_link` tem 68 eventos, o
--     `rotated_secondary` 14 e o `claim` self-service 2. Dos 27 que ficaram elegiveis ao
--     first_link desde 29/06, 25 ligaram. O zero de setembro e fila seca, nao defeito.
--   * 88% das contas nascem de OAuth (google 107, linkedin_oidc 31, azure 7) contra 23 de OTP.
--     A pessoa ja consegue criar conta sozinha. O que faltava era o portal dizer COM QUAL E-MAIL.
--
-- Por isso esta migration NAO cria um quarto mecanismo de identidade. Ela liga o portal aos tres
-- que ja funcionam, e fecha o ponto cego que nenhum deles cobre.
--
-- ⚠️ A ARMADILHA QUE DECIDE O DESENHO (secao 4 do handoff de 14/09): o reconhecimento liga conta
-- nova a membro pelo e-mail PRIMARIO DO MEMBRO. Se o acesso nascer com outro endereco, a pessoa
-- entra como ghost. E os dois enderecos divergem por caminhos diferentes — o da CANDIDATURA
-- envelhece sozinho (foi o que aconteceu com `c9c2058d`, corrigido em 14/09 03:34), o do MEMBRO e
-- o que o login consulta. Entao tudo aqui resolve o membro e le o primario DELE, nunca
-- `selection_applications.email`.
--
-- ⚠️ E o membro e resolvido pelo ENGAGEMENT antes do e-mail, porque o engagement e o vinculo
-- estrutural e o e-mail e o que envelhece. Medido em 105 candidaturas aprovadas: engagement
-- resolve 97, e-mail resolve 103, e os dois juntos resolvem 104. Por isso os DOIS, nessa ordem.

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 1. `_mask_email` — mostrar a caixa certa sem entregar o endereco
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- O portal e anonimo: quem tem o token ve a pagina. O token e a credencial, mas mascarar e
-- barato e o e-mail do MEMBRO pode ser um endereco que a pessoa nao usou na candidatura.
CREATE OR REPLACE FUNCTION public._mask_email(p_email text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
    WHEN p_email IS NULL OR position('@' in p_email) = 0 THEN NULL
    ELSE
      CASE WHEN length(split_part(p_email, '@', 1)) <= 1
           THEN left(split_part(p_email, '@', 1), 1) || '***'
           ELSE left(split_part(p_email, '@', 1), 1) || '***' || right(split_part(p_email, '@', 1), 1)
      END
      || '@'
      || left(split_part(p_email, '@', 2), 1) || '***.'
      || reverse(split_part(reverse(split_part(p_email, '@', 2)), '.', 1))
  END;
$function$;

REVOKE EXECUTE ON FUNCTION public._mask_email(text) FROM PUBLIC, anon, authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 2. `_portal_member_for_application` — o resolvedor unico (engagement, depois e-mail)
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Existe como funcao propria para que `consume_onboarding_token` e `request_portal_account_setup`
-- NAO tenham duas copias da mesma regra. Duas copias divergem, e a que diverge silenciosamente e
-- a que manda o e-mail para o endereco errado.
CREATE OR REPLACE FUNCTION public._portal_member_for_application(p_application_id uuid)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  -- (a) vinculo ESTRUTURAL: candidatura -> engagement -> person -> member. Imune ao e-mail velho.
  SELECT m.id INTO v_member_id
    FROM public.engagements e
    JOIN public.members m ON m.person_id = e.person_id
   WHERE e.selection_application_id = p_application_id
   ORDER BY e.created_at
   LIMIT 1;

  IF v_member_id IS NOT NULL THEN
    RETURN v_member_id;
  END IF;

  -- (b) fallback por e-mail. Alcanca as candidaturas aprovadas antes de o engagement existir
  -- (medido: 7 de 105 so resolvem por aqui).
  SELECT m.id INTO v_member_id
    FROM public.selection_applications sa
    JOIN public.members m ON lower(m.email) = lower(sa.email)
   WHERE sa.id = p_application_id
   LIMIT 1;

  RETURN v_member_id;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public._portal_member_for_application(uuid) FROM PUBLIC, anon, authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 3. DEFEITO A — `consume_onboarding_token` para de perguntar o rotulo a fonte errada
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- O portal resolvia o rotulo em `cycle.onboarding_steps`, o JSONB por ciclo, que esta em 0 e que
-- NUNCA conteve os passos do catalogo (a #2245 filtrou pelo catalogo e sobrou vazio porque so
-- havia as 5 chaves orfas). Todo passo caia no fallback `?? step.step_key` e a pessoa lia
-- `complete_profile`, `volunteer_term`, `first_meeting`.
--
-- O campo novo e `step_catalog`, ADITIVO: `cycle.onboarding_steps` continua no payload exatamente
-- como estava. Isso e de proposito — a RPC (banco) e o componente (worker) sao dois veiculos de
-- deploy, e trocar a FORMA de um campo que o componente vigente le faria a versao antiga
-- renderizar `[object Object]`, que e pior que a chave crua. Aditivo e seguro em qualquer ordem.
--
-- As tres linguas vao juntas e quem escolhe e o componente: o banco nao conhece o locale do
-- visitante, e um `p_lang` mudaria a assinatura e obrigaria DROP + CREATE de uma RPC que a pagina
-- SSR ja chama em producao.
CREATE OR REPLACE FUNCTION public.consume_onboarding_token(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_token_row onboarding_tokens%ROWTYPE;
  v_app selection_applications%ROWTYPE;
  v_cycle selection_cycles%ROWTYPE;
  v_progress jsonb;
  v_video_screenings jsonb;
  v_step_catalog jsonb;
  v_member_id uuid;
  v_member_auth_id uuid;
  v_primary_email text;
  v_result jsonb;
BEGIN
  UPDATE onboarding_tokens
     SET consumed_at = COALESCE(consumed_at, now()),
         last_accessed_at = now(),
         access_count = access_count + 1
   WHERE token = p_token
     AND expires_at > now()
  RETURNING * INTO v_token_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired token'
      USING ERRCODE = 'invalid_authorization_specification';
  END IF;

  IF v_token_row.source_type = 'pmi_application' THEN
    SELECT * INTO v_app
    FROM selection_applications
    WHERE id = v_token_row.source_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Token references missing application';
    END IF;

    SELECT * INTO v_cycle
    FROM selection_cycles
    WHERE id = v_app.cycle_id;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'step_key', op.step_key,
      'status', op.status,
      'completed_at', op.completed_at,
      'evidence_url', op.evidence_url,
      'notes', op.notes,
      'sla_deadline', op.sla_deadline
    ) ORDER BY op.created_at), '[]'::jsonb)
    INTO v_progress
    FROM onboarding_progress op
    WHERE op.application_id = v_app.id;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'pillar', vs.pillar,
      'question_index', vs.question_index,
      'status', vs.status,
      'uploaded_at', vs.uploaded_at
    ) ORDER BY vs.question_index, vs.created_at), '[]'::jsonb)
    INTO v_video_screenings
    FROM pmi_video_screenings vs
    WHERE vs.application_id = v_app.id;

    -- #2273 defeito A — o CATALOGO, que e onde os rotulos sempre estiveram.
    -- Vai inteiro, sem filtrar por papel: quem decide quais passos a pessoa tem e
    -- `onboarding_progress`, ja semeado. Filtrar aqui duplicaria a regra de elegibilidade em
    -- dois lugares, e a copia e que envelhece.
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'key', os.id,
      'step_order', os.step_order,
      'icon', os.icon,
      'is_required', os.is_required,
      'applies_to_role', os.applies_to_role,
      'label', jsonb_build_object(
        'pt-BR', os.label_pt, 'en-US', os.label_en, 'es-LATAM', os.label_es
      ),
      'description', jsonb_build_object(
        'pt-BR', os.description_pt, 'en-US', os.description_en, 'es-LATAM', os.description_es
      )
    ) ORDER BY os.step_order), '[]'::jsonb)
    INTO v_step_catalog
    FROM onboarding_steps os;

    -- #2273 defeito B — o estado de conta, para o portal poder dizer COM QUAL e-mail entrar.
    v_member_id := public._portal_member_for_application(v_app.id);
    IF v_member_id IS NOT NULL THEN
      SELECT m.auth_id,
             COALESCE(
               (SELECT me.email::text FROM public.member_emails me
                 WHERE me.member_id = m.id AND me.is_primary IS TRUE LIMIT 1),
               m.email
             )
        INTO v_member_auth_id, v_primary_email
      FROM public.members m WHERE m.id = v_member_id;
    END IF;

    v_result := jsonb_build_object(
      'source_type', 'pmi_application',
      'scopes', v_token_row.scopes,
      'application', jsonb_build_object(
        'id', v_app.id,
        'applicant_name', v_app.applicant_name,
        'email', v_app.email,
        'phone', v_app.phone,
        'linkedin_url', v_app.linkedin_url,
        'credly_url', v_app.credly_url,
        'role_applied', v_app.role_applied,
        'cycle_id', v_app.cycle_id,
        'has_consent', v_app.consent_ai_analysis_at IS NOT NULL
                       AND v_app.consent_ai_analysis_revoked_at IS NULL,
        'has_revoked', v_app.consent_ai_analysis_revoked_at IS NOT NULL,
        'has_voice_biometric_consent', v_app.consent_voice_biometric_at IS NOT NULL
                       AND v_app.consent_voice_biometric_revoked_at IS NULL,
        'has_voice_biometric_revoked', v_app.consent_voice_biometric_revoked_at IS NOT NULL,
        'status', v_app.status
      ),
      'cycle', jsonb_build_object(
        'id', v_cycle.id,
        'cycle_code', v_cycle.cycle_code,
        'title', v_cycle.title,
        'phase', v_cycle.phase,
        'onboarding_steps', v_cycle.onboarding_steps
      ),
      'step_catalog', v_step_catalog,
      'account_state', jsonb_build_object(
        'member_exists',     v_member_id IS NOT NULL,
        'has_account',       v_member_auth_id IS NOT NULL,
        'masked_email',      public._mask_email(v_primary_email),
        'can_request_setup', v_member_id IS NOT NULL
                             AND v_member_auth_id IS NULL
                             AND v_app.status = 'approved'
      ),
      'onboarding_progress', v_progress,
      'video_screenings', v_video_screenings,
      'token_metadata', jsonb_build_object(
        'access_count', v_token_row.access_count,
        'expires_at', v_token_row.expires_at,
        'first_access', v_token_row.consumed_at = v_token_row.last_accessed_at
      )
    );

  ELSIF v_token_row.source_type IN ('initiative_invitation', 'direct_assignment') THEN
    v_result := jsonb_build_object(
      'source_type', v_token_row.source_type,
      'scopes', v_token_row.scopes,
      'pending_implementation', true,
      'message', 'Esse fluxo ainda não está ativo. Aguarde comunicação.'
    );

  ELSE
    RAISE EXCEPTION 'Unknown source_type: %', v_token_row.source_type;
  END IF;

  RETURN v_result;
END;
$function$;

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 4. DEFEITO B — `request_portal_account_setup`: a segunda via, com o destinatario no servidor
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- O caminho PRIMARIO do portal e o OAuth que ja existe (88% das contas): o portal mostra o e-mail
-- certo e abre o modal de login. Esta RPC e a ALTERNATIVA, para quem nao tem Google/LinkedIn
-- naquele endereco.
--
-- Ela nao recebe e-mail nenhum por parametro, de proposito. Quem escolhe o destinatario e o
-- servidor, lendo o primario do MEMBRO — se o cliente pudesse escolher, a armadilha da secao 4
-- voltaria pela porta da frente e a pessoa nasceria ghost.
--
-- Anonima porque o portal e anonimo: o token de 32 bytes E a credencial. Sem token nao ha
-- resposta, entao nao ha enumeracao a proteger — mas ha caixa de entrada de terceiro a proteger,
-- e por isso o teto de 3 por hora por candidatura.
CREATE OR REPLACE FUNCTION public.request_portal_account_setup(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_token_row onboarding_tokens%ROWTYPE;
  v_app selection_applications%ROWTYPE;
  v_member_id uuid;
  v_member public.members%ROWTYPE;
  v_primary_email text;
  v_recent int;
  v_service_role_key text;
BEGIN
  -- Le o token SEM consumir: `consume_onboarding_token` incrementa `access_count` a cada carga da
  -- pagina, e essa contagem e o sinal que diz se a pessoa CLICOU no link. Um pedido de acesso nao
  -- e um clique no e-mail, e somar os dois apagaria a unica metrica de intencao que existe.
  SELECT * INTO v_token_row
    FROM public.onboarding_tokens
   WHERE token = p_token
     AND expires_at > now()
     AND source_type = 'pmi_application';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'state', 'invalid_or_expired');
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = v_token_row.source_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'state', 'invalid_or_expired');
  END IF;

  -- So para quem ja foi aprovado. Quem esta em avaliacao ainda nao tem lugar para entrar.
  IF v_app.status <> 'approved' THEN
    RETURN jsonb_build_object('success', false, 'state', 'not_approved');
  END IF;

  v_member_id := public._portal_member_for_application(v_app.id);
  IF v_member_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'state', 'no_member');
  END IF;

  SELECT * INTO v_member FROM public.members WHERE id = v_member_id;

  IF v_member.auth_id IS NOT NULL THEN
    -- Ja tem acesso: mandar link de criacao seria convidar a criar uma SEGUNDA identidade.
    RETURN jsonb_build_object(
      'success', false, 'state', 'already_linked',
      'masked_email', public._mask_email(v_member.email)
    );
  END IF;

  v_primary_email := COALESCE(
    (SELECT me.email::text FROM public.member_emails me
      WHERE me.member_id = v_member_id AND me.is_primary IS TRUE LIMIT 1),
    v_member.email
  );

  IF COALESCE(v_primary_email, '') = '' THEN
    RETURN jsonb_build_object('success', false, 'state', 'no_email');
  END IF;

  -- Teto por candidatura. A contagem sai do proprio audit, que e onde o pedido fica registrado —
  -- sem tabela nova para manter, e com o efeito colateral util de o pedido ser auditavel.
  SELECT count(*) INTO v_recent
    FROM public.admin_audit_log
   WHERE action = 'portal.account_setup_requested'
     AND target_id = v_app.id
     AND created_at > now() - interval '1 hour';

  IF v_recent >= 3 THEN
    RETURN jsonb_build_object('success', false, 'state', 'rate_limited');
  END IF;

  INSERT INTO public.admin_audit_log (
    actor_id, action, target_type, target_id, changes, metadata
  ) VALUES (
    v_member_id,
    'portal.account_setup_requested',
    'selection_application',
    v_app.id,
    jsonb_build_object(
      'member_id', v_member_id,
      'masked_email', public._mask_email(v_primary_email),
      'resolved_via', 'primary_member_email'
    ),
    jsonb_build_object('source', 'request_portal_account_setup', 'issue', 2273)
  );

  -- Despacho da EF, que e quem tem a Admin API para gerar o link de acesso. O Postgres nao
  -- consegue criar sessao de auth; e por isso que esta metade vive numa Edge Function.
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
        -- So o token do portal. A EF RE-RESOLVE tudo do zero: um payload que carregasse o e-mail
        -- seria um destinatario escolhido fora do servidor, que e exatamente o que esta RPC existe
        -- para impedir.
        body    := jsonb_build_object('portal_token', p_token)
      );
    ELSE
      RAISE NOTICE 'request_portal_account_setup: no service_role_key in vault, EF not dispatched';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'request_portal_account_setup dispatch failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'state', 'sent',
    'masked_email', public._mask_email(v_primary_email)
  );
END;
$function$;

-- O portal e anonimo: esta e uma das poucas RPCs que anon PRECISA alcancar.
GRANT EXECUTE ON FUNCTION public.request_portal_account_setup(text) TO anon, authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 5. O PONTO CEGO — `detect_unlinked_accounts`: o reconhecimento so existia no NAVEGADOR
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- `get_member_by_auth` (step 3) e `try_auto_link_ghost` fazem o first_link, e os dois so rodam
-- quando o navegador DA PESSOA chama o Nav. Quem cria a conta e nao volta ao site fica sem
-- vinculo indefinidamente, e nada no servidor percebe. Medido em 14/09: 2 pessoas nesse estado,
-- uma delas com login em 11/09 e o membro criado em 10/09 — elegivel, e nao ligada.
--
-- Este detector ALERTA, e nao liga. Ligar automaticamente no servidor reintroduziria justamente o
-- ramo que o P168 R3-a removeu do cliente depois do incidente de identidade: um match por e-mail
-- decidido sem ninguem olhando. Decisao do dono, 14/09.
CREATE OR REPLACE FUNCTION public.detect_unlinked_accounts()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp', 'auth'
AS $function$
DECLARE
  v_caller_id uuid;
  v_is_service boolean := (current_setting('request.jwt.claims', true)::jsonb->>'role') IS NOT DISTINCT FROM 'service_role';
  v_rows jsonb;
  v_count int;
BEGIN
  -- Service-role (cron) OU manage_platform. Nao e leitura publica: a lista e um mapa de pessoas
  -- que estao a um passo de entrar, e o e-mail sai mascarado mesmo para quem passa no portao.
  IF NOT v_is_service THEN
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform'::text) THEN
      RAISE EXCEPTION 'Unauthorized: requires manage_platform';
    END IF;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'member_id',     x.member_id,
           'masked_email',  public._mask_email(x.email),
           'member_since',  x.created_at,
           'account_since', x.auth_created_at,
           'last_sign_in',  x.last_sign_in_at,
           'member_status', x.member_status
         ) ORDER BY x.last_sign_in_at DESC NULLS LAST), '[]'::jsonb),
         count(*)
    INTO v_rows, v_count
  FROM (
    SELECT m.id AS member_id, m.email, m.created_at, m.member_status,
           u.created_at AS auth_created_at, u.last_sign_in_at
      FROM public.members m
      JOIN auth.users u
        ON lower(u.email) = lower(COALESCE(
             (SELECT me.email::text FROM public.member_emails me
               WHERE me.member_id = m.id AND me.is_primary IS TRUE LIMIT 1),
             m.email))
     WHERE m.auth_id IS NULL
       AND m.anonymized_at IS NULL
       AND NOT EXISTS (SELECT 1 FROM public.members m2 WHERE m2.auth_id = u.id)
       AND NOT (u.id = ANY(COALESCE(m.secondary_auth_ids, '{}'::uuid[])))
  ) x;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller_id, 'platform.unlinked_accounts_detected', 'platform', NULL,
    jsonb_build_object('count', v_count),
    jsonb_build_object('source', 'detect_unlinked_accounts', 'issue', 2273,
                       'via', CASE WHEN v_is_service THEN 'service_role' ELSE 'manage_platform' END)
  );

  RETURN jsonb_build_object('success', true, 'count', v_count, 'members', v_rows);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.detect_unlinked_accounts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.detect_unlinked_accounts() TO authenticated, service_role;

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 6. O template do e-mail da segunda via
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Molde do `pmi_welcome_with_token`, que e o que ja entrega (medido: `email.delivered` em 3s no
-- reenvio de 14/09). Sai por `campaign_send_one_off`, e nao por um fetch direto ao Resend, para
-- herdar supressao, idempotencia e metrica do caminho central.
INSERT INTO public.campaign_templates (name, slug, subject, body_html, body_text, category, variables)
VALUES (
  'Portal de onboarding — criar acesso à plataforma',
  'portal_account_setup',
  jsonb_build_object(
    'pt', 'Seu acesso à plataforma do Núcleo IA & GP',
    'en', 'Your access to the Núcleo IA & GP platform',
    'es', 'Su acceso a la plataforma del Núcleo IA & GP'
  ),
  jsonb_build_object(
    'pt', '<p>Olá <b>{{first_name}}</b>!</p><p>Você pediu, pelo portal de onboarding, um link para entrar na plataforma do Núcleo IA &amp; GP.</p><p><a href="{{access_url}}" style="background:#0066cc;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;">Entrar na plataforma</a></p><p><small>Este link vale por {{expires_in_minutes}} minutos e abre a sessão no endereço que está no seu cadastro. Se não foi você, ignore este e-mail.</small></p><p>Equipe GP</p>',
    'en', '<p>Hi <b>{{first_name}}</b>!</p><p>You requested a sign-in link from the onboarding portal of Núcleo IA &amp; GP.</p><p><a href="{{access_url}}" style="background:#0066cc;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;">Sign in</a></p><p><small>This link is valid for {{expires_in_minutes}} minutes and opens the session on the address registered in your record. If this was not you, ignore this email.</small></p><p>GP Team</p>',
    'es', '<p>¡Hola <b>{{first_name}}</b>!</p><p>Usted solicitó, desde el portal de onboarding, un enlace para entrar en la plataforma del Núcleo IA &amp; GP.</p><p><a href="{{access_url}}" style="background:#0066cc;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;">Entrar en la plataforma</a></p><p><small>Este enlace es válido por {{expires_in_minutes}} minutos y abre la sesión en la dirección registrada en su ficha. Si no fue usted, ignore este correo.</small></p><p>Equipo GP</p>'
  ),
  jsonb_build_object(
    'pt', 'Olá {{first_name}}!' || chr(10) || chr(10) || 'Link para entrar na plataforma: {{access_url}}' || chr(10) || chr(10) || 'Vale por {{expires_in_minutes}} minutos. Se não foi você, ignore.' || chr(10) || chr(10) || 'Equipe GP',
    'en', 'Hi {{first_name}}!' || chr(10) || chr(10) || 'Sign-in link: {{access_url}}' || chr(10) || chr(10) || 'Valid for {{expires_in_minutes}} minutes. If this was not you, ignore it.' || chr(10) || chr(10) || 'GP Team',
    'es', '¡Hola {{first_name}}!' || chr(10) || chr(10) || 'Enlace para entrar: {{access_url}}' || chr(10) || chr(10) || 'Válido por {{expires_in_minutes}} minutos. Si no fue usted, ignórelo.' || chr(10) || chr(10) || 'Equipo GP'
  ),
  'onboarding',
  jsonb_build_object(
    'first_name',         jsonb_build_object('type', 'text',   'required', true),
    'access_url',         jsonb_build_object('type', 'text',   'required', true),
    'expires_in_minutes', jsonb_build_object('type', 'number', 'required', true)
  )
)
ON CONFLICT (slug) DO UPDATE
  SET subject    = EXCLUDED.subject,
      body_html  = EXCLUDED.body_html,
      body_text  = EXCLUDED.body_text,
      variables  = EXCLUDED.variables,
      updated_at = now();

COMMENT ON FUNCTION public.consume_onboarding_token(text) IS
  '#2273 — devolve `step_catalog` (os rotulos vem do catalogo `onboarding_steps`, nao do JSONB por ciclo, que esta vazio e nunca os teve) e `account_state` (para o portal dizer com qual e-mail entrar). Ambos ADITIVOS: `cycle.onboarding_steps` segue no payload para a versao anterior do componente nao quebrar entre os dois deploys.';

COMMENT ON FUNCTION public.request_portal_account_setup(text) IS
  '#2273 — segunda via de acesso para candidatura approved, anonima pelo token do portal. NAO recebe e-mail por parametro: o destinatario e o primario do MEMBRO, resolvido no servidor. Teto de 3/hora por candidatura. Nao consome o token (access_count mede clique no e-mail, nao pedido de acesso).';

COMMENT ON FUNCTION public.detect_unlinked_accounts() IS
  '#2273 — alerta (nao liga) sobre membros sem auth_id que ja tem conta no proprio e-mail primario. O first_link so roda no navegador da pessoa; sem este detector, quem nao volta ao site fica ghost e ninguem percebe.';