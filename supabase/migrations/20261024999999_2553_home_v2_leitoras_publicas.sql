-- #2553 PR 2 (home v2): leitoras públicas novas, num pacote aditivo. Nenhuma tela lê estas funções quando a
-- migration entra; quem passa a lê-las são as PRs de front que vêm depois (leitora depois da escritora).
--
-- Decisões do GP em 19 e 20/10/2026 (artefato "Home v2 do Núcleo", aba de decisões) que este arquivo implementa:
--   D3  gestão e lideranças só em contagem por função; mural CPMAI sem consentimento novo: exige o credly_url no
--       perfil, só membros ativos, filtro pelo SELO da certificação (nunca pelo texto "cpmai", que pega quem só tem
--       o curso introdutório), e cada nome leva ao Credly da própria pessoa;
--   D4  o ranking com nomes sai do visitante: get_public_gamification_summary é o agregado que substitui
--       get_public_leaderboard no /gamification (o REVOKE da antiga é um pacote posterior, depois do front);
--   D8  o vínculo campo -> linha mora numa tabela de configuração nova, que nasce vazia;
--   D9  trilha com uma população só: a equipe de pesquisa (v_operational_members), a mesma dos "pesquisadores";
--   D11 entrada por capítulo só com o ano e sem situação jurídica; os 10 capítulos anunciados no 21º CBGPL
--       entram em 30/04/2026, último dia do congresso;
--   cursos: EL106, EL174 e EL251 são gratuitos só para membro PMI, e is_free sozinho não diz isso;
--   canais: os links públicos saem de comms_channel_config, nunca das colunas de credencial.
--
-- Toda função pública aqui é SECURITY DEFINER, não devolve PII além do que a decisão nomeia (o nome e o link do
-- Credly no mural) e exclui iniciativa confidencial pelo portão rls_can_see_initiative() (ADR-0105).
--
-- (1)  research_line_fields: vertical (community_vertical) x linha de pesquisa; deny-all, lida só pela (2).
-- (2)  get_public_line_fields()
-- (3)  get_public_home_team()
-- (4)  get_public_cpmai_wall()
-- (5)  get_public_trail_summary()
-- (6)  get_public_gamification_summary()
-- (7)  get_public_channels()
-- (8)  get_public_chapter_entries()
-- (9)  courses.free_for + get_trail_courses com a coluna nova (DROP + CREATE, porque é RETURNS TABLE)
-- (10) partner_chapters.partnership_start: os 10 capítulos anunciados e a sede + COMMENT com o significado novo
-- (11) comms_channel_config: a URL pública do Instagram de volta ao config
-- (12) portfolio_kpi_targets: o rótulo de 2 metas diz a janela do ano (D9)
-- (13) calc_trail_completion_pct: a meta da trilha conta a equipe de pesquisa, a mesma população do hero
--
-- Fora deste pacote, de propósito: a vaga VEP com link (D1, opção a). vep_opportunities não guarda a URL pública
-- da vaga nem o prazo de inscrição (vep_url aponta para o painel do recrutador, e end_date é o fim do mandato), então
-- a home segue no formulário de interesse (D1, opção b) até um pacote próprio trazer essas duas colunas.
--
-- Rollback: DROP das funções (2) a (8) e da tabela (1); get_trail_courses pela captura de
--   20260673500000_p169_get_trail_courses_public_rpc.sql (DROP + CREATE + o mesmo GRANT);
--   ALTER TABLE courses DROP CONSTRAINT courses_free_for_matches_is_free, DROP COLUMN free_for; is_free = true nos 3
--   códigos; partnership_start = NULL nos 10 com partnership_status = 'announced_at_risk' e 2025-07-01 no PMI-GO (a
--   linha de auditoria desta migration lista os códigos e o antes do GO); config do instagram sem a chave profile_url;
--   metric_label de cpmai_certified e webinars_completed pelo "antes" da linha de auditoria kpi.label_set;
--   calc_trail_completion_pct pela captura de 20260805000081_p277_419_m6_trail_cpmai_canonical.sql.

