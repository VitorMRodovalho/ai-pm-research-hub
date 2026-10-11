-- #2593, fatia C2 — convite e cancelamento ao convidado externo da Agenda Viva, com ICS, e aviso no sino ao dono.
--
-- Decisões do GP (09–11/10/2026): o convite sai só na CONFIRMAÇÃO do bloco; textos (1) convite e (2) cancelamento
-- aprovados em pt-BR, EN e ES; idioma do convite = event_agenda_blocks.guest_language; o convite cita o membro
-- que trouxe o convidado; "Atualizado" com ICS novo e lembrete da véspera ficam para a C3; o dono do bloco sabe
-- pelo sino (notificação interna, não e-mail) quando a coordenação confirma ou cancela o bloco dele.
--
-- Corpos vivos conferidos contra as capturas (11/10/2026): confirm 08bd9082 (20260805000179), cancel be094368
-- (20261011112204), _delivery_mode_for 0b7ea6b6 (20261010192333), create_notification e email_suppressed_among
-- iguais às capturas.
--
-- (1) Templates agenda-convite-convidado e agenda-cancelamento-convidado: o miolo é o texto aprovado; o resto é o
--     template avulso-corpo-livre (assinatura e o rodapé de pessoa externa aprovado na fatia B), lido aqui mesmo,
--     para o rodapé ter uma fonte só. Os valores ({{block_title}}, {{member_name}}, {{date}}, {{time}},
--     {{duration}}, {{link}}, {{first_name}}) são preenchidos e ESCAPADOS pelo send-campaign
--     (_shared/agenda-guest-invite.ts), que também monta o ICS (METHOD:REQUEST / CANCEL, mesmo UID, SEQUENCE maior).
-- (2) _agenda_guest_send(bloco, 'invite'|'cancel', autor, despachar): cria o envio (tema eventos) e o destinatário com
--     o e-mail DIGITADO (vínculo do bloco), no idioma do bloco. O audience_filter não leva e-mail nem nome do
--     convidado (o envio fica guardado e não é varrido; o destinatário é anonimizado pela varredura da fatia A).
--     Não envia: sem e-mail no vínculo, reunião já começada, endereço suprimido (descadastro), convite já enviado
--     ao mesmo convidado, ou cancelamento de quem nunca foi convidado.
-- (3) confirm_agenda_block: convidado externo ainda não avisado recebe o convite. guest_notified_at é carimbado
--     pelo send-campaign só quando o provedor aceita o envio (e nunca em sandbox): é o que libera o nome público.
-- (4) cancel_agenda_block: convidado já avisado recebe o cancelamento ANTES de o vínculo sair.
-- (5) Sino ao dono: agenda_block_confirmed e agenda_block_cancelled, catalogados como suppress (só no aplicativo)
--     no ADR-0022, com WHEN próprio em _delivery_mode_for (não caem no ELSE).
--
-- Nenhum envio real até o GP dar OK ao merge (a orquestradora aplica; a EF send-campaign é publicada por ela).
--
-- Rollback: recriar confirm (20260805000179), cancel (20261011112204) e _delivery_mode_for (20261010192333) pelas
--   capturas; DROP de _agenda_guest_send e _agenda_block_owner_notice; DELETE dos dois templates pelo slug.

