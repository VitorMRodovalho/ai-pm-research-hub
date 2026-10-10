-- #2586, fatia B: envio avulso de corpo livre pelo admin, rastreável, e histórico de comunicação por pessoa.
-- Depende da fatia A (campaign_themes, campaign_sends.theme, campaign_recipients.person_id, _external_person_upsert).
--
-- Decisões do GP (09/10/2026), registradas na #2586:
--   * envio avulso a UMA pessoa não precisa de segunda aprovação; registra quem enviou (approved_by = sent_by);
--   * o tema é obrigatório (taxonomia da fatia A); o reply-to sai do tema ou do padrão da plataforma (EF);
--   * e-mail externo: pessoa por _external_person_upsert, guarda de envio + 1 ano.
--
-- (1) Template 'avulso-corpo-livre'. O corpo digitado não entra cru no HTML: a EF (send-campaign, função pura
--     _shared/freeform-message.ts) escapa e quebra em parágrafos. O bloco <!--EXTERNO--> é o aviso de
--     privacidade (art. 9 da LGPD), que só o destinatário externo recebe. TEXTO DO AVISO SUJEITO À APROVAÇÃO
--     DO GP antes do apply.
-- (2) admin_send_one_off_message: manage_platform (o mesmo portão de admin_send_campaign). Destinatário: um membro,
--     uma candidatura ou um e-mail; e-mail que é de membro vira o membro (entra no limite por pessoa e no
--     histórico dele). Domínio reservado (example, test, invalid, localhost) é recusado. Limite por quem envia,
--     por dia, em platform_settings. Tudo continua sujeito ao teto diário do hub, ao limite de 1 e-mail por
--     membro por dia e à supressão (EF, #2580 e #2130).
-- (3) get_member_communications: o que o membro recebeu, quando, tema, assunto e estado (entregue, aberto,
--     clicado, bounce, reclamação, suprimido). Gate: manage_member ou manage_platform (o mesmo critério de
--     get_application_communications). Não devolve corpo de mensagem.
--
-- Revisão do conselho (09-10/10/2026): nome que se perdia no SELECT INTO; e-mail com validação estrita (um
-- "x<alvo@dominio>" passaria pela supressão); limite por endereço externo e trava por quem envia; endereço suprimido
-- é recusado ANTES de criar o envio, com aviso; descadastro conta só para externo (a mensagem da gestão a um membro
-- é administrativa, e o membro não recebe o link); assunto no histórico só para manage_platform; auditoria com a
-- pessoa; índices do limite e do histórico.
--
-- Rollback: DROP das duas funções; DELETE do template 'avulso-corpo-livre' (se nenhum envio o usar) e da chave
--   campaign_one_off_daily_limit_per_sender.

-- ── (1) template e limite ─────────────────────────────────────────────────────
INSERT INTO public.campaign_templates (name, slug, subject, body_html, body_text, target_audience, category, theme, variables)
VALUES (
  'Mensagem avulsa (corpo livre)',
  'avulso-corpo-livre',
  '{"pt":"{{subject}}","en":"{{subject}}","es":"{{subject}}"}'::jsonb,
  jsonb_build_object(
    'pt', '{{content_html}}<p>Equipe do Núcleo IA &amp; GP</p><!--EXTERNO--><hr><p style="font-size:12px;color:#555;margin:0 0 4px">Você recebeu esta mensagem do Núcleo IA &amp; GP, programa de capítulos do PMI no Brasil. Controlador: PMI Goiás (PMI-GO).</p><p style="font-size:12px;color:#555;margin:0 0 4px">Usamos o seu nome e e-mail só para este contato (legítimo interesse), com envio por um provedor de e-mail, e os guardamos por até 1 ano; depois, eles são anonimizados.</p><p style="font-size:12px;color:#555;margin:0">Não quer receber mais mensagens assim? <a href="{unsubscribe_url}">Descadastre-se</a>. Para exercer os seus direitos (LGPD, art. 18), responda a este e-mail ou escreva para dpo@pmigo.org.br. <a href="{platform.url}/privacy">Política de privacidade</a>.</p><!--/EXTERNO-->',

    'en', '{{content_html}}<p>The AI &amp; PM Research Hub team</p><!--EXTERNO--><hr><p style="font-size:12px;color:#555;margin:0 0 4px">You received this message from the AI &amp; PM Research Hub (Núcleo IA &amp; GP), a program of PMI chapters in Brazil. Controller: PMI Goiás (PMI-GO).</p><p style="font-size:12px;color:#555;margin:0 0 4px">We use your name and e-mail only for this contact (legitimate interest), sent through an e-mail provider, and keep them for up to 1 year; after that, they are anonymized.</p><p style="font-size:12px;color:#555;margin:0">Don’t want messages like this? <a href="{unsubscribe_url}">Unsubscribe</a>. To exercise your rights under the Brazilian LGPD (art. 18), reply to this e-mail or write to dpo@pmigo.org.br. <a href="{platform.url}/privacy">Privacy policy</a>.</p><!--/EXTERNO-->',

    'es', '{{content_html}}<p>Equipo del Núcleo IA &amp; GP</p><!--EXTERNO--><hr><p style="font-size:12px;color:#555;margin:0 0 4px">Recibiste este mensaje del Núcleo IA &amp; GP, programa de capítulos del PMI en Brasil. Responsable: PMI Goiás (PMI-GO).</p><p style="font-size:12px;color:#555;margin:0 0 4px">Usamos tu nombre y correo solo para este contacto (interés legítimo), con envío por un proveedor de correo, y los guardamos hasta 1 año; después, se anonimizan.</p><p style="font-size:12px;color:#555;margin:0">¿No quieres recibir más mensajes así? <a href="{unsubscribe_url}">Darte de baja</a>. Para ejercer tus derechos (LGPD de Brasil, art. 18), responde a este correo o escribe a dpo@pmigo.org.br. <a href="{platform.url}/privacy">Política de privacidad</a>.</p><!--/EXTERNO-->'
  ),
  jsonb_build_object(
    'pt', E'{{content_text}}\n\nEquipe do Núcleo IA & GP[[EXTERNO]]\n\n--\nVocê recebeu esta mensagem do Núcleo IA & GP, programa de capítulos do PMI no Brasil. Controlador: PMI Goiás (PMI-GO).\nUsamos o seu nome e e-mail só para este contato (legítimo interesse), com envio por um provedor de e-mail, e os guardamos por até 1 ano; depois, eles são anonimizados.\nNão quer receber mais mensagens assim? {unsubscribe_url}\nPara exercer os seus direitos (LGPD, art. 18), responda a este e-mail ou escreva para dpo@pmigo.org.br. Política de privacidade: {platform.url}/privacy[[/EXTERNO]]',

    'en', E'{{content_text}}\n\nThe AI & PM Research Hub team[[EXTERNO]]\n\n--\nYou received this message from the AI & PM Research Hub (Núcleo IA & GP), a program of PMI chapters in Brazil. Controller: PMI Goiás (PMI-GO).\nWe use your name and e-mail only for this contact (legitimate interest), sent through an e-mail provider, and keep them for up to 1 year; after that, they are anonymized.\nDon’t want messages like this? {unsubscribe_url}\nTo exercise your rights under the Brazilian LGPD (art. 18), reply to this e-mail or write to dpo@pmigo.org.br. Privacy policy: {platform.url}/privacy[[/EXTERNO]]',

    'es', E'{{content_text}}\n\nEquipo del Núcleo IA & GP[[EXTERNO]]\n\n--\nRecibiste este mensaje del Núcleo IA & GP, programa de capítulos del PMI en Brasil. Responsable: PMI Goiás (PMI-GO).\nUsamos tu nombre y correo solo para este contacto (interés legítimo), con envío por un proveedor de correo, y los guardamos hasta 1 año; después, se anonimizan.\n¿No quieres recibir más mensajes así? {unsubscribe_url}\nPara ejercer tus derechos (LGPD de Brasil, art. 18), responde a este correo o escribe a dpo@pmigo.org.br. Política de privacidad: {platform.url}/privacy[[/EXTERNO]]'
  ),
  '{"all": false, "roles": [], "chapters": [], "designations": []}'::jsonb,
  'operational',
  'comunicacao',
  '{"subject": {"type": "text", "required": true}, "body": {"type": "text", "required": true}}'::jsonb
)
ON CONFLICT (slug) DO NOTHING;

INSERT INTO public.platform_settings (key, value, description) VALUES
  ('campaign_one_off_daily_limit_per_sender', to_jsonb(30),
   '#2586: quantas mensagens avulsas de corpo livre uma pessoa da gestão envia por dia (cada uma a um destinatário).'),
  ('campaign_one_off_external_limits', '{"per_day": 1, "per_30_days": 3}'::jsonb,
   '#2586: quantas mensagens avulsas um mesmo endereço EXTERNO recebe por dia e em 30 dias, somando quem envia.')
ON CONFLICT (key) DO NOTHING;

-- o limite por quem envia e o histórico por membro leem estas colunas
CREATE INDEX IF NOT EXISTS idx_campaign_sends_sender_created ON public.campaign_sends (sent_by, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_campaign_recipients_member ON public.campaign_recipients (member_id) WHERE member_id IS NOT NULL;

-- ── (2) envio avulso ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_send_one_off_message(
  p_member_id uuid DEFAULT NULL,
  p_application_id uuid DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_name text DEFAULT NULL,
  p_theme text DEFAULT NULL,
  p_subject text DEFAULT NULL,
  p_body text DEFAULT NULL,
  p_language text DEFAULT 'pt-BR'
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  c_reserved_domain constant text := '@([^@]*\.)?(example\.(com|org|net)|test|invalid|localhost)$';
  v_caller      uuid;
  v_limit       integer;
  v_sent_today  integer;
  v_template_id uuid;
  v_send_id     uuid := gen_random_uuid();
  v_lang        text;
  v_kind        text;
  v_member_id   uuid;
  v_email       text;
  v_name        text;
  v_person_id   uuid;
  v_key         text;
  v_request_id  bigint;
  v_m_id        uuid;
  v_m_name      text;
  v_m_email     text;
  v_ext_limits  jsonb;
  v_ext_day     integer;
  v_ext_month   integer;
BEGIN
  SELECT m.id INTO v_caller FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller IS NULL OR NOT public.can_by_member(v_caller, 'manage_platform') THEN
    RAISE EXCEPTION 'Forbidden: only management can send one-off messages' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF ((p_member_id IS NOT NULL)::int + (p_application_id IS NOT NULL)::int + (NULLIF(btrim(p_email), '') IS NOT NULL)::int) <> 1 THEN
    RAISE EXCEPTION 'Exactly one recipient: member, application or e-mail' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.campaign_themes t WHERE t.slug = p_theme AND t.is_active) THEN
    RAISE EXCEPTION 'Unknown or inactive theme: %', p_theme USING ERRCODE = 'check_violation';
  END IF;
  IF length(btrim(coalesce(p_subject, ''))) NOT BETWEEN 1 AND 200 THEN
    RAISE EXCEPTION 'Subject must have 1 to 200 characters' USING ERRCODE = 'check_violation';
  END IF;
  IF length(btrim(coalesce(p_body, ''))) NOT BETWEEN 1 AND 10000 THEN
    RAISE EXCEPTION 'Body must have 1 to 10000 characters' USING ERRCODE = 'check_violation';
  END IF;

  -- trava por quem envia: duas chamadas simultâneas não passam juntas do limite
  PERFORM pg_advisory_xact_lock(hashtext('one_off_sender:' || v_caller::text));
  v_limit := COALESCE((SELECT (s.value #>> '{}')::integer FROM public.platform_settings s
                       WHERE s.key = 'campaign_one_off_daily_limit_per_sender'), 30);
  SELECT count(*) INTO v_sent_today FROM public.campaign_sends cs
  WHERE cs.sent_by = v_caller AND cs.created_at > now() - interval '1 day'
    AND cs.audience_filter->>'source' = 'admin_one_off';
  IF v_sent_today >= v_limit THEN
    RAISE EXCEPTION 'Daily limit of % one-off messages reached', v_limit USING ERRCODE = 'check_violation';
  END IF;

  -- destinatário
  IF p_member_id IS NOT NULL THEN
    SELECT m.id, m.name, lower(btrim(m.email)) INTO v_member_id, v_name, v_m_email FROM public.members m WHERE m.id = p_member_id;
    IF v_member_id IS NULL THEN RAISE EXCEPTION 'Member not found' USING ERRCODE = 'no_data_found'; END IF;
    IF v_m_email IS NULL OR v_m_email = '' THEN
      RAISE EXCEPTION 'Member has no e-mail' USING ERRCODE = 'check_violation';
    END IF;
    v_kind := 'member';
  ELSIF p_application_id IS NOT NULL THEN
    SELECT lower(btrim(a.email)), COALESCE(NULLIF(btrim(a.applicant_name), ''), a.first_name)
      INTO v_email, v_name
    FROM public.selection_applications a WHERE a.id = p_application_id AND a.anonymized_at IS NULL;
    IF v_email IS NULL THEN RAISE EXCEPTION 'Application not found' USING ERRCODE = 'no_data_found'; END IF;
    v_kind := 'application';
  ELSE
    v_email := lower(btrim(p_email));
    -- nome digitado: sem caracteres de controle e com no máximo 120 caracteres
    v_name := NULLIF(left(btrim(regexp_replace(coalesce(p_name, ''), '[[:cntrl:]]', '', 'g')), 120), '');
    v_kind := 'external';
  END IF;

  IF v_email IS NOT NULL THEN
    -- estrito: um endereço com "<", vírgula ou aspas escaparia da supressão (o provedor leria outro destinatário)
    IF length(v_email) > 254 OR v_email !~ '^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)+$' OR v_email ~* c_reserved_domain THEN
      RAISE EXCEPTION 'Invalid or reserved e-mail address' USING ERRCODE = 'check_violation';
    END IF;
    -- e-mail de membro vira o membro: entra no limite por pessoa e no histórico dele. Variáveis próprias: um
    -- SELECT INTO sem linha zera os alvos, e o nome digitado ou da candidatura se perderia.
    SELECT m.id, m.name, lower(btrim(m.email)) INTO v_m_id, v_m_name, v_m_email
    FROM public.members m
    WHERE lower(m.email) = v_email
       OR EXISTS (SELECT 1 FROM unnest(m.secondary_emails) se WHERE lower(se) = v_email)
    ORDER BY m.is_active DESC, m.created_at
    LIMIT 1;
    IF v_m_id IS NOT NULL THEN
      v_member_id := v_m_id;
      v_name := v_m_name;
      v_email := NULL;
      v_kind := 'member';
    ELSIF v_kind = 'external' THEN
      v_person_id := public._external_person_upsert(v_email, v_name, 'campaign_one_off', v_send_id, current_date + 365);
    END IF;
  END IF;

  -- endereço suprimido (reclamação, bounce permanente, supressão do provedor; e, para externo, o descadastro)
  -- é recusado aqui, antes de existir envio: a gestão fica sabendo na hora, e não por um "na fila" eterno
  IF cardinality(public.email_suppressed_among(ARRAY[COALESCE(v_email, v_m_email)], v_member_id IS NULL)) > 0 THEN
    RAISE EXCEPTION 'Recipient address is suppressed' USING ERRCODE = 'check_violation';
  END IF;

  -- limite por endereço EXTERNO, somando quem envia
  IF v_member_id IS NULL THEN
    v_ext_limits := COALESCE((SELECT s.value FROM public.platform_settings s WHERE s.key = 'campaign_one_off_external_limits'),
                             '{"per_day": 1, "per_30_days": 3}'::jsonb);
    SELECT count(*) FILTER (WHERE cs.created_at > now() - interval '1 day'),
           count(*) FILTER (WHERE cs.created_at > now() - interval '30 days')
      INTO v_ext_day, v_ext_month
    FROM public.campaign_recipients cr
    JOIN public.campaign_sends cs ON cs.id = cr.send_id
    WHERE lower(cr.external_email) = v_email AND cs.audience_filter->>'source' = 'admin_one_off';
    IF v_ext_day >= COALESCE((v_ext_limits->>'per_day')::int, 1)
       OR v_ext_month >= COALESCE((v_ext_limits->>'per_30_days')::int, 3) THEN
      RAISE EXCEPTION 'Per-address limit reached for this external e-mail' USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  SELECT t.id INTO v_template_id FROM public.campaign_templates t WHERE t.slug = 'avulso-corpo-livre';
  IF v_template_id IS NULL THEN RAISE EXCEPTION 'Template avulso-corpo-livre missing'; END IF;
  v_lang := public.normalize_platform_language(COALESCE(NULLIF(btrim(p_language), ''), 'pt-BR'));

  -- uma pessoa só: sem segunda aprovação (decisão do GP); quem enviou fica registrado como quem aprovou
  INSERT INTO public.campaign_sends (id, template_id, sent_by, approved_by, approved_at, audience_filter,
                                     status, recipient_count, theme)
  VALUES (v_send_id, v_template_id, v_caller, v_caller, now(),
          jsonb_build_object('type', 'transactional', 'one_off', true, 'freeform', true,
                             'source', 'admin_one_off', 'recipient_kind', v_kind,
                             'variables', jsonb_build_object('subject', btrim(p_subject), 'body', p_body)),
          'pending_delivery', 1, p_theme);

  INSERT INTO public.campaign_recipients (send_id, member_id, external_email, external_name, person_id, language)
  VALUES (v_send_id, v_member_id, v_email, CASE WHEN v_member_id IS NULL THEN v_name END, v_person_id, v_lang);

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (v_caller, 'campaign.one_off_sent', 'campaign_send', v_send_id,
          jsonb_build_object('recipient_kind', v_kind, 'theme', p_theme, 'member_id', v_member_id, 'person_id', v_person_id),
          jsonb_build_object('source', 'admin_send_one_off_message'));

  -- despacho assíncrono, como campaign_send_one_off: falha aqui deixa o envio pending_delivery para o cron
  BEGIN
    SELECT ds.decrypted_secret INTO v_key FROM vault.decrypted_secrets ds WHERE ds.name = 'service_role_key' LIMIT 1;
    IF v_key IS NOT NULL THEN
      SELECT net.http_post(
        url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/send-campaign',
        body := jsonb_build_object('send_id', v_send_id),
        headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key)
      ) INTO v_request_id;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'send-campaign dispatch failed: % (send_id=%)', SQLERRM, v_send_id;
  END;

  -- não devolve nome nem e-mail resolvido: só o tipo (o upsert não verifica identidade)
  RETURN jsonb_build_object('send_id', v_send_id, 'recipient_kind', v_kind, 'status', 'pending_delivery');
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_send_one_off_message(uuid, uuid, text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_send_one_off_message(uuid, uuid, text, text, text, text, text, text) TO authenticated, service_role;

-- ── (3) histórico por pessoa ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_member_communications(p_member_id uuid, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller   uuid;
  v_platform boolean;
  v_result   jsonb;
BEGIN
  SELECT m.id INTO v_caller FROM public.members m WHERE m.auth_id = auth.uid();
  v_platform := v_caller IS NOT NULL AND public.can_by_member(v_caller, 'manage_platform');
  IF v_caller IS NULL OR NOT (public.can_by_member(v_caller, 'manage_member') OR v_platform) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member or manage_platform' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(x) ORDER BY x.created_at DESC), '[]'::jsonb) INTO v_result
  FROM (
    SELECT cs.id AS send_id,
           cs.created_at,
           cs.sent_at,
           COALESCE(cs.theme, ct.theme) AS theme,
           ct.slug AS template_slug,
           -- o assunto digitado pela gestão pode ser sensível: só manage_platform o vê
           CASE WHEN cs.audience_filter->>'freeform' = 'true'
                THEN CASE WHEN v_platform THEN cs.audience_filter->'variables'->>'subject' END
                ELSE ct.subject->>'pt' END AS subject,
           cs.audience_filter->>'source' AS source,
           cs.status AS send_status,
           cr.delivered, cr.delivered_at, cr.first_opened_at, cr.open_count, cr.clicked_at, cr.click_count,
           cr.bounce_type, cr.bounced_at, cr.complained_at, cr.suppressed_at, cr.unsubscribed, cr.deferred_until
    FROM public.campaign_recipients cr
    JOIN public.campaign_sends cs ON cs.id = cr.send_id
    JOIN public.campaign_templates ct ON ct.id = cs.template_id
    WHERE cr.member_id = p_member_id
    ORDER BY cs.created_at DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500)
  ) x;

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_member_communications(uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_member_communications(uuid, integer) TO authenticated, service_role;

-- ── pós-condição ──────────────────────────────────────────────────────────────
DO $postcondition$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.campaign_templates
                 WHERE slug = 'avulso-corpo-livre' AND theme = 'comunicacao'
                   AND body_html->>'pt' LIKE '%{{content_html}}%<!--EXTERNO-->%' || 'dpo@pmigo.org.br' || '%<!--/EXTERNO-->%'
                   AND body_text->>'pt' LIKE '%{{content_text}}%[[EXTERNO]]%[[/EXTERNO]]%') THEN
    RAISE EXCEPTION '#2586: template avulso-corpo-livre ausente ou sem o bloco do aviso externo';
  END IF;
  IF has_function_privilege('anon', 'public.admin_send_one_off_message(uuid, uuid, text, text, text, text, text, text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.get_member_communications(uuid, integer)', 'EXECUTE') THEN
    RAISE EXCEPTION '#2586: anon executa uma das funções novas';
  END IF;
END
$postcondition$;

NOTIFY pgrst, 'reload schema';
