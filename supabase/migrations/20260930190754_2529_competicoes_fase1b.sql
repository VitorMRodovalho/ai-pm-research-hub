-- #2529 / ADR-0133, fase 1b: título curto, retenção por resultado com anonimização, e a edição piloto em rascunho.
--
-- Decisões do GP, confirmadas por ele diretamente em 30/09/2026 (pacote da lane do hackathon, commit d9c6e49 do
-- nucleo-hackathon): campos, declarações e textos da confirmação; título curto no assunto do e-mail; base legal
-- (contrato para o necessário, consentimento só no opcional); retenção: inscrição não selecionada anonimizada 6 meses
-- depois do dia do hackathon, participante 3 anos depois; abertura 19/10 às 09h00 e encerramento 09/11 às 23h59
-- (minuto inteiro); confirmação em até 48 h depois do envio conta; slug hackathon-impacto-social-2026.
--
-- O que muda:
--   (1) editions ganha short_title (assunto do e-mail), privacy_summary (resumo do aviso no formulário) e a retenção em
--       MESES por resultado (retention_unselected_months, retention_participant_months), contada do dia do hackathon
--       (events.date via event_id). Sai retention_days, que contava da inscrição e não servia a nenhuma das duas regras.
--       Abrir passa a exigir também o link do aviso e as duas retenções;
--   (2) registrations ganha anonymized_at, e o e-mail e o nome deixam de ser obrigatórios SÓ na linha anonimizada; um
--       CHECK garante que a linha anonimizada não guarda nada que aponte alguém;
--   (3) a limpeza passa a ANONIMIZAR a inscrição confirmada no fim da retenção (antes apagava), e anonimiza também a
--       pessoa que a competição criou quando ela não tem outra inscrição identificada nem outro vínculo. O "outro
--       vínculo" é lido do catálogo (toda FK que aponta para persons), não de lista escrita à mão. Fecha a lacuna
--       registrada no adendo da ADR-0133;
--   (4) competition_register deixa de gravar retention_until (o prazo não existe antes do dia do hackathon e do
--       resultado) e CORRIGE um defeito da fase 1: sem UTM na URL, v_ans->'utm' chega como o null do JSON (não o NULL do
--       SQL), o CHECK utm IS NULL OR jsonb_typeof(utm) = 'object' recusava a linha, e a inscrição sem UTM (o caso comum)
--       falhava. Nenhuma edição existia, então ninguém foi afetado; agora só grava UTM que seja objeto. A leitura
--       pública devolve título curto, resumo do aviso e o link de cada declaração; o conteúdo do e-mail devolve o
--       título curto; a declaração pode apontar o edital ou o aviso (link = rules | privacy);
--   (5) a edição piloto nasce em RASCUNHO, com a versão 1 do formulário. Não abre por aqui: abrir exige a versão da
--       política (a seção "Competições" da política da plataforma, que espera revisão jurídica), e o dia do hackathon
--       (D1) ainda não foi decidido.
--
-- ROLLBACK: DELETE da edição piloto e da sua versão de formulário; DELETE da política 'competition.registrations/anonymize';
--   recriar competition.purge, competition_register, competition_edition_public, _competition_email_payload e
--   form_version_guard pela migration 20260930162444; DROP das funções retention_date e person_has_other_links; DROP das
--   colunas novas e dos CHECKs novos, e de volta retention_days e os CHECKs antigos (sem dado a restaurar: nenhuma
--   inscrição existe).

-- ─── (1) edição ────────────────────────────────────────────────────────────────────────────────
ALTER TABLE competition.editions
  ADD COLUMN short_title text CHECK (short_title IS NULL OR char_length(short_title) BETWEEN 3 AND 60),
  ADD COLUMN privacy_summary text CHECK (privacy_summary IS NULL OR char_length(privacy_summary) <= 1200),
  ADD COLUMN retention_unselected_months int CHECK (retention_unselected_months IS NULL OR retention_unselected_months BETWEEN 1 AND 120),
  ADD COLUMN retention_participant_months int CHECK (retention_participant_months IS NULL OR retention_participant_months BETWEEN 1 AND 120);
