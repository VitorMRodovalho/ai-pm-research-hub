-- #2296 item 3 — a decisao por badge do Credly vira DADO, e o detector para de repetir o decidido.
--
-- O PROBLEMA: `_credly_unmapped_rows()` lista 39 badges / 64 ocorrencias, e TODOS os 39 estao em
-- `badge`/10 por DECISAO, nao por lacuna. O detector nao sabe disso, entao repete mensalmente uma
-- lista em que nada e novo. Um detector que nao distingue "novo" de "ja decidido" ensina a ignorar.
--
-- ONDE A DECISAO VIVIA ATE AGORA, e por que isso e fragil:
--   * 17 dos 39 estao afirmados UM A UM em guard de teste (medido em 16/09):
--       - 6 em tests/edge-functions/classify-badge.test.mjs (#1209, GP 2026-07-08)
--       - 11 mais na camada B de tests/contracts/2296-taxonomia-dos-badges-do-credly.test.mjs
--     ('Lifelong Learning' aparece nos dois; a uniao e 17, nao 18.)
--   * Os outros 22 estao cobertos apenas por uma FRASE DE FAMILIA em comentario
--     ("participation/recognition + out-of-domain certs"). Prosa nao e afirmacao por badge.
--
-- ⚠️ O handoff de 16/09 dizia "33 badges sem afirmacao". Medido arquivo por arquivo, sao 22: a
-- conta antiga olhou so o guard de edge-functions e nao contou a camada B, que tambem nomeia
-- badge a badge. O passe de julgamento que sobra para o dono e menor do que se pensava.
--
-- O QUE ESTA MIGRATION FAZ, e o que deliberadamente NAO faz:
--   FAZ  — cria a tabela, e SEMEIA apenas as 17 decisoes que JA existem afirmadas em guard,
--          copiando a razao e a data da fonte. Isso e conversao de prosa em dado, nao julgamento novo.
--   FAZ  — `_credly_unmapped_rows()` passa a excluir badge com decisao registrada, entao o detector
--          cai de 39 para 22 e passa a listar so o que ainda espera decisao.
--   NAO FAZ — nao decide nada sobre os 22 restantes. Essa e decisao do dono, e inventa-la aqui
--          seria exatamente o erro que a camada G da #2296 documenta: em 15/09 levei ao dono uma
--          recomendacao sem a regra do #1209 na tela, e ele aprovou algo que uma decisao anterior
--          ja tinha negado. Decisao sem a norma na tela nao e decisao informada.
--
-- A TABELA NAO SUBSTITUI OS GUARDS. Os guards afirmam o comportamento do CLASSIFICADOR (codigo);
-- esta tabela afirma a DECISAO EDITORIAL (dado). Um badge pode ter decisao registrada aqui e
-- continuar guardado la — e e o caso dos 17. Apagar os guards por causa desta tabela trocaria uma
-- assercao executavel por uma linha de configuracao.
--
-- Cross-ref: #2296, #1209 (o limite fora-do-dominio), #1087 (ledger append-only), #1149 (preco
--            de UMA tabela), ADR-0009.