-- ── (1) templates ────────────────────────────────────────────────────────────
DO $templates$
DECLARE
  v_base record;
  v_inv  jsonb := jsonb_build_object(
    'pt', jsonb_build_object(
      'subject', 'Convite: {{block_title}} na Reunião Geral do Núcleo IA & GP, {{date}}',
      'html', '<p>Olá, {{first_name}},</p><p>{{member_name}} confirmou a sua participação na Reunião Geral do Núcleo IA &amp; GP.</p><p>Bloco: {{block_title}} ({{duration}} min)<br>Quando: {{date}}, às {{time}} (horário de Brasília)<br>Link da reunião: <a href="{{link}}">{{link}}</a></p><p>O convite em anexo reserva o horário na sua agenda. Se não puder participar, responda a este e-mail.</p>',
      'text', E'Olá, {{first_name}},\n\n{{member_name}} confirmou a sua participação na Reunião Geral do Núcleo IA & GP.\n\nBloco: {{block_title}} ({{duration}} min)\nQuando: {{date}}, às {{time}} (horário de Brasília)\nLink da reunião: {{link}}\n\nO convite em anexo reserva o horário na sua agenda. Se não puder participar, responda a este e-mail.'),
    'en', jsonb_build_object(
      'subject', 'Invitation: {{block_title}} at the AI & PM Research Hub General Meeting, {{date}}',
      'html', '<p>Hello, {{first_name}},</p><p>{{member_name}} has confirmed your participation in the AI &amp; PM Research Hub (Núcleo IA &amp; GP) General Meeting.</p><p>Block: {{block_title}} ({{duration}} min)<br>When: {{date}}, at {{time}} (Brasília time)<br>Meeting link: <a href="{{link}}">{{link}}</a></p><p>The attached invitation holds the time in your calendar. If you cannot attend, reply to this e-mail.</p>',
      'text', E'Hello, {{first_name}},\n\n{{member_name}} has confirmed your participation in the AI & PM Research Hub (Núcleo IA & GP) General Meeting.\n\nBlock: {{block_title}} ({{duration}} min)\nWhen: {{date}}, at {{time}} (Brasília time)\nMeeting link: {{link}}\n\nThe attached invitation holds the time in your calendar. If you cannot attend, reply to this e-mail.'),
    'es', jsonb_build_object(
      'subject', 'Invitación: {{block_title}} en la Reunión General del Núcleo IA & GP, {{date}}',
      'html', '<p>Hola, {{first_name}},</p><p>{{member_name}} confirmó tu participación en la Reunión General del Núcleo IA &amp; GP.</p><p>Bloque: {{block_title}} ({{duration}} min)<br>Cuándo: {{date}}, a las {{time}} (hora de Brasilia)<br>Enlace de la reunión: <a href="{{link}}">{{link}}</a></p><p>La invitación adjunta reserva el horario en tu agenda. Si no puedes participar, responde a este correo.</p>',
      'text', E'Hola, {{first_name}},\n\n{{member_name}} confirmó tu participación en la Reunión General del Núcleo IA & GP.\n\nBloque: {{block_title}} ({{duration}} min)\nCuándo: {{date}}, a las {{time}} (hora de Brasilia)\nEnlace de la reunión: {{link}}\n\nLa invitación adjunta reserva el horario en tu agenda. Si no puedes participar, responde a este correo.'));
  v_can  jsonb := jsonb_build_object(
    'pt', jsonb_build_object(
      'subject', 'Cancelado: {{block_title}} na Reunião Geral do Núcleo IA & GP, {{date}}',
      'html', '<p>Olá, {{first_name}},</p><p>O bloco {{block_title}} na Reunião Geral de {{date}} foi cancelado. O arquivo em anexo libera o horário na sua agenda.</p><p>Obrigado pela disponibilidade.</p>',
      'text', E'Olá, {{first_name}},\n\nO bloco {{block_title}} na Reunião Geral de {{date}} foi cancelado. O arquivo em anexo libera o horário na sua agenda.\n\nObrigado pela disponibilidade.'),
    'en', jsonb_build_object(
      'subject', 'Cancelled: {{block_title}} at the AI & PM Research Hub General Meeting, {{date}}',
      'html', '<p>Hello, {{first_name}},</p><p>The block {{block_title}} at the General Meeting on {{date}} has been cancelled. The attached file frees the time in your calendar.</p><p>Thank you for your availability.</p>',
      'text', E'Hello, {{first_name}},\n\nThe block {{block_title}} at the General Meeting on {{date}} has been cancelled. The attached file frees the time in your calendar.\n\nThank you for your availability.'),
    'es', jsonb_build_object(
      'subject', 'Cancelado: {{block_title}} en la Reunión General del Núcleo IA & GP, {{date}}',
      'html', '<p>Hola, {{first_name}},</p><p>El bloque {{block_title}} en la Reunión General del {{date}} fue cancelado. El archivo adjunto libera el horario en tu agenda.</p><p>Gracias por tu disponibilidad.</p>',
      'text', E'Hola, {{first_name}},\n\nEl bloque {{block_title}} en la Reunión General del {{date}} fue cancelado. El archivo adjunto libera el horario en tu agenda.\n\nGracias por tu disponibilidad.'));
  r record;
  k text;
  v_subject jsonb;
  v_html jsonb;
  v_text jsonb;
