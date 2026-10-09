-- #2609 — Descrição e horário da tribo editáveis pela plataforma, com uma fonte só.
--
-- Medido em 09/10/2026, nas 13 tribos ativas:
--   * a descrição pública vinha das chaves data.tribeN.desc dos dicionários (mudar exigia PR);
--     initiatives.description e tribes.notes guardam NOTA INTERNA (nome de líder, link de Meet,
--     "a confirmar"), e nenhuma das 13 era igual ao texto no ar. A página da tribo exibia tribes.notes
--     como descrição para membro logado.
--   * o horário estava em três lugares: a regra recorrente (que alimenta tribe_meeting_slots),
--     tribes.meeting_schedule (texto livre do lápis da página da tribo) e o fallback i18n
--     data.tribeN.meetings. 11 tribos têm regra; T10 e T11 só têm o texto livre.
--
-- Decisões do GP (09/10/2026, registradas na #2609):
--   * o texto canônico é o que está no ar (os três dicionários), migrado para o banco aqui;
--   * o horário vem só da regra recorrente; T10 e T11 mostram "a definir" até o líder cadastrar a regra.
--
-- (1) initiatives.description_i18n e deliverables_i18n ({pt,en,es}, o padrão de tribes.name_i18n).
--     initiatives.description segue como nota interna e não é exibida.
-- (2) update_initiative_public_profile: grava os dois campos. Mesma autoridade do painel de reuniões
--     recorrentes (_can_manage_recurring_rule: manage_platform ou liderança da iniciativa no roster),
--     com trilha em admin_audit_log.
-- (3) get_tribe_public_profiles: leitora pública (anon) da descrição, dos entregáveis e dos horários
--     derivados da regra (tribe_meeting_slots), com o portão da ADR-0105.
-- (4) tribes.meeting_schedule fica aposentada: nenhuma tela lê nem grava (o front sai na mesma PR).
--     A coluna e os dados ficam, para consulta, até uma remoção decidida à parte.
-- (5) Seed das 13 tribos ativas com o texto dos dicionários (só onde description_i18n é NULL).
-- (6) can_edit_initiative_public_profile: a tela pergunta ao servidor se mostra o editor, pelo mesmo
--     portão da escrita (antes ela adivinhava por tribes.leader_member_id, que não é o roster).
--
-- Revisão do conselho (09/10/2026): chamada sem nenhum dos dois campos é recusada (não grava auditoria
-- vazia); a leitora usa DISTINCT ON por tribo, e a pós-condição conta tribos distintas, para que uma
-- iniciativa duplicada não compense uma ausente. Hoje são 15 research_tribe, nenhuma duplicada.
--
-- Rollback: DROP FUNCTION update_initiative_public_profile(uuid, jsonb, jsonb),
--   can_edit_initiative_public_profile(uuid) e get_tribe_public_profiles(); ALTER TABLE initiatives DROP COLUMN description_i18n, deliverables_i18n.

-- ── (1) colunas ───────────────────────────────────────────────────────────────
ALTER TABLE public.initiatives
  ADD COLUMN IF NOT EXISTS description_i18n  jsonb,
  ADD COLUMN IF NOT EXISTS deliverables_i18n jsonb;

ALTER TABLE public.initiatives DROP CONSTRAINT IF EXISTS initiatives_description_i18n_shape;
ALTER TABLE public.initiatives ADD CONSTRAINT initiatives_description_i18n_shape
  CHECK (description_i18n IS NULL OR (jsonb_typeof(description_i18n) = 'object'
         AND description_i18n - ARRAY['pt','en','es'] = '{}'::jsonb));
ALTER TABLE public.initiatives DROP CONSTRAINT IF EXISTS initiatives_deliverables_i18n_shape;
ALTER TABLE public.initiatives ADD CONSTRAINT initiatives_deliverables_i18n_shape
  CHECK (deliverables_i18n IS NULL OR (jsonb_typeof(deliverables_i18n) = 'object'
         AND deliverables_i18n - ARRAY['pt','en','es'] = '{}'::jsonb));

COMMENT ON COLUMN public.initiatives.description_i18n IS
  '#2609: descrição PÚBLICA da iniciativa, {pt,en,es}. Editada por update_initiative_public_profile.';
COMMENT ON COLUMN public.initiatives.deliverables_i18n IS
  '#2609: entregáveis exibidos na apresentação pública, {pt:[...],en:[...],es:[...]}.';
COMMENT ON COLUMN public.initiatives.description IS
  'Nota interna da iniciativa. A descrição pública é description_i18n (#2609).';
COMMENT ON COLUMN public.tribes.meeting_schedule IS
  'APOSENTADA (#2609): nenhuma tela lê nem grava. O horário vem da regra recorrente (tribe_meeting_slots).';

-- ── (2) edição ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.update_initiative_public_profile(
  p_initiative_id uuid,
  p_description_i18n jsonb DEFAULT NULL,
  p_deliverables_i18n jsonb DEFAULT NULL
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_member uuid;
  v_before jsonb;
  v_desc   jsonb;
  v_deliv  jsonb;
  v_key    text;
  v_val    jsonb;
  v_items  jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT m.id INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  -- mesma autoridade do painel de reuniões recorrentes: quem edita o horário edita a apresentação
  IF v_member IS NULL OR NOT public._can_manage_recurring_rule(v_member, p_initiative_id) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform or initiative leadership'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_description_i18n IS NULL AND p_deliverables_i18n IS NULL THEN
    RAISE EXCEPTION 'Nothing to update: pass description_i18n and/or deliverables_i18n' USING ERRCODE = 'check_violation';
  END IF;

  SELECT jsonb_build_object('description_i18n', i.description_i18n, 'deliverables_i18n', i.deliverables_i18n)
    INTO v_before
  FROM public.initiatives i WHERE i.id = p_initiative_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Initiative not found: %', p_initiative_id USING ERRCODE = 'no_data_found';
  END IF;

  IF p_description_i18n IS NOT NULL THEN
    IF jsonb_typeof(p_description_i18n) <> 'object' OR p_description_i18n - ARRAY['pt','en','es'] <> '{}'::jsonb THEN
      RAISE EXCEPTION 'description_i18n must be an object with keys pt, en, es' USING ERRCODE = 'check_violation';
    END IF;
    v_desc := '{}'::jsonb;
    FOR v_key, v_val IN SELECT key, value FROM jsonb_each(p_description_i18n) LOOP
      IF jsonb_typeof(v_val) <> 'string' THEN
        RAISE EXCEPTION 'description_i18n.% must be text', v_key USING ERRCODE = 'check_violation';
      END IF;
      IF length(btrim(v_val #>> '{}')) > 1500 THEN
        RAISE EXCEPTION 'description_i18n.% exceeds 1500 characters', v_key USING ERRCODE = 'check_violation';
      END IF;
      IF btrim(v_val #>> '{}') <> '' THEN
        v_desc := v_desc || jsonb_build_object(v_key, btrim(v_val #>> '{}'));
      END IF;
    END LOOP;
    IF NOT (v_desc ? 'pt') THEN
      RAISE EXCEPTION 'description_i18n.pt is required' USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  IF p_deliverables_i18n IS NOT NULL THEN
    IF jsonb_typeof(p_deliverables_i18n) <> 'object' OR p_deliverables_i18n - ARRAY['pt','en','es'] <> '{}'::jsonb THEN
      RAISE EXCEPTION 'deliverables_i18n must be an object with keys pt, en, es' USING ERRCODE = 'check_violation';
    END IF;
    v_deliv := '{}'::jsonb;
    FOR v_key, v_val IN SELECT key, value FROM jsonb_each(p_deliverables_i18n) LOOP
      IF jsonb_typeof(v_val) <> 'array' THEN
        RAISE EXCEPTION 'deliverables_i18n.% must be a list', v_key USING ERRCODE = 'check_violation';
      END IF;
      SELECT COALESCE(jsonb_agg(btrim(e #>> '{}') ORDER BY o), '[]'::jsonb) INTO v_items
      FROM jsonb_array_elements(v_val) WITH ORDINALITY AS x(e, o)
      WHERE jsonb_typeof(e) = 'string' AND btrim(e #>> '{}') <> '';
      IF jsonb_array_length(v_items) > 8
         OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(v_items) AS t(item) WHERE length(t.item) > 300) THEN
        RAISE EXCEPTION 'deliverables_i18n.% allows up to 8 items of 300 characters', v_key USING ERRCODE = 'check_violation';
      END IF;
      IF jsonb_array_length(v_items) > 0 THEN
        v_deliv := v_deliv || jsonb_build_object(v_key, v_items);
      END IF;
    END LOOP;
  END IF;

  UPDATE public.initiatives i
  SET description_i18n  = CASE WHEN p_description_i18n IS NULL THEN i.description_i18n ELSE v_desc END,
      deliverables_i18n = CASE WHEN p_deliverables_i18n IS NULL THEN i.deliverables_i18n
                               ELSE NULLIF(v_deliv, '{}'::jsonb) END,
      updated_at = now()
  WHERE i.id = p_initiative_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (v_member, 'initiative.public_profile_updated', 'initiative', p_initiative_id,
          jsonb_build_object('before', v_before,
                             'after', (SELECT jsonb_build_object('description_i18n', i.description_i18n,
                                                                 'deliverables_i18n', i.deliverables_i18n)
                                       FROM public.initiatives i WHERE i.id = p_initiative_id)),
          jsonb_build_object('source', 'update_initiative_public_profile'));

  RETURN jsonb_build_object('success', true);
END;
$function$;

REVOKE ALL ON FUNCTION public.update_initiative_public_profile(uuid, jsonb, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_initiative_public_profile(uuid, jsonb, jsonb) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.can_edit_initiative_public_profile(p_initiative_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT COALESCE(public._can_manage_recurring_rule(
           (SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid()), p_initiative_id), false)
$function$;

REVOKE ALL ON FUNCTION public.can_edit_initiative_public_profile(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_edit_initiative_public_profile(uuid) TO authenticated, service_role;

-- ── (3) leitura pública ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_tribe_public_profiles()
 RETURNS TABLE(tribe_id integer, description_i18n jsonb, deliverables_i18n jsonb, slots jsonb)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT DISTINCT ON (t.id)
         t.id,
         i.description_i18n,
         i.deliverables_i18n,
         COALESCE((
           SELECT jsonb_agg(jsonb_build_object('day_of_week', s.day_of_week,
                                               'time_start', s.time_start, 'time_end', s.time_end)
                            ORDER BY s.day_of_week, s.time_start)
           FROM public.tribe_meeting_slots s
           WHERE s.tribe_id = t.id AND s.is_active = true
         ), '[]'::jsonb)
  FROM public.tribes t
  JOIN public.initiatives i ON i.legacy_tribe_id = t.id AND i.kind = 'research_tribe'
  WHERE t.is_active = true
    AND public.rls_can_see_initiative(i.id)
  ORDER BY t.id, (i.status = 'active') DESC, i.updated_at DESC
$function$;

REVOKE ALL ON FUNCTION public.get_tribe_public_profiles() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_tribe_public_profiles() TO anon, authenticated, service_role;

-- ── (5) seed: texto no ar em 09/10/2026 (dicionários pt-BR, en-US, es-LATAM) ───
UPDATE public.initiatives SET description_i18n = $j${"pt":"Fazer um simples pedido para uma IA já não é suficiente para entregas de excelência. É hora de elevar o nível com a engenharia de agentes! O desafio não é buscar um \"prompt mágico\", mas organizar múltiplos prompts e modelos em uma arquitetura de agentes capaz de planejar, executar e se autocorrigir.","en":"Making a simple request to an AI is no longer enough for excellence. It's time to level up with agent engineering! The challenge is not finding a \"magic prompt\", but organizing multiple prompts and models into an agent architecture capable of planning, executing, and self-correcting.","es":"Hacer una simple solicitud a una IA ya no es suficiente para entregas de excelencia. ¡Es hora de elevar el nivel con la ingeniería de agentes! El desafío no es buscar un \"prompt mágico\", sino organizar múltiples prompts y modelos en una arquitectura de agentes capaz de planificar, ejecutar y autocorregirse."}$j$::jsonb,
  deliverables_i18n = $j${"pt":["Radar Tecnológico do GP (comparativo GPT vs Claude vs Gemini por artefato)","Padrões de Arquitetura de Agentes (com código Python)","1-2 Artigos científicos"],"en":["PM Tech Radar (GPT vs Claude vs Gemini comparison by artifact)","Agent Architecture Patterns (with Python code)","1-2 Scientific articles"],"es":["Radar Tecnológico del GP (comparativo GPT vs Claude vs Gemini por artefacto)","Patrones de Arquitectura de Agentes (con código Python)","1-2 Artículos científicos"]}$j$::jsonb
WHERE id = '89e13063-0be5-4f59-a162-0392f4408178' AND legacy_tribe_id = 1 AND description_i18n IS NULL;

UPDATE public.initiatives SET description_i18n = $j${"pt":"Sem cultura, a IA escala o caos. Com 80%+ dos projetos em ambientes multiculturais, precisamos de Inteligência Cultural. O \"internal stickiness\" bloqueia fluxo de informação — é o inimigo invisível dos projetos.","en":"Without culture, AI scales chaos. With 80%+ of projects in multicultural environments, we need Cultural Intelligence. \"Internal stickiness\" blocks information flow — it's the invisible enemy of projects.","es":"Sin cultura, la IA escala el caos. Con 80%+ de los proyectos en ambientes multiculturales, necesitamos Inteligencia Cultural. El \"internal stickiness\" bloquea el flujo de información — es el enemigo invisible de los proyectos."}$j$::jsonb,
  deliverables_i18n = $j${"pt":["Entregas mensais práticas (ferramentas de uso imediato)","Framework Inteligência Cultural + IA","Pesquisa com metodologias mistas","Artigos acadêmicos"],"en":["Monthly practical deliverables (ready-to-use tools)","Cultural Intelligence + AI Framework","Mixed-methods research","Academic articles"],"es":["Entregas mensuales prácticas (herramientas de uso inmediato)","Framework Inteligencia Cultural + IA","Investigación con metodologías mixtas","Artículos académicos"]}$j$::jsonb
WHERE id = '05635518-d831-4548-b7c0-89fe5e5e7651' AND legacy_tribe_id = 4 AND description_i18n IS NULL;

UPDATE public.initiatives SET description_i18n = $j${"pt":"A IA está transformando o trabalho do gestor de projetos: menos execução operacional e mais validação, curadoria, julgamento, responsabilidade e liderança de ecossistemas híbridos. A Tribo Talentos & Upskilling investiga quais capacidades passam a ser críticas nesse novo contexto e como desenvolvê-las de forma prática e aplicável ao trabalho, integrando liderança, pessoas, governança, dados, avaliação crítica e aprendizagem.","en":"AI is transforming the project manager's work: less operational execution and more validation, curation, judgment, accountability and leadership of hybrid ecosystems. The Talent & Upskilling tribe investigates which capabilities become critical in this new context and how to develop them in a practical way that applies to real work, integrating leadership, people, governance, data, critical evaluation and learning.","es":"La IA está transformando el trabajo del gestor de proyectos: menos ejecución operativa y más validación, curaduría, juicio, responsabilidad y liderazgo de ecosistemas híbridos. La Tribu Talentos & Upskilling investiga qué capacidades pasan a ser críticas en este nuevo contexto y cómo desarrollarlas de forma práctica y aplicable al trabajo, integrando liderazgo, personas, gobernanza, datos, evaluación crítica y aprendizaje."}$j$::jsonb,
  deliverables_i18n = $j${"pt":["Artigo de Mercado 1 (LinkedIn, ago/2026): “A Crise dos 93 Cêntimos”","Artigo de Mercado 2 (LinkedIn, set/2026): “O Paradoxo da Autonomia”","Webinário Nacional (nov/2026) com convidado internacional","Artigo Científico Final (dez/2026), padrão editorial do PMJ"],"en":["Market Article 1 (LinkedIn, Aug 2026): “The 93-Cent Crisis”","Market Article 2 (LinkedIn, Sep 2026): “The Autonomy Paradox”","National Webinar (Nov 2026) with an international guest","Final Scientific Article (Dec 2026), to PMJ editorial standards"],"es":["Artículo de Mercado 1 (LinkedIn, ago/2026): “La Crisis de los 93 Céntimos”","Artículo de Mercado 2 (LinkedIn, sep/2026): “La Paradoja de la Autonomía”","Webinario Nacional (nov/2026) con invitado internacional","Artículo Científico Final (dic/2026), estándar editorial del PMJ"]}$j$::jsonb
WHERE id = '18a40313-b6d9-4d60-b1b1-ede526685bcb' AND legacy_tribe_id = 5 AND description_i18n IS NULL;

UPDATE public.initiatives SET description_i18n = $j${"pt":"Chega de decisões milionárias baseadas em intuição! A IA para priorização ainda é uma \"caixa preta\". Vamos transformá-la em \"caixa de vidro\" — transparente, explicável e auditável.","en":"No more million-dollar decisions based on intuition! AI for prioritization is still a \"black box\". We will transform it into a \"glass box\" — transparent, explainable, and auditable.","es":"¡Basta de decisiones millonarias basadas en intuición! La IA para priorización sigue siendo una \"caja negra\". La transformaremos en \"caja de vidrio\" — transparente, explicable y auditable."}$j$::jsonb,
  deliverables_i18n = $j${"pt":["Modelos Híbridos (IA + julgamento humano)","Métricas além do ROI (riscos, reputação, aprendizado)","Artigos mensais no LinkedIn","Protótipo de plataforma IA para simulação e priorização"],"en":["Hybrid Models (AI + human judgment)","Metrics beyond ROI (risks, reputation, learning)","Monthly LinkedIn articles","AI platform prototype for simulation and prioritization"],"es":["Modelos Híbridos (IA + juicio humano)","Métricas más allá del ROI (riesgos, reputación, aprendizaje)","Artículos mensuales en LinkedIn","Prototipo de plataforma IA para simulación y priorización"]}$j$::jsonb
WHERE id = '6c7e5945-1457-4eb3-ae99-28d7b1e72db9' AND legacy_tribe_id = 6 AND description_i18n IS NULL;

UPDATE public.initiatives SET description_i18n = $j${"pt":"83% das organizações planejam implantar IA, mas apenas 29% se sentem prontas. 46% das PoCs são descartadas. Riscos silenciosos: alucinações, dados, vieses. Fim das \"PoCs Eternas\"!","en":"83% of organizations plan to deploy AI, but only 29% feel ready. 46% of PoCs are discarded. Silent risks: hallucinations, data, biases. End of \"Eternal PoCs\"!","es":"83% de las organizaciones planean implementar IA, pero solo 29% se sienten listas. 46% de las PoCs son descartadas. Riesgos silenciosos: alucinaciones, datos, sesgos. ¡Fin de las \"PoCs Eternas\"!"}$j$::jsonb,
  deliverables_i18n = $j${"pt":["Framework de Governança de IA","Matriz de Qualidade de Dados","Guia de Métricas de Valor (ROI real)","Checklist Critérios de Aceite (GenAI/RAG)","Toolkit v1.0 Governança"],"en":["AI Governance Framework","Data Quality Matrix","Value Metrics Guide (real ROI)","Acceptance Criteria Checklist (GenAI/RAG)","Governance Toolkit v1.0"],"es":["Framework de Gobernanza de IA","Matriz de Calidad de Datos","Guía de Métricas de Valor (ROI real)","Checklist Criterios de Aceptación (GenAI/RAG)","Toolkit v1.0 Gobernanza"]}$j$::jsonb
WHERE id = 'd01c1f43-4dab-487f-a3fc-fb1634bf8eaf' AND legacy_tribe_id = 7 AND description_i18n IS NULL;

UPDATE public.initiatives SET description_i18n = $j${"pt":"15-20% da população mundial é neurodivergente. Apenas 25% dos neuroatípicos empregados se sentem incluídos. Vamos desenvolver o Neuroadvantage Framework 1.0: um \"exoesqueleto cognitivo\" suportado por IA.","en":"15-20% of the world population is neurodivergent. Only 25% of employed neuroatypical individuals feel included. We will develop the Neuroadvantage Framework 1.0: a \"cognitive exoskeleton\" supported by AI.","es":"15-20% de la población mundial es neurodivergente. Solo 25% de los neurotípicos empleados se sienten incluidos. Desarrollaremos el Neuroadvantage Framework 1.0: un \"exoesqueleto cognitivo\" soportado por IA."}$j$::jsonb,
  deliverables_i18n = $j${"pt":["Neuroadvantage Framework 1.0 (5 pilares)","Artigo científico (pilar teórico)","Webinar prático (pilar tecnológico)","Testes práticos + versão 1.0 para o mercado"],"en":["Neuroadvantage Framework 1.0 (5 pillars)","Scientific article (theoretical pillar)","Practical webinar (technological pillar)","Practical tests + market v1.0"],"es":["Neuroadvantage Framework 1.0 (5 pilares)","Artículo científico (pilar teórico)","Webinar práctico (pilar tecnológico)","Pruebas prácticas + versión 1.0 para el mercado"]}$j$::jsonb
WHERE id = '9cbaf0b9-de4d-4e40-8375-5767cc97a9a4' AND legacy_tribe_id = 8 AND description_i18n IS NULL;

UPDATE public.initiatives SET description_i18n = $j${"pt":"Metodologia CPMAI aplicada a projetos de IA — do Entendimento do Negócio à Operacionalização — com profundidade vertical na indústria da construção: casos reais, forecasting preditivo, automação documental e agentes nos fluxos de design, engenharia e construção.","en":"The CPMAI methodology applied to AI projects — from Business Understanding to Operationalization — with vertical depth in the construction industry: real cases, predictive forecasting, document automation, and AI agents across design, engineering, and construction workflows.","es":"La metodología CPMAI aplicada a proyectos de IA — del Entendimiento del Negocio a la Operacionalización — con profundidad vertical en la industria de la construcción: casos reales, forecasting predictivo, automatización documental y agentes en los flujos de diseño, ingeniería y construcción."}$j$::jsonb,
  deliverables_i18n = NULL
WHERE id = '90ee7685-27c1-4fb8-9c45-1b33cd797e23' AND legacy_tribe_id = 9 AND description_i18n IS NULL;

UPDATE public.initiatives SET description_i18n = $j${"pt":"Agentes de IA como copilotos de PMO e Engenharia para produzir entregáveis com método — rastreáveis, reprodutíveis e com controle de qualidade. Da geração improvisada à geração metodológica, no espírito do ciclo de vida do CPMAI.","en":"AI agents as copilots for PMO and Engineering to produce deliverables with method — traceable, reproducible, and quality-controlled. From improvised to methodical generation, in the spirit of the CPMAI lifecycle.","es":"Agentes de IA como copilotos de PMO e Ingeniería para producir entregables con método — trazables, reproducibles y con control de calidad. De la generación improvisada a la metodológica, en el espíritu del ciclo de vida del CPMAI."}$j$::jsonb,
  deliverables_i18n = NULL
WHERE id = 'c856abd8-cce9-44a2-bc01-7c67ab6e7f6b' AND legacy_tribe_id = 10 AND description_i18n IS NULL;

UPDATE public.initiatives SET description_i18n = $j${"pt":"O PMO como capacidade organizacional inteligente: agentes e simuladores de decisão, serviços e outcomes de PMO, e governança de valor conectando iniciativas de IA à estratégia. Ancorado no PMO Practice Guide e no PMI M.O.R.E.","en":"The PMO as an intelligent organizational capability: decision agents and simulators, PMO services and outcomes, and value governance connecting AI initiatives to strategy. Anchored in the PMO Practice Guide and PMI M.O.R.E.","es":"El PMO como capacidad organizacional inteligente: agentes y simuladores de decisión, servicios y outcomes de PMO, y gobernanza de valor conectando iniciativas de IA a la estrategia. Anclado en el PMO Practice Guide y el PMI M.O.R.E."}$j$::jsonb,
  deliverables_i18n = NULL
WHERE id = '37566ae4-a9c3-4517-be55-e51696471a87' AND legacy_tribe_id = 11 AND description_i18n IS NULL;

UPDATE public.initiatives SET description_i18n = $j${"pt":"Uso aplicado de IA generativa no fluxo do gerente de projetos: prompts para cronogramas, riscos e planos de comunicação; automação de atas, relatórios de status e análise de documentos. O pilar do \"first mover\" — mais tempo em estratégia, menos em tarefa manual.","en":"Applied use of generative AI in the project manager workflow: prompts for schedules, risks, and communication plans; automation of minutes, status reports, and document analysis. The \"first mover\" pillar — more time on strategy, less on manual work.","es":"Uso aplicado de IA generativa en el flujo del gerente de proyectos: prompts para cronogramas, riesgos y planes de comunicación; automatización de actas, informes de estado y análisis de documentos. El pilar del \"first mover\" — más tiempo en estrategia, menos en tarea manual."}$j$::jsonb,
  deliverables_i18n = NULL
WHERE id = '9b56dedc-5cab-4b1d-92e0-95ccdcc6c87b' AND legacy_tribe_id = 12 AND description_i18n IS NULL;

UPDATE public.initiatives SET description_i18n = $j${"pt":"Governança e qualidade de dados como camada de execução de projetos de IA: traduz a norma ANSI/PMI 26-007 e o domínio CPMAI \"Identify Data Needs\" em mecanismos, templates e ferramentas práticas — stewardship, linhagem e Definition of Ready para dados. Fronteiras: ética na T7, ROI na T6.","en":"Data governance and quality as an execution layer of AI projects: translating the ANSI/PMI 26-007 standard and the CPMAI \"Identify Data Needs\" domain into practical mechanisms, templates, and tools — stewardship, lineage, and a Definition of Ready for data. Boundaries: ethics in T7, ROI in T6.","es":"Gobernanza y calidad de datos como capa de ejecución de proyectos de IA: traduce la norma ANSI/PMI 26-007 y el dominio CPMAI \"Identify Data Needs\" en mecanismos, plantillas y herramientas prácticas — stewardship, linaje y Definition of Ready para datos. Fronteras: ética en T7, ROI en T6."}$j$::jsonb,
  deliverables_i18n = NULL
WHERE id = '7502b6c2-5c8c-472c-bab0-09f757b98ea4' AND legacy_tribe_id = 13 AND description_i18n IS NULL;

UPDATE public.initiatives SET description_i18n = $j${"pt":"Base \"101\" de fluência em IA generativa que prepara os pesquisadores antes das tribos temáticas. Formato aberto de aprendizado, sem entregável externo — o fundamento conceitual que sustenta o Radar e a Produtividade Aumentada.","en":"A \"101\" foundation in generative AI literacy that prepares researchers before the thematic tribes. An open learning format with no external deliverable — the conceptual foundation underpinning Radar and Augmented Productivity.","es":"Base \"101\" de fluidez en IA generativa que prepara a los investigadores antes de las tribus temáticas. Formato abierto de aprendizaje, sin entregable externo — el fundamento conceptual que sustenta el Radar y la Productividad Aumentada."}$j$::jsonb,
  deliverables_i18n = NULL
WHERE id = 'f186a558-8d0d-49ec-a729-abc05528085e' AND legacy_tribe_id = 14 AND description_i18n IS NULL;

UPDATE public.initiatives SET description_i18n = $j${"pt":"80 grupos de WhatsApp. Uma única cabeça. Todo gestor brasileiro conhece essa realidade e quase ninguém mede: o projeto vive nos grupos de mensagens, e a atenção não acompanha. A tribo estuda como a IA separa o que exige ação do ruído, devolvendo a atenção do gestor ao que importa e investigando o que escapa. Se a dor é sua, te espero na tribo.","en":"80 WhatsApp groups. One single head. Every Brazilian manager knows this reality and almost nobody measures it: the project lives in messaging groups, and attention cannot keep up. The tribe studies how AI separates what requires action from the noise, giving the manager's attention back to what matters and investigating what slips through. If this pain is yours, I'll see you in the tribe.","es":"80 grupos de WhatsApp. Una sola cabeza. Todo gestor brasileño conoce esta realidad y casi nadie la mide: el proyecto vive en los grupos de mensajes, y la atención no da abasto. La tribu estudia cómo la IA separa lo que exige acción del ruido, devolviendo la atención del gestor a lo que importa e investigando lo que se escapa. Si el dolor es tuyo, te espero en la tribu."}$j$::jsonb,
  deliverables_i18n = $j${"pt":["Artigo científico 1, \"A Máquina que Aprende a Decidir como Você\" (RQ1): como uma triagem aprende o critério de um gestor pela forma como ele responde, adia ou ignora mensagens?","Artigo científico 2, \"O que Passa Despercebido\" (RQ2): o que circula pelos canais informais de comunicação de projetos, e quanto disso são decisões e riscos?","Artigo científico 3, \"Por que a Triagem Acerta\" (RQ3): quais fatores de contexto mais determinam se a IA entende a realidade de um projeto?"],"en":["Scientific paper 1, \"The Machine that Learns to Decide Like You\" (RQ1): how does a triage system learn a manager's criteria from the way they reply to, postpone or ignore messages?","Scientific paper 2, \"What Goes Unnoticed\" (RQ2): what flows through the informal communication channels of projects, and how much of it is decisions and risks?","Scientific paper 3, \"Why the Triage Gets It Right\" (RQ3): which context factors most determine whether AI understands the reality of a project?"],"es":["Artículo científico 1, \"La Máquina que Aprende a Decidir como Tú\" (RQ1): ¿cómo aprende un sistema de triaje el criterio de un gestor por la forma en que responde, pospone o ignora mensajes?","Artículo científico 2, \"Lo que Pasa Desapercibido\" (RQ2): ¿qué circula por los canales informales de comunicación de proyectos, y cuánto de eso son decisiones y riesgos?","Artículo científico 3, \"Por qué el Triaje Acierta\" (RQ3): ¿qué factores de contexto determinan más si la IA entiende la realidad de un proyecto?"]}$j$::jsonb
WHERE id = '90fc06e0-8d77-4322-89ce-51a6b48b302c' AND legacy_tribe_id = 15 AND description_i18n IS NULL;

-- ── pós-condição: aborta a migration inteira se algo saiu errado ─────────────
DO $postcondition$
DECLARE
  v_n integer;
BEGIN
  SELECT count(*) INTO v_n
  FROM public.tribes t
  JOIN public.initiatives i ON i.legacy_tribe_id = t.id AND i.kind = 'research_tribe'
  WHERE t.is_active
    AND NOT (coalesce(i.description_i18n->>'pt', '') <> '' AND coalesce(i.description_i18n->>'en', '') <> ''
             AND coalesce(i.description_i18n->>'es', '') <> '');
  IF v_n <> 0 THEN RAISE EXCEPTION '#2609: % tribo(s) ativa(s) sem descrição nas 3 línguas', v_n; END IF;

  SELECT count(DISTINCT tribe_id) INTO v_n FROM public.get_tribe_public_profiles();
  IF v_n <> (SELECT count(*) FROM public.tribes WHERE is_active) THEN
    RAISE EXCEPTION '#2609: get_tribe_public_profiles devolveu % linhas', v_n;
  END IF;
END
$postcondition$;

NOTIFY pgrst, 'reload schema';
