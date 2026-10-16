-- #2593, fatia C3a — o convidado externo já avisado acompanha o EVENTO: mudança de data, hora, fuso, link ou duração
-- manda um aviso de atualização com ICS de mesmo UID (a agenda dele se atualiza); cancelar a reunião manda o
-- cancelamento que já existe; e um lembrete sai na véspera, às 9h de Brasília.
--
-- Decisões do GP (16/10/2026): C3 antes de 20/10; textos de atualização e de lembrete aprovados (o lembrete sem ICS),
-- os dois com o rodapé de pessoa externa do convite. Medido antes: update_event não olha os blocos, events não tem
-- gatilho para o convidado e não existe lembrete.
--
-- (1) Templates agenda-atualizacao-convidado e agenda-lembrete-convidado, montados como os da C2 (miolo aprovado
--     dentro do avulso-corpo-livre, para o rodapé ter uma fonte só).
-- (2) _agenda_guest_send passa a aceitar 'update' e 'reminder'. Os dois só para bloco confirmado E já avisado
--     (guest_notified_at): quem não recebeu o convite não recebe atualização nem lembrete. O lembrete sai uma vez por
--     bloco e por horário da reunião (um envio que não falhou para o mesmo start_utc bloqueia o segundo).
-- (3) Gatilho em events (AFTER UPDATE OF date, time_start, timezone, meeting_link, duration_minutes, status):
--     reunião cancelada => 'cancel'; mudança de quando/onde => 'update'. O autor do envio é quem mudou o evento ou,
--     sem sessão, o dono do bloco (campaign_sends.sent_by é obrigatório). Falha no aviso não impede a mudança do
--     evento (melhor-esforço com WARNING). O envio só sai depois do COMMIT (pg_net), então uma mudança desfeita não
--     avisa ninguém.
-- (4) Cron agenda-guest-reminder (12:00 UTC = 9h de Brasília): blocos confirmados e avisados de reuniões de AMANHÃ
--     no fuso do evento, fora as canceladas.
--
-- ⚠️ ORDEM DE DEPLOY: publicar a EF send-campaign ANTES de aplicar esta migration (ela passa a tratar 'update' sem
--    carimbar o aviso e 'reminder' sem anexo; a EF antiga mandaria o lembrete com ICS).
--
-- Rollback: recriar _agenda_guest_send pela captura da C2 (20261011143731); DROP TRIGGER
--   trg_event_agenda_guest_lifecycle e das funções novas; cron.unschedule('agenda-guest-reminder'); DELETE dos dois
--   templates pelo slug.