ALTER TABLE competition.editions DROP CONSTRAINT editions_check2;
ALTER TABLE competition.editions DROP CONSTRAINT editions_retention_days_check;
ALTER TABLE competition.editions DROP COLUMN retention_days;
ALTER TABLE competition.editions ADD CONSTRAINT editions_open_requires_config
  CHECK (status = 'draft' OR (registration_opens_at IS NOT NULL AND registration_closes_at IS NOT NULL
         AND current_form_version_id IS NOT NULL AND privacy_policy_version IS NOT NULL AND privacy_notice_url IS NOT NULL
         AND legal_basis IS NOT NULL AND retention_unselected_months IS NOT NULL AND retention_participant_months IS NOT NULL));

-- ─── (2) inscrição anonimizável ────────────────────────────────────────────────────────────────
ALTER TABLE competition.registrations
  ADD COLUMN anonymized_at timestamptz,
  ALTER COLUMN email DROP NOT NULL,
  ALTER COLUMN full_name DROP NOT NULL;
ALTER TABLE competition.registrations DROP CONSTRAINT registrations_check1;
ALTER TABLE competition.registrations ADD CONSTRAINT registrations_person_after_confirm
  CHECK (status = 'pending_confirmation' OR person_id IS NOT NULL OR anonymized_at IS NOT NULL);
ALTER TABLE competition.registrations ADD CONSTRAINT registrations_identified_until_anonymized
  CHECK (anonymized_at IS NOT NULL OR (email IS NOT NULL AND full_name IS NOT NULL));
ALTER TABLE competition.registrations ADD CONSTRAINT registrations_anonymized_is_empty
  CHECK (anonymized_at IS NULL OR (full_name IS NULL AND social_name IS NULL AND email IS NULL AND leader_email IS NULL
         AND github_username IS NULL AND institution IS NULL AND course IS NULL AND team_name IS NULL AND person_id IS NULL));

-- ─── (3) retenção e limpeza ────────────────────────────────────────────────────────────────────
-- O prazo de uma inscrição: dia do hackathon + meses do resultado (selecionada = participante; o resto = não
-- selecionada). NULL enquanto a edição não tiver o dia ou a regra: aí nada vence.
CREATE FUNCTION competition.retention_date(p_edition competition.editions, p_status text) RETURNS date
 LANGUAGE sql STABLE SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  SELECT (ev.date + make_interval(months => CASE WHEN p_status = 'selected'
                                                 THEN p_edition.retention_participant_months
                                                 ELSE p_edition.retention_unselected_months END))::date
    FROM public.events ev WHERE ev.id = p_edition.event_id;
$function$;

-- A pessoa tem outro vínculo na plataforma? Toda FK que aponta para persons, lida do catálogo; as inscrições de
-- competição ficam de fora, porque são elas que estão sendo anonimizadas.
CREATE FUNCTION competition.person_has_other_links(p_person uuid) RETURNS boolean
 LANGUAGE plpgsql STABLE SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
  v_fk  record;
  v_hit boolean;
BEGIN
  FOR v_fk IN
    SELECT c.conrelid::regclass AS tbl, a.attname AS col
      FROM pg_constraint c
      JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
     WHERE c.contype = 'f' AND c.confrelid = 'public.persons'::regclass
       AND c.conrelid <> 'competition.registrations'::regclass
       AND array_length(c.conkey, 1) = 1
  LOOP
    EXECUTE format('SELECT EXISTS (SELECT 1 FROM %s WHERE %I = $1)', v_fk.tbl, v_fk.col) INTO v_hit USING p_person;
    IF v_hit THEN RETURN true; END IF;
  END LOOP;
  RETURN false;
END
$function$;

CREATE OR REPLACE FUNCTION competition.purge(p_dry_run boolean DEFAULT true) RETURNS jsonb
 LANGUAGE plpgsql SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
  v_pending    int;
  v_due        int;
  v_tokens     int;
  v_no_event   int;
  v_persons    int := 0;
  v_person_ids uuid[];
  v_pid        uuid;
  v_report     jsonb;
