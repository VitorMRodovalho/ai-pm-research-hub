-- #2529 / ADR-0133, fase 1: a camada de competições e a inscrição pública (formulário sem login).
--
-- Decisões do GP em 30/09/2026: aprovar a ADR-0133 ("aprovo a ADR, pode começar a construir"); superar a
-- decisão de 25/09 (a inscrição fica no Supabase do hub, numa camada própria); o programa tem iniciativa
-- própria; contato só por e-mail. Regra de prazo pelo MINUTO INTEIRO ("23h59" vale até 23:59:59), repassada
-- pela lane da banca e ainda por confirmar com o GP.
--
-- Esta fase entrega o que o formulário de 19/10 precisa, testado até ~12/10:
--   (1) schema `competition`, FORA da API de dados (medido: a API expõe só public e graphql_public); as
--       tabelas têm RLS ligada e nenhuma política, e ninguém além do dono das funções as lê;
--   (2) o tipo de iniciativa `competition` (config, ADR-0009) sem vínculos prometidos ainda (os de
--       participante e revisor entram na fase 2, com o catálogo de vínculos admitindo-os, #2417), e a
--       iniciativa do programa;
--   (3) edições, versões imutáveis e validadas do formulário, inscrições, declarações aceitas, links de
--       acesso (só o hash, com validade) e histórico;
--   (4) funções em public: leitura pública da edição, inscrição (anon), confirmação do e-mail, leitura,
--       correção e desistência pelo link, lista para quem organiza (com registro de acesso a dado pessoal)
--       e o conteúdo do e-mail para a Edge Function;
--   (5) a limpeza: inscrição não confirmada sai em 48 h, e a confirmada no fim da retenção da edição.
--
-- Revisão de segurança (security-engineer, 30/09) incorporada antes de aplicar:
--   C1  confirmação do e-mail em duas etapas: a inscrição nasce `pending_confirmation`, SEM pessoa e SEM
--       consentimento; `persons` e `consent_records` só são escritos quando o dono do e-mail confirma;
--   H1  links NÃO giram (cada envio cria um token novo e os anteriores seguem valendo até expirar);
--       teto por inscrição (1 e-mail a cada 15 min, 3 em 24 h) e teto por edição por hora; chamada
--       anônima sem IP é recusada (o limitador por IP falha aberto quando não há IP);
--   H2  e-mail em regex estrita; nome e equipe em conjunto fechado de caracteres; nenhum campo aceita
--       caractere de controle nem < >;
--   H3  corpo até 8 KiB e só objeto; tamanho de cada campo checado antes da tabela; violação de CHECK
--       vira resposta genérica, nunca erro cru;
--   M1  token com validade; a leitura devolve o e-mail mascarado;  M2  a equipe só conta inscrição
--   confirmada;  M3  tipo de consentimento validado na criação do formulário; sem hash de IP (sha256 de
--   IPv4 sem sal se reverte por força bruta); limpeza agendada e registrada em data_retention_policy;
--   desistência pela própria pessoa, que revoga o consentimento;  M3b  o log de acesso nomeia todos os
--   campos e o número de linhas;  L1  search_path só com pg_catalog e pg_temp, tudo qualificado;
--   L2  revogação explícita de tudo no schema no fim (ALTER DEFAULT PRIVILEGES por schema não revoga o
--   EXECUTE que o padrão global concede a PUBLIC);  L3  falha ao enfileirar o e-mail vira evento;
--   L4  a leitura pública das declarações não expõe o tipo de consentimento.
--   M4 (diferença de tempo entre e-mail novo e já inscrito) fica aceito e registrado na ADR: os dois
--   caminhos enfileiram um e-mail e devolvem a mesma resposta.
-- Fases seguintes: validação conjunta e equipes (até 09/11), sorteio e resultado (13/11), submissão (dia
-- do hackathon), resultado final e certificados (depois).
--
-- ROLLBACK: SELECT cron.unschedule('competition-purge-hourly'); DELETE FROM public.data_retention_policy
--   WHERE executor = 'competition-purge-hourly'; DROP das funções public.competition_* e
--   public._competition_email_payload; DROP SCHEMA competition CASCADE; DELETE da iniciativa do programa e
--   da linha 'competition' de initiative_kinds.

-- ─── (1) a camada ───────────────────────────────────────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS competition;
REVOKE ALL ON SCHEMA competition FROM PUBLIC, anon, authenticated;
COMMENT ON SCHEMA competition IS
  'ADR-0133: competições (hackathons e awards). Fora da API de dados; acesso só por funções SECURITY DEFINER em public.';

-- ─── (2) tipo de iniciativa e programa ─────────────────────────────────────────────────────────
INSERT INTO public.initiative_kinds (
  slug, display_name, description, icon, icon_emoji, has_board, has_meeting_notes, has_deliverables,
  has_attendance, has_certificate, custom_fields_schema, lifecycle_states, organization_id,
  allowed_engagement_kinds, required_engagement_kinds
) VALUES (
  'competition', 'Competição (programa)',
  'Programa de competições em série (hackathons e awards). As edições, inscrições e equipes ficam no schema competition (ADR-0133).',
  'trophy', '🏆', false, false, false, false, true, '{}'::jsonb,
  ARRAY['draft', 'active', 'concluded', 'archived'], '2b4f58ab-7c45-4170-8718-b77ee69ff906',
  ARRAY[]::text[], ARRAY[]::text[]
) ON CONFLICT (slug) DO NOTHING;

INSERT INTO public.initiatives (kind, organization_id, title, description, status, metadata, join_policy, visibility)
SELECT 'competition', '2b4f58ab-7c45-4170-8718-b77ee69ff906', 'Programa Hackathon de Impacto Social',
       'Série de edições do Hackathon de Impacto Social (ADR-0133). Quem organiza fica no grupo de trabalho "Hackathon de Impacto Social".',
       'active',
       jsonb_build_object('name_i18n', jsonb_build_object(
         'pt', 'Programa Hackathon de Impacto Social', 'en', 'Social Impact Hackathon Program', 'es', 'Programa Hackathon de Impacto Social')),
       'invite_only', 'standard'
WHERE NOT EXISTS (SELECT 1 FROM public.initiatives WHERE kind = 'competition' AND title = 'Programa Hackathon de Impacto Social');

-- ─── (3) tabelas ───────────────────────────────────────────────────────────────────────────────
CREATE TABLE competition.editions (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id        uuid NOT NULL REFERENCES public.organizations(id),
  program_initiative_id  uuid NOT NULL REFERENCES public.initiatives(id),
  slug                   text NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9][a-z0-9-]{2,79}$'),
  title                  text NOT NULL,
  modality               text NOT NULL CHECK (modality IN ('hackathon', 'award')),
  status                 text NOT NULL DEFAULT 'draft'
                           CHECK (status IN ('draft', 'open', 'closed', 'in_review', 'results', 'done')),
  timezone               text NOT NULL DEFAULT 'America/Sao_Paulo',
  -- As horas guardam o MINUTO exibido; o prazo vale até o fim desse minuto (competition.within_window).
  registration_opens_at  timestamptz,
  registration_closes_at timestamptz,
  event_id               uuid REFERENCES public.events(id),
  submission_deadline_at timestamptz,
  team_min               int,
  team_max               int,
  requires_technical_profile boolean NOT NULL DEFAULT false,  -- regra da EQUIPE (ao menos um perfil técnico)
  current_form_version_id uuid,
  rules_url              text,
  privacy_notice_url     text,
  privacy_policy_version text,
  confirmation_note      text,   -- recado da edição no e-mail (ex.: lembrete da 2.8)
  legal_basis            text,   -- decisão (a) do GP; abrir exige base legal e retenção preenchidas
  retention_days         int CHECK (retention_days IS NULL OR retention_days > 0),
  email_hourly_cap       int NOT NULL DEFAULT 200 CHECK (email_hourly_cap BETWEEN 1 AND 5000),
  certificate_levels     jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  CHECK (team_min IS NULL OR (team_min >= 1 AND team_max IS NOT NULL AND team_max >= team_min)),
  CHECK (registration_opens_at IS NULL OR registration_closes_at IS NULL OR registration_opens_at < registration_closes_at),
  -- Uma edição só abre com a janela, a política e a decisão (a) preenchidas.
  CHECK (status = 'draft' OR (registration_opens_at IS NOT NULL AND registration_closes_at IS NOT NULL
         AND current_form_version_id IS NOT NULL AND privacy_policy_version IS NOT NULL
         AND legal_basis IS NOT NULL AND retention_days IS NOT NULL))
);