-- ── (1) templates ────────────────────────────────────────────────────────────
DO $templates$
DECLARE
  v_base record;
  v_upd  jsonb := jsonb_build_object(
    'pt', jsonb_build_object(
      'subject', 'Atualizado: {{block_title}} na Reunião Geral do Núcleo IA & GP, {{date}}',
      'html', '<p>Olá, {{first_name}},</p><p>A Reunião Geral em que você vai participar mudou. Os dados atualizados do seu bloco:</p><p>Bloco: {{block_title}} ({{duration}} min)<br>Quando: {{date}}, às {{time}} (horário de Brasília)<br>Link da reunião: <a href="{{link}}">{{link}}</a></p><p>O convite em anexo atualiza o horário na sua agenda. Se não puder participar no novo horário, responda a este e-mail.</p>',
      'text', E'Olá, {{first_name}},\n\nA Reunião Geral em que você vai participar mudou. Os dados atualizados do seu bloco:\n\nBloco: {{block_title}} ({{duration}} min)\nQuando: {{date}}, às {{time}} (horário de Brasília)\nLink da reunião: {{link}}\n\nO convite em anexo atualiza o horário na sua agenda. Se não puder participar no novo horário, responda a este e-mail.'),
    'en', jsonb_build_object(
      'subject', 'Updated: {{block_title}} at the AI & PM Research Hub General Meeting, {{date}}',
      'html', '<p>Hello, {{first_name}},</p><p>The General Meeting you are joining has changed. The updated details of your block:</p><p>Block: {{block_title}} ({{duration}} min)<br>When: {{date}}, at {{time}} (Brasília time)<br>Meeting link: <a href="{{link}}">{{link}}</a></p><p>The attached invitation updates the time in your calendar. If you cannot attend at the new time, reply to this e-mail.</p>',
      'text', E'Hello, {{first_name}},\n\nThe General Meeting you are joining has changed. The updated details of your block:\n\nBlock: {{block_title}} ({{duration}} min)\nWhen: {{date}}, at {{time}} (Brasília time)\nMeeting link: {{link}}\n\nThe attached invitation updates the time in your calendar. If you cannot attend at the new time, reply to this e-mail.'),
    'es', jsonb_build_object(
      'subject', 'Actualizado: {{block_title}} en la Reunión General del Núcleo IA & GP, {{date}}',
      'html', '<p>Hola, {{first_name}},</p><p>La Reunión General en la que vas a participar cambió. Los datos actualizados de tu bloque:</p><p>Bloque: {{block_title}} ({{duration}} min)<br>Cuándo: {{date}}, a las {{time}} (hora de Brasilia)<br>Enlace de la reunión: <a href="{{link}}">{{link}}</a></p><p>La invitación adjunta actualiza el horario en tu agenda. Si no puedes participar en el nuevo horario, responde a este correo.</p>',
      'text', E'Hola, {{first_name}},\n\nLa Reunión General en la que vas a participar cambió. Los datos actualizados de tu bloque:\n\nBloque: {{block_title}} ({{duration}} min)\nCuándo: {{date}}, a las {{time}} (hora de Brasilia)\nEnlace de la reunión: {{link}}\n\nLa invitación adjunta actualiza el horario en tu agenda. Si no puedes participar en el nuevo horario, responde a este correo.'));
  v_rem  jsonb := jsonb_build_object(
    'pt', jsonb_build_object(
      'subject', 'Amanhã: {{block_title}} na Reunião Geral do Núcleo IA & GP',
      'html', '<p>Olá, {{first_name}},</p><p>Lembrete: o seu bloco na Reunião Geral do Núcleo IA &amp; GP é amanhã.</p><p>Bloco: {{block_title}} ({{duration}} min)<br>Quando: {{date}}, às {{time}} (horário de Brasília)<br>Link da reunião: <a href="{{link}}">{{link}}</a></p><p>Se algo mudou do seu lado, responda a este e-mail.</p>',
      'text', E'Olá, {{first_name}},\n\nLembrete: o seu bloco na Reunião Geral do Núcleo IA & GP é amanhã.\n\nBloco: {{block_title}} ({{duration}} min)\nQuando: {{date}}, às {{time}} (horário de Brasília)\nLink da reunião: {{link}}\n\nSe algo mudou do seu lado, responda a este e-mail.'),
    'en', jsonb_build_object(
      'subject', 'Tomorrow: {{block_title}} at the AI & PM Research Hub General Meeting',
      'html', '<p>Hello, {{first_name}},</p><p>Reminder: your block at the AI &amp; PM Research Hub (Núcleo IA &amp; GP) General Meeting is tomorrow.</p><p>Block: {{block_title}} ({{duration}} min)<br>When: {{date}}, at {{time}} (Brasília time)<br>Meeting link: <a href="{{link}}">{{link}}</a></p><p>If anything has changed on your side, reply to this e-mail.</p>',
      'text', E'Hello, {{first_name}},\n\nReminder: your block at the AI & PM Research Hub (Núcleo IA & GP) General Meeting is tomorrow.\n\nBlock: {{block_title}} ({{duration}} min)\nWhen: {{date}}, at {{time}} (Brasília time)\nMeeting link: {{link}}\n\nIf anything has changed on your side, reply to this e-mail.'),
    'es', jsonb_build_object(
      'subject', 'Mañana: {{block_title}} en la Reunión General del Núcleo IA & GP',
      'html', '<p>Hola, {{first_name}},</p><p>Recordatorio: tu bloque en la Reunión General del Núcleo IA &amp; GP es mañana.</p><p>Bloque: {{block_title}} ({{duration}} min)<br>Cuándo: {{date}}, a las {{time}} (hora de Brasilia)<br>Enlace de la reunión: <a href="{{link}}">{{link}}</a></p><p>Si algo cambió de tu lado, responde a este correo.</p>',
      'text', E'Hola, {{first_name}},\n\nRecordatorio: tu bloque en la Reunión General del Núcleo IA & GP es mañana.\n\nBloque: {{block_title}} ({{duration}} min)\nCuándo: {{date}}, a las {{time}} (hora de Brasilia)\nEnlace de la reunión: {{link}}\n\nSi algo cambió de tu lado, responde a este correo.'));
  r record;
  k text;
  v_subject jsonb;
  v_html jsonb;
  v_text jsonb;