BEGIN
  SELECT count(*) INTO v_pending FROM competition.registrations
   WHERE status = 'pending_confirmation' AND submitted_at < now() - interval '48 hours';
  -- Vencida = confirmada, ainda identificada, e com o prazo que sai do dia do hackathon e do resultado.
  SELECT count(*), array_agg(DISTINCT r.person_id) FILTER (WHERE r.person_id IS NOT NULL)
    INTO v_due, v_person_ids
    FROM competition.registrations r JOIN competition.editions e ON e.id = r.edition_id
   WHERE r.anonymized_at IS NULL AND r.status <> 'pending_confirmation'
     AND competition.retention_date(e, r.status) < current_date;
  SELECT count(*) INTO v_tokens FROM competition.registration_tokens WHERE expires_at < now();
  -- Edição encerrada há mais de 30 dias sem o dia do hackathon: sem ele, nenhum prazo corre.
  SELECT count(*) INTO v_no_event FROM competition.editions
   WHERE status <> 'draft' AND event_id IS NULL AND registration_closes_at < now() - interval '30 days';

  IF NOT p_dry_run THEN
    -- A pendente nunca provou o e-mail: sai inteira.
    DELETE FROM competition.registrations
     WHERE status = 'pending_confirmation' AND submitted_at < now() - interval '48 hours';
    -- A confirmada é ANONIMIZADA, não apagada: sai tudo que aponta alguém; ficam estado, perfil técnico,
    -- origem e canal, que servem a relatório de alcance sem apontar ninguém.
    UPDATE competition.registrations r SET
      retention_until = competition.retention_date(e, r.status),
      full_name = NULL, social_name = NULL, email = NULL, leader_email = NULL, github_username = NULL,
      institution = NULL, course = NULL, team_name = NULL, person_id = NULL,
      anonymized_at = now(), updated_at = now()
      FROM competition.editions e
     WHERE e.id = r.edition_id AND r.anonymized_at IS NULL AND r.status <> 'pending_confirmation'
       AND competition.retention_date(e, r.status) < current_date;
    DELETE FROM competition.registration_tokens t
     WHERE t.expires_at < now()
        OR EXISTS (SELECT 1 FROM competition.registrations r WHERE r.id = t.registration_id AND r.anonymized_at IS NOT NULL);
    -- A pessoa que a competição criou, sem outra inscrição identificada e sem nenhum outro vínculo, é
    -- anonimizada como a plataforma já faz (anonymize_by_engagement_kind).
    FOREACH v_pid IN ARRAY coalesce(v_person_ids, '{}'::uuid[]) LOOP
      IF EXISTS (SELECT 1 FROM public.persons p
                  WHERE p.id = v_pid AND p.anonymized_at IS NULL AND p.consent_version LIKE 'competition:%')
         AND NOT EXISTS (SELECT 1 FROM competition.registrations r WHERE r.person_id = v_pid)
         AND NOT competition.person_has_other_links(v_pid) THEN
        UPDATE public.persons SET
          name = 'Pessoa Anonimizada #' || substr(v_pid::text, 1, 8),
          email = 'anon_' || substr(v_pid::text, 1, 8) || '@removed.local',
          auth_id = NULL, anonymized_at = now()
        WHERE id = v_pid;
        v_persons := v_persons + 1;
      END IF;
    END LOOP;
  END IF;

  v_report := jsonb_build_object('dry_run', p_dry_run, 'pending_unconfirmed', v_pending, 'due_anonymization', v_due,
                                 'persons', CASE WHEN p_dry_run THEN coalesce(array_length(v_person_ids, 1), 0) ELSE v_persons END,
                                 'expired_tokens', v_tokens, 'closed_editions_without_event', v_no_event);
  IF NOT p_dry_run AND v_pending + v_due > 0 THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (NULL, 'competition.purge', 'system', NULL, v_report, NULL);
  END IF;
  RETURN v_report;
END
$function$;

UPDATE public.data_retention_policy
   SET description = 'Inscrições de competição NÃO confirmadas (ADR-0133): saem em 2 dias, porque o e-mail nunca foi provado.'
 WHERE table_name = 'competition.registrations' AND cleanup_type = 'delete';