-- Versão do formulário: validada ao nascer e imutável depois; cada inscrição aponta a versão que respondeu.
CREATE TABLE competition.form_versions (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  edition_id   uuid NOT NULL REFERENCES competition.editions(id) ON DELETE CASCADE,
  version      int NOT NULL CHECK (version >= 1),
  fields       jsonb NOT NULL,   -- {<campo>: {label:{pt-BR:..}, required?, options?, help?}}
  declarations jsonb NOT NULL,   -- [{key, version, required?, consent_policy_type?, text:{pt-BR:..}}]
  created_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (edition_id, version),
  CHECK (jsonb_typeof(fields) = 'object' AND jsonb_typeof(declarations) = 'array')
);
ALTER TABLE competition.editions
  ADD CONSTRAINT editions_current_form_version_fkey
  FOREIGN KEY (current_form_version_id) REFERENCES competition.form_versions(id);

CREATE TABLE competition.registrations (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  edition_id         uuid NOT NULL REFERENCES competition.editions(id),
  person_id          uuid REFERENCES public.persons(id),   -- só depois que o dono do e-mail confirma
  form_version_id    uuid NOT NULL REFERENCES competition.form_versions(id),
  status             text NOT NULL DEFAULT 'pending_confirmation'
                       CHECK (status IN ('pending_confirmation', 'submitted', 'valid', 'excluded', 'selected',
                                         'waitlisted', 'not_selected', 'withdrawn')),
  full_name          text NOT NULL CHECK (char_length(full_name) BETWEEN 2 AND 150),
  social_name        text CHECK (social_name IS NULL OR char_length(social_name) BETWEEN 2 AND 150),
  email              text NOT NULL CHECK (char_length(email) <= 254
                       AND email ~ '^[a-z0-9._%+-]{1,64}@([a-z0-9-]+\.)+[a-z]{2,63}$'),
  institution        text CHECK (institution IS NULL OR char_length(institution) <= 200),
  course             text CHECK (course IS NULL OR char_length(course) <= 200),
  team_name          text CHECK (team_name IS NULL OR char_length(team_name) BETWEEN 1 AND 80),
  is_leader          boolean,
  leader_email       text CHECK (leader_email IS NULL OR (char_length(leader_email) <= 254
                       AND leader_email ~ '^[a-z0-9._%+-]{1,64}@([a-z0-9-]+\.)+[a-z]{2,63}$')),
  technical_profile  boolean,
  technical_area     text CHECK (technical_area IS NULL OR char_length(technical_area) <= 120),
  github_username    text CHECK (github_username IS NULL OR github_username ~ '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$'),
  origin             text CHECK (origin IS NULL OR char_length(origin) <= 120),
  heard_from         text CHECK (heard_from IS NULL OR char_length(heard_from) <= 120),
  utm                jsonb CHECK (utm IS NULL OR jsonb_typeof(utm) = 'object'),
  enrollment_verified_at timestamptz,
  enrollment_verified_by uuid REFERENCES public.members(id),
  submitted_at       timestamptz NOT NULL DEFAULT now(),
  confirmed_at       timestamptz,
  updated_at         timestamptz NOT NULL DEFAULT now(),
  retention_until    date,
  UNIQUE (edition_id, email),
  UNIQUE (edition_id, person_id),
  CHECK ((status = 'pending_confirmation') = (confirmed_at IS NULL)),
  CHECK (status = 'pending_confirmation' OR person_id IS NOT NULL),
  CHECK (is_leader IS NOT TRUE OR leader_email = email)
);
CREATE INDEX registrations_edition_leader_idx ON competition.registrations (edition_id, leader_email);
CREATE INDEX registrations_pending_idx ON competition.registrations (submitted_at) WHERE status = 'pending_confirmation';