-- ── (1) campo -> linha ────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.research_line_fields (
  vertical_initiative_id uuid NOT NULL REFERENCES public.initiatives(id) ON DELETE CASCADE,
  line_initiative_id     uuid NOT NULL REFERENCES public.initiatives(id) ON DELETE CASCADE,
  created_at             timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (vertical_initiative_id, line_initiative_id)
);
CREATE INDEX IF NOT EXISTS rlf_line_idx ON public.research_line_fields (line_initiative_id);
ALTER TABLE public.research_line_fields ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.research_line_fields FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE public.research_line_fields IS
  '#2553 D8 (GP 20/10/2026): o campo de atuação (iniciativa community_vertical) a que cada linha de pesquisa (iniciativa com legacy_tribe_id) serve. A coordenação preenche uma vez, com as lideranças. Deny-all: a home lê só por get_public_line_fields(), e a tabela vazia esconde o filtro por campo.';

-- o par só vale entre uma vertical e uma linha de pesquisa: o resto é erro de cadastro, recusado na hora
CREATE OR REPLACE FUNCTION public._research_line_fields_pair_check()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.initiatives v
                 WHERE v.id = NEW.vertical_initiative_id AND v.kind = 'community_vertical') THEN
    RAISE EXCEPTION 'research_line_fields: % não é uma vertical (community_vertical)', NEW.vertical_initiative_id
      USING ERRCODE = '23514';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.initiatives l
                 WHERE l.id = NEW.line_initiative_id AND l.legacy_tribe_id IS NOT NULL) THEN
    RAISE EXCEPTION 'research_line_fields: % não é uma linha de pesquisa (sem legacy_tribe_id)', NEW.line_initiative_id
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION public._research_line_fields_pair_check() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_research_line_fields_pair_check ON public.research_line_fields;
CREATE TRIGGER trg_research_line_fields_pair_check
  BEFORE INSERT OR UPDATE ON public.research_line_fields
  FOR EACH ROW EXECUTE FUNCTION public._research_line_fields_pair_check();