INSERT INTO public.data_retention_policy (table_name, retention_days, cleanup_type, description, is_active, executor)
VALUES ('competition.registrations', 180, 'anonymize',
        'Inscrições de competição confirmadas (ADR-0133): anonimizadas depois do dia do hackathon, 6 meses a não selecionada '
        || 'e 3 anos a de participante (competition.editions.retention_*_months). A pessoa que a competição criou, sem outro '
        || 'vínculo, é anonimizada junto. 180 é o horizonte da não selecionada; o de participante vem da edição.',
        true, 'competition-purge-hourly');

-- ─── (4) funções que mudam ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION competition.form_version_guard() RETURNS trigger
 LANGUAGE plpgsql SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION 'competition: versão do formulário é imutável; crie uma versão nova';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(NEW.fields) k
              WHERE k <> ALL (ARRAY['full_name', 'social_name', 'email', 'email_confirm', 'institution', 'course',
                                    'team_name', 'is_leader', 'leader_email', 'technical_profile', 'technical_area',
                                    'github_username', 'origin', 'heard_from'])) THEN
    RAISE EXCEPTION 'competition: campo desconhecido no formulário';
  END IF;
  IF NOT (NEW.fields ? 'full_name' AND NEW.fields ? 'email') THEN
    RAISE EXCEPTION 'competition: o formulário precisa de full_name e email';
  END IF;
  IF NEW.fields ? 'is_leader' AND NOT (NEW.fields ? 'leader_email' AND NEW.fields ? 'team_name') THEN
    RAISE EXCEPTION 'competition: is_leader exige leader_email e team_name no formulário';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_each(NEW.fields) f
              WHERE jsonb_typeof(f.value) IS DISTINCT FROM 'object'
                 OR (f.value ? 'required' AND jsonb_typeof(f.value->'required') IS DISTINCT FROM 'boolean')
                 OR (f.value ? 'options' AND (jsonb_typeof(f.value->'options') IS DISTINCT FROM 'array'
                       OR jsonb_array_length(f.value->'options') = 0
                       OR EXISTS (SELECT 1 FROM jsonb_array_elements(f.value->'options') o
                                   WHERE coalesce(o->>'value', '') !~ '^[a-z0-9_]{1,60}$')))) THEN
    RAISE EXCEPTION 'competition: definição de campo malformada';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(NEW.declarations) d
              WHERE jsonb_typeof(d) IS DISTINCT FROM 'object'
                 OR coalesce(d->>'key', '') !~ '^[a-z0-9_]{1,40}$'
                 OR jsonb_typeof(d->'version') IS DISTINCT FROM 'number'
                 OR (d->>'version') !~ '^[1-9][0-9]{0,3}$'
                 OR (d ? 'required' AND jsonb_typeof(d->'required') IS DISTINCT FROM 'boolean')
                 OR (d ? 'consent_policy_type' AND coalesce(d->>'consent_policy_type', '')
                       <> ALL (ARRAY['privacy_policy', 'communication_preferences', 'image_voice_publicity', 'ai_analysis', 'other']))
                 OR (d ? 'link' AND coalesce(d->>'link', '') <> ALL (ARRAY['rules', 'privacy']))
                 OR jsonb_typeof(d->'text') IS DISTINCT FROM 'object'
                 OR NOT (d->'text' ? 'pt-BR')) THEN
    RAISE EXCEPTION 'competition: declaração malformada';
  END IF;
  IF (SELECT count(*) <> count(DISTINCT d->>'key') FROM jsonb_array_elements(NEW.declarations) d) THEN
    RAISE EXCEPTION 'competition: chave de declaração repetida';
  END IF;
  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION public.competition_edition_public(p_slug text) RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
  e competition.editions;
  f competition.form_versions;
