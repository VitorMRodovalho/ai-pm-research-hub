-- #2586 + #2593, fatia A (banco): temas de comunicação e o caminho único de "pessoa externa por e-mail",
-- com prazo de guarda e varredura diária. Decisões do GP (09/10/2026), registradas nas duas issues:
--   * taxonomia fechada de 11 temas: os 10 aprovados mais 'plataforma' (alertas operacionais da gestão);
--   * guarda: evento + 1 ano (convidado), envio + 1 ano (e-mail externo), também para os envios antigos;
--   * a pessoa externa nasce com consent_status 'pending' (finalidade: convite ou envio).
--
-- (1) campaign_themes + campaign_templates.theme + campaign_sends.theme. A coluna `category` NÃO muda: cinco
--     funções (exec_funnel_summary, exec_funnel_v2, fork_idea_to_channel, get_application_communications,
--     notify_privacy_policy_change), a tela de campanhas e o MCP leem os seus valores; ela fica como o TIPO
--     do envio, e o tema é uma coluna nova. Os 55 templates recebem tema (mapeamento mostrado ao GP).
-- (2) platform_settings: reply-to padrão das campanhas e ORGANIZER dos convites de agenda (decisão do GP: caixa
--     institucional do Núcleo; trocar depois sem PR, quando a #2642 decidir a conta das reuniões).
-- (3) person_external_links: cada uso de um e-mail de fora (convidado de agenda, envio avulso, certificado de
--     convidado), com o seu prazo. _external_person_upsert acha a pessoa pelo e-mail principal ou secundário
--     (como o certificado já faz) ou a cria; e-mail de membro ou de quem tem login segue o ciclo de vida de
--     membro e não ganha vínculo de prazo.
-- (4) _external_contact_retention_sweep, diária:
--     a) anonimiza e-mail, nome, erro e user agent em campaign_recipients de envio externo com mais de 1 ano,
--        SALVO e-mail de membro (members.email/secondary_emails, ou persons com membro ou login) ou de
--        candidatura não anonimizada (o prazo da seleção é outro). Cada envio vence pela própria data: um uso
--        novo do e-mail não renova envio antigo. Medido em 09/10: 692 linhas externas, 615 de e-mail de
--        candidatura, 491 de membro (há sobreposição), 13 de mais ninguém; a mais antiga é de 29/04/2026;
--     b) apaga vínculos vencidos;
--     c) apaga a pessoa CRIADA por este caminho (consent_version = 'external-contact') que ficou sem vínculo e
--        sem nenhum laço: login, membro, PMI ID, engajamento, certificado, progresso, afiliação, acesso ao
--        Drive, inscrição em competição (FK NO ACTION, medida pela orquestradora em 10/10). Pessoa que já existia antes (candidato, competição, membro) só perde o vínculo. O critério é
--        de ESTADO, então quem uma FK pulou hoje é revista amanhã;
--     d) troca o nome do convidado externo da agenda por "Convidado(a) externo(a)" 1 ano depois da reunião
--        (hoje: 14 blocos com nome de convidado, 2 externos; o coapresentador membro não é tocado).
--     A lista de supressão de e-mail (#2130) não é tocada: quem pediu para não receber continua sem receber.
--     'pending' aqui NÃO é "falta consentir": é tratamento por legítimo interesse (convite, envio pontual),
--     sem consentimento coletado. Nada promove a 'accepted' por RSVP de calendário.
--     Revisão do conselho (legal-counsel, security-engineer, data-architect, 09/10/2026) incorporada.
-- (5) campaign_recipients.person_id, para o envio avulso a pessoa externa (fatia B).
--
-- Rollback: SELECT cron.unschedule('external-contact-retention-daily'); DELETE das duas linhas de
--   data_retention_policy com esse executor; DROP das funções novas, de person_external_links e
--   campaign_themes; DROP das colunas theme e person_id; DELETE das duas chaves de platform_settings.

-- ── (1) temas ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.campaign_themes (
  slug        text PRIMARY KEY CHECK (slug ~ '^[a-z]+$'),
  label_i18n  jsonb NOT NULL CHECK (jsonb_typeof(label_i18n) = 'object' AND label_i18n ? 'pt'),
  reply_to    text CHECK (reply_to IS NULL OR reply_to ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  sort_order  integer NOT NULL DEFAULT 0,
  is_active   boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.campaign_themes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.campaign_themes FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.campaign_themes TO authenticated;
DROP POLICY IF EXISTS campaign_themes_read_authenticated ON public.campaign_themes;
-- só membro lê (o guard derivado do catálogo barra leitura por autenticado sem linha em members)
CREATE POLICY campaign_themes_read_authenticated ON public.campaign_themes FOR SELECT TO authenticated USING (public.rls_is_member());
COMMENT ON TABLE public.campaign_themes IS
  '#2586: taxonomia fechada de temas de comunicação (templates e envios); a #2580 agrupa por ela. reply_to NULL = padrão de platform_settings.';

INSERT INTO public.campaign_themes (slug, label_i18n, sort_order) VALUES
  ('filiacao',     '{"pt":"Filiação","en":"Membership","es":"Afiliación"}', 10),
  ('selecao',      '{"pt":"Seleção","en":"Selection","es":"Selección"}', 20),
  ('onboarding',   '{"pt":"Onboarding","en":"Onboarding","es":"Onboarding"}', 30),
  ('conta',        '{"pt":"Conta e acesso","en":"Account and access","es":"Cuenta y acceso"}', 40),
  ('governanca',   '{"pt":"Governança","en":"Governance","es":"Gobernanza"}', 50),
  ('eventos',      '{"pt":"Eventos","en":"Events","es":"Eventos"}', 60),
  ('iniciativas',  '{"pt":"Tribos e iniciativas","en":"Tribes and initiatives","es":"Tribus e iniciativas"}', 70),
  ('curadoria',    '{"pt":"Curadoria","en":"Curation","es":"Curaduría"}', 80),
  ('certificados', '{"pt":"Certificados","en":"Certificates","es":"Certificados"}', 90),
  ('comunicacao',  '{"pt":"Comunicação","en":"Communication","es":"Comunicación"}', 100),
  ('plataforma',   '{"pt":"Plataforma (alertas da gestão)","en":"Platform (management alerts)","es":"Plataforma (alertas de la gestión)"}', 110)
ON CONFLICT (slug) DO NOTHING;

ALTER TABLE public.campaign_templates ADD COLUMN IF NOT EXISTS theme text REFERENCES public.campaign_themes(slug);
ALTER TABLE public.campaign_sends     ADD COLUMN IF NOT EXISTS theme text REFERENCES public.campaign_themes(slug);
CREATE INDEX IF NOT EXISTS idx_campaign_templates_theme ON public.campaign_templates (theme);
CREATE INDEX IF NOT EXISTS idx_campaign_sends_theme ON public.campaign_sends (theme);
COMMENT ON COLUMN public.campaign_templates.category IS
  'TIPO do envio (operational, announcement, onboarding, newsletter). O assunto do Núcleo é `theme` (#2586).';
COMMENT ON COLUMN public.campaign_templates.theme IS '#2586: tema do Núcleo (campaign_themes).';
COMMENT ON COLUMN public.campaign_sends.theme IS
  '#2586: tema do envio; NULL = o tema do template. O envio avulso de corpo livre grava o seu.';

UPDATE public.campaign_templates SET theme = 'certificados'
WHERE theme IS NULL AND slug IN (
    'cert-ciclo3-encerramento-2026-07');

UPDATE public.campaign_templates SET theme = 'comunicacao'
WHERE theme IS NULL AND slug IN (
    'beta-candidatos',
    'beta-comms',
    'beta-deputy',
    'beta-launch-all',
    'beta-liaisons',
    'beta-lideres',
    'beta-pesquisadores',
    'beta-sponsors',
    'blog-announcement',
    'mcp-29-tools-novo-dominio',
    'pmi-key-personnel',
    'reengagement-inactive');

UPDATE public.campaign_templates SET theme = 'conta'
WHERE theme IS NULL AND slug IN (
    'leadership-platform-access-cbgpl',
    'member_access_invite',
    'portal_account_setup');

UPDATE public.campaign_templates SET theme = 'curadoria'
WHERE theme IS NULL AND slug IN (
    'chamada-curadoria-4-vagas-out2026');

UPDATE public.campaign_templates SET theme = 'eventos'
WHERE theme IS NULL AND slug IN (
    'live-aberta-quinzenal-2026-05-07',
    'savethedate-aftershow-excandidatos-2026-07',
    'webinar-t6-04ago-membros');

UPDATE public.campaign_templates SET theme = 'governanca'
WHERE theme IS NULL AND slug IN (
    'governance_curator_review_request',
    'governance_recirculation_batch',
    'governance_recirculation_request',
    'onda-e-c4-guests-reselect-termo-v9',
    'privacy-v22-platform-v3',
    'tribe_term_needed_c4',
    'volunteer_term_reaccept_v9',
    'volunteer_term_signing_leaders_c4',
    'volunteer_term_signing_reminder_c4');

UPDATE public.campaign_templates SET theme = 'iniciativas'
WHERE theme IS NULL AND slug IN (
    'pesquisa-tribo4-cultura-change-reforco-set2026',
    'pesquisa-tribo4-cultura-change-set2026',
    'tribe_registration_open_c4');

UPDATE public.campaign_templates SET theme = 'onboarding'
WHERE theme IS NULL AND slug IN (
    'c4-onboarding-pendencias-2026-07',
    'cycle4_pre_onboarding_whatsapp_20260613',
    'onboarding-researcher',
    'onboarding-tribe-leader',
    'pmi_consent_nudge',
    'pmi_welcome_with_token',
    'preonb-checklist-c4-kickoff-2026-07',
    'preonb-kickoff-day-reminder-c4-2026-07-09');

UPDATE public.campaign_templates SET theme = 'plataforma'
WHERE theme IS NULL AND slug IN (
    'cron_failure_alert',
    'platform_alert_digest');

UPDATE public.campaign_templates SET theme = 'selecao'
WHERE theme IS NULL AND slug IN (
    'interview_noshow_soft_reschedule',
    'interview_reminder_1h',
    'interview_reschedule_nudge',
    'interview_reschedule_request',
    'interview_two_strike_close',
    'peer_review_request',
    'pre_eval_pause',
    'selection_cutoff_approved',
    'selection_interview_invite_dual_2026',
    'selection_interview_urgency_deadline_2026',
    'selection_interview_urgent_reminder_c4',
    'selection_vep_expired_reapply_invite',
    'vep_offer_accept_reminder');

-- ── (2) configurações ─────────────────────────────────────────────────────────
INSERT INTO public.platform_settings (key, value, description) VALUES
  ('campaign_default_reply_to', to_jsonb('nucleoia@pmigo.org.br'::text),
   '#2586: reply-to padrão das campanhas; campaign_themes.reply_to sobrepõe por tema.'),
  ('agenda_invite_organizer_email', to_jsonb('nucleoia@pmigo.org.br'::text),
   '#2593: ORGANIZER do ICS do convite ao convidado externo (recebe aceite e recusa). Decisão do GP em 09/10/2026; a conta das reuniões está na #2642.')
ON CONFLICT (key) DO NOTHING;

-- ── (3) pessoa externa ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.person_external_links (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id       uuid NOT NULL REFERENCES public.persons(id) ON DELETE CASCADE,
  purpose         text NOT NULL CHECK (purpose IN ('agenda_guest', 'campaign_one_off', 'event_guest_certificate')),
  source_id       uuid NOT NULL,
  retention_until date NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT person_external_links_once UNIQUE (person_id, purpose, source_id)
);
CREATE INDEX IF NOT EXISTS idx_person_external_links_retention ON public.person_external_links (retention_until);
ALTER TABLE public.person_external_links ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.person_external_links FROM PUBLIC, anon, authenticated;
DROP POLICY IF EXISTS rpc_only_deny_all ON public.person_external_links;
CREATE POLICY rpc_only_deny_all ON public.person_external_links FOR ALL USING (false);
COMMENT ON TABLE public.person_external_links IS
  '#2586/#2593: cada uso de e-mail de pessoa de fora, com prazo de guarda. A pessoa só é apagada quando todos vencem e ela não tem outro vínculo (_external_contact_retention_sweep).';

ALTER TABLE public.campaign_recipients ADD COLUMN IF NOT EXISTS person_id uuid REFERENCES public.persons(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_campaign_recipients_person ON public.campaign_recipients (person_id) WHERE person_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public._external_person_upsert(
  p_email text, p_name text, p_purpose text, p_source_id uuid, p_retention_until date
)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_email     text := lower(btrim(coalesce(p_email, '')));
  v_id        uuid;
  v_protected boolean := false;
BEGIN
  IF v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RAISE EXCEPTION 'A valid e-mail is required' USING ERRCODE = 'check_violation';
  END IF;
  IF p_purpose IS NULL OR p_purpose NOT IN ('agenda_guest', 'campaign_one_off', 'event_guest_certificate') THEN
    RAISE EXCEPTION 'Unknown purpose: %', p_purpose USING ERRCODE = 'check_violation';
  END IF;
  IF p_source_id IS NULL OR p_retention_until IS NULL THEN
    RAISE EXCEPTION 'source_id and retention_until are required' USING ERRCODE = 'check_violation';
  END IF;

  -- persons.email não é UNIQUE: duas chamadas simultâneas para o mesmo e-mail criariam duas pessoas
  PERFORM pg_advisory_xact_lock(hashtext('external_person:' || v_email));

  -- mesma busca do certificado de convidado: e-mail principal ou secundário; membro tem prioridade
  SELECT p.id,
         (p.legacy_member_id IS NOT NULL OR p.auth_id IS NOT NULL OR p.pmi_id IS NOT NULL
          OR EXISTS (SELECT 1 FROM public.members m WHERE m.person_id = p.id))
    INTO v_id, v_protected
  FROM public.persons p
  WHERE lower(p.email) = v_email
     OR EXISTS (SELECT 1 FROM unnest(p.secondary_emails) se WHERE lower(se) = v_email)
  ORDER BY (p.legacy_member_id IS NOT NULL) DESC, (p.auth_id IS NOT NULL) DESC, p.created_at
  LIMIT 1;

  IF v_id IS NULL THEN
    -- a marca de origem: só a pessoa criada aqui pode ser apagada pela varredura
    INSERT INTO public.persons (name, email, consent_status, consent_version)
    VALUES (COALESCE(NULLIF(btrim(p_name), ''), split_part(v_email, '@', 1)), v_email, 'pending', 'external-contact')
    RETURNING id INTO v_id;
    v_protected := false;
  END IF;

  -- membro, quem tem login ou PMI ID segue o próprio ciclo de vida: sem vínculo de prazo
  IF NOT v_protected THEN
    INSERT INTO public.person_external_links (person_id, purpose, source_id, retention_until)
    VALUES (v_id, p_purpose, p_source_id, p_retention_until)
    ON CONFLICT (person_id, purpose, source_id) DO UPDATE
      SET retention_until = GREATEST(public.person_external_links.retention_until, EXCLUDED.retention_until),
          updated_at = now();
  END IF;

  RETURN v_id;
END;
$function$;

COMMENT ON FUNCTION public._external_person_upsert(text, text, text, uuid, date) IS
  '#2586/#2593: acha ou cria a pessoa de um e-mail de fora. O e-mail NÃO é verificado: o chamador não deve tratar a pessoa como identidade confirmada nem devolver ao cliente nome ou e-mail da pessoa resolvida (seria oráculo de "este e-mail é de membro"). pending = legítimo interesse, sem consentimento coletado.';

REVOKE ALL ON FUNCTION public._external_person_upsert(text, text, text, uuid, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._external_person_upsert(text, text, text, uuid, date) TO service_role;

-- O certificado de convidado já existente passa a ter o seu vínculo (prazo = retention_until do certificado).
INSERT INTO public.person_external_links (person_id, purpose, source_id, retention_until)
SELECT g.person_id, 'event_guest_certificate', g.id, g.retention_until
FROM public.event_guest_certificates g
JOIN public.persons p ON p.id = g.person_id
WHERE p.legacy_member_id IS NULL AND p.auth_id IS NULL AND g.retention_until IS NOT NULL
ON CONFLICT (person_id, purpose, source_id) DO NOTHING;

-- ── (4) varredura diária ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._external_contact_retention_sweep(p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_cutoff     timestamptz := now() - interval '1 year';
  v_guest_name constant text := 'Convidado(a) externo(a)';
  v_recipients integer := 0;
  v_links      integer := 0;
  v_guests     integer := 0;
  v_deleted    uuid[] := '{}';
  v_skipped    uuid[] := '{}';
  r            record;
BEGIN
  -- (a) envio a e-mail externo com mais de 1 ano. Os e-mails protegidos vêm numa CTE só, para a busca ser
  --     um anti-join em hash e não um seq scan por linha.
  IF p_dry_run THEN
    WITH protected AS (
      SELECT lower(p.email) AS e FROM public.persons p
       WHERE p.legacy_member_id IS NOT NULL OR p.auth_id IS NOT NULL
      UNION SELECT lower(se) FROM public.persons p, unnest(p.secondary_emails) se
       WHERE p.legacy_member_id IS NOT NULL OR p.auth_id IS NOT NULL
      UNION SELECT lower(m.email) FROM public.members m
      UNION SELECT lower(se) FROM public.members m, unnest(m.secondary_emails) se
      UNION SELECT lower(a.email) FROM public.selection_applications a WHERE a.anonymized_at IS NULL
    )
    SELECT count(*) INTO v_recipients
    FROM public.campaign_recipients cr
    WHERE cr.member_id IS NULL AND cr.external_email IS NOT NULL AND cr.created_at < v_cutoff
      AND NOT EXISTS (SELECT 1 FROM protected pr WHERE pr.e = lower(cr.external_email));
  ELSE
    WITH protected AS (
      SELECT lower(p.email) AS e FROM public.persons p
       WHERE p.legacy_member_id IS NOT NULL OR p.auth_id IS NOT NULL
      UNION SELECT lower(se) FROM public.persons p, unnest(p.secondary_emails) se
       WHERE p.legacy_member_id IS NOT NULL OR p.auth_id IS NOT NULL
      UNION SELECT lower(m.email) FROM public.members m
      UNION SELECT lower(se) FROM public.members m, unnest(m.secondary_emails) se
      UNION SELECT lower(a.email) FROM public.selection_applications a WHERE a.anonymized_at IS NULL
    )
    UPDATE public.campaign_recipients cr
    SET external_email = NULL, external_name = NULL, error_message = NULL, last_user_agent = NULL, person_id = NULL
    WHERE cr.member_id IS NULL AND cr.external_email IS NOT NULL AND cr.created_at < v_cutoff
      AND NOT EXISTS (SELECT 1 FROM protected pr WHERE pr.e = lower(cr.external_email));
    GET DIAGNOSTICS v_recipients = ROW_COUNT;
  END IF;

  -- (b) vínculos vencidos
  IF p_dry_run THEN
    SELECT count(*) INTO v_links FROM public.person_external_links l WHERE l.retention_until < current_date;
  ELSE
    DELETE FROM public.person_external_links l WHERE l.retention_until < current_date;
    GET DIAGNOSTICS v_links = ROW_COUNT;
  END IF;

  -- (c) por ESTADO: pessoa criada por este caminho, sem vínculo vigente e sem nenhum outro laço
  FOR r IN
    SELECT p.id FROM public.persons p
    WHERE p.consent_version = 'external-contact'
      AND p.auth_id IS NULL AND p.legacy_member_id IS NULL AND p.pmi_id IS NULL
      AND NOT EXISTS (SELECT 1 FROM public.person_external_links l
                      WHERE l.person_id = p.id AND l.retention_until >= current_date)
      AND NOT EXISTS (SELECT 1 FROM public.members m WHERE m.person_id = p.id)
      AND NOT EXISTS (SELECT 1 FROM public.engagements en
                      WHERE en.person_id = p.id OR en.granted_by = p.id OR en.revoked_by = p.id)
      AND NOT EXISTS (SELECT 1 FROM public.event_guest_certificates g WHERE g.person_id = p.id)
      AND NOT EXISTS (SELECT 1 FROM public.initiative_member_progress imp WHERE imp.person_id = p.id)
      AND NOT EXISTS (SELECT 1 FROM public.member_chapter_affiliations mca WHERE mca.person_id = p.id)
      AND NOT EXISTS (SELECT 1 FROM public.drive_membership_grants dmg WHERE dmg.grantee_person_id = p.id)
      -- FK NO ACTION: com inscrição de competição o DELETE falharia; a competição tem a própria retenção
      AND NOT EXISTS (SELECT 1 FROM competition.registrations cr2 WHERE cr2.person_id = p.id)
  LOOP
    IF p_dry_run THEN
      v_deleted := v_deleted || r.id;
    ELSE
      BEGIN
        DELETE FROM public.persons WHERE id = r.id;
        v_deleted := v_deleted || r.id;
      EXCEPTION WHEN foreign_key_violation THEN
        v_skipped := v_skipped || r.id;
      END;
    END IF;
  END LOOP;

  -- (d) nome do convidado externo na agenda, 1 ano depois da reunião
  IF p_dry_run THEN
    SELECT count(*) INTO v_guests
    FROM public.event_agenda_blocks b JOIN public.events e ON e.id = b.event_id
    WHERE b.external_guest AND b.guest_name IS NOT NULL AND b.guest_name <> v_guest_name
      AND e.date < current_date - interval '1 year';
  ELSE
    UPDATE public.event_agenda_blocks b SET guest_name = v_guest_name
    FROM public.events e
    WHERE e.id = b.event_id
      AND b.external_guest AND b.guest_name IS NOT NULL AND b.guest_name <> v_guest_name
      AND e.date < current_date - interval '1 year';
    GET DIAGNOSTICS v_guests = ROW_COUNT;
  END IF;

  -- trilha só quando houve efeito (ou pulo): um dia sem nada não vira linha de auditoria
  IF NOT p_dry_run AND (v_recipients + v_links + v_guests + cardinality(v_deleted) + cardinality(v_skipped)) > 0 THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, changes, metadata)
    VALUES (NULL, 'lgpd.external_contact_retention_sweep', 'retention',
            jsonb_build_object('recipients_anonymized', v_recipients, 'links_deleted', v_links,
                               'agenda_guest_names_anonymized', v_guests,
                               'persons_deleted', to_jsonb(v_deleted), 'persons_skipped_fk', to_jsonb(v_skipped)),
            jsonb_build_object('source', '_external_contact_retention_sweep'));
  END IF;

  RETURN jsonb_build_object('dry_run', p_dry_run, 'recipients_anonymized', v_recipients,
                            'links_deleted', v_links, 'agenda_guest_names_anonymized', v_guests,
                            'persons_deleted', cardinality(v_deleted), 'persons_skipped_fk', cardinality(v_skipped),
                            'person_ids', to_jsonb(v_deleted));
END;
$function$;

-- Cron não tem sessão: o worker acima não depende dela, e o wrapper só o chama de verdade.
CREATE OR REPLACE FUNCTION public._external_contact_retention_cron()
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT public._external_contact_retention_sweep(false);
$function$;

REVOKE ALL ON FUNCTION public._external_contact_retention_sweep(boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._external_contact_retention_cron() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._external_contact_retention_sweep(boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public._external_contact_retention_cron() TO service_role;

INSERT INTO public.data_retention_policy (table_name, retention_days, cleanup_type, description, is_active, executor)
SELECT v.table_name, v.retention_days, v.cleanup_type, v.description, true, 'external-contact-retention-daily'
FROM (VALUES
  ('campaign_recipients', 365, 'anonymize',
   'LGPD (#2586): envio a e-mail externo anonimizado 1 ano depois do envio, salvo e-mail de membro ou de candidatura não anonimizada.'),
  ('person_external_links', 365, 'delete',
   'LGPD (#2586/#2593): vínculo de pessoa externa apagado no seu retention_until (evento + 1 ano, envio + 1 ano); a pessoa criada por esse caminho e sem outro laço sai junto, e o nome do convidado externo na agenda é anonimizado 1 ano depois da reunião.')
) AS v(table_name, retention_days, cleanup_type, description)
WHERE NOT EXISTS (SELECT 1 FROM public.data_retention_policy d
                  WHERE d.table_name = v.table_name AND d.executor = 'external-contact-retention-daily');

-- Todo dia às 05:23 UTC (02:23 em Brasília). pg_cron: schedule com nome existente atualiza o job.
SELECT cron.schedule('external-contact-retention-daily', '23 5 * * *',
                     $$SELECT public._external_contact_retention_cron()$$);

-- ── pós-condição: aborta a migration inteira se algo saiu errado ─────────────
DO $postcondition$
DECLARE
  v_n        integer;
  v_dry      jsonb;
  v_ctrl     jsonb;
  v_ctrl_new uuid;
  v_ctrl_old uuid;
BEGIN
  SELECT count(*) INTO v_n FROM public.campaign_themes;
  IF v_n <> 11 THEN RAISE EXCEPTION '#2586: esperava 11 temas, há %', v_n; END IF;

  SELECT count(*) INTO v_n FROM public.campaign_templates WHERE theme IS NULL;
  IF v_n <> 0 THEN RAISE EXCEPTION '#2586: % template(s) sem tema', v_n; END IF;

  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'external-contact-retention-daily' AND active) THEN
    RAISE EXCEPTION '#2586: job external-contact-retention-daily ausente ou inativo';
  END IF;

  SELECT count(*) INTO v_n FROM public.data_retention_policy
  WHERE executor = 'external-contact-retention-daily' AND is_active;
  IF v_n <> 2 THEN RAISE EXCEPTION '#2586: esperava 2 políticas com o executor novo, há %', v_n; END IF;

  -- a varredura roda em modo ensaio sem erro; hoje nada venceu (o envio externo mais antigo é de 29/04/2026)
  v_dry := public._external_contact_retention_sweep(true);
  IF (v_dry->>'recipients_anonymized')::int <> 0 THEN
    RAISE EXCEPTION '#2586: o ensaio anonimizaria % envio(s) hoje; esperava 0', v_dry->>'recipients_anonymized';
  END IF;

  -- Controles em subtransação desfeita (nada fica gravado): o instrumento precisa saber dizer SIM e NÃO.
  --   positivo: pessoa criada pelo caminho externo, com vínculo vencido -> entra na conta de apagadas;
  --   negativo: pessoa que já existia (sem a marca de origem), com vínculo vencido -> NÃO entra.
  BEGIN
    v_ctrl_new := public._external_person_upsert('controle-2586-novo@exemplo.invalid', 'Controle', 'campaign_one_off',
                                                 gen_random_uuid(), current_date + 1);
    UPDATE public.person_external_links SET retention_until = current_date - 1 WHERE person_id = v_ctrl_new;
    INSERT INTO public.persons (name, email, consent_status)
    VALUES ('Controle antigo', 'controle-2586-antigo@exemplo.invalid', 'pending') RETURNING id INTO v_ctrl_old;
    INSERT INTO public.person_external_links (person_id, purpose, source_id, retention_until)
    VALUES (v_ctrl_old, 'campaign_one_off', gen_random_uuid(), current_date - 1);
    v_ctrl := public._external_contact_retention_sweep(true);
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'controle-2586-desfazer';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'controle-2586-desfazer' THEN RAISE; END IF;
  END;
  IF NOT (v_ctrl->'person_ids') ? v_ctrl_new::text THEN
    RAISE EXCEPTION '#2586: controle positivo falhou: a pessoa criada pelo caminho externo não seria apagada';
  END IF;
  IF (v_ctrl->'person_ids') ? v_ctrl_old::text THEN
    RAISE EXCEPTION '#2586: controle negativo falhou: a pessoa sem a marca de origem seria apagada';
  END IF;
END
$postcondition$;

NOTIFY pgrst, 'reload schema';