-- ── (2) o vínculo para a home ─────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_public_line_fields()
 RETURNS TABLE(tribe_id integer, vertical_id uuid, vertical_title text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT l.legacy_tribe_id, v.id, v.title
  FROM public.research_line_fields f
  JOIN public.initiatives v ON v.id = f.vertical_initiative_id
  JOIN public.initiatives l ON l.id = f.line_initiative_id
  WHERE v.kind = 'community_vertical' AND v.status = 'active'
    AND l.legacy_tribe_id IS NOT NULL AND l.status = 'active'
    AND coalesce(v.visibility, 'standard') <> 'confidential'
    AND coalesce(l.visibility, 'standard') <> 'confidential'
    AND public.rls_can_see_initiative(v.id)
    AND public.rls_can_see_initiative(l.id)
  ORDER BY l.legacy_tribe_id, v.title;
$function$;
COMMENT ON FUNCTION public.get_public_line_fields() IS
  '#2553 D8: pares (linha, campo) de research_line_fields, só entre iniciativas ativas e não confidenciais. Vazio = a home esconde o filtro por campo.';
REVOKE ALL ON FUNCTION public.get_public_line_fields() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_line_fields() TO anon, authenticated, service_role;

-- ── (3) quem faz, por função, em contagem ─────────────────────────────────────────────────────────────────────
-- Pessoas distintas. Liderança = engajamento ativo e vigente com papel de condução numa iniciativa ativa e não
-- confidencial; linha = iniciativa com legacy_tribe_id. Nenhum nome sai daqui (D3).
CREATE OR REPLACE FUNCTION public.get_public_home_team()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH active_members AS (
    SELECT m.id, m.operational_role, coalesce(m.designations, '{}'::text[]) AS designations
    FROM public.members m
    WHERE m.is_active = true AND m.current_cycle_active = true
  ),
  live_engagements AS (
    SELECT e.person_id, e.role, i.legacy_tribe_id, i.kind, i.metadata
    FROM public.engagements e
    JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.status = 'active'
      AND e.start_date <= CURRENT_DATE
      AND (e.end_date IS NULL OR e.end_date >= CURRENT_DATE)
      AND i.status = 'active'
      AND coalesce(i.visibility, 'standard') <> 'confidential'
      AND public.rls_can_see_initiative(i.id)
  )
  SELECT jsonb_build_object(
    'management', (
      SELECT count(*) FROM active_members a
      WHERE a.operational_role IN ('manager', 'deputy_manager') OR 'co_gp' = ANY (a.designations)
    ),
    'line_leaders', (
      SELECT count(DISTINCT le.person_id) FROM live_engagements le
      WHERE le.legacy_tribe_id IS NOT NULL AND le.role IN ('leader', 'co_leader')
    ),
    'initiative_leaders', (
      SELECT count(DISTINCT le.person_id) FROM live_engagements le
      WHERE le.legacy_tribe_id IS NULL AND le.kind <> 'community_vertical'
        AND le.role IN ('leader', 'co_leader', 'coordinator', 'owner')
    ),
    'curators', (
      SELECT count(DISTINCT le.person_id) FROM live_engagements le WHERE le.role = 'curator'
    ),
    'hub_members', (
      SELECT count(DISTINCT le.person_id) FROM live_engagements le
      WHERE le.kind = 'workgroup' AND coalesce((le.metadata->>'landing_arm')::boolean, false) = true
    ),
    'chapter_focal_points', (
      SELECT count(*) FROM active_members a
      WHERE a.operational_role IN ('sponsor', 'chapter_liaison')
         OR a.designations && ARRAY['sponsor', 'chapter_liaison']::text[]
    ),
    'researchers', (SELECT count(*) FROM public.v_operational_members)
  );
$function$;
COMMENT ON FUNCTION public.get_public_home_team() IS
  '#2553 D3 (GP 21/10/2026): a equipe por função, em contagem de pessoas distintas, para a home pública. researchers = v_operational_members, a mesma população do hero (get_homepage_stats.members).';
REVOKE ALL ON FUNCTION public.get_public_home_team() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_home_team() TO anon, authenticated, service_role;

-- ── (4) mural PMI-CPMAI ───────────────────────────────────────────────────────────────────────────────────────
-- O selo é o da certificação, pelo nome que o catálogo de cursos registra para o PMI_CPMAI_MASTER (fonte única):
-- o curso introdutório tem outro selo e não entra. Sem credly_url no perfil a pessoa some na hora, mesmo que o
-- último sync ainda guarde o selo. Sai só o que a D3 nomeia: nome, ano da certificação e o Credly da pessoa.
CREATE OR REPLACE FUNCTION public.get_public_cpmai_wall()
 RETURNS TABLE(name text, certified_year integer, credly_url text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT m.name,
         min(CASE WHEN b->>'issued_at' ~ '^[0-9]{4}-' THEN left(b->>'issued_at', 4)::integer END),
         btrim(m.credly_url)
  FROM public.members m
  CROSS JOIN LATERAL jsonb_array_elements(
    CASE WHEN jsonb_typeof(m.credly_badges) = 'array' THEN m.credly_badges ELSE '[]'::jsonb END
  ) AS b
  WHERE m.is_active = true
    AND m.current_cycle_active = true
    AND btrim(coalesce(m.credly_url, '')) ~* '^https://(www\.)?credly\.com/'
    AND b->>'name' = (SELECT c.credly_badge_name FROM public.courses c WHERE c.code = 'PMI_CPMAI_MASTER')
  GROUP BY m.id, m.name, m.credly_url
  ORDER BY 2 NULLS LAST, 1;
$function$;
COMMENT ON FUNCTION public.get_public_cpmai_wall() IS
  '#2553 D3 (GP 20/10/2026): mural PMI-CPMAI sem consentimento novo. Membro ativo no ciclo, com credly_url no perfil e com o selo cujo nome é courses.credly_badge_name do PMI_CPMAI_MASTER. Devolve nome, ano da certificação e o link do Credly da pessoa.';
REVOKE ALL ON FUNCTION public.get_public_cpmai_wall() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_cpmai_wall() TO anon, authenticated, service_role;

-- ── (5) trilha, em agregado ───────────────────────────────────────────────────────────────────────────────────
-- População = a equipe de pesquisa (v_operational_members), a mesma do hero. Curso conta uma vez por pessoa.
CREATE OR REPLACE FUNCTION public.get_public_trail_summary()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH trail AS (
    SELECT c.id FROM public.courses c WHERE c.is_trail = true
  ),
  per_person AS (
    SELECT om.id,
           count(DISTINCT cp.course_id) FILTER (WHERE cp.status = 'completed') AS done
    FROM public.v_operational_members om
    LEFT JOIN public.course_progress cp
      ON cp.member_id = om.id AND cp.course_id IN (SELECT t.id FROM trail t)
    GROUP BY om.id
  ),
  total AS (SELECT count(*)::integer AS n FROM trail)
  SELECT jsonb_build_object(
    'population', (SELECT count(*) FROM per_person),
    'trail_courses', (SELECT n FROM total),
    'completed_all', (SELECT count(*) FROM per_person p, total WHERE total.n > 0 AND p.done >= total.n),
    'avg_pct', (SELECT round(coalesce(avg(p.done::numeric / nullif(total.n, 0)), 0) * 100)
                FROM per_person p, total)
  );
$function$;
COMMENT ON FUNCTION public.get_public_trail_summary() IS
  '#2553 D9: trilha para o visitante, sem nome. population = v_operational_members; completed_all = quem concluiu todos os cursos is_trail; avg_pct = média com crédito parcial.';
REVOKE ALL ON FUNCTION public.get_public_trail_summary() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_trail_summary() TO anon, authenticated, service_role;

-- ── (6) gamificação, em agregado (substitui o leaderboard com nomes para o visitante) ─────────────────────────
-- Mesma população e mesma soma vitalícia de get_public_leaderboard; os níveis vêm de platform_settings, a fonte
-- única que get_gamification_rules_catalog já serve ao membro.
CREATE OR REPLACE FUNCTION public.get_public_gamification_summary()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH xp AS (
    SELECT gp.member_id, sum(gp.points) AS total
    FROM public.gamification_points gp
    GROUP BY gp.member_id
  ),
  pool AS (
    SELECT coalesce(xp.total, 0) AS pts
    FROM public.members m
    LEFT JOIN xp ON xp.member_id = m.id
    WHERE m.is_active = true AND m.current_cycle_active = true AND m.gamification_opt_out = false
  ),
  levels AS (
    SELECT t.slug, t.emoji, t.min_points, t.max_points
    FROM public.platform_settings ps
    CROSS JOIN LATERAL jsonb_to_recordset(
      CASE WHEN jsonb_typeof(ps.value) = 'array' THEN ps.value ELSE '[]'::jsonb END
    ) AS t(slug text, emoji text, min_points integer, max_points integer)
    WHERE ps.key = 'gamification_level_thresholds'
  )
  SELECT jsonb_build_object(
    'participants', (SELECT count(*) FROM pool),
    'with_points', (SELECT count(*) FROM pool WHERE pts > 0),
    'total_points', (SELECT coalesce(sum(pts), 0) FROM pool),
    'levels', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'slug', l.slug, 'emoji', l.emoji, 'min_points', l.min_points, 'max_points', l.max_points,
               'members', (SELECT count(*) FROM pool p
                           WHERE p.pts >= l.min_points AND (l.max_points IS NULL OR p.pts <= l.max_points)))
             ORDER BY l.min_points)
      FROM levels l), '[]'::jsonb)
  );