BEGIN
  SELECT * INTO e FROM competition.editions WHERE slug = p_slug;
  IF NOT FOUND OR (e.status = 'draft' AND NOT coalesce((SELECT public.can_by_member(m.id, 'manage_platform')
                                                        FROM public.members m WHERE m.auth_id = auth.uid()), false)) THEN
    RETURN jsonb_build_object('error', 'not_found');
  END IF;
  SELECT * INTO f FROM competition.form_versions WHERE id = e.current_form_version_id;
  RETURN jsonb_build_object(
    'slug', e.slug, 'title', e.title, 'short_title', e.short_title, 'modality', e.modality, 'status', e.status, 'timezone', e.timezone,
    'registration_opens_at', e.registration_opens_at, 'registration_closes_at', e.registration_closes_at,
    'is_open', e.status = 'open' AND competition.within_window(e.registration_opens_at, e.registration_closes_at),
    'team_min', e.team_min, 'team_max', e.team_max, 'requires_technical_profile', e.requires_technical_profile,
    'rules_url', e.rules_url, 'privacy_notice_url', e.privacy_notice_url, 'privacy_summary', e.privacy_summary,
    'confirmation_note', e.confirmation_note,
    'form', CASE WHEN f.id IS NULL THEN NULL ELSE jsonb_build_object(
      'version', f.version, 'fields', f.fields,
      'declarations', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                         'key', x.d->>'key', 'version', (x.d->>'version')::int,
                         'required', coalesce((x.d->>'required')::boolean, false), 'link', x.d->>'link',
                         'text', x.d->'text') ORDER BY x.n), '[]'::jsonb)
                         FROM jsonb_array_elements(f.declarations) WITH ORDINALITY AS x(d, n))) END);
END
$function$;

CREATE OR REPLACE FUNCTION public.competition_register(p_slug text, p_payload jsonb) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
  e        competition.editions;
  f        competition.form_versions;
  r        competition.registrations;
  v_err    text;
  v_ans    jsonb;
  v_decl   jsonb;
  v_reg    uuid;
  v_token  text;
  v_generic constant jsonb := jsonb_build_object('ok', true, 'message', 'received');
