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
-- Rollback: DROP das duas funções; DELETE do template 'avulso-corpo-livre' (se nenhum envio o usar) e da chave
--   campaign_one_off_daily_limit_per_sender.

-- ── (1) template e limite ─────────────────────────────────────────────────────
INSERT INTO public.campaign_templates (name, slug, subject, body_html, body_text, target_audience, category, theme, variables)
VALUES (
  'Mensagem avulsa (corpo livre)',
  'avulso-corpo-livre',
  '{"pt":"{{subject}}","en":"{{subject}}","es":"{{subject}}"}'::jsonb,
  jsonb_build_object(
    'pt', '{{content_html}}<p>Equipe do Núcleo IA &amp; GP</p><!--EXTERNO--><hr><p style="font-size:12px;color:#666">Você recebeu esta mensagem do Núcleo IA &amp; GP, programa de capítulos do PMI no Brasil, sob a responsabilidade do PMI Goiás (PMI-GO). Usamos o seu nome e e-mail só para este contato (legítimo interesse) e os guardamos por até 1 ano após o envio; depois, eles são anonimizados. O envio passa por um provedor de e-mail. Para não receber mais: <a href="{unsubscribe_url}">descadastrar</a>. Para exercer os seus direitos (LGPD, art. 18), responda a este e-mail ou escreva para dpo@pmigo.org.br. <a href="{platform.url}/privacy">Política de privacidade</a>.</p><!--/EXTERNO-->',
    'en', '{{content_html}}<p>The AI &amp; PM Research Hub team</p><!--EXTERNO--><hr><p style="font-size:12px;color:#666">You received this message from the AI &amp; PM Research Hub (Núcleo IA &amp; GP), a program of PMI chapters in Brazil, under the responsibility of PMI Goiás (PMI-GO). We use your name and e-mail only for this contact (legitimate interest) and keep them for up to 1 year after sending; after that, they are anonymized. The message goes through an e-mail provider. To stop receiving messages: <a href="{unsubscribe_url}">unsubscribe</a>. To exercise your rights under the Brazilian LGPD (art. 18), reply to this e-mail or write to dpo@pmigo.org.br. <a href="{platform.url}/privacy">Privacy policy</a>.</p><!--/EXTERNO-->',
    'es', '{{content_html}}<p>Equipo del Núcleo IA &amp; GP</p><!--EXTERNO--><hr><p style="font-size:12px;color:#666">Recibiste este mensaje del Núcleo IA &amp; GP, programa de capítulos del PMI en Brasil, bajo la responsabilidad del PMI Goiás (PMI-GO). Usamos tu nombre y correo solo para este contacto (interés legítimo) y los guardamos hasta 1 año después del envío; después, se anonimizan. El envío pasa por un proveedor de correo. Para no recibir más: <a href="{unsubscribe_url}">darte de baja</a>. Para ejercer tus derechos (LGPD de Brasil, art. 18), responde a este correo o escribe a dpo@pmigo.org.br. <a href="{platform.url}/privacy">Política de privacidad</a>.</p><!--/EXTERNO-->'
  ),
  jsonb_build_object(
    'pt', E'{{content_text}}\n\nEquipe do Núcleo IA & GP[[EXTERNO]]\n\n--\nVocê recebeu esta mensagem do Núcleo IA & GP, programa de capítulos do PMI no Brasil, sob a responsabilidade do PMI Goiás (PMI-GO). Usamos o seu nome e e-mail só para este contato (legítimo interesse) e os guardamos por até 1 ano após o envio; depois, eles são anonimizados. O envio passa por um provedor de e-mail. Para não receber mais: {unsubscribe_url}. Para exercer os seus direitos (LGPD, art. 18), responda a este e-mail ou escreva para dpo@pmigo.org.br. Política de privacidade: {platform.url}/privacy[[/EXTERNO]]',
    'en', E'{{content_text}}\n\nThe AI & PM Research Hub team[[EXTERNO]]\n\n--\nYou received this message from the AI & PM Research Hub (Núcleo IA & GP), a program of PMI chapters in Brazil, under the responsibility of PMI Goiás (PMI-GO). We use your name and e-mail only for this contact (legitimate interest) and keep them for up to 1 year after sending; after that, they are anonymized. The message goes through an e-mail provider. To stop receiving messages: {unsubscribe_url}. To exercise your rights under the Brazilian LGPD (art. 18), reply to this e-mail or write to dpo@pmigo.org.br. Privacy policy: {platform.url}/privacy[[/EXTERNO]]',
    'es', E'{{content_text}}\n\nEquipo del Núcleo IA & GP[[EXTERNO]]\n\n--\nRecibiste este mensaje del Núcleo IA & GP, programa de capítulos del PMI en Brasil, bajo la responsabilidad del PMI Goiás (PMI-GO). Usamos tu nombre y correo solo para este contacto (interés legítimo) y los guardamos hasta 1 año después del envío; después, se anonimizan. El envío pasa por un proveedor de correo. Para no recibir más: {unsubscribe_url}. Para ejercer tus derechos (LGPD de Brasil, art. 18), responde a este correo o escribe a dpo@pmigo.org.br. Política de privacidad: {platform.url}/privacy[[/EXTERNO]]'
  ),
  '{"all": false, "roles": [], "chapters": [], "designations": []}'::jsonb,
  'operational',
  'comunicacao',
  '{"subject": {"type": "text", "required": true}, "body": {"type": "text", "required": true}}'::jsonb
)
ON CONFLICT (slug) DO NOTHING;

