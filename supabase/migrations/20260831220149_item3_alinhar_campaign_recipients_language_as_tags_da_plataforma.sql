-- =====================================================================
-- item 3 — alinhar campaign_recipients.language as tags da plataforma
-- Timestamp DELIBERADAMENTE EM ABERTO: quem aplica escolhe (> head atual).
--
-- Por que nao e so "UPDATE + DEFAULT + CHECK":
--   os 2 caminhos de escrita gravam SUBTAG NUA (2 letras). Um CHECK nas 3
--   tags completas reprovaria o proximo envio com contato externo — um caminho
--   que, medido, NUNCA produziu linha em 5,5 meses. Por isso as funcoes
--   NORMALIZAM na entrada, em vez de so trocar o literal: o banco passa a se
--   defender sozinho, independente da ordem de deploy do frontend.
--
-- Superficies desta migracao: helper + 2 funcoes + dado + DEFAULT + CHECK.
-- Superficies FORA dela (frontend/EF, PR separada, deploy ANTES desta):
--   supabase/functions/send-campaign/index.ts:146-147
--   src/pages/admin/campaigns.astro:610
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. helper canonico: uma unica definicao de "qual e a tag da plataforma"
--    IMMUTABLE (so depende da entrada) — usavel em CHECK, indice e default.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.normalize_platform_language(p_lang text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $normalize_platform_language$
  SELECT CASE
           WHEN p_lang IS NULL          THEN 'pt-BR'
           WHEN lower(p_lang) LIKE 'en%' THEN 'en-US'
           WHEN lower(p_lang) LIKE 'es%' THEN 'es-LATAM'
           ELSE 'pt-BR'
         END;
$normalize_platform_language$;

COMMENT ON FUNCTION public.normalize_platform_language(text) IS
  'Mapeia qualquer entrada de idioma (subtag nua, tag completa, variante regional, NULL) para uma das 3 tags da plataforma: pt-BR / en-US / es-LATAM. Fallback = pt-BR (o mesmo que o caminho de render ja fazia no ELSE). Fonte unica desse mapa.';

-- ---------------------------------------------------------------------
-- 2. admin_send_campaign — corpo VIVO (md5 92663761d6f1ec8c8f5c7c0ddd5b92a9)
--    com 2 trocas: tag completa no ramo de membro; normalizacao no externo.
--    Atributos preservados na integra (VOLATILE / SECDEF / search_path):
--    CREATE OR REPLACE reconstroi a funcao do que voce DECLARA.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_send_campaign(p_template_id uuid, p_audience_filter jsonb DEFAULT '{}'::jsonb, p_scheduled_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_external_contacts jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_send_id uuid;
  v_count int := 0;
  v_ext_count int := 0;
  v_skipped_reserved int := 0;
  v_sends_last_hour int;
  v_sends_last_day int;
  v_member record;
  v_tmpl record;
  v_roles text[];
  v_desigs text[];
  v_chapters text[];
  v_all boolean;
  v_include_inactive boolean;
  v_ext record;
  v_ext_email text;
  -- RFC 2606 / RFC 6761 reserved domains: mail here can never reach a person.
  c_reserved_domain constant text := '@([^@]*\.)?(example\.(com|org|net)|test|invalid|localhost)$';
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Forbidden: only GP/DM can send campaigns';
  END IF;

  SELECT COUNT(*) INTO v_sends_last_hour FROM public.campaign_sends
  WHERE sent_by = v_caller_id AND created_at > now() - interval '1 hour' AND status NOT IN ('draft','failed');
  IF v_sends_last_hour >= 1 THEN RAISE EXCEPTION 'Rate limit: max 1 campaign per hour'; END IF;

  SELECT COUNT(*) INTO v_sends_last_day FROM public.campaign_sends
  WHERE sent_by = v_caller_id AND created_at > now() - interval '1 day' AND status NOT IN ('draft','failed');
  IF v_sends_last_day >= 3 THEN RAISE EXCEPTION 'Rate limit: max 3 campaigns per day'; END IF;

  SELECT * INTO v_tmpl FROM public.campaign_templates WHERE id = p_template_id;
  IF v_tmpl IS NULL THEN RAISE EXCEPTION 'Template not found'; END IF;

  v_roles := ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_audience_filter->'roles', '[]'::jsonb)));
  v_desigs := ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_audience_filter->'designations', '[]'::jsonb)));
  v_chapters := ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_audience_filter->'chapters', '[]'::jsonb)));
  v_all := COALESCE((p_audience_filter->>'all')::boolean, false);
  v_include_inactive := COALESCE((p_audience_filter->>'include_inactive')::boolean, false);

  INSERT INTO public.campaign_sends (id, template_id, sent_by, audience_filter, status, scheduled_at)
  VALUES (gen_random_uuid(), p_template_id, v_caller_id, p_audience_filter,
          CASE WHEN p_scheduled_at IS NOT NULL THEN 'scheduled' ELSE 'pending_delivery' END, p_scheduled_at)
  RETURNING id INTO v_send_id;

  FOR v_member IN
    SELECT m.id, 'pt-BR' AS lang
    FROM public.members m
    WHERE m.email IS NOT NULL
      AND m.email !~* c_reserved_domain
      -- dimensão 1: atividade. include_inactive AMPLIA, nunca substitui a dimensão 2.
      AND (
        (m.is_active = true AND m.current_cycle_active = true)
        OR (v_include_inactive AND (m.is_active = false OR m.current_cycle_active = false))
      )
      -- dimensão 2: segmento. Sem `all` e sem lista alguma, ninguém é selecionado (decisão (a)).
      AND (
        v_all
        OR (array_length(v_roles, 1) > 0 AND m.operational_role = ANY(v_roles))
        OR (array_length(v_desigs, 1) > 0 AND m.designations && v_desigs)
        OR (array_length(v_chapters, 1) > 0 AND m.chapter = ANY(v_chapters))
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.campaign_recipients cr2
        JOIN public.campaign_sends cs2 ON cs2.id = cr2.send_id
        WHERE cr2.member_id = m.id AND cr2.unsubscribed = true
      )
  LOOP
    INSERT INTO public.campaign_recipients (send_id, member_id, language)
    VALUES (v_send_id, v_member.id, v_member.lang);
    v_count := v_count + 1;
  END LOOP;

  FOR v_ext IN SELECT * FROM jsonb_array_elements(p_external_contacts)
  LOOP
    v_ext_email := v_ext.value->>'email';
    IF v_ext_email IS NULL OR v_ext_email ~* c_reserved_domain THEN
      v_skipped_reserved := v_skipped_reserved + 1;
      CONTINUE;
    END IF;
    INSERT INTO public.campaign_recipients (send_id, external_email, external_name, language)
    VALUES (v_send_id, v_ext_email, v_ext.value->>'name', public.normalize_platform_language(COALESCE(v_ext.value->>'language', 'en-US')));
    v_ext_count := v_ext_count + 1;
  END LOOP;

  UPDATE public.campaign_sends SET recipient_count = v_count + v_ext_count WHERE id = v_send_id;

  RETURN jsonb_build_object(
    'send_id', v_send_id, 'member_recipients', v_count, 'external_recipients', v_ext_count,
    'total_recipients', v_count + v_ext_count,
    'skipped_reserved_domain', v_skipped_reserved,
    'status', CASE WHEN p_scheduled_at IS NOT NULL THEN 'scheduled' ELSE 'pending_delivery' END
  );