BEGIN
  v_err := coalesce(competition.gate('competition_register', 5, 60), competition.gate('competition_register_h', 20, 3600));
  IF v_err IS NOT NULL THEN RETURN jsonb_build_object('error', v_err); END IF;

  SELECT * INTO e FROM competition.editions WHERE slug = p_slug;
  IF NOT FOUND OR e.status <> 'open' OR NOT competition.within_window(e.registration_opens_at, e.registration_closes_at) THEN
    RETURN jsonb_build_object('error', 'closed');
  END IF;
  SELECT * INTO f FROM competition.form_versions WHERE id = e.current_form_version_id;

  BEGIN
    v_ans  := competition.normalize_answers(e, f, p_payload);
    v_decl := competition.accepted_declarations(f, p_payload);
  EXCEPTION WHEN raise_exception OR invalid_text_representation OR check_violation THEN
    RETURN competition.invalid_response(SQLERRM);
  END;

  -- O teto da edição vem ANTES de saber se o e-mail já existe, para a resposta 'busy' não virar oráculo.
  IF NOT competition.may_email(e, NULL) THEN
    RETURN jsonb_build_object('error', 'busy');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('competition_registration:' || e.id::text || ':' || (v_ans->>'email')));
  SELECT * INTO r FROM competition.registrations WHERE edition_id = e.id AND email = v_ans->>'email' FOR UPDATE;

  IF FOUND THEN
    IF NOT competition.may_email(e, r.id) THEN
      RETURN v_generic;
    END IF;
    IF r.status = 'pending_confirmation' THEN
      BEGIN
        UPDATE competition.registrations SET
          form_version_id = f.id, full_name = v_ans->>'full_name', social_name = v_ans->>'social_name',
          institution = v_ans->>'institution', course = v_ans->>'course', team_name = v_ans->>'team_name',
          is_leader = (v_ans->>'is_leader')::boolean, leader_email = v_ans->>'leader_email',
          technical_profile = (v_ans->>'technical_profile')::boolean, technical_area = v_ans->>'technical_area',
          github_username = v_ans->>'github_username', origin = v_ans->>'origin', heard_from = v_ans->>'heard_from',
          utm = CASE WHEN jsonb_typeof(v_ans->'utm') = 'object' THEN v_ans->'utm' END, submitted_at = now(), updated_at = now()
        WHERE id = r.id;
      EXCEPTION WHEN check_violation THEN
        RETURN competition.invalid_response(NULL);
      END;
      DELETE FROM competition.registration_declarations WHERE registration_id = r.id;
      INSERT INTO competition.registration_declarations (registration_id, declaration_key, text_version, consent_policy_type)
      SELECT r.id, d->>'key', (d->>'version')::int, d->>'consent_policy_type' FROM jsonb_array_elements(v_decl) AS x(d);
      INSERT INTO competition.registration_events (registration_id, event, detail)
      VALUES (r.id, 'resubmitted', jsonb_build_object('form_version', f.version));
      v_token := competition.issue_token(r.id, now() + interval '48 hours');
      PERFORM competition.dispatch_email(r.id, v_token, 'confirm');
    ELSE
      v_token := competition.issue_token(r.id, greatest(now() + interval '1 day', competition.link_valid_until(e)));
      INSERT INTO competition.registration_events (registration_id, event) VALUES (r.id, 'link_resent');
      PERFORM competition.dispatch_email(r.id, v_token, 'link_resent');
    END IF;
    RETURN v_generic;
  END IF;

  BEGIN
    INSERT INTO competition.registrations (
      edition_id, form_version_id, full_name, social_name, email, institution, course, team_name,
      is_leader, leader_email, technical_profile, technical_area, github_username, origin, heard_from, utm)
    VALUES (
      e.id, f.id, v_ans->>'full_name', v_ans->>'social_name', v_ans->>'email', v_ans->>'institution',
      v_ans->>'course', v_ans->>'team_name', (v_ans->>'is_leader')::boolean, v_ans->>'leader_email',
      (v_ans->>'technical_profile')::boolean, v_ans->>'technical_area', v_ans->>'github_username',
      v_ans->>'origin', v_ans->>'heard_from', CASE WHEN jsonb_typeof(v_ans->'utm') = 'object' THEN v_ans->'utm' END)
    RETURNING id INTO v_reg;
  EXCEPTION WHEN check_violation THEN
    RETURN competition.invalid_response(NULL);
  END;
  INSERT INTO competition.registration_declarations (registration_id, declaration_key, text_version, consent_policy_type)
  SELECT v_reg, d->>'key', (d->>'version')::int, d->>'consent_policy_type' FROM jsonb_array_elements(v_decl) AS x(d);
  INSERT INTO competition.registration_events (registration_id, event, detail)
  VALUES (v_reg, 'created', jsonb_build_object('form_version', f.version));
  v_token := competition.issue_token(v_reg, now() + interval '48 hours');
  PERFORM competition.dispatch_email(v_reg, v_token, 'confirm');
  RETURN v_generic;
END
$function$;

CREATE OR REPLACE FUNCTION public._competition_email_payload(p_registration_id uuid, p_token text) RETURNS jsonb
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
    'to', r.email, 'name', coalesce(r.social_name, r.full_name), 'edition_slug', e.slug, 'edition_title', e.title, 'edition_short_title', e.short_title,
    'pending', r.status = 'pending_confirmation',
    'confirm_by', CASE WHEN r.status = 'pending_confirmation' THEN r.submitted_at + interval '48 hours' END,
    'team_name', r.team_name, 'is_leader', r.is_leader, 'leader_email', r.leader_email,
    'closes_at', e.registration_closes_at, 'timezone', e.timezone, 'confirmation_note', e.confirmation_note,
    'rules_url', e.rules_url, 'privacy_notice_url', e.privacy_notice_url)
  FROM competition.registrations r JOIN competition.editions e ON e.id = r.edition_id
  WHERE r.id = p_registration_id AND r.id = competition.registration_by_token(p_token);
$function$;

-- ─── (5) a edição piloto, em rascunho ─────────────────────────────────────────────────────────
INSERT INTO competition.editions (
  organization_id, program_initiative_id, slug, title, short_title, modality, status, timezone,
  registration_opens_at, registration_closes_at, team_min, team_max, requires_technical_profile,
  rules_url, privacy_notice_url, privacy_summary, confirmation_note, legal_basis,
  retention_unselected_months, retention_participant_months)