BEGIN
  SELECT body_html, body_text INTO v_base FROM public.campaign_templates WHERE slug = 'avulso-corpo-livre';
  IF NOT FOUND THEN RAISE EXCEPTION '#2593: template avulso-corpo-livre ausente (é dele que vem o rodapé aprovado)'; END IF;

  FOR r IN SELECT * FROM (VALUES
      ('agenda-atualizacao-convidado', 'Agenda Viva: atualização ao convidado externo', v_upd),
      ('agenda-lembrete-convidado', 'Agenda Viva: lembrete na véspera ao convidado externo', v_rem)) AS t(slug, name, txt)
  LOOP
    v_subject := '{}'::jsonb; v_html := '{}'::jsonb; v_text := '{}'::jsonb;
    FOREACH k IN ARRAY ARRAY['pt', 'en', 'es'] LOOP
      IF strpos(v_base.body_html->>k, '{{content_html}}') = 0 OR strpos(v_base.body_text->>k, '{{content_text}}') = 0 THEN
        RAISE EXCEPTION '#2593: o template avulso mudou de forma (%), o miolo não tem onde entrar', k;
      END IF;
      v_subject := v_subject || jsonb_build_object(k, r.txt->k->>'subject');
      v_html := v_html || jsonb_build_object(k, replace(v_base.body_html->>k, '{{content_html}}', r.txt->k->>'html'));
      v_text := v_text || jsonb_build_object(k, replace(v_base.body_text->>k, '{{content_text}}', r.txt->k->>'text'));
    END LOOP;
    INSERT INTO public.campaign_templates (name, slug, subject, body_html, body_text, target_audience, category, theme, variables)
    VALUES (r.name, r.slug, v_subject, v_html, v_text,
            '{"all": false, "roles": [], "chapters": [], "designations": []}'::jsonb, 'operational', 'eventos',
            '{"block_title": {"type": "text", "required": true}, "member_name": {"type": "text", "required": true}, "start_utc": {"type": "text", "required": true}, "duration": {"type": "text", "required": true}, "link": {"type": "text", "required": true}}'::jsonb)
    ON CONFLICT (slug) DO UPDATE
      SET name = EXCLUDED.name, subject = EXCLUDED.subject, body_html = EXCLUDED.body_html,
          body_text = EXCLUDED.body_text, theme = EXCLUDED.theme, variables = EXCLUDED.variables;
  END LOOP;
END
$templates$;