END;
$function$;

-- ---------------------------------------------------------------------
-- 3. campaign_send_one_off — corpo VIVO (md5 8cee7fc0d045c676a83fbd085b14e14c)
--    1 troca: o passthrough do caller passa a ser normalizado.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.campaign_send_one_off(p_template_slug text, p_to_email text, p_variables jsonb DEFAULT '{}'::jsonb, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_template_id uuid;
  v_send_id uuid;
  v_system_sender_id uuid;
  v_recipient_lang text;
  v_service_role_key text;
  v_dispatch_request_id bigint;
BEGIN
  SELECT id INTO v_template_id FROM public.campaign_templates WHERE slug = p_template_slug;
  IF v_template_id IS NULL THEN
    RAISE EXCEPTION 'Template not found: %', p_template_slug USING ERRCODE = 'no_data_found';
  END IF;

  SELECT m.id INTO v_system_sender_id
  FROM public.members m
  WHERE public.can_by_member(m.id, 'manage_platform') = true
    AND m.is_active = true
  ORDER BY
    CASE m.operational_role
      WHEN 'manager' THEN 1
      WHEN 'gp_lead' THEN 2
      WHEN 'deputy_manager' THEN 3
      WHEN 'co_gp' THEN 4
      ELSE 99
    END,
    m.created_at
  LIMIT 1;

  IF v_system_sender_id IS NULL THEN
    RAISE EXCEPTION 'No GP-tier active member found to attribute system one-off send';
  END IF;

  v_recipient_lang := public.normalize_platform_language(COALESCE(p_metadata->>'language', p_variables->>'lang', 'pt-BR'));

  -- Direct INSERT — variables stored in audience_filter for EF rendering
  INSERT INTO public.campaign_sends (
    id, template_id, sent_by, audience_filter, status, recipient_count, scheduled_at
  ) VALUES (
    gen_random_uuid(),
    v_template_id,
    v_system_sender_id,
    jsonb_build_object(
      'type', 'transactional',
      'one_off', true,
      'source', COALESCE(p_metadata->>'source', 'system'),
      'variables', p_variables
    ),
    'pending_delivery',
    1,
    NULL
  )
  RETURNING id INTO v_send_id;

  INSERT INTO public.campaign_recipients (
    send_id, external_email, external_name, language
  ) VALUES (
    v_send_id,
    p_to_email,
    p_metadata->>'recipient_name',
    v_recipient_lang
  );

  -- Async dispatch: invoke send-campaign EF (handles Resend delivery)
  -- If dispatch fails, the row stays pending_delivery and can be retried.
  BEGIN
    SELECT decrypted_secret INTO v_service_role_key
    FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

    IF v_service_role_key IS NOT NULL THEN
      SELECT net.http_post(
        url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/send-campaign',
        body := jsonb_build_object('send_id', v_send_id),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_service_role_key
        )
      ) INTO v_dispatch_request_id;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'send-campaign EF dispatch failed: % (send_id=%)', SQLERRM, v_send_id;
  END;

  RETURN jsonb_build_object(
    'send_id', v_send_id,
    'system_sender_id', v_system_sender_id,
    'template_slug', p_template_slug,
    'to_email', p_to_email,
    'status', 'pending_delivery',
    'mode', 'one_off_transactional',
    'dispatch_request_id', v_dispatch_request_id
  );