INSERT INTO public.platform_settings (key, value, description) VALUES
  ('campaign_one_off_daily_limit_per_sender', to_jsonb(30),
   '#2586: quantas mensagens avulsas de corpo livre uma pessoa da gestão envia por dia (cada uma a um destinatário).')
ON CONFLICT (key) DO NOTHING;

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
    SELECT m.id, m.name INTO v_member_id, v_name FROM public.members m WHERE m.id = p_member_id;
    IF v_member_id IS NULL THEN RAISE EXCEPTION 'Member not found' USING ERRCODE = 'no_data_found'; END IF;
    v_kind := 'member';
  ELSIF p_application_id IS NOT NULL THEN
    SELECT lower(btrim(a.email)), COALESCE(NULLIF(btrim(a.applicant_name), ''), a.first_name)
      INTO v_email, v_name
    FROM public.selection_applications a WHERE a.id = p_application_id AND a.anonymized_at IS NULL;
    IF v_email IS NULL THEN RAISE EXCEPTION 'Application not found' USING ERRCODE = 'no_data_found'; END IF;
    v_kind := 'application';
  ELSE
    v_email := lower(btrim(p_email));
    v_name := NULLIF(btrim(p_name), '');
    v_kind := 'external';
  END IF;

  IF v_email IS NOT NULL THEN
    IF v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' OR v_email ~* c_reserved_domain THEN
      RAISE EXCEPTION 'Invalid or reserved e-mail domain' USING ERRCODE = 'check_violation';
    END IF;
    -- e-mail de membro vira o membro: entra no limite por pessoa e no histórico dele
    SELECT m.id, m.name INTO v_member_id, v_name
    FROM public.members m
    WHERE lower(m.email) = v_email
       OR EXISTS (SELECT 1 FROM unnest(m.secondary_emails) se WHERE lower(se) = v_email)
    ORDER BY m.is_active DESC, m.created_at
    LIMIT 1;
    IF v_member_id IS NOT NULL THEN
      v_email := NULL;
      v_kind := 'member';
    ELSIF v_kind = 'external' THEN
      v_person_id := public._external_person_upsert(v_email, v_name, 'campaign_one_off', v_send_id, current_date + 365);
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
          jsonb_build_object('recipient_kind', v_kind, 'theme', p_theme, 'member_id', v_member_id),
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
  v_caller uuid;
  v_result jsonb;
BEGIN
  SELECT m.id INTO v_caller FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller IS NULL OR NOT (public.can_by_member(v_caller, 'manage_member')
                              OR public.can_by_member(v_caller, 'manage_platform')) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member or manage_platform' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(x) ORDER BY x.created_at DESC), '[]'::jsonb) INTO v_result
  FROM (
    SELECT cs.id AS send_id,
           cs.created_at,
           cs.sent_at,
           COALESCE(cs.theme, ct.theme) AS theme,
           ct.slug AS template_slug,
           CASE WHEN cs.audience_filter->>'freeform' = 'true'
                THEN cs.audience_filter->'variables'->>'subject'
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
                   AND body_html->>'pt' LIKE '%{{content_html}}%<!--EXTERNO-->%dpo@pmigo.org.br%<!--/EXTERNO-->%'
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