-- ── (2) envio ao convidado: + atualização e lembrete ─────────────────────────
CREATE OR REPLACE FUNCTION public._agenda_guest_send(p_block_id uuid, p_kind text, p_actor uuid, p_dispatch boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_b         record;
  v_email     text;
  v_template  uuid;
  v_send_id   uuid := gen_random_uuid();
  v_organizer text;
  v_key       text;
  v_request   bigint;
  v_start_utc text;
BEGIN
  IF p_kind NOT IN ('invite', 'cancel', 'update', 'reminder') THEN
    RAISE EXCEPTION 'Unknown agenda guest message kind: %', p_kind USING ERRCODE = 'check_violation';
  END IF;

  SELECT b.id, b.status, b.external_guest, b.guest_name, b.guest_person_id, b.guest_language, b.guest_notified_at,
         b.title, b.duration_min, m.name AS member_name, e.meeting_link,
         (e.date + COALESCE(e.time_start, '00:00'::time)) AT TIME ZONE COALESCE(e.timezone, 'America/Sao_Paulo') AS start_at,
         e.time_start, COALESCE(e.duration_minutes, 90) AS event_minutes
    INTO v_b
  FROM public.event_agenda_blocks b
  JOIN public.events e ON e.id = b.event_id
  JOIN public.members m ON m.id = b.owner_member_id
  WHERE b.id = p_block_id;
  IF NOT FOUND OR NOT v_b.external_guest OR v_b.time_start IS NULL OR v_b.start_at <= now() THEN
    RETURN NULL;  -- sem convidado externo, sem hora configurada, ou reunião já começada: não há o que avisar
  END IF;
  IF p_kind = 'invite' AND (v_b.status <> 'confirmed' OR v_b.guest_notified_at IS NOT NULL) THEN
    RETURN NULL;
  END IF;
  IF p_kind = 'cancel' AND v_b.guest_notified_at IS NULL THEN
    RETURN NULL;  -- quem nunca recebeu convite não recebe cancelamento
  END IF;
  -- C3: atualização e lembrete só para quem já recebeu o convite, e só com o bloco ainda de pé
  IF p_kind IN ('update', 'reminder') AND (v_b.status <> 'confirmed' OR v_b.guest_notified_at IS NULL) THEN
    RETURN NULL;
  END IF;

  v_start_utc := to_char(v_b.start_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');

  -- o e-mail DIGITADO para este bloco (vínculo), nunca o principal da pessoa
  SELECT l.contact_email INTO v_email FROM public.person_external_links l
  WHERE l.purpose = 'agenda_guest' AND l.source_id = p_block_id
  ORDER BY l.updated_at DESC LIMIT 1;
  IF v_email IS NULL THEN RETURN NULL; END IF;

  -- descadastro vale para o convidado externo: endereço suprimido não recebe nada
  IF cardinality(public.email_suppressed_among(ARRAY[v_email], true)) > 0 THEN RETURN NULL; END IF;

  -- um convite por convidado por bloco: confirmar de novo (o reparo do XP) não manda outro
  IF p_kind = 'invite' AND EXISTS (
       SELECT 1 FROM public.campaign_sends s
       WHERE s.audience_filter->>'source' = 'agenda_guest' AND s.audience_filter->>'kind' = 'invite'
         AND s.audience_filter->>'block_id' = p_block_id::text
         AND s.audience_filter->>'guest_person_id' IS NOT DISTINCT FROM v_b.guest_person_id::text
         -- failed não conta; sent sem carimbo é sandbox (o sent real carimbou e já saiu acima)
         AND s.status NOT IN ('failed', 'sent')) THEN
    RETURN NULL;
  END IF;

  -- C3: um lembrete por bloco e por horário da reunião; se a reunião mudar de dia, o novo dia ganha o seu
  IF p_kind = 'reminder' AND EXISTS (
       SELECT 1 FROM public.campaign_sends s
       WHERE s.audience_filter->>'source' = 'agenda_guest' AND s.audience_filter->>'kind' = 'reminder'
         AND s.audience_filter->>'block_id' = p_block_id::text
         AND s.audience_filter->'variables'->>'start_utc' = v_start_utc
         AND s.status <> 'failed') THEN
    RETURN NULL;
  END IF;

  SELECT t.id INTO v_template FROM public.campaign_templates t
  WHERE t.slug = CASE p_kind WHEN 'invite' THEN 'agenda-convite-convidado'
                             WHEN 'cancel' THEN 'agenda-cancelamento-convidado'
                             WHEN 'update' THEN 'agenda-atualizacao-convidado'
                             ELSE 'agenda-lembrete-convidado' END;
  IF v_template IS NULL THEN RAISE EXCEPTION 'Agenda guest template missing (%)', p_kind; END IF;

  SELECT s.value #>> '{}' INTO v_organizer FROM public.platform_settings s WHERE s.key = 'agenda_invite_organizer_email';
  IF v_organizer IS NULL THEN RAISE EXCEPTION 'platform_settings.agenda_invite_organizer_email missing'; END IF;

  -- o envio fica guardado: nada do convidado aqui (nem e-mail, nem nome); o destinatário é que leva o contato
  INSERT INTO public.campaign_sends (id, template_id, sent_by, approved_by, approved_at, audience_filter,
                                     status, recipient_count, theme)
  VALUES (v_send_id, v_template, p_actor, p_actor, now(),
          jsonb_build_object(
            'type', 'transactional', 'one_off', true, 'source', 'agenda_guest', 'kind', p_kind,
            'block_id', p_block_id, 'guest_person_id', v_b.guest_person_id,
            'variables', jsonb_build_object(
              'block_title', v_b.title, 'member_name', v_b.member_name, 'duration', v_b.duration_min,
              'start_utc', v_start_utc,
              'link', COALESCE(v_b.meeting_link, '')),
            'ics', jsonb_build_object(
              'uid', 'agenda-block-' || p_block_id::text || '@nucleoia.vitormr.dev',
              -- SEQUENCE cresce com o relógio, em segundos: o cancelamento vence o convite mesmo no mesmo minuto,
              -- e a atualização vence o convite anterior
              'sequence', extract(epoch FROM now())::bigint,
              'end_utc', to_char((v_b.start_at + make_interval(mins => v_b.event_minutes)) AT TIME ZONE 'UTC',
                                 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
              'organizer_email', v_organizer,
              'organizer_name', 'Núcleo IA & GP')),
          'pending_delivery', 1, 'eventos');

  INSERT INTO public.campaign_recipients (send_id, member_id, external_email, external_name, person_id, language)
  VALUES (v_send_id, NULL, v_email, v_b.guest_name, v_b.guest_person_id, v_b.guest_language);

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (p_actor, 'agenda.guest_' || p_kind || '_queued', 'event_agenda_block', p_block_id,
          jsonb_build_object('send_id', v_send_id, 'language', v_b.guest_language),
          jsonb_build_object('source', '_agenda_guest_send', 'issue', 2593));

  IF p_dispatch THEN
    -- despacho assíncrono, como o envio avulso: falha aqui deixa o envio pending_delivery para o cron
    BEGIN
      SELECT ds.decrypted_secret INTO v_key FROM vault.decrypted_secrets ds WHERE ds.name = 'service_role_key' LIMIT 1;
      IF v_key IS NOT NULL THEN
        SELECT net.http_post(
          url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/send-campaign',
          body := jsonb_build_object('send_id', v_send_id),
          headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key)
        ) INTO v_request;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'send-campaign dispatch failed: % (send_id=%)', SQLERRM, v_send_id;
    END;
  END IF;

  RETURN v_send_id;
END;
$function$;

REVOKE ALL ON FUNCTION public._agenda_guest_send(uuid, text, uuid, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._agenda_guest_send(uuid, text, uuid, boolean) TO service_role;

-- ── (3) o evento muda, o convidado já avisado fica sabendo ────────────────────
CREATE OR REPLACE FUNCTION public._trg_event_agenda_guest_lifecycle()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_kind  text;
  v_actor uuid;
  r       record;
BEGIN
  IF NEW.status = 'cancelled' AND OLD.status IS DISTINCT FROM 'cancelled' THEN
    v_kind := 'cancel';
  ELSIF NEW.status IS DISTINCT FROM 'cancelled'
    AND (NEW.date IS DISTINCT FROM OLD.date OR NEW.time_start IS DISTINCT FROM OLD.time_start
         OR NEW.timezone IS DISTINCT FROM OLD.timezone OR NEW.meeting_link IS DISTINCT FROM OLD.meeting_link
         OR NEW.duration_minutes IS DISTINCT FROM OLD.duration_minutes) THEN
    v_kind := 'update';
  ELSE
    RETURN NEW;
  END IF;

  SELECT m.id INTO v_actor FROM public.members m WHERE m.auth_id = auth.uid();

  FOR r IN
    SELECT b.id, b.owner_member_id FROM public.event_agenda_blocks b
    WHERE b.event_id = NEW.id AND b.external_guest AND b.status = 'confirmed' AND b.guest_notified_at IS NOT NULL
  LOOP
    BEGIN
      PERFORM public._agenda_guest_send(r.id, v_kind, COALESCE(v_actor, r.owner_member_id), true);
    EXCEPTION WHEN OTHERS THEN
      -- melhor-esforço: uma falha no aviso ao convidado não pode impedir a mudança do evento
      RAISE WARNING 'agenda guest % for block % failed: %', v_kind, r.id, SQLERRM;
    END;
  END LOOP;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public._trg_event_agenda_guest_lifecycle() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_event_agenda_guest_lifecycle ON public.events;
CREATE TRIGGER trg_event_agenda_guest_lifecycle
  AFTER UPDATE OF date, time_start, timezone, meeting_link, duration_minutes, status ON public.events
  FOR EACH ROW EXECUTE FUNCTION public._trg_event_agenda_guest_lifecycle();

-- ── (4) lembrete na véspera ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._agenda_guest_reminder_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  r        record;
  v_send   uuid;
  v_queued integer := 0;
  v_skip   integer := 0;
BEGIN
  IF public._request_is_rest_caller() THEN
    RAISE EXCEPTION 'Unauthorized: _agenda_guest_reminder_cron is cron-only';
  END IF;

  FOR r IN
    SELECT b.id, b.owner_member_id
    FROM public.event_agenda_blocks b
    JOIN public.events e ON e.id = b.event_id
    WHERE b.external_guest AND b.status = 'confirmed' AND b.guest_notified_at IS NOT NULL
      AND e.status IS DISTINCT FROM 'cancelled'
      AND e.date = (now() AT TIME ZONE COALESCE(e.timezone, 'America/Sao_Paulo'))::date + 1
  LOOP
    v_send := public._agenda_guest_send(r.id, 'reminder', r.owner_member_id, true);
    IF v_send IS NULL THEN v_skip := v_skip + 1; ELSE v_queued := v_queued + 1; END IF;
  END LOOP;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (NULL, 'agenda.guest_reminder_cron_run', 'system', NULL,
          jsonb_build_object('queued', v_queued, 'skipped', v_skip),
          jsonb_build_object('source', '_agenda_guest_reminder_cron', 'issue', 2593));

  RETURN jsonb_build_object('queued', v_queued, 'skipped', v_skip);
END;
$function$;

REVOKE ALL ON FUNCTION public._agenda_guest_reminder_cron() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._agenda_guest_reminder_cron() TO service_role;

SELECT cron.unschedule('agenda-guest-reminder')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'agenda-guest-reminder');

SELECT cron.schedule(
  'agenda-guest-reminder',
  '0 12 * * *',
  $cron$SELECT public._agenda_guest_reminder_cron();$cron$
);

-- ── pós-condição ──────────────────────────────────────────────────────────────
DO $postcondition$
DECLARE
  v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM public.campaign_templates t
  WHERE t.slug IN ('agenda-atualizacao-convidado', 'agenda-lembrete-convidado')
    AND t.subject ?& ARRAY['pt', 'en', 'es'] AND t.body_html ?& ARRAY['pt', 'en', 'es'] AND t.body_text ?& ARRAY['pt', 'en', 'es']
    AND t.body_html->>'pt' LIKE '%<!--EXTERNO-->%<!--/EXTERNO-->%'
    AND t.body_text->>'pt' LIKE '%[[EXTERNO]]%[[/EXTERNO]]%'
    AND t.body_html->>'pt' NOT LIKE '%{{content_html}}%' AND t.body_text->>'pt' NOT LIKE '%{{content_text}}%';
  IF v_n <> 2 THEN RAISE EXCEPTION '#2593 C3: esperava os 2 templates completos, achei %', v_n; END IF;

  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'agenda-guest-reminder' AND schedule = '0 12 * * *' AND active) THEN
    RAISE EXCEPTION '#2593 C3: o cron do lembrete não ficou agendado';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_event_agenda_guest_lifecycle'
                   AND tgrelid = 'public.events'::regclass AND NOT tgisinternal) THEN
    RAISE EXCEPTION '#2593 C3: gatilho do evento ausente';
  END IF;
  IF has_function_privilege('authenticated', 'public._agenda_guest_reminder_cron()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public._agenda_guest_send(uuid, text, uuid, boolean)', 'EXECUTE') THEN
    RAISE EXCEPTION '#2593 C3: auxiliar de envio alcançável por authenticated';
  END IF;

  -- controle em subtransação desfeita, SEM despacho: as regras de atualização e de lembrete
  DECLARE
    v_event uuid;
    v_owner uuid;
    v_block uuid;
    v_send  uuid;
    v_tpl   text;
  BEGIN
    SELECT e.id INTO v_event FROM public.events e
    WHERE e.type = 'geral' AND e.status IS DISTINCT FROM 'cancelled' AND e.time_start IS NOT NULL
      AND (e.date + e.time_start) AT TIME ZONE COALESCE(e.timezone, 'America/Sao_Paulo') > now()
    ORDER BY (e.date + e.time_start) LIMIT 1;
    SELECT m.id INTO v_owner FROM public.members m
    WHERE v_event IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.event_agenda_blocks b WHERE b.event_id = v_event AND b.owner_member_id = m.id)
    LIMIT 1;
    IF v_event IS NULL OR v_owner IS NULL THEN
      RAISE NOTICE '#2593 C3: sem reunião geral futura para o controle; pulado';
    ELSE
      INSERT INTO public.event_agenda_blocks (event_id, owner_member_id, format_slug, title, duration_min,
                                              guest_name, external_guest, guest_language, status, sort_order, created_by)
      SELECT v_event, v_owner, f.slug, 'controle #2593 C3', 5, 'Controle C3', true, 'en-US', 'confirmed', 998, v_owner
      FROM public.agenda_block_formats f WHERE f.active LIMIT 1
      RETURNING id INTO v_block;
      IF v_block IS NULL THEN RAISE EXCEPTION '#2593 C3: controle sem formato de bloco ativo para inserir'; END IF;
      PERFORM public._agenda_guest_attach(v_block, 'Controle C3', 'controle-2593-c3@example.org');

      -- sem o convite registrado, nem atualização nem lembrete
      IF public._agenda_guest_send(v_block, 'update', v_owner, false) IS NOT NULL
         OR public._agenda_guest_send(v_block, 'reminder', v_owner, false) IS NOT NULL THEN
        RAISE EXCEPTION '#2593 C3: atualização ou lembrete montados para quem não recebeu o convite';
      END IF;

      UPDATE public.event_agenda_blocks SET guest_notified_at = now() WHERE id = v_block;

      v_send := public._agenda_guest_send(v_block, 'update', v_owner, false);
      SELECT t.slug INTO v_tpl FROM public.campaign_sends s JOIN public.campaign_templates t ON t.id = s.template_id WHERE s.id = v_send;
      IF v_tpl IS DISTINCT FROM 'agenda-atualizacao-convidado' THEN
        RAISE EXCEPTION '#2593 C3: a atualização não foi montada com o template certo (%)', v_tpl;
      END IF;

      v_send := public._agenda_guest_send(v_block, 'reminder', v_owner, false);
      SELECT t.slug INTO v_tpl FROM public.campaign_sends s JOIN public.campaign_templates t ON t.id = s.template_id WHERE s.id = v_send;
      IF v_tpl IS DISTINCT FROM 'agenda-lembrete-convidado' THEN
        RAISE EXCEPTION '#2593 C3: o lembrete não foi montado com o template certo (%)', v_tpl;
      END IF;
      -- um lembrete por bloco e horário
      IF public._agenda_guest_send(v_block, 'reminder', v_owner, false) IS NOT NULL THEN
        RAISE EXCEPTION '#2593 C3: o segundo lembrete do mesmo horário foi montado';
      END IF;

      -- bloco que deixou de estar confirmado não recebe atualização
      UPDATE public.event_agenda_blocks SET status = 'reserved' WHERE id = v_block;
      IF public._agenda_guest_send(v_block, 'update', v_owner, false) IS NOT NULL THEN
        RAISE EXCEPTION '#2593 C3: atualização montada para bloco não confirmado';
      END IF;

      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = '__2593c3_rollback__';
    END IF;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> '__2593c3_rollback__' THEN RAISE; END IF;
  END;
END
$postcondition$;