-- Links de acesso: só o hash, cada um com validade. Um envio novo cria um token novo e NÃO invalida os
-- anteriores (girar deixaria um terceiro, repetindo o formulário, derrubar o link de quem se inscreveu).
CREATE TABLE competition.registration_tokens (
  token_hash      text PRIMARY KEY,
  registration_id uuid NOT NULL REFERENCES competition.registrations(id) ON DELETE CASCADE,
  created_at      timestamptz NOT NULL DEFAULT now(),
  expires_at      timestamptz NOT NULL
);
CREATE INDEX registration_tokens_registration_idx ON competition.registration_tokens (registration_id);

CREATE TABLE competition.registration_declarations (
  registration_id     uuid NOT NULL REFERENCES competition.registrations(id) ON DELETE CASCADE,
  declaration_key     text NOT NULL,
  text_version        int NOT NULL,
  consent_policy_type text,   -- quando a declaração é um consentimento, o tipo gravado em consent_records ao confirmar
  accepted_at         timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (registration_id, declaration_key, text_version)
);

CREATE TABLE competition.registration_events (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  registration_id uuid NOT NULL REFERENCES competition.registrations(id) ON DELETE CASCADE,
  event           text NOT NULL CHECK (event IN ('created', 'resubmitted', 'confirmed', 'updated', 'link_resent',
                                                 'withdrawn', 'status_changed', 'email_queued', 'email_failed')),
  actor_member_id uuid REFERENCES public.members(id),  -- NULL quando foi a própria pessoa, pelo link
  detail          jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX registration_events_registration_idx ON competition.registration_events (registration_id, created_at);
CREATE INDEX registration_events_email_idx ON competition.registration_events (created_at) WHERE event = 'email_queued';

-- RLS ligada e sem política: ninguém lê pela API (o schema nem é exposto); só as funções abaixo.
ALTER TABLE competition.editions ENABLE ROW LEVEL SECURITY;
ALTER TABLE competition.form_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE competition.registrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE competition.registration_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE competition.registration_declarations ENABLE ROW LEVEL SECURITY;
ALTER TABLE competition.registration_events ENABLE ROW LEVEL SECURITY;

-- Versão do formulário: validada ao nascer (campos conhecidos, declarações bem formadas, tipo de
-- consentimento aceito por consent_records) e imutável depois.
CREATE FUNCTION competition.form_version_guard() RETURNS trigger
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
CREATE TRIGGER trg_form_version_guard BEFORE INSERT OR UPDATE ON competition.form_versions
  FOR EACH ROW EXECUTE FUNCTION competition.form_version_guard();

-- ─── (4) regras e funções ──────────────────────────────────────────────────────────────────────
-- O prazo vale pelo MINUTO INTEIRO: "23h59" aceita até 23:59:59.999.
CREATE FUNCTION competition.within_window(p_opens timestamptz, p_closes timestamptz) RETURNS boolean
 LANGUAGE sql STABLE SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  SELECT p_opens IS NOT NULL AND p_closes IS NOT NULL
     AND now() >= p_opens
     AND now() < date_trunc('minute', p_closes) + interval '1 minute';
$function$;

-- Até quando o link de uma inscrição confirmada vale: 30 dias depois do fim da janela (ver e desistir).
CREATE FUNCTION competition.link_valid_until(p_edition competition.editions) RETURNS timestamptz
 LANGUAGE sql STABLE SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  SELECT date_trunc('minute', p_edition.registration_closes_at) + interval '1 minute' + interval '30 days';
$function$;

CREATE FUNCTION competition.token_hash(p_token text) RETURNS text
 LANGUAGE sql IMMUTABLE SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  SELECT encode(extensions.digest(p_token, 'sha256'), 'hex');
$function$;

-- O mesmo e-mail dá sempre o mesmo hash (minúsculo, sem espaço), para achar o consentimento depois.
CREATE FUNCTION competition.email_hash(p_email text) RETURNS text
 LANGUAGE sql IMMUTABLE SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  SELECT encode(extensions.digest(lower(btrim(p_email)), 'sha256'), 'hex');
$function$;

-- Porta de entrada das funções anônimas: exige o IP do cliente (o limitador falha aberto sem ele, então
-- chamada anônima sem IP é recusada) e aplica o limite por IP. Devolve NULL ou o código do erro.
CREATE FUNCTION competition.gate(p_action text, p_limit int, p_window_s int) RETURNS text
 LANGUAGE plpgsql SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
  v_ip text;
BEGIN
  BEGIN
    v_ip := NULLIF(current_setting('request.headers', true)::jsonb->>'cf-connecting-ip', '');
  EXCEPTION WHEN OTHERS THEN
    v_ip := NULL;
  END;
  IF v_ip IS NULL AND coalesce(auth.role(), '') <> 'service_role' THEN
    RETURN 'unavailable';
  END IF;
  IF NOT public.rl_check_and_bump(p_action, p_limit, p_window_s) THEN
    RETURN 'rate_limited';
  END IF;
  RETURN NULL;
END
$function$;

-- Teto de e-mail: por edição e por hora, e por inscrição (1 a cada 15 min, 3 em 24 h). Conta os e-mails
-- efetivamente enfileirados.
CREATE FUNCTION competition.may_email(p_edition competition.editions, p_registration_id uuid) RETURNS boolean
 LANGUAGE sql STABLE SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  SELECT (SELECT count(*) FROM competition.registration_events ev
            JOIN competition.registrations r ON r.id = ev.registration_id
           WHERE r.edition_id = p_edition.id AND ev.event = 'email_queued'
             AND ev.created_at > now() - interval '1 hour') < p_edition.email_hourly_cap
     AND (p_registration_id IS NULL OR (
          NOT EXISTS (SELECT 1 FROM competition.registration_events ev
                       WHERE ev.registration_id = p_registration_id AND ev.event = 'email_queued'
                         AND ev.created_at > now() - interval '15 minutes')
      AND (SELECT count(*) FROM competition.registration_events ev
            WHERE ev.registration_id = p_registration_id AND ev.event = 'email_queued'
              AND ev.created_at > now() - interval '24 hours') < 3));
$function$;

-- Valida as respostas contra a edição e a versão do formulário e devolve os campos normalizados, ou
-- levanta 'competition:<código>[:<campo>]'. Campo que a versão não declara é ignorado.
CREATE FUNCTION competition.normalize_answers(p_edition competition.editions, p_form competition.form_versions, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql STABLE SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
  f        jsonb := p_form.fields;
  v_email_re constant text := '^[a-z0-9._%+-]{1,64}@([a-z0-9-]+\.)+[a-z]{2,63}$';
  v_out    jsonb := '{}'::jsonb;
  v_key    text;
  v_val    text;
  v_max    int;
  v_email  text;
  v_lead   boolean;
  v_lemail text;
  v_tech   boolean;
  v_gh     text;
  v_utm    jsonb;
BEGIN
  IF jsonb_typeof(p_payload) IS DISTINCT FROM 'object' OR octet_length(p_payload::text) > 8192 THEN
    RAISE EXCEPTION 'competition:payload_invalid';
  END IF;

  FOREACH v_key IN ARRAY ARRAY['full_name', 'social_name', 'institution', 'course', 'team_name',
                               'technical_area', 'origin', 'heard_from'] LOOP
    v_val := NULL;
    IF f ? v_key AND jsonb_typeof(p_payload->v_key) = 'string' THEN
      v_val := NULLIF(btrim(p_payload->>v_key), '');
    END IF;
    IF v_val IS NOT NULL THEN
      v_max := CASE v_key WHEN 'full_name' THEN 150 WHEN 'social_name' THEN 150 WHEN 'team_name' THEN 80
                          WHEN 'institution' THEN 200 WHEN 'course' THEN 200 ELSE 120 END;
      IF char_length(v_val) > v_max THEN
        RAISE EXCEPTION 'competition:too_long:%', v_key;
      END IF;
      IF v_val ~ '[[:cntrl:]<>]' THEN
        RAISE EXCEPTION 'competition:text_invalid:%', v_key;
      END IF;
      IF v_key IN ('full_name', 'social_name')
         AND (char_length(v_val) < 2 OR v_val !~ '^[[:alpha:]]([[:alpha:] .''’-]*[[:alpha:].])?$') THEN
        RAISE EXCEPTION 'competition:name_invalid:%', v_key;
      END IF;
      IF v_key = 'team_name' AND v_val !~ '^[[:alnum:]][[:alnum:] .''’&+#_!()-]*$' THEN
        RAISE EXCEPTION 'competition:team_name_invalid:team_name';
      END IF;
      -- Campo com lista na versão do formulário só aceita um dos valores dela.
      IF jsonb_typeof(f->v_key->'options') = 'array'
         AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(f->v_key->'options') o WHERE o->>'value' = v_val) THEN
        RAISE EXCEPTION 'competition:option_invalid:%', v_key;
      END IF;
    ELSIF v_key = 'full_name'
       OR (v_key <> 'technical_area' AND coalesce((f->v_key->>'required')::boolean, false))
       OR (v_key = 'team_name' AND p_edition.team_min IS NOT NULL) THEN
      RAISE EXCEPTION 'competition:required:%', v_key;
    END IF;
    v_out := v_out || jsonb_build_object(v_key, v_val);
  END LOOP;

  v_email := CASE WHEN jsonb_typeof(p_payload->'email') = 'string' THEN lower(btrim(p_payload->>'email')) END;
  IF v_email IS NULL OR char_length(v_email) > 254 OR v_email !~ v_email_re THEN
    RAISE EXCEPTION 'competition:email_invalid:email';
  END IF;
  IF f ? 'email_confirm'
     AND (CASE WHEN jsonb_typeof(p_payload->'email_confirm') = 'string'
               THEN lower(btrim(p_payload->>'email_confirm')) END) IS DISTINCT FROM v_email THEN
    RAISE EXCEPTION 'competition:email_mismatch:email_confirm';
  END IF;

  v_lead := CASE WHEN f ? 'is_leader' AND jsonb_typeof(p_payload->'is_leader') = 'boolean'
                 THEN (p_payload->'is_leader')::boolean END;
  v_lemail := CASE WHEN f ? 'leader_email' AND jsonb_typeof(p_payload->'leader_email') = 'string'
                   THEN NULLIF(lower(btrim(p_payload->>'leader_email')), '') END;
  IF v_lead IS NULL AND (p_edition.team_min IS NOT NULL OR coalesce((f->'is_leader'->>'required')::boolean, false)) THEN
    RAISE EXCEPTION 'competition:required:is_leader';
  END IF;
  IF v_lead IS TRUE THEN
    v_lemail := v_email;
  ELSIF v_lead IS FALSE THEN
    IF v_lemail IS NULL THEN
      RAISE EXCEPTION 'competition:required:leader_email';
    ELSIF char_length(v_lemail) > 254 OR v_lemail !~ v_email_re THEN
      RAISE EXCEPTION 'competition:email_invalid:leader_email';
    ELSIF v_lemail = v_email THEN
      RAISE EXCEPTION 'competition:leader_is_self:leader_email';
    END IF;
  ELSE
    v_lemail := NULL;
  END IF;

  v_tech := CASE WHEN f ? 'technical_profile' AND jsonb_typeof(p_payload->'technical_profile') = 'boolean'
                 THEN (p_payload->'technical_profile')::boolean END;
  IF v_tech IS NULL AND coalesce((f->'technical_profile'->>'required')::boolean, false) THEN
    RAISE EXCEPTION 'competition:required:technical_profile';
  END IF;
  IF v_tech IS NOT TRUE THEN
    v_out := v_out || jsonb_build_object('technical_area', NULL);
  ELSIF f ? 'technical_area' AND v_out->>'technical_area' IS NULL THEN
    RAISE EXCEPTION 'competition:required:technical_area';
  END IF;

  v_gh := CASE WHEN f ? 'github_username' AND jsonb_typeof(p_payload->'github_username') = 'string'
               THEN NULLIF(regexp_replace(btrim(p_payload->>'github_username'), '^@', ''), '') END;
  IF v_gh IS NOT NULL AND v_gh !~ '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$' THEN
    RAISE EXCEPTION 'competition:github_invalid:github_username';
  ELSIF v_gh IS NULL AND coalesce((f->'github_username'->>'required')::boolean, false) THEN
    RAISE EXCEPTION 'competition:required:github_username';
  END IF;

  -- UTM: só as cinco chaves conhecidas, com valor curto e sem caractere especial; o resto é descartado.
  SELECT jsonb_object_agg(t.k, t.v) INTO v_utm
    FROM jsonb_each_text(CASE WHEN jsonb_typeof(p_payload->'utm') = 'object' THEN p_payload->'utm' ELSE '{}'::jsonb END) AS t(k, v)
   WHERE t.k IN ('utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content')
     AND t.v ~ '^[A-Za-z0-9._~+-]{1,100}$';

  RETURN v_out || jsonb_build_object(
    'email', v_email, 'is_leader', v_lead, 'leader_email', v_lemail, 'technical_profile', v_tech,
    'github_username', v_gh, 'utm', v_utm);
END
$function$;

-- Confere as declarações contra a versão do formulário: toda obrigatória aceita. Devolve as aceitas.
CREATE FUNCTION competition.accepted_declarations(p_form competition.form_versions, p_payload jsonb) RETURNS jsonb
 LANGUAGE plpgsql STABLE SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
  v_d   jsonb;
  v_acc jsonb := '[]'::jsonb;
BEGIN
  FOR v_d IN SELECT d FROM jsonb_array_elements(p_form.declarations) AS x(d) LOOP
    IF (p_payload->'declarations'->(v_d->>'key')) = 'true'::jsonb THEN
      v_acc := v_acc || jsonb_build_array(jsonb_build_object(
        'key', v_d->>'key', 'version', (v_d->>'version')::int, 'consent_policy_type', v_d->>'consent_policy_type'));
    ELSIF coalesce((v_d->>'required')::boolean, false) THEN
      RAISE EXCEPTION 'competition:declaration_required:%', v_d->>'key';
    END IF;
  END LOOP;
  RETURN v_acc;
END
$function$;

-- Enfileira o e-mail pela Edge Function (o token vai só no corpo da chamada; no banco fica o hash) e
-- registra o resultado: 'email_queued' é o que os tetos contam; 'email_failed' deixa a falha visível.
CREATE FUNCTION competition.dispatch_email(p_registration_id uuid, p_token text, p_kind text) RETURNS void
 LANGUAGE plpgsql SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
  v_key text;
BEGIN
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
  IF v_key IS NULL THEN
    INSERT INTO competition.registration_events (registration_id, event, detail)
    VALUES (p_registration_id, 'email_failed', jsonb_build_object('kind', p_kind, 'reason', 'no_service_key'));
    RETURN;
  END IF;
  PERFORM net.http_post(
    url     := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/send-competition-email',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
    body    := jsonb_build_object('registration_id', p_registration_id, 'token', p_token, 'kind', p_kind));
  INSERT INTO competition.registration_events (registration_id, event, detail)
  VALUES (p_registration_id, 'email_queued', jsonb_build_object('kind', p_kind));
EXCEPTION WHEN OTHERS THEN
  INSERT INTO competition.registration_events (registration_id, event, detail)
  VALUES (p_registration_id, 'email_failed', jsonb_build_object('kind', p_kind, 'sqlstate', SQLSTATE));
END
$function$;

-- Cria um link novo para a inscrição e devolve o token em claro (só para o e-mail).
CREATE FUNCTION competition.issue_token(p_registration_id uuid, p_expires_at timestamptz) RETURNS text
 LANGUAGE plpgsql SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
  v_token text := encode(extensions.gen_random_bytes(32), 'hex');
BEGIN
  INSERT INTO competition.registration_tokens (token_hash, registration_id, expires_at)
  VALUES (competition.token_hash(v_token), p_registration_id, p_expires_at);
  RETURN v_token;
END
$function$;

-- A inscrição dona de um token válido (formato conferido antes, para não gastar consulta com lixo).
CREATE FUNCTION competition.registration_by_token(p_token text) RETURNS uuid
 LANGUAGE sql STABLE SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  SELECT t.registration_id FROM competition.registration_tokens t
   WHERE coalesce(p_token, '') ~ '^[0-9a-f]{64}$'
     AND t.token_hash = competition.token_hash(p_token) AND t.expires_at > now();
$function$;

-- Traduz o erro de validação em resposta: código e campo, nunca a mensagem crua do banco.
CREATE FUNCTION competition.invalid_response(p_sqlerrm text) RETURNS jsonb
 LANGUAGE sql IMMUTABLE SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  SELECT CASE WHEN p_sqlerrm ~ '^competition:[a-z_]+'
              THEN jsonb_build_object('error', 'invalid', 'code', split_part(p_sqlerrm, ':', 2),
                                      'field', NULLIF(split_part(p_sqlerrm, ':', 3), ''))
              ELSE jsonb_build_object('error', 'invalid', 'code', 'invalid_value') END;
$function$;

-- Limpeza: inscrição não confirmada sai em 48 h; a confirmada, no fim da retenção da edição; token
-- vencido sai também. A chamada nua CONTA e não apaga; o cron chama com p_dry_run := false.
CREATE FUNCTION competition.purge(p_dry_run boolean DEFAULT true) RETURNS jsonb
 LANGUAGE plpgsql SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
  v_pending  int;
  v_retained int;
  v_tokens   int;
  v_report   jsonb;
BEGIN
  IF p_dry_run THEN
    SELECT count(*) INTO v_pending FROM competition.registrations
     WHERE status = 'pending_confirmation' AND submitted_at < now() - interval '48 hours';
    SELECT count(*) INTO v_retained FROM competition.registrations WHERE retention_until < current_date;
    SELECT count(*) INTO v_tokens FROM competition.registration_tokens WHERE expires_at < now();
  ELSE
    DELETE FROM competition.registrations
     WHERE status = 'pending_confirmation' AND submitted_at < now() - interval '48 hours';
    GET DIAGNOSTICS v_pending = ROW_COUNT;
    DELETE FROM competition.registrations WHERE retention_until < current_date;
    GET DIAGNOSTICS v_retained = ROW_COUNT;
    DELETE FROM competition.registration_tokens WHERE expires_at < now();
    GET DIAGNOSTICS v_tokens = ROW_COUNT;
  END IF;
  v_report := jsonb_build_object('dry_run', p_dry_run, 'pending_unconfirmed', v_pending,
                                 'past_retention', v_retained, 'expired_tokens', v_tokens);
  IF NOT p_dry_run AND v_pending + v_retained > 0 THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (NULL, 'competition.purge', 'system', NULL, v_report, NULL);
  END IF;
  RETURN v_report;
END
$function$;

-- Leitura pública da edição: só o que o formulário precisa, nenhum dado pessoal. Das declarações sai só
-- chave, versão, obrigatoriedade e texto (o tipo de consentimento é detalhe interno).
CREATE FUNCTION public.competition_edition_public(p_slug text) RETURNS jsonb
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
    'slug', e.slug, 'title', e.title, 'modality', e.modality, 'status', e.status, 'timezone', e.timezone,
    'registration_opens_at', e.registration_opens_at, 'registration_closes_at', e.registration_closes_at,
    'is_open', e.status = 'open' AND competition.within_window(e.registration_opens_at, e.registration_closes_at),
    'team_min', e.team_min, 'team_max', e.team_max, 'requires_technical_profile', e.requires_technical_profile,
    'rules_url', e.rules_url, 'privacy_notice_url', e.privacy_notice_url, 'confirmation_note', e.confirmation_note,
    'form', CASE WHEN f.id IS NULL THEN NULL ELSE jsonb_build_object(
      'version', f.version, 'fields', f.fields,
      'declarations', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                         'key', x.d->>'key', 'version', (x.d->>'version')::int,
                         'required', coalesce((x.d->>'required')::boolean, false), 'text', x.d->'text') ORDER BY x.n), '[]'::jsonb)
                         FROM jsonb_array_elements(f.declarations) WITH ORDINALITY AS x(d, n))) END);