$function$;
COMMENT ON FUNCTION public.get_public_gamification_summary() IS
  '#2553 D4 (GP 20/10/2026): o /gamification do visitante em agregado, sem nome. Mesma população de get_public_leaderboard; níveis de platform_settings.gamification_level_thresholds.';
REVOKE ALL ON FUNCTION public.get_public_gamification_summary() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_gamification_summary() TO anon, authenticated, service_role;

-- ── (7) canais oficiais ───────────────────────────────────────────────────────────────────────────────────────
-- Só a URL pública de cada canal, pela chave que o seed de cada um usa. As colunas de credencial (api_key,
-- oauth_token, oauth_refresh_token) nunca entram no SELECT.
CREATE OR REPLACE FUNCTION public.get_public_channels()
 RETURNS TABLE(channel text, url text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT c.channel, u.url
  FROM public.comms_channel_config c
  CROSS JOIN LATERAL (
    SELECT CASE c.channel
             WHEN 'linkedin'  THEN c.config->>'company_url'
             WHEN 'instagram' THEN c.config->>'profile_url'
             WHEN 'youtube'   THEN c.config->>'channel_url'
             WHEN 'spotify'   THEN c.config->>'show_url'
           END AS url
  ) AS u
  WHERE u.url ~ '^https://[^[:space:]]+$'
  ORDER BY CASE c.channel WHEN 'linkedin' THEN 1 WHEN 'instagram' THEN 2 WHEN 'youtube' THEN 3 ELSE 4 END;
$function$;
COMMENT ON FUNCTION public.get_public_channels() IS
  '#2553 (GP 20/10/2026): os links públicos dos canais oficiais, de comms_channel_config.config. Nunca devolve credencial.';
REVOKE ALL ON FUNCTION public.get_public_channels() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_channels() TO anon, authenticated, service_role;

-- ── (8) desde quando cada capítulo participa ──────────────────────────────────────────────────────────────────
-- Só o ano e a sede (D11): partnership_status não sai daqui.
CREATE OR REPLACE FUNCTION public.get_public_chapter_entries()
 RETURNS TABLE(display_code text, entry_year integer, is_host boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT 'PMI-' || cr.chapter_code,
         extract(year FROM pc.partnership_start)::integer,
         coalesce(cr.is_contracting_chapter, false)
  FROM public.chapter_registry cr
  LEFT JOIN public.partner_chapters pc ON pc.chapter_code = 'PMI-' || cr.chapter_code AND pc.is_active = true
  WHERE cr.is_active = true AND cr.country = 'BR'
  ORDER BY coalesce(cr.is_contracting_chapter, false) DESC, pc.partnership_start NULLS LAST, cr.chapter_code;
$function$;
COMMENT ON FUNCTION public.get_public_chapter_entries() IS
  '#2553 D11 (GP 20/10/2026): ano de entrada de cada capítulo (partner_chapters.partnership_start) e a sede (is_contracting_chapter). Sem situação jurídica.';
REVOKE ALL ON FUNCTION public.get_public_chapter_entries() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_chapter_entries() TO anon, authenticated, service_role;

-- ── (9) para quem o curso é gratuito ─────────────────────────────────────────────────────────────────────────
-- Convenção já em uso (migration 2741): is_free = true é gratuito para todos; gratuito só para membro PMI é
-- is_free = false. EL106 (DATA_LANDSCAPE), EL174 (AI_INFRA) e EL251 (AI_AGILE) estavam com is_free = true.
-- free_for dá o rótulo de três estados e o CHECK amarra os dois campos, para que nunca digam coisas diferentes.
ALTER TABLE public.courses ADD COLUMN IF NOT EXISTS free_for text
  CHECK (free_for IN ('everyone', 'pmi_members'));

DO $do$
DECLARE
  v_rows integer;
BEGIN
  UPDATE public.courses SET is_free = false
  WHERE code IN ('DATA_LANDSCAPE', 'AI_INFRA', 'AI_AGILE');
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 3 THEN
    RAISE EXCEPTION '#2553 cursos: esperava 3 cursos gratuitos só para membro PMI, achei %', v_rows;
  END IF;
END;
$do$;

UPDATE public.courses SET free_for = CASE
    WHEN code IN ('DATA_LANDSCAPE', 'AI_INFRA', 'AI_AGILE', 'AGENTIC_FOUNDATIONS', 'AGENTIC_BUILD_LAB') THEN 'pmi_members'
    WHEN is_free = true THEN 'everyone'
    ELSE NULL
  END;

ALTER TABLE public.courses DROP CONSTRAINT IF EXISTS courses_free_for_matches_is_free;
ALTER TABLE public.courses ADD CONSTRAINT courses_free_for_matches_is_free
  CHECK (coalesce(free_for = 'everyone', false) = coalesce(is_free, false));

COMMENT ON COLUMN public.courses.free_for IS
  '#2553 (GP 20/10/2026): para quem o curso é gratuito. everyone = todos (is_free = true); pmi_members = só membro PMI; NULL = pago. A home mostra o rótulo a partir daqui.';

DROP FUNCTION IF EXISTS public.get_trail_courses();
CREATE FUNCTION public.get_trail_courses()
RETURNS TABLE(
  code              text,
  name              text,
  tier              text,
  is_trail          boolean,
  url               text,
  sort_order        integer,
  credly_badge_name text,
  has_credly        boolean,
  free_for          text
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT
    c.code,
    c.name,
    c.tier,
    c.is_trail,
    c.url,
    c.sort_order,
    c.credly_badge_name,
    (c.credly_badge_name IS NOT NULL) AS has_credly,
    c.free_for
  FROM public.courses c
  ORDER BY
    CASE c.tier
      WHEN 'core' THEN 1
      WHEN 'specialty' THEN 2
      WHEN 'complementary' THEN 3
      WHEN 'master' THEN 4
      ELSE 5
    END,
    c.sort_order,
    c.code;
$function$;

GRANT EXECUTE ON FUNCTION public.get_trail_courses() TO anon, authenticated, service_role;

-- ── (10) entrada de cada capítulo ─────────────────────────────────────────────────────────────────────────────
-- D11 (GP 20/10/2026): PMI Goiás desde 2024 (piloto); MG, DF, CE e RS desde 2025; os outros 10 desde 30/04/2026,
-- último dia do 21º CBGPL. Medido pela orquestradora em 21/10/2026: os 5 assinados estavam em 2025-07-01 (início do
-- cycle_2) e os 10 anunciados sem data. O GO passa ao início do ciclo 'pilot' (cycles.cycle_start), lido da tabela
-- de ciclos e não escrito aqui. Nenhuma função lia partnership_start (medido em 21/10/2026, com controle de 3 que
-- leem partnership_status); os guards da tabela afirmam partnership_status, que não muda aqui.
DO $do$
DECLARE
  v_codes      text[];
  v_pilot      date;
  v_go_before  date;
  v_go_rows    integer;
BEGIN
  WITH changed AS (
    UPDATE public.partner_chapters SET partnership_start = DATE '2026-04-30'
    WHERE partnership_start IS NULL AND partnership_status = 'announced_at_risk'
    RETURNING chapter_code
  )
  SELECT array_agg(chapter_code ORDER BY chapter_code) INTO v_codes FROM changed;

  IF coalesce(array_length(v_codes, 1), 0) <> 10 THEN
    RAISE EXCEPTION '#2553 capítulos: esperava 10 capítulos anunciados sem data, achei %', coalesce(array_length(v_codes, 1), 0);
  END IF;

  SELECT c.cycle_start INTO v_pilot FROM public.cycles c WHERE c.cycle_code = 'pilot';
  IF v_pilot IS NULL OR extract(year FROM v_pilot) <> 2024 THEN
    RAISE EXCEPTION '#2553 capítulos: o ciclo pilot deveria começar em 2024, achei %', v_pilot;
  END IF;

  SELECT pc.partnership_start INTO v_go_before FROM public.partner_chapters pc WHERE pc.chapter_code = 'PMI-GO';
  UPDATE public.partner_chapters SET partnership_start = v_pilot
  WHERE chapter_code = 'PMI-GO' AND partnership_start = DATE '2025-07-01';
  GET DIAGNOSTICS v_go_rows = ROW_COUNT;
  IF v_go_rows <> 1 THEN
    RAISE EXCEPTION '#2553 capítulos: esperava o PMI-GO em 2025-07-01, achei %', v_go_before;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, changes, metadata)
  VALUES (NULL, 'chapters.entry_date_set', 'partner_chapters',
          jsonb_build_object(
            'announced', jsonb_build_object('partnership_start', '2026-04-30', 'chapter_codes', to_jsonb(v_codes)),
            'host', jsonb_build_object('chapter_code', 'PMI-GO', 'before', v_go_before, 'after', v_pilot)),
          jsonb_build_object('issue', '#2553', 'source', 'migration',
                             'decision', 'GP 20/10/2026 (D11): entrada por capítulo, só o ano'));
END;
$do$;

COMMENT ON COLUMN public.partner_chapters.partnership_start IS
  '#2553 (GP 20/10/2026): data de entrada do capítulo no Núcleo, mostrada ao público só como ano (get_public_chapter_entries). Não indica assinatura do acordo: isso é partnership_status. A sede (PMI-GO) entra no início do ciclo pilot (cycles.cycle_start); os capítulos anunciados no 21º CBGPL entram em 2026-04-30, último dia do congresso.';

-- ── (11) a URL pública do Instagram volta ao config ───────────────────────────────────────────────────────────
-- Medido pela orquestradora em 21/10/2026: o config do instagram perdeu a chave profile_url do seed (W94) e hoje só
-- tem chaves de integração. O valor é o que o rodapé publica hoje. As outras chaves ficam como estão.
DO $do$
DECLARE
  v_rows integer;
BEGIN
  UPDATE public.comms_channel_config
  SET config = coalesce(config, '{}'::jsonb) || jsonb_build_object('profile_url', 'https://www.instagram.com/nucleo.ia.gp')
  WHERE channel = 'instagram' AND NOT (coalesce(config, '{}'::jsonb) ? 'profile_url');
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION '#2553 canais: esperava 1 linha do instagram sem profile_url, achei %', v_rows;
  END IF;
END;
$do$;

-- ── (12) o rótulo das metas diz o que contam ──────────────────────────────────────────────────────────────────
-- D9 (GP 20/10/2026): a meta de CPMAI conta as certificações conquistadas no ano (get_cpmai_certified_goal_count do
-- ano corrente), e a de webinars os realizados desde 1º de janeiro (get_webinars_count). O rótulo passa a dizer isso;
-- o ano em si fica fora do banco, no título da seção. Medido pela orquestradora em 21/10/2026: portfolio_kpi_targets
-- tem só o ciclo cycle3-2026, uma linha por métrica, e o único leitor de metric_label é exec_portfolio_health. A
-- troca exige o rótulo de hoje: se alguém o mudou antes, a migration para em vez de sobrescrever.
DO $do$
DECLARE
  v_rows       integer;
  v_cpmai_old  jsonb;
  v_web_old    jsonb;
  v_cpmai_new  jsonb := jsonb_build_object(
    'pt', 'Certificações PMI-CPMAI conquistadas no ano',
    'en', 'PMI-CPMAI certifications earned this year',
    'es', 'Certificaciones PMI-CPMAI obtenidas en el año');
  v_web_new    jsonb := jsonb_build_object(
    'pt', 'Webinars realizados no ano',
    'en', 'Webinars held this year',
    'es', 'Webinars realizados en el año');
BEGIN
  SELECT metric_label INTO v_cpmai_old FROM public.portfolio_kpi_targets
  WHERE cycle_code = 'cycle3-2026' AND metric_key = 'cpmai_certified';
  UPDATE public.portfolio_kpi_targets SET metric_label = v_cpmai_new
  WHERE cycle_code = 'cycle3-2026' AND metric_key = 'cpmai_certified' AND metric_label->>'pt' = 'Certificados CPMAI';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION '#2553 metas: esperava 1 linha de cpmai_certified com o rótulo "Certificados CPMAI", achei % (rótulo atual %)', v_rows, v_cpmai_old;
  END IF;

  SELECT metric_label INTO v_web_old FROM public.portfolio_kpi_targets
  WHERE cycle_code = 'cycle3-2026' AND metric_key = 'webinars_completed';
  UPDATE public.portfolio_kpi_targets SET metric_label = v_web_new
  WHERE cycle_code = 'cycle3-2026' AND metric_key = 'webinars_completed' AND metric_label->>'pt' = 'Webinares/Talks';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION '#2553 metas: esperava 1 linha de webinars_completed com o rótulo "Webinares/Talks", achei % (rótulo atual %)', v_rows, v_web_old;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, changes, metadata)
  VALUES (NULL, 'kpi.label_set', 'portfolio_kpi_targets',
          jsonb_build_object(
            'cpmai_certified', jsonb_build_object('before', v_cpmai_old, 'after', v_cpmai_new),
            'webinars_completed', jsonb_build_object('before', v_web_old, 'after', v_web_new)),
          jsonb_build_object('issue', '#2553', 'source', 'migration', 'cycle_code', 'cycle3-2026',
                             'decision', 'GP 20/10/2026 (D9): o rótulo diz a janela de cada meta'));
END;
$do$;

-- ── (13) a meta da trilha conta a equipe de pesquisa ─────────────────────────────────────────────────────────
-- GP 22/10/2026 (opção a): a meta da trilha conta a mesma população dos pesquisadores do hero. A coorte deixa de ser
-- uma lista de exclusão de papéis e passa a ser v_operational_members (ADR-0126), a mesma de get_homepage_stats.members
-- e de get_public_trail_summary; cada curso concluído conta uma vez por pessoa, como na summary. Medido pela
-- orquestradora em 22/10/2026: as duas populações têm as mesmas 84 pessoas, nenhum membro ativo tem papel fora das duas
-- listas, e a meta vale 47. A troca não pode mudar o número de hoje: se mudar, a migration para.
-- Leitores no prosrc (orquestradora, 21/10/2026): exec_portfolio_health, get_annual_kpis e um comentário em
-- get_public_trail_ranking.
CREATE TEMP TABLE _2553_trail_antes ON COMMIT DROP AS
  SELECT public.calc_trail_completion_pct() AS calc,
         (SELECT (e->>'current')::numeric FROM jsonb_array_elements(public.exec_portfolio_health()) e
          WHERE e->>'metric_key' = 'certification_trail') AS health,
         public.get_annual_kpis() AS annual;

CREATE OR REPLACE FUNCTION public.calc_trail_completion_pct()
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- #2553 (GP 22/10/2026, opção a): a meta da trilha conta a mesma população dos pesquisadores do hero
  -- (v_operational_members). Crédito parcial: média, por pessoa, dos cursos is_trail concluídos (cada curso uma vez)
  -- sobre o total de cursos is_trail, que segue dinâmico. É a conta de get_public_trail_summary.avg_pct.
  SELECT ROUND(COALESCE(AVG(per.done::numeric / NULLIF(tot.n, 0)) * 100, 0))
  FROM (
    SELECT om.id,
           COUNT(DISTINCT cp.course_id) FILTER (WHERE cp.status = 'completed') AS done
    FROM public.v_operational_members om
    LEFT JOIN public.course_progress cp
      ON cp.member_id = om.id AND cp.course_id IN (SELECT c.id FROM public.courses c WHERE c.is_trail = true)
    GROUP BY om.id
  ) per
  CROSS JOIN (SELECT COUNT(*) AS n FROM public.courses WHERE is_trail = true) tot;
$function$;

DO $do$
DECLARE
  v_before record;
  v_calc   numeric;
  v_health numeric;
  v_annual jsonb;
BEGIN
  SELECT * INTO v_before FROM _2553_trail_antes;
  v_calc := public.calc_trail_completion_pct();
  SELECT (e->>'current')::numeric INTO v_health FROM jsonb_array_elements(public.exec_portfolio_health()) e
  WHERE e->>'metric_key' = 'certification_trail';
  v_annual := public.get_annual_kpis();

  IF v_calc IS DISTINCT FROM v_before.calc OR v_health IS DISTINCT FROM v_before.health
     OR v_annual IS DISTINCT FROM v_before.annual THEN
    RAISE EXCEPTION '#2553 trilha: a troca de população mudou o número de hoje (calc % -> %, meta % -> %, get_annual_kpis igual: %)',
      v_before.calc, v_calc, v_before.health, v_health, v_annual IS NOT DISTINCT FROM v_before.annual;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, changes, metadata)
  VALUES (NULL, 'kpi.trail_cohort_aligned', 'calc_trail_completion_pct',
          jsonb_build_object('before', v_before.calc, 'after', v_calc, 'cohort', 'v_operational_members'),
          jsonb_build_object('issue', '#2553', 'source', 'migration',
                             'decision', 'GP 22/10/2026 (opção a): a meta da trilha conta a mesma população dos pesquisadores do hero'));
END;
$do$;

NOTIFY pgrst, 'reload schema';