SELECT '2b4f58ab-7c45-4170-8718-b77ee69ff906', i.id, 'hackathon-impacto-social-2026',
       'Hackathon de Impacto Social: IA & Gestão de Projetos', 'Hackathon de Impacto Social', 'hackathon', 'draft',
       'America/Sao_Paulo',
       '2026-10-19 09:00'::timestamp AT TIME ZONE 'America/Sao_Paulo',
       '2026-11-09 23:59'::timestamp AT TIME ZONE 'America/Sao_Paulo',
       3, 5, true,
       'https://hackathon.nucleoia.org/edital/', 'https://nucleoia.pmigo.org.br/privacy#competicoes',
       'Quem trata os seus dados é o Núcleo de Estudos e Pesquisa em IA & Gerenciamento de Projetos, com o CNPJ do PMI Goiás. Eles servem para conduzir esta edição, da inscrição ao certificado, com base na sua adesão ao Edital; o aviso de próximas edições só vale com o seu consentimento, que você pode revogar. A inscrição não selecionada é anonimizada 6 meses depois do dia do hackathon, e a de participante, 3 anos depois. Pedidos sobre os seus dados: dpo@pmigo.org.br.',
       'Sua equipe precisa ter de 3 a 5 pessoas inscritas até 09/11, às 23h59, cada uma com o próprio cadastro, e ao menos uma com perfil técnico. Inscrever-se não garante a vaga: se houver mais equipes válidas que vagas, a seleção é por sorteio público, com a Loteria Federal como semente. Toda equipe recebe o resultado por escrito em 13/11. Lembre: uma declaração falsa de qualquer integrante desclassifica a equipe inteira (2.8). Confira quem você convida.',
       'Execução de contrato ou procedimentos preliminares (adesão ao Edital) para o necessário à edição; consentimento só para o opcional (D6, e D7 quando existir). Decisão (a) do GP em 30/09/2026; o aviso passa por revisão jurídica antes de abrir.',
       6, 36
  FROM public.initiatives i
 WHERE i.kind = 'competition' AND i.title = 'Programa Hackathon de Impacto Social'
ON CONFLICT (slug) DO NOTHING;