END
$function$;

-- Inscrição pública. A resposta é a mesma para e-mail novo e já inscrito (não revela quem se inscreveu).
-- Nada vai para persons nem para consent_records aqui: a inscrição nasce pendente e só vale quando o dono
-- do e-mail confirma pelo link (competition_registration_confirm).
--   e-mail novo              -> inscrição pendente + e-mail de confirmação;
--   pendente, mesmo e-mail   -> as respostas novas substituem as anteriores (ninguém provou o e-mail ainda)
--                               e sai um link novo; os anteriores seguem valendo;
--   confirmada, mesmo e-mail -> nada muda; sai um link novo de acesso.
-- Acima do teto da inscrição, nada muda e nada sai, com a mesma resposta; acima do teto da edição, a
-- resposta é 'busy' para qualquer e-mail, novo ou não.
CREATE FUNCTION public.competition_register(p_slug text, p_payload jsonb) RETURNS jsonb
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
          utm = v_ans->'utm', submitted_at = now(), updated_at = now()
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
      is_leader, leader_email, technical_profile, technical_area, github_username, origin, heard_from, utm,
      retention_until)
    VALUES (
      e.id, f.id, v_ans->>'full_name', v_ans->>'social_name', v_ans->>'email', v_ans->>'institution',
      v_ans->>'course', v_ans->>'team_name', (v_ans->>'is_leader')::boolean, v_ans->>'leader_email',
      (v_ans->>'technical_profile')::boolean, v_ans->>'technical_area', v_ans->>'github_username',
      v_ans->>'origin', v_ans->>'heard_from', v_ans->'utm', (now() + make_interval(days => e.retention_days))::date)
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

