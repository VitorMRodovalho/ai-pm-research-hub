-- #3063: a triagem por IA escolhe a rubrica pelo PERFIL da vaga.
--
-- A rubrica de triagem foi escrita para pesquisa ("faz pesquisa, publica artigo, lidera tribo?"). Numa vaga de
-- apoio ela mede a coisa errada. Decisão do GP em 14/11/2026, que vale como o memorando da ADR-0076 para o ciclo 4:
-- as vagas de apoio ganham rubrica própria, que lê o título, as horas e as perguntas da vaga; a rubrica de pesquisa
-- não muda, e as notas de pesquisa continuam comparáveis.
--
-- Vagas de apoio, escolhidas pelo GP: Onboarding e Engajamento (76629), Comunicação (76628), Coordenação de
-- Publicações (76630), Curadoria (76624), Time de Apoio CPMAI (76664) e Gerente de Projeto CPMAI (76661).
-- Propriedade Intelectual (72562) e as vagas de pesquisa e liderança ficam em 'research'.

ALTER TABLE public.vep_opportunities
  ADD COLUMN IF NOT EXISTS triage_profile text NOT NULL DEFAULT 'research';

ALTER TABLE public.vep_opportunities
  ADD CONSTRAINT vep_opportunities_triage_profile_check CHECK (triage_profile IN ('research', 'apoio'));

COMMENT ON COLUMN public.vep_opportunities.triage_profile IS
  '#3063: qual rubrica a triagem por IA usa para as candidaturas desta vaga. research = a rubrica de pesquisa (v1-cycle3); apoio = a rubrica de aderência à vaga, que lê título, horas e essay_mapping. Decisão do GP, 14/11/2026.';

UPDATE public.vep_opportunities
   SET triage_profile = 'apoio'
 WHERE opportunity_id IN ('76629', '76628', '76630', '76624', '76664', '76661');