CREATE TABLE IF NOT EXISTS public.credly_badge_decisions (
  badge_name       text PRIMARY KEY,
  decided_category text        NOT NULL CHECK (length(btrim(decided_category)) > 0),
  rationale        text        NOT NULL CHECK (length(btrim(rationale)) > 0),
  decision_source  text        NOT NULL CHECK (length(btrim(decision_source)) > 0),
  decided_on       date        NOT NULL,
  decided_by       uuid        REFERENCES public.members(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.credly_badge_decisions IS
  'Decisao editorial por badge do Credly (#2296 item 3). Responde "ja decidimos sobre este badge?", '
  'que e a pergunta que _credly_unmapped_rows() nao sabia fazer e por isso repetia 39 nomes todo mes. '
  'NAO substitui os guards de classify-badge: aqueles afirmam o CODIGO, esta tabela afirma a DECISAO. '
  'decided_by e NULL nas linhas historicas de proposito — a decisao veio de uma issue, nao de uma '
  'sessao, e decision_source carrega a procedencia.';

COMMENT ON COLUMN public.credly_badge_decisions.decided_category IS
  'A categoria que a decisao determina. O dominio valido e CATEGORY_POINTS em '
  'supabase/functions/_shared/classify-badge.ts — deliberadamente SEM CHECK com lista fixa aqui, '
  'para nao criar uma segunda copia do catalogo que envelhece sozinha (#1149). O guard da #2296 '
  'deriva o dominio do proprio classificador e reprova categoria inexistente.';

ALTER TABLE public.credly_badge_decisions ENABLE ROW LEVEL SECURITY;

-- Leitura para membro autenticado: e configuracao editorial, nao PII.
DROP POLICY IF EXISTS credly_badge_decisions_read_auth ON public.credly_badge_decisions;
CREATE POLICY credly_badge_decisions_read_auth
  ON public.credly_badge_decisions FOR SELECT TO authenticated USING (true);

-- Escrita so para quem administra a plataforma (mesmo desenho de gamification_rules).
DROP POLICY IF EXISTS credly_badge_decisions_write_manage_platform ON public.credly_badge_decisions;
CREATE POLICY credly_badge_decisions_write_manage_platform
  ON public.credly_badge_decisions FOR ALL TO authenticated
  USING (public.rls_can('manage_platform')) WITH CHECK (public.rls_can('manage_platform'));

REVOKE ALL ON public.credly_badge_decisions FROM anon;
GRANT SELECT ON public.credly_badge_decisions TO authenticated;
GRANT ALL    ON public.credly_badge_decisions TO service_role;

-- ---------------------------------------------------------------------------
-- Seed: SO o que ja estava afirmado em guard. Nomes copiados verbatim do banco (com simbolos),
-- porque e por eles que _credly_unmapped_rows() casa.
-- ---------------------------------------------------------------------------
INSERT INTO public.credly_badge_decisions
  (badge_name, decided_category, rationale, decision_source, decided_on)
VALUES
  -- Grupo 1 — #1209 (GP, 2026-07-08). Guard: tests/edge-functions/classify-badge.test.mjs.
  ('Lifelong Learning', 'badge',
   'Participacao/fidelidade. Mantido em badge/10 por decisao, e o guard do #1209 usa este nome como '
   'controle de que as palavras-chave novas nao sobre-capturam.',
   'issue #1209 (GP, 2026-07-08) + tests/edge-functions/classify-badge.test.mjs', '2026-07-08'),
  ('Essentials for Projects', 'badge',
   'Nao e "PMI Essentials": o guard do #1209 usa este nome exatamente para provar que a palavra-chave '
   'nao alarga para fora do programa do PMI.',
   'issue #1209 (GP, 2026-07-08) + tests/edge-functions/classify-badge.test.mjs', '2026-07-08'),
  ('Oracle Certified Professional, Java SE 5 Programmer', 'badge',
   'Certificacao real, porem FORA do dominio do nucleo (IA + GP). O limite do #1209 e explicito: '
   'out-of-domain cert fica em 10.',
   'issue #1209 (GP, 2026-07-08) + tests/edge-functions/classify-badge.test.mjs', '2026-07-08'),
  ('DevOps Essentials Professional Certificate - DEPC® !', 'badge',
   'Certificacao real, porem fora do dominio IA + GP (mesmo limite do #1209).',
   'issue #1209 (GP, 2026-07-08) + tests/edge-functions/classify-badge.test.mjs', '2026-07-08'),
  ('OneTrust Certified Privacy Professional', 'badge',
   'Certificacao real, porem fora do dominio IA + GP (mesmo limite do #1209).',
   'issue #1209 (GP, 2026-07-08) + tests/edge-functions/classify-badge.test.mjs', '2026-07-08'),
  ('Product and Project Collaboration', 'badge',
   'Participacao/reconhecimento. Mantido em badge/10 pelo limite do #1209.',
   'issue #1209 (GP, 2026-07-08) + tests/edge-functions/classify-badge.test.mjs', '2026-07-08'),
  -- Grupo 2 — camada B da #2296 (2026-09-15). Guard: tests/contracts/2296-taxonomia-...test.mjs.
  ('Lifelong Learning 2026', 'badge',
   'Variacao anual de fidelidade. Participacao e associacao permanecem em 10, e isso e a regra.',
   'issue #2296 camada B + tests/contracts/2296-taxonomia-dos-badges-do-credly.test.mjs', '2026-09-15'),
  ('Chapter Leader 2023', 'badge',
   'Reconhecimento de atuacao em capitulo. Participacao/reconhecimento vale 10 por regra.',
   'issue #2296 camada B + tests/contracts/2296-taxonomia-dos-badges-do-credly.test.mjs', '2026-09-15'),
  ('ACMP Member Badge', 'badge',
   'Associacao a entidade. Associacao vale 10 por regra.',
   'issue #2296 camada B + tests/contracts/2296-taxonomia-dos-badges-do-credly.test.mjs', '2026-09-15'),
  ('APM Student', 'badge',
   'Associacao estudantil. Associacao vale 10 por regra.',
   'issue #2296 camada B + tests/contracts/2296-taxonomia-dos-badges-do-credly.test.mjs', '2026-09-15'),
  ('CertiProf Online Summit Attendee (Version 2)', 'badge',
   'Presenca em evento. Participacao vale 10 por regra.',
   'issue #2296 camada B + tests/contracts/2296-taxonomia-dos-badges-do-credly.test.mjs', '2026-09-15'),
  ('Construction Management Association of America Member', 'badge',
   'Associacao a entidade. Associacao vale 10 por regra.',
   'issue #2296 camada B + tests/contracts/2296-taxonomia-dos-badges-do-credly.test.mjs', '2026-09-15'),
  ('Worldwide Communities - Community Champion 2019', 'badge',
   'Reconhecimento de comunidade. Reconhecimento vale 10 por regra.',
   'issue #2296 camada B + tests/contracts/2296-taxonomia-dos-badges-do-credly.test.mjs', '2026-09-15'),
  ('Survey Contributor of The Agile Adoption Report 2021', 'badge',
   'Contribuicao com pesquisa de terceiro. Participacao vale 10 por regra.',
   'issue #2296 camada B + tests/contracts/2296-taxonomia-dos-badges-do-credly.test.mjs', '2026-09-15'),
  ('FY26 LevelUp Super Luminary', 'badge',
   'Reconhecimento interno de empregador. Reconhecimento vale 10 por regra.',
   'issue #2296 camada B + tests/contracts/2296-taxonomia-dos-badges-do-credly.test.mjs', '2026-09-15'),
  ('Instructor Recognition - First Class Delivered', 'badge',
   'Reconhecimento de marco de instrutor. Reconhecimento vale 10 por regra.',
   'issue #2296 camada B + tests/contracts/2296-taxonomia-dos-badges-do-credly.test.mjs', '2026-09-15'),
  ('Mentor Silver', 'badge',
   'Reconhecimento de mentoria por faixa. Reconhecimento vale 10 por regra.',
   'issue #2296 camada B + tests/contracts/2296-taxonomia-dos-badges-do-credly.test.mjs', '2026-09-15')
ON CONFLICT (badge_name) DO NOTHING;

-- ---------------------------------------------------------------------------
-- O detector passa a perguntar "ja decidimos sobre este?" antes de listar.
-- Assinatura e atributos preservados: LANGUAGE sql, STABLE, SET search_path.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._credly_unmapped_rows()
RETURNS TABLE(badge_name text, occurrences integer, members integer)
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $function$
  -- #2296: o filtro NOT EXISTS e a unica mudanca de comportamento. Sem ele o detector repetia
  -- mensalmente 39 nomes em que nada era novo, e um detector que nao separa "novo" de
  -- "ja decidido" ensina o leitor a ignorar a lista inteira.
  SELECT regexp_replace(gp.reason, '^Credly:\s*', '') AS badge_name,
         count(*)::int AS occurrences,
         count(DISTINCT gp.member_id)::int AS members
  FROM public.gamification_points gp
  WHERE gp.category = 'badge' AND gp.reason ILIKE 'Credly:%'
    AND NOT EXISTS (
      SELECT 1 FROM public.credly_badge_decisions d
      WHERE d.badge_name = regexp_replace(gp.reason, '^Credly:\s*', '')
    )
  GROUP BY 1
  ORDER BY count(*) DESC, 1;
$function$;