-- Confirmação do e-mail, pelo link. Só aqui a inscrição passa a valer: liga (ou cria) a pessoa no
-- cadastro único e grava os consentimentos, porque só aqui o dono do e-mail está provado.
-- Vale mesmo depois do fim da janela, se a inscrição foi feita dentro dela (o link de 48 h é o limite).
CREATE FUNCTION public.competition_registration_confirm(p_token text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
  r        competition.registrations;
  e        competition.editions;
  f        competition.form_versions;
  v_err    text;
  v_person uuid;
BEGIN
  v_err := competition.gate('competition_token', 20, 60);
  IF v_err IS NOT NULL THEN RETURN jsonb_build_object('error', v_err); END IF;
  SELECT * INTO r FROM competition.registrations WHERE id = competition.registration_by_token(p_token) FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
  IF r.status <> 'pending_confirmation' THEN
    RETURN jsonb_build_object('ok', true, 'message', 'already_confirmed');
  END IF;
  SELECT * INTO e FROM competition.editions WHERE id = r.edition_id;
  SELECT * INTO f FROM competition.form_versions WHERE id = r.form_version_id;

  -- Uma pessoa por e-mail na organização; a trava evita duas criações simultâneas.
  PERFORM pg_advisory_xact_lock(hashtext('competition_person:' || r.email));
  SELECT p.id INTO v_person FROM public.persons p
   WHERE p.organization_id = e.organization_id AND lower(p.email) = r.email AND p.anonymized_at IS NULL
   ORDER BY (p.auth_id IS NOT NULL) DESC, p.created_at LIMIT 1;
  IF v_person IS NULL THEN
    INSERT INTO public.persons (organization_id, name, email, consent_status, consent_accepted_at, consent_version)
    VALUES (e.organization_id, r.full_name, r.email, 'accepted', now(), 'competition:' || e.slug || ':v' || f.version)
    RETURNING id INTO v_person;
  END IF;

  BEGIN
    UPDATE competition.registrations
       SET person_id = v_person, status = 'submitted', confirmed_at = now(), updated_at = now()
     WHERE id = r.id;
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('error', 'conflict');
  END;

  INSERT INTO public.consent_records (email_hash, policy_type, policy_version, accepted_at, channel, organization_id, evidence)
  SELECT competition.email_hash(r.email), d.consent_policy_type,
         CASE WHEN d.consent_policy_type = 'privacy_policy' AND e.privacy_policy_version IS NOT NULL
              THEN e.privacy_policy_version
              ELSE 'competition:' || e.slug || ':' || d.declaration_key || ':v' || d.text_version END,
         d.accepted_at, 'email_link', e.organization_id,
         jsonb_build_object('source', 'competition', 'edition', e.slug, 'registration_id', r.id,
                            'declaration', d.declaration_key, 'text_version', d.text_version, 'confirmed_at', now())
    FROM competition.registration_declarations d
   WHERE d.registration_id = r.id AND d.consent_policy_type IS NOT NULL;

  UPDATE competition.registration_tokens SET expires_at = greatest(expires_at, competition.link_valid_until(e))
   WHERE registration_id = r.id;
  INSERT INTO competition.registration_events (registration_id, event) VALUES (r.id, 'confirmed');
  RETURN jsonb_build_object('ok', true, 'message', 'confirmed');
END
$function$;

-- A própria inscrição, pelo link. O e-mail volta mascarado: quem tem o link já sabe qual é.
CREATE FUNCTION public.competition_registration_get(p_token text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
  r     competition.registrations;
  e     competition.editions;
  f     competition.form_versions;
  v_err text;
BEGIN
  v_err := competition.gate('competition_token', 20, 60);
  IF v_err IS NOT NULL THEN RETURN jsonb_build_object('error', v_err); END IF;
  SELECT * INTO r FROM competition.registrations WHERE id = competition.registration_by_token(p_token);
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
  SELECT * INTO e FROM competition.editions WHERE id = r.edition_id;
  SELECT * INTO f FROM competition.form_versions WHERE id = r.form_version_id;
  RETURN jsonb_build_object(
    'edition', e.slug, 'edition_title', e.title, 'status', r.status,
    'confirm_by', CASE WHEN r.status = 'pending_confirmation' THEN r.submitted_at + interval '48 hours' END,
    'editable', r.status = 'submitted' AND e.status = 'open'
                AND competition.within_window(e.registration_opens_at, e.registration_closes_at),
    'can_withdraw', r.status <> 'withdrawn',
    'form', jsonb_build_object('version', f.version, 'fields', f.fields, 'declarations', '[]'::jsonb),
    'registration', jsonb_build_object(
      'full_name', r.full_name, 'social_name', r.social_name,
      'email_masked', left(split_part(r.email, '@', 1), 1) || '***@' || split_part(r.email, '@', 2),
      'institution', r.institution, 'course', r.course, 'team_name', r.team_name, 'is_leader', r.is_leader,
      'leader_email', r.leader_email, 'technical_profile', r.technical_profile, 'technical_area', r.technical_area,
      'github_username', r.github_username, 'origin', r.origin, 'heard_from', r.heard_from));
END
$function$;

-- Correção pela própria pessoa, depois de confirmar e enquanto a janela estiver aberta. O e-mail não muda
-- por aqui (é a chave da inscrição e do link).
CREATE FUNCTION public.competition_registration_update(p_token text, p_payload jsonb) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
  r     competition.registrations;
  e     competition.editions;
  f     competition.form_versions;
  v_err text;
  v_ans jsonb;
BEGIN
  v_err := competition.gate('competition_token', 20, 60);
  IF v_err IS NOT NULL THEN RETURN jsonb_build_object('error', v_err); END IF;
  SELECT * INTO r FROM competition.registrations WHERE id = competition.registration_by_token(p_token) FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
  SELECT * INTO e FROM competition.editions WHERE id = r.edition_id;
  IF r.status <> 'submitted' OR e.status <> 'open'
     OR NOT competition.within_window(e.registration_opens_at, e.registration_closes_at) THEN
    RETURN jsonb_build_object('error', 'closed');
  END IF;
  SELECT * INTO f FROM competition.form_versions WHERE id = r.form_version_id;
  BEGIN
    v_ans := competition.normalize_answers(e, f,
               (CASE WHEN jsonb_typeof(p_payload) = 'object' THEN p_payload ELSE '{}'::jsonb END - 'email' - 'email_confirm')
               || jsonb_build_object('email', r.email, 'email_confirm', r.email));
    UPDATE competition.registrations SET
      full_name = v_ans->>'full_name', social_name = v_ans->>'social_name', institution = v_ans->>'institution',
      course = v_ans->>'course', team_name = v_ans->>'team_name', is_leader = (v_ans->>'is_leader')::boolean,
      leader_email = v_ans->>'leader_email', technical_profile = (v_ans->>'technical_profile')::boolean,
      technical_area = v_ans->>'technical_area', github_username = v_ans->>'github_username',
      origin = v_ans->>'origin', heard_from = v_ans->>'heard_from', updated_at = now()
    WHERE id = r.id;
  EXCEPTION WHEN raise_exception OR invalid_text_representation OR check_violation THEN
    RETURN competition.invalid_response(SQLERRM);
  END;
  INSERT INTO competition.registration_events (registration_id, event) VALUES (r.id, 'updated');
  RETURN jsonb_build_object('ok', true, 'message', 'updated');
END
$function$;

-- Desistência pela própria pessoa (LGPD art. 18). Pendente: a inscrição some inteira. Confirmada: vira
-- 'withdrawn', perde os campos opcionais, os consentimentos desta edição são revogados e os links deixam
-- de valer; nome, e-mail e equipe ficam para quem organiza até o fim da retenção.
CREATE FUNCTION public.competition_registration_withdraw(p_token text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
  r     competition.registrations;
  e     competition.editions;
  v_err text;
BEGIN
  v_err := competition.gate('competition_token', 20, 60);
  IF v_err IS NOT NULL THEN RETURN jsonb_build_object('error', v_err); END IF;
  SELECT * INTO r FROM competition.registrations WHERE id = competition.registration_by_token(p_token) FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
  IF r.status = 'withdrawn' THEN RETURN jsonb_build_object('ok', true, 'message', 'withdrawn'); END IF;
  IF r.status = 'pending_confirmation' THEN
    DELETE FROM competition.registrations WHERE id = r.id;
    RETURN jsonb_build_object('ok', true, 'message', 'withdrawn');
  END IF;
  SELECT * INTO e FROM competition.editions WHERE id = r.edition_id;
  UPDATE competition.registrations SET
    status = 'withdrawn', social_name = NULL, institution = NULL, course = NULL, technical_area = NULL,
    github_username = NULL, origin = NULL, heard_from = NULL, utm = NULL, updated_at = now()
  WHERE id = r.id;
  UPDATE public.consent_records SET revoked_at = now(), revocation_reason = 'competition_withdraw'
   WHERE email_hash = competition.email_hash(r.email) AND revoked_at IS NULL
     AND evidence->>'source' = 'competition' AND evidence->>'registration_id' = r.id::text;
  DELETE FROM competition.registration_tokens WHERE registration_id = r.id;
  INSERT INTO competition.registration_events (registration_id, event, detail)
  VALUES (r.id, 'withdrawn', jsonb_build_object('from_status', r.status));
  RETURN jsonb_build_object('ok', true, 'message', 'withdrawn');
END
$function$;

-- Lista para quem organiza, agrupada pela liderança. Só inscrição confirmada entra (a pendente é e-mail
-- não provado); a equipe só conta quem segue no páreo. Registra o acesso com os campos e o número de linhas.
CREATE FUNCTION public.competition_registrations_list(p_edition_slug text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
  v_member  uuid;
  e         competition.editions;
  v_rows    jsonb;
  v_n       int;
  v_pending int;
  v_teams   jsonb;
BEGIN
  SELECT m.id INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member IS NULL OR NOT public.can_by_member(v_member, 'manage_platform') THEN
    RAISE EXCEPTION 'competition: requer manage_platform' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO e FROM competition.editions WHERE slug = p_edition_slug;
  IF NOT FOUND THEN RAISE EXCEPTION 'competition: edição não encontrada'; END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.leader_email, x.is_leader DESC, x.submitted_at), '[]'::jsonb), count(*)
    INTO v_rows, v_n
    FROM (SELECT r.id, r.status, r.full_name, r.social_name, r.email, r.institution, r.course, r.team_name,
                 r.is_leader, r.leader_email, r.technical_profile, r.technical_area, r.github_username,
                 r.origin, r.heard_from, r.submitted_at, r.confirmed_at, r.updated_at
            FROM competition.registrations r
           WHERE r.edition_id = e.id AND r.status <> 'pending_confirmation') x;
  SELECT count(*) INTO v_pending FROM competition.registrations r
   WHERE r.edition_id = e.id AND r.status = 'pending_confirmation';

  SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.leader_email), '[]'::jsonb) INTO v_teams
    FROM (SELECT r.leader_email,
                 count(*) AS members,
                 array_agg(DISTINCT r.team_name) AS team_names,
                 bool_or(r.technical_profile) AS has_technical,
                 bool_or(r.is_leader AND r.email = r.leader_email) AS leader_registered,
                 (e.team_min IS NOT NULL AND (count(*) < e.team_min OR count(*) > e.team_max)) AS size_out_of_range,
                 count(DISTINCT lower(btrim(r.team_name))) > 1 AS team_name_diverges
            FROM competition.registrations r
           WHERE r.edition_id = e.id AND r.leader_email IS NOT NULL
             AND r.status IN ('submitted', 'valid', 'selected', 'waitlisted', 'not_selected')
           GROUP BY r.leader_email) t;

  INSERT INTO public.pii_access_log (accessor_id, target_member_id, fields_accessed, context, reason, actor_kind)
  VALUES (v_member, NULL,
          ARRAY['full_name', 'social_name', 'email', 'institution', 'course', 'team_name', 'leader_email',
                'technical_profile', 'technical_area', 'github_username', 'origin', 'heard_from'],
          'competition_registrations_list', 'edition=' || e.slug || ' rows=' || v_n, 'human');

  RETURN jsonb_build_object('edition', e.slug, 'pending_confirmation', v_pending, 'registrations', v_rows, 'teams', v_teams);