BEGIN
  SELECT body_html, body_text INTO v_base FROM public.campaign_templates WHERE slug = 'avulso-corpo-livre';
  IF NOT FOUND THEN RAISE EXCEPTION '#2593: template avulso-corpo-livre ausente (é dele que vem o rodapé aprovado)'; END IF;

  FOR r IN SELECT * FROM (VALUES
      ('agenda-convite-convidado', 'Agenda Viva: convite ao convidado externo', v_inv),
      ('agenda-cancelamento-convidado', 'Agenda Viva: cancelamento ao convidado externo', v_can)) AS t(slug, name, txt)
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
      SET subject = EXCLUDED.subject, body_html = EXCLUDED.body_html, body_text = EXCLUDED.body_text,
          theme = EXCLUDED.theme, variables = EXCLUDED.variables;
  END LOOP;
END
$templates$;

-- ── (2) envio ao convidado ───────────────────────────────────────────────────
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
BEGIN
  IF p_kind NOT IN ('invite', 'cancel') THEN
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
         AND s.status IS DISTINCT FROM 'failed') THEN
    RETURN NULL;
  END IF;

  SELECT t.id INTO v_template FROM public.campaign_templates t
  WHERE t.slug = CASE p_kind WHEN 'invite' THEN 'agenda-convite-convidado' ELSE 'agenda-cancelamento-convidado' END;
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
              'start_utc', to_char(v_b.start_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
              'link', COALESCE(v_b.meeting_link, '')),
            'ics', jsonb_build_object(
              'uid', 'agenda-block-' || p_block_id::text || '@nucleoia.vitormr.dev',
              -- SEQUENCE cresce com o relógio: o cancelamento sempre vence o convite que veio antes
              'sequence', (extract(epoch FROM now()) / 60)::bigint,
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

-- ── (5) sino ao dono ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._agenda_block_owner_notice(p_block_id uuid, p_type text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_b record;
BEGIN
  IF p_type NOT IN ('agenda_block_confirmed', 'agenda_block_cancelled') THEN
    RAISE EXCEPTION 'Unknown agenda block notice: %', p_type USING ERRCODE = 'check_violation';
  END IF;
  SELECT b.owner_member_id, b.title, e.date INTO v_b
  FROM public.event_agenda_blocks b JOIN public.events e ON e.id = b.event_id
  WHERE b.id = p_block_id;
  IF NOT FOUND THEN RETURN; END IF;
  PERFORM public.create_notification(
    v_b.owner_member_id, p_type,
    CASE p_type WHEN 'agenda_block_confirmed' THEN 'Seu bloco na Reunião Geral foi confirmado'
                ELSE 'Seu bloco na Reunião Geral foi cancelado' END,
    '"' || v_b.title || '", Reunião Geral de ' || to_char(v_b.date, 'DD/MM/YYYY') || '.',
    '/reunioes-gerais', 'agenda_block', p_block_id);
END;
$function$;

REVOKE ALL ON FUNCTION public._agenda_guest_send(uuid, text, uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._agenda_block_owner_notice(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._agenda_guest_send(uuid, text, uuid, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public._agenda_block_owner_notice(uuid, text) TO service_role;

CREATE OR REPLACE FUNCTION public._delivery_mode_for(p_type text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE p_type
    -- PR-2 (email audit): the per-signing leadership alert is now in-app only; the daily
    -- digest (volunteer_term_signed_digest) carries the single aggregated email.
    WHEN 'volunteer_agreement_signed'    THEN 'suppress'
    WHEN 'volunteer_term_signed_digest'  THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_pending'  THEN 'transactional_immediate'
    WHEN 'system_alert'                  THEN 'transactional_immediate'
    -- #1169: ready is redundant with issued at the email layer (issued carries the single email);
    -- kept in-app only. Every ready-cert already fired an issued email (0 ready-without-issued/60d).
    WHEN 'certificate_ready'             THEN 'suppress'
    WHEN 'certificate_issued'            THEN 'transactional_immediate'
    WHEN 'member_offboarded'             THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_advanced'    THEN 'transactional_immediate'
    WHEN 'ip_ratification_chain_approved'   THEN 'transactional_immediate'
    WHEN 'ip_ratification_awaiting_members' THEN 'transactional_immediate'
    WHEN 'webinar_status_confirmed'      THEN 'transactional_immediate'
    WHEN 'webinar_status_completed'      THEN 'transactional_immediate'
    WHEN 'webinar_status_cancelled'      THEN 'transactional_immediate'
    WHEN 'weekly_card_digest_member'     THEN 'transactional_immediate'
    WHEN 'governance_cr_new'             THEN 'transactional_immediate'
    WHEN 'governance_cr_vote'            THEN 'transactional_immediate'
    WHEN 'governance_cr_approved'        THEN 'transactional_immediate'
    WHEN 'sponsor_finance_entry_logged'  THEN 'transactional_immediate'
    WHEN 'governance_manual_proposed'    THEN 'transactional_immediate'
    WHEN 'engagement_renewal_d7_urgent'  THEN 'transactional_immediate'
    -- p153 OPP-153.1: project_charter (TAP) notifications
    WHEN 'project_charter_invite'        THEN 'transactional_immediate'
    WHEN 'project_charter_approved'      THEN 'transactional_immediate'
    -- p159 S#1 T1 (2026-05-14): selection_termo_due é o "email principal" pós-VEP-Active
    WHEN 'selection_termo_due'           THEN 'transactional_immediate'
    -- #2325 (2026-09-16): o LEMBRETE de que o termo segue aberto. Tipo proprio, separado de
    -- `selection_termo_due` (que anuncia a ABERTURA, no aceite do VEP, e e alvo de replay).
    -- Nasceu porque a cobranca saia como `system`, que o catalogo manda suprimir: 26 avisos a
    -- 16 pessoas que nunca deixaram a plataforma. Catalogado de proposito em vez de cair no
    -- ELSE: o ELSE e `digest_weekly`, que carimba como entregue o que nao renderiza (#2286).
    WHEN 'volunteer_term_pending'        THEN 'transactional_immediate'
    -- p228 #260 W2 Leaf 1 (2026-05-23): Selection funnel Policy Matrix
    WHEN 'selection_approved'            THEN 'transactional_immediate'
    WHEN 'selection_interview_scheduled' THEN 'transactional_immediate'
    WHEN 'peer_review_requested'         THEN 'transactional_immediate'
    WHEN 'selection_evaluation_complete' THEN 'suppress'
    WHEN 'selection_interview_noshow'    THEN 'digest_weekly'
    -- p228 #260 W2 Leaf 2 (2026-05-23): admin reminder for overdue interviews
    WHEN 'selection_interview_overdue'   THEN 'digest_weekly'
    -- p228 #260 W2 Leaf 4 (2026-05-23): candidate invite to book interview after
    -- objective evaluations cleared + research_score >= cycle cutoff.
    WHEN 'selection_cutoff_approved'     THEN 'transactional_immediate'
    -- (end p228)
    -- #2013 (2026-08-26): o teto de lembretes de reagendamento foi atingido e o caso vira
    -- trabalho de gente. Imediato de proposito: e o unico aviso, e o digest semanal so
    -- entrega a quem tem OUTRO conteudo na semana (#2010).
    WHEN 'selection_reschedule_escalated' THEN 'transactional_immediate'
    -- #186 (2026-06-05): curation committee broadcast when an item enters curation_pending
    WHEN 'curation_item_submitted'       THEN 'transactional_immediate'
    WHEN 'engagement_renewal_d30'        THEN 'digest_weekly'
    WHEN 'engagement_renewal_d60_gp_aggregate' THEN 'digest_weekly'
    -- #625 F3 (2026-06-11): radar de renovação de filiação
    WHEN 'affiliation_renewal_d7_urgent'  THEN 'transactional_immediate'
    WHEN 'affiliation_renewal_d30'        THEN 'digest_weekly'
    WHEN 'affiliation_verification_stale' THEN 'digest_weekly'
    -- #1855 (2026-08-18): faixa de filiacao ja VENCIDA. Catalogado de proposito, e nao deixado
    -- cair no ELSE, pelo mesmo motivo registrado no bloco 5b da #625: o ELSE e um default de
    -- conveniencia e um dia muda. digest_weekly porque o PM decidiu 'so lembrete, mesmo tom'.
    WHEN 'affiliation_renewal_expired'    THEN 'digest_weekly'
    -- #2152 (2026-09-03): a verificacao ficou atras do VEP. Vai para a diretoria, nao para o
    -- membro, e no mesmo modo da faixa irma de verificacao obsoleta: e trabalho de fila, nao
    -- urgencia. Catalogado em vez de cair no ELSE, pelo motivo registrado acima.
    WHEN 'affiliation_vep_divergence'     THEN 'digest_weekly'
    -- #1224 PR2 (2026-07-09): one-time onboarding nudge when the PMI enrichment cannot resolve
    -- an entry chapter (profile_private / no_fetch / not_affiliated / ambiguous-no-choice).
    WHEN 'entry_chapter_action_needed'    THEN 'transactional_immediate'
    -- #740 Wave 3c-i (B8): agreement rejected / reissued — member must re-sign, deliver immediately
    WHEN 'volunteer_agreement_rejected'  THEN 'transactional_immediate'
    WHEN 'volunteer_agreement_reissued'  THEN 'transactional_immediate'
    WHEN 'attendance_detractor'          THEN 'suppress'
    WHEN 'info'                          THEN 'suppress'
    WHEN 'system'                        THEN 'suppress'
    -- #2285 (2026-09-14): o detector de contas nao ligadas passou a ter cron. Catalogado de
    -- proposito, e nao deixado cair no ELSE, pelo mesmo motivo registrado acima para #625,
    -- #1855 e #2152. Aqui o ELSE e pior que um default inconveniente: digest_weekly monta as
    -- secoes por lista branca de tipos e carimba como entregue o que nao renderizou (#2286).
    -- #2580 C1 (2026-10-08): no sino na hora; o e-mail sai no resumo diario da gestao. `suppress` e nao
    -- digest_weekly: o resumo semanal so le digest_weekly, entao nao ha carimbo sem renderizar (#2286).
    WHEN 'unlinked_accounts_detected'     THEN 'suppress'
    -- #2580 C: o resumo diario da gestao e um e-mail proprio.
    WHEN 'management_daily_digest'        THEN 'transactional_immediate'
    -- #2444 (2026-09-24): rodizio de pareceristas da curadoria. Imediato de proposito: a
    -- designacao e o lembrete sao o que da dono ao parecer; o digest semanal chegaria depois do
    -- prazo de 7 dias. O vencido vai para quem gere a plataforma, tambem imediato: e decisao.
    WHEN 'curation_review_assigned'       THEN 'transactional_immediate'
    WHEN 'curation_review_overdue'        THEN 'transactional_immediate'
    -- #2496 (2026-09-27): aviso a tribo (participantes do card e lideranca da iniciativa) de que o
    -- item entrou em curadoria. Imediato de proposito: caia em card_moved (digest_weekly), com o
    -- codigo cru do status e link generico, e nenhuma das 3 pessoas da tribo recebeu e-mail.
    WHEN 'curation_submitted_to_tribe'    THEN 'transactional_immediate'
    -- #2621 (2026-10-09): a DECISAO da curadoria volta para a mesma audiencia do aviso de entrada
    -- (participantes do card e lideranca ativa da iniciativa). Imediatos de proposito: devolucao e
    -- rejeicao nao avisavam ninguem, e o primeiro parecer real da plataforma passou mudo; no ELSE
    -- (digest_weekly) o pedido de ajuste chegaria dias depois, com o prazo do autor correndo.
    WHEN 'curation_decision_returned'     THEN 'transactional_immediate'
    WHEN 'curation_decision_rejected'     THEN 'transactional_immediate'
    WHEN 'curation_decision_approved'     THEN 'transactional_immediate'
    -- #2495 (2026-09-27): piloto do wiki vivo (ADR-0129, emenda 2). Imediatos de proposito: a
    -- lideranca publica na hora e o comite audita em 14 dias; um aviso que chegasse no digest
    -- semanal comeria metade do prazo. O vencido vai para quem gere a plataforma.
    WHEN 'wiki_review_requested'          THEN 'transactional_immediate'
    WHEN 'wiki_page_decision'             THEN 'transactional_immediate'
    WHEN 'wiki_audit_requested'           THEN 'transactional_immediate'
    WHEN 'wiki_audit_overdue'             THEN 'transactional_immediate'
    -- #2495 fase B2 (2026-09-29): "Sugerir melhoria". Imediatos pelo mesmo motivo dos avisos do wiki
    -- acima: a sugestao vai a quem decide sobre a pagina, e a resposta volta a quem sugeriu; um aviso
    -- no digest semanal chegaria depois de a pessoa ter esquecido o que sugeriu.
    WHEN 'wiki_suggestion_received'       THEN 'transactional_immediate'
    WHEN 'wiki_suggestion_decision'       THEN 'transactional_immediate'
    -- #2444 (2026-09-24): a revisao do lider e a devolucao ao autor. Imediatos de proposito: caiam no
    -- ELSE (digest_weekly) e, medido, leader_review_requested nunca gerou uma linha sequer; sem aviso,
    -- 16 cards ficaram parados em leader_review desde maio.
    WHEN 'leader_review_requested'        THEN 'transactional_immediate'
    WHEN 'leader_review_returned'         THEN 'transactional_immediate'
    -- #2454 (2026-09-24): falha de acesso ao Drive. Imediatos: a pessoa esta sem acesso a pasta da
    -- iniciativa agora (e nao sabia: 3 casos medidos), e a falha da conta de servico e acao do
    -- administrador do Workspace.
    WHEN 'drive_access_action_needed'     THEN 'transactional_immediate'
    WHEN 'drive_access_admin_needed'      THEN 'transactional_immediate'
    -- Varredura de dado pessoal no tracker publico (10/10/2026). Imediato de proposito: o dado segue publico
    -- enquanto ninguem age, e no ELSE (digest_weekly) o e-mail chegaria em ate sete dias.
    WHEN 'tracker_pii_found'              THEN 'transactional_immediate'
    -- #2593 (C2, decisão do GP 11/10/2026): o dono do bloco da Agenda Viva sabe pelo sino, não por e-mail, quando
    -- a coordenação confirma ou cancela o bloco dele. Catalogados para não cair no ELSE (digest_weekly), que
    -- mandaria um resumo semanal de algo que só serve na hora.
    WHEN 'agenda_block_confirmed'         THEN 'suppress'
    WHEN 'agenda_block_cancelled'         THEN 'suppress'
    ELSE 'digest_weekly'
  END;
$function$;

-- ── (3) confirmação ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.confirm_agenda_block(p_block_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_caller  uuid;
  v_block   record;
  v_present boolean;
  v_invite  uuid;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT public.can_by_member(v_caller, 'manage_event') THEN
    RETURN jsonb_build_object('error', 'access_denied', 'required', 'manage_event');
  END IF;

  SELECT * INTO v_block FROM public.event_agenda_blocks WHERE id = p_block_id FOR UPDATE;
  IF v_block.id IS NULL THEN RETURN jsonb_build_object('error', 'block_not_found'); END IF;
  IF v_block.status = 'cancelled' THEN
    RETURN jsonb_build_object('error', 'cannot_confirm_cancelled', 'block_id', p_block_id);
  END IF;
  -- Re-confirming an already-confirmed block is intentionally a no-op on XP (the credit is
  -- idempotent by ref_id) but DOES re-attempt the credit — this is the heal path for
  -- "confirmed before attendance was marked, then corrected to present, then re-confirmed".

  v_present := EXISTS (
    SELECT 1 FROM public.attendance
    WHERE event_id = v_block.event_id AND member_id = v_block.owner_member_id AND present = true
  );

  UPDATE public.event_agenda_blocks
     SET status = 'confirmed', confirmed_at = now()
   WHERE id = p_block_id;

  IF v_present THEN
    PERFORM public._grant_agenda_block_xp(p_block_id);
  END IF;

  -- #2593 (C2): convidado externo ainda não avisado recebe o convite com ICS; o carimbo guest_notified_at só vem
  -- quando o provedor aceita o envio (send-campaign), e é ele que libera o nome na agenda pública
  IF v_block.external_guest AND v_block.guest_notified_at IS NULL THEN
    v_invite := public._agenda_guest_send(p_block_id, 'invite', v_caller, true);
  END IF;

  -- #2593 (C2): o dono sabe pelo sino quando OUTRA pessoa confirma o bloco dele (só na transição, não no reparo)
  IF v_block.status IS DISTINCT FROM 'confirmed' AND v_block.owner_member_id <> v_caller THEN
    PERFORM public._agenda_block_owner_notice(p_block_id, 'agenda_block_confirmed');
  END IF;

  RETURN jsonb_build_object('success', true, 'block_id', p_block_id, 'status', 'confirmed',
                            'xp_credited', v_present, 'guest_invite_send_id', v_invite);
END;
$function$;

REVOKE ALL ON FUNCTION public.confirm_agenda_block(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_agenda_block(uuid) TO authenticated;

-- ── (4) cancelamento ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cancel_agenda_block(
  p_block_id uuid,
  p_reason   text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_caller   uuid;
  v_is_admin boolean;
  v_block    record;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  v_is_admin := public.can_by_member(v_caller, 'manage_event');

  SELECT b.*, (e.date + COALESCE(e.time_start,'00:00'::time)) AT TIME ZONE COALESCE(e.timezone,'America/Sao_Paulo') AS start_at
    INTO v_block
    FROM public.event_agenda_blocks b JOIN public.events e ON e.id = b.event_id
    WHERE b.id = p_block_id
    FOR UPDATE OF b;
  IF v_block.id IS NULL THEN RETURN jsonb_build_object('error', 'block_not_found'); END IF;
  IF v_block.status = 'cancelled' THEN RETURN jsonb_build_object('success', true, 'block_id', p_block_id, 'already', true); END IF;

  IF NOT v_is_admin THEN
    IF v_block.owner_member_id <> v_caller THEN RETURN jsonb_build_object('error', 'access_denied'); END IF;
    IF now() >= v_block.start_at THEN RETURN jsonb_build_object('error', 'cancel_window_closed'); END IF;
  END IF;

  -- #2593 (C2): convidado que já recebeu o convite recebe o cancelamento com ICS, que libera a agenda dele. O
  -- envio copia o e-mail para o destinatário antes de o vínculo sair, então a ordem importa.
  IF v_block.external_guest AND v_block.guest_notified_at IS NOT NULL THEN
    PERFORM public._agenda_guest_send(p_block_id, 'cancel', v_caller, true);
  END IF;

  -- #2593: bloco cancelado não precisa mais do contato do convidado; o vínculo sai e a varredura decide a pessoa
  PERFORM public._agenda_guest_detach(p_block_id);
  UPDATE public.event_agenda_blocks
     SET status = 'cancelled', cancelled_by = v_caller, cancelled_reason = p_reason, guest_person_id = NULL
   WHERE id = p_block_id;

  -- #2593 (C2): cancelado por outra pessoa (a coordenação), o dono sabe pelo sino
  IF v_block.owner_member_id <> v_caller THEN
    PERFORM public._agenda_block_owner_notice(p_block_id, 'agenda_block_cancelled');
  END IF;

  RETURN jsonb_build_object('success', true, 'block_id', p_block_id, 'status', 'cancelled');
END
$function$;

REVOKE ALL ON FUNCTION public.cancel_agenda_block(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_agenda_block(uuid, text) TO authenticated;

-- ── pós-condição ──────────────────────────────────────────────────────────────
DO $postcondition$
DECLARE
  v_n integer;
BEGIN
  -- os dois templates, nos 3 idiomas, com o miolo aprovado e o rodapé de pessoa externa do avulso
  SELECT count(*) INTO v_n FROM public.campaign_templates t
  WHERE t.slug IN ('agenda-convite-convidado', 'agenda-cancelamento-convidado')
    AND t.subject ?& ARRAY['pt', 'en', 'es'] AND t.body_html ?& ARRAY['pt', 'en', 'es'] AND t.body_text ?& ARRAY['pt', 'en', 'es']
    AND t.body_html->>'pt' LIKE '%<!--EXTERNO-->%<!--/EXTERNO-->%'
    AND t.body_text->>'pt' LIKE '%[[EXTERNO]]%[[/EXTERNO]]%'
    AND t.body_html->>'pt' NOT LIKE '%{{content_html}}%' AND t.body_text->>'pt' NOT LIKE '%{{content_text}}%';
  IF v_n <> 2 THEN RAISE EXCEPTION '#2593: esperava os 2 templates completos, achei %', v_n; END IF;

  -- o sino ao dono não vira e-mail
  IF public._delivery_mode_for('agenda_block_confirmed') <> 'suppress'
     OR public._delivery_mode_for('agenda_block_cancelled') <> 'suppress'
     OR public._delivery_mode_for('tipo_que_nao_existe') <> 'digest_weekly' THEN
    RAISE EXCEPTION '#2593: modo de entrega do sino fora do esperado';
  END IF;

  IF has_function_privilege('authenticated', 'public._agenda_guest_send(uuid, text, uuid, boolean)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public._agenda_block_owner_notice(uuid, text)', 'EXECUTE') THEN
    RAISE EXCEPTION '#2593: auxiliar de envio alcançável por authenticated';
  END IF;

  -- controle em subtransação desfeita, SEM despacho: o envio leva o contato só no destinatário, no idioma do bloco
  DECLARE
    v_event uuid;
    v_owner uuid;
    v_block uuid;
    v_send  uuid;
    v_af    jsonb;
    v_rec   record;
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
      RAISE NOTICE '#2593: sem reunião geral futura para o controle; pulado';
    ELSE
      INSERT INTO public.event_agenda_blocks (event_id, owner_member_id, format_slug, title, duration_min,
                                              guest_name, external_guest, guest_language, status, sort_order, created_by)
      SELECT v_event, v_owner, f.slug, 'controle #2593 C2', 5, 'Controle C2', true, 'es-LATAM', 'confirmed', 999, v_owner
      FROM public.agenda_block_formats f WHERE f.active LIMIT 1
      RETURNING id INTO v_block;
      PERFORM public._agenda_guest_attach(v_block, 'Controle C2', 'controle-2593-c2@example.org');

      v_send := public._agenda_guest_send(v_block, 'invite', v_owner, false);
      IF v_send IS NULL THEN RAISE EXCEPTION '#2593: o convite não foi montado'; END IF;
      SELECT audience_filter INTO v_af FROM public.campaign_sends WHERE id = v_send;
      IF v_af::text ~ 'controle-2593-c2@' OR v_af::text ~ 'Controle C2' THEN
        RAISE EXCEPTION '#2593: o envio guardou contato do convidado';
      END IF;
      SELECT external_email, external_name, language INTO v_rec FROM public.campaign_recipients WHERE send_id = v_send;
      IF v_rec.external_email IS DISTINCT FROM 'controle-2593-c2@example.org' OR v_rec.language IS DISTINCT FROM 'es-LATAM' THEN
        RAISE EXCEPTION '#2593: destinatário do convite fora do esperado (%)', to_jsonb(v_rec);
      END IF;
      -- um convite por convidado por bloco
      IF public._agenda_guest_send(v_block, 'invite', v_owner, false) IS NOT NULL THEN
        RAISE EXCEPTION '#2593: o segundo convite ao mesmo convidado foi montado';
      END IF;
      -- sem aviso registrado, não há cancelamento a mandar
      IF public._agenda_guest_send(v_block, 'cancel', v_owner, false) IS NOT NULL THEN
        RAISE EXCEPTION '#2593: cancelamento montado para quem não foi avisado';
      END IF;
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = '__2593c2_rollback__';
    END IF;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> '__2593c2_rollback__' THEN RAISE; END IF;
  END;
END
$postcondition$;