INSERT INTO competition.form_versions (edition_id, version, fields, declarations)
SELECT e.id, 1,
       '{"full_name": {"required": true, "label": {"pt-BR": "Nome completo"}}, "social_name": {"label": {"pt-BR": "Nome social"}, "help": {"pt-BR": "Se preencher, é o nome que usamos no certificado e nas mensagens."}}, "email": {"required": true, "label": {"pt-BR": "E-mail"}}, "email_confirm": {"required": true, "label": {"pt-BR": "Confirme o e-mail"}}, "institution": {"required": true, "label": {"pt-BR": "Instituição de ensino superior"}}, "course": {"required": true, "label": {"pt-BR": "Curso"}}, "team_name": {"required": true, "label": {"pt-BR": "Nome da equipe"}}, "is_leader": {"required": true, "label": {"pt-BR": "Você lidera a equipe?"}}, "leader_email": {"label": {"pt-BR": "E-mail de quem lidera a equipe"}, "help": {"pt-BR": "Todos da equipe informam o mesmo e-mail. É assim que juntamos a equipe."}}, "technical_profile": {"required": true, "label": {"pt-BR": "Você tem perfil técnico?"}, "help": {"pt-BR": "Tem perfil técnico quem consegue construir e pôr para rodar a parte de software do protótipo: programar, integrar APIs ou modelos de IA, ou montar a solução com ferramentas de desenvolvimento, e explicar como ela funciona. É autodeclarado, e o curso não decide: estudante de outra área que programa conta. Ferramentas low-code ou no-code contam, desde que você explique a lógica."}}, "technical_area": {"label": {"pt-BR": "Área técnica"}, "options": [{"value": "software", "label": {"pt-BR": "Desenvolvimento de software"}}, {"value": "dados_ia", "label": {"pt-BR": "Dados e IA"}}, {"value": "infra", "label": {"pt-BR": "Infraestrutura, nuvem ou DevOps"}}, {"value": "low_code", "label": {"pt-BR": "Low-code ou no-code"}}, {"value": "outra", "label": {"pt-BR": "Outra área técnica"}}]}, "github_username": {"label": {"pt-BR": "Usuário do GitHub"}, "help": {"pt-BR": "Opcional. Ajuda a banca a ligar você aos commits do repositório da equipe."}}, "origin": {"label": {"pt-BR": "Você tem vínculo com algum capítulo do PMI ou Student Club?"}, "help": {"pt-BR": "Opcional. Serve para sabermos qual organização promotora trouxe você. Não conta na seleção."}, "options": [{"value": "student_club_pmi_df", "label": {"pt-BR": "Student Club do PMI-DF"}}, {"value": "student_club_outro", "label": {"pt-BR": "Student Club de outro capítulo"}}, {"value": "pmi_go", "label": {"pt-BR": "PMI-GO"}}, {"value": "pmi_df", "label": {"pt-BR": "PMI-DF"}}, {"value": "pmi_ce", "label": {"pt-BR": "PMI-CE"}}, {"value": "pmi_mg", "label": {"pt-BR": "PMI-MG"}}, {"value": "pmi_rs", "label": {"pt-BR": "PMI-RS"}}, {"value": "pmi_outro", "label": {"pt-BR": "Outro capítulo do PMI"}}, {"value": "nenhum", "label": {"pt-BR": "Nenhum"}}]}, "heard_from": {"label": {"pt-BR": "Como soube do hackathon?"}, "help": {"pt-BR": "Opcional. Serve para sabermos quais canais de divulgação funcionam. Não conta na seleção."}, "options": [{"value": "instagram", "label": {"pt-BR": "Instagram"}}, {"value": "linkedin", "label": {"pt-BR": "LinkedIn"}}, {"value": "whatsapp", "label": {"pt-BR": "WhatsApp (grupo ou mensagem)"}}, {"value": "email", "label": {"pt-BR": "E-mail"}}, {"value": "site", "label": {"pt-BR": "Site do hackathon ou do Núcleo"}}, {"value": "ensino", "label": {"pt-BR": "Professor(a) ou instituição de ensino"}}, {"value": "pmi", "label": {"pt-BR": "Capítulo do PMI ou Student Club"}}, {"value": "indicacao", "label": {"pt-BR": "Indicação de colega ou amigo(a)"}}, {"value": "evento", "label": {"pt-BR": "Evento ou palestra"}}, {"value": "outro", "label": {"pt-BR": "Outro"}}]}}'::jsonb,
       '[{"key": "maior_de_18", "version": 1, "required": true, "text": {"pt-BR": "Declaro que tenho 18 anos ou mais."}}, {"key": "estudante_ies", "version": 1, "required": true, "text": {"pt-BR": "Declaro que estou regularmente matriculado(a) em curso de ensino superior no semestre em curso. Sei que, se minha equipe chegar à final, precisarei comprovar a matrícula depois do dia do hackathon."}}, {"key": "penalidade_coletiva", "version": 1, "required": true, "text": {"pt-BR": "Li e entendi: uma declaração falsa de qualquer integrante desclassifica a equipe inteira, em qualquer fase, inclusive depois do resultado."}}, {"key": "aceite_edital", "version": 1, "required": true, "link": "rules", "text": {"pt-BR": "Li e aceito o Edital 01/2026, incluindo o código de conduta."}}, {"key": "ciencia_privacidade", "version": 1, "required": true, "link": "privacy", "text": {"pt-BR": "Li o aviso de privacidade."}}, {"key": "proximas_edicoes", "version": 1, "required": false, "consent_policy_type": "communication_preferences", "text": {"pt-BR": "Quero receber aviso das próximas edições do programa."}}]'::jsonb
  FROM competition.editions e WHERE e.slug = 'hackathon-impacto-social-2026'
ON CONFLICT (edition_id, version) DO NOTHING;

UPDATE competition.editions e SET current_form_version_id = f.id, updated_at = now()
  FROM competition.form_versions f
 WHERE e.slug = 'hackathon-impacto-social-2026' AND f.edition_id = e.id AND f.version = 1
   AND e.current_form_version_id IS NULL;

-- ─── permissões ────────────────────────────────────────────────────────────────────────────────
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA competition FROM PUBLIC, anon, authenticated;