END
$function$;

-- Conteúdo do e-mail, para a Edge Function (só service_role). O token não é guardado: chega no corpo da
-- chamada, e só abre o conteúdo se for um link válido DESTA inscrição.
CREATE FUNCTION public._competition_email_payload(p_registration_id uuid, p_token text) RETURNS jsonb
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
    'to', r.email, 'name', coalesce(r.social_name, r.full_name), 'edition_slug', e.slug, 'edition_title', e.title,
    'pending', r.status = 'pending_confirmation',
    'confirm_by', CASE WHEN r.status = 'pending_confirmation' THEN r.submitted_at + interval '48 hours' END,
    'team_name', r.team_name, 'is_leader', r.is_leader, 'leader_email', r.leader_email,
    'closes_at', e.registration_closes_at, 'timezone', e.timezone, 'confirmation_note', e.confirmation_note,
    'rules_url', e.rules_url, 'privacy_notice_url', e.privacy_notice_url)
  FROM competition.registrations r JOIN competition.editions e ON e.id = r.edition_id
  WHERE r.id = p_registration_id AND r.id = competition.registration_by_token(p_token);
$function$;

-- ─── (5) a limpeza, agendada e registrada ─────────────────────────────────────────────────────
SELECT cron.schedule('competition-purge-hourly', '23 * * * *', 'SELECT competition.purge(p_dry_run := false);');