END;
$$;

-- ---------------------------------------------------------------------
-- 4. o dado: normalizado PELO HELPER, nao por replace() de string.
--    O lado canonico (o enum das 3 tags) PRODUZ o valor; a coluna so
--    diz qual linha atualizar.
-- ---------------------------------------------------------------------
UPDATE public.campaign_recipients
   SET language = public.normalize_platform_language(language)
 WHERE language IS DISTINCT FROM public.normalize_platform_language(language);

-- ---------------------------------------------------------------------
-- 5. DEFAULT e CHECK. Nome explicito no constraint: nome auto-gerado e
--    engolido pelo handler e nao da para derrubar depois.
-- ---------------------------------------------------------------------
ALTER TABLE public.campaign_recipients
  ALTER COLUMN language SET DEFAULT 'pt-BR';

ALTER TABLE public.campaign_recipients
  DROP CONSTRAINT IF EXISTS campaign_recipients_language_platform_tag_check;

ALTER TABLE public.campaign_recipients
  ADD CONSTRAINT campaign_recipients_language_platform_tag_check
  CHECK (language IN ('pt-BR','en-US','es-LATAM'));

-- 5b. NOT NULL: 0 nulos hoje e o DEFAULT garante daqui pra frente.
--     Sem isto, o CHECK admite NULL (NULL IN (...) e NULL, e CHECK passa),
--     e "qual e o idioma" volta a ter duas respostas.
--     >>> DECISAO DE QUEM APLICA: remover esta linha se preferir manter
--     >>> a coluna anulavel. Nada mais no pacote depende dela.
ALTER TABLE public.campaign_recipients
  ALTER COLUMN language SET NOT NULL;

-- ---------------------------------------------------------------------
-- 6. superficie do PostgREST: NOTIFY ANTES do db:types.
-- ---------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';