INSERT INTO public.data_retention_policy (table_name, retention_days, cleanup_type, description, is_active, executor)
VALUES ('competition.registrations', 2, 'delete',
        'Inscrições de competição (ADR-0133). As NÃO confirmadas saem em 2 dias (e-mail nunca provado). As '
        || 'confirmadas saem no retention_until de cada uma, que vem de competition.editions.retention_days '
        || '(decisão (a) do GP, obrigatória para abrir a edição).',
        true, 'competition-purge-hourly');

-- ─── permissões ────────────────────────────────────────────────────────────────────────────────
-- Revogação explícita no fim: ALTER DEFAULT PRIVILEGES por schema não revoga o EXECUTE que o padrão global
-- concede a PUBLIC, então quem fecha é isto, depois de tudo criado.
REVOKE ALL ON ALL TABLES IN SCHEMA competition FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA competition FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA competition FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.competition_edition_public(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.competition_edition_public(text) TO anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.competition_register(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.competition_register(text, jsonb) TO anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.competition_registration_confirm(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.competition_registration_confirm(text) TO anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.competition_registration_get(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.competition_registration_get(text) TO anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.competition_registration_update(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.competition_registration_update(text, jsonb) TO anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.competition_registration_withdraw(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.competition_registration_withdraw(text) TO anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.competition_registrations_list(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.competition_registrations_list(text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public._competition_email_payload(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._competition_email_payload(uuid, text) TO service_role;
