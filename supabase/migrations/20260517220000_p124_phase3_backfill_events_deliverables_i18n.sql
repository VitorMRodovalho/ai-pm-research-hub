-- p124 phase 3 — backfill EN/ES for high-frequency event title patterns and
-- the 6 cycle-3 Tribo 1 (Radar Tecnológico) deliverables (the data sample
-- shown in the user's HAR while navigating /tribe/1?lang=en-US).
--
-- Coverage:
--   - 7 weekly tribe meetings × ~10 weeks = ~70 events get EN/ES via pattern
--   - 7 tribe kick-offs (one-off per tribe)
--   - The 6 'Reunião Geral — Semana N' recurring events
--   - The 'Reunião de Liderança' series (~3 events)
--   - All 6 Tribo 1 deliverables (full title + description)
--
-- Out of scope (PT fallback acceptable for now):
--   - One-off interviews ('Entrevista — Ciclo 2026-1 (X)')
--   - Legacy 2024-2025 events
--   - Other tribes' deliverables (~65 rows) — incremental later
--
-- Tribe name lookup uses initiatives.metadata.name_i18n (already trilingual).
-- For the 'Reunião Semanal' patterns, we substitute the localized name.

-- ── 1. Weekly tribe meetings (Reunião Semanal) ──
WITH tribe_names AS (
  SELECT
    legacy_tribe_id,
    title AS canonical_pt,
    metadata->'name_i18n'->>'en' AS name_en,
    metadata->'name_i18n'->>'es' AS name_es
  FROM public.initiatives
  WHERE kind = 'research_tribe'
)
UPDATE public.events e
SET title_i18n = jsonb_build_object(
  'pt', e.title,
  'en', tn.name_en || ' — Weekly Meeting',
  'es', tn.name_es || ' — Reunión Semanal'
)
FROM tribe_names tn
WHERE e.title = tn.canonical_pt || ' — Reunião Semanal';

-- ── 2. Tribe kick-offs ──
WITH tribe_names AS (
  SELECT
    title AS canonical_pt,
    metadata->'name_i18n'->>'en' AS name_en,
    metadata->'name_i18n'->>'es' AS name_es
  FROM public.initiatives
  WHERE kind = 'research_tribe'
)
UPDATE public.events e
SET title_i18n = jsonb_build_object(
  'pt', e.title,
  'en', tn.name_en || ' — Kick-off',
  'es', tn.name_es || ' — Kick-off'
)
FROM tribe_names tn
WHERE e.title = tn.canonical_pt || ' — Kick-off';

-- ── 3. Reunião Geral patterns ──
UPDATE public.events
SET title_i18n = jsonb_build_object(
  'pt', title,
  'en', regexp_replace(title, 'Reunião Geral — Semana (\d+)', 'General Meeting — Week \1', 'g'),
  'es', regexp_replace(title, 'Reunião Geral — Semana (\d+)', 'Reunión General — Semana \1', 'g')
)
WHERE title ~ '^Reunião Geral — Semana \d+$';

UPDATE public.events
SET title_i18n = jsonb_build_object(
  'pt', title,
  'en', '[Núcleo IA] Opening Event (Kick-off) + General Meeting – Cycle 3 (2026/1)',
  'es', '[Núcleo IA] Evento de Apertura (Kick-off) + Reunión General – Ciclo 3 (2026/1)'
)
WHERE title = '[Núcleo IA] Evento de Abertura (Kick-off) + Reunião Geral – Ciclo 3 (2026/1)';

UPDATE public.events
SET title_i18n = jsonb_build_object(
  'pt', title,
  'en', '[Núcleo IA] Recurring General Meeting – Cycle 3 (2026/1) AI & PM Research Hub',
  'es', '[Núcleo IA] Reunión General Recurrente – Ciclo 3 (2026/1) AI & PM Research Hub'
)
WHERE title = '[Núcleo IA] Reunião Geral Recorrente – Ciclo 3 (2026/1) Núcleo de Estudos e Pesquisa em IA & GP';

UPDATE public.events
SET title_i18n = jsonb_build_object(
  'pt', title,
  'en', '[Núcleo IA] Leadership Meeting — GP + Leaders Chat (pre-General)',
  'es', '[Núcleo IA] Reunión de Liderazgo — Charla GP + Líderes (pre-General)'
)
WHERE title = '[Núcleo IA] Reunião de Liderança — Bate-papo GP + Líderes (pré-Geral)';

-- Future-dated General meetings ('Reunião Geral — YYYY-MM-DD')
UPDATE public.events
SET title_i18n = jsonb_build_object(
  'pt', title,
  'en', regexp_replace(title, 'Reunião Geral', 'General Meeting'),
  'es', regexp_replace(title, 'Reunião Geral', 'Reunión General')
)
WHERE title ~ '^Reunião Geral — \d{4}-\d{2}-\d{2}$';

-- ── 4. Tribo 1 (Radar Tecnológico) deliverables ──
UPDATE public.tribe_deliverables
SET
  title_i18n = jsonb_build_object(
    'pt', 'Finalizar Curso 01 da Trilha IA',
    'en', 'Complete Course 01 of AI Trail',
    'es', 'Completar Curso 01 de la Ruta de IA'
  ),
  description_i18n = jsonb_build_object(
    'pt', 'Generative AI Overview for Project Managers',
    'en', 'Generative AI Overview for Project Managers',
    'es', 'Visión General de IA Generativa para Gerentes de Proyectos'
  )
WHERE id = 'b68a0ba2-4c53-49ef-b592-8def2044b067';

UPDATE public.tribe_deliverables
SET
  title_i18n = jsonb_build_object(
    'pt', 'Pesquisa: Artefatos de GP Potencializáveis com IA',
    'en', 'Research: PM Artifacts Augmentable with AI',
    'es', 'Investigación: Artefactos de GP Potenciables con IA'
  ),
  description_i18n = jsonb_build_object(
    'pt', 'Levantamento de quais entregas da Gestão de Projetos podem ser potencializadas pelo uso de IA e como isso tem sido feito atualmente. Matriz de avaliação com foco em arquitetura agêntica. Entrevistas com profissionais e revisão de literatura sobre automação de artefatos de GP.',
    'en', 'Survey of which Project Management deliverables can be augmented by AI use and how this is being done today. Evaluation matrix focused on agentic architecture. Interviews with practitioners and literature review on PM artifact automation.',
    'es', 'Relevamiento de qué entregas de la Gestión de Proyectos pueden ser potenciadas por el uso de IA y cómo se ha hecho esto actualmente. Matriz de evaluación con foco en arquitectura agéntica. Entrevistas con profesionales y revisión de literatura sobre automatización de artefactos de GP.'
  )
WHERE id = '57b85b8f-fa8d-4321-99e7-d3b106626c82';

UPDATE public.tribe_deliverables
SET
  title_i18n = jsonb_build_object(
    'pt', 'Artigo LinkedIn — Quick Win Radar Tecnológico',
    'en', 'LinkedIn Article — Technology Radar Quick Win',
    'es', 'Artículo LinkedIn — Quick Win Radar Tecnológico'
  ),
  description_i18n = jsonb_build_object(
    'pt', 'Artigo rápido para LinkedIn com insights iniciais da pesquisa sobre como IA transforma artefatos clássicos de GP. Foco em visibilidade externa e engajamento da comunidade PMI. Formato acessível com exemplos práticos de ferramentas.',
    'en', 'Quick LinkedIn article with initial research insights on how AI transforms classic PM artifacts. Focus on external visibility and PMI community engagement. Accessible format with practical tool examples.',
    'es', 'Artículo rápido para LinkedIn con insights iniciales de la investigación sobre cómo la IA transforma artefactos clásicos de GP. Foco en visibilidad externa y participación de la comunidad PMI. Formato accesible con ejemplos prácticos de herramientas.'
  )
WHERE id = '9a5428b7-0bb0-4cc1-b3e1-1f48eebd3437';

UPDATE public.tribe_deliverables
SET
  title_i18n = jsonb_build_object(
    'pt', 'Matriz de Artefatos Potencializáveis por IA',
    'en', 'Matrix of AI-Augmentable Artifacts',
    'es', 'Matriz de Artefactos Potenciables por IA'
  ),
  description_i18n = jsonb_build_object(
    'pt', 'Framework de classificação de artefatos de GP segundo potencial de potencialização por IA. Eixos: complexidade do artefato × maturidade da IA disponível × impacto no projeto. Resultado: ranking priorizado para implementação de padrões agênticos.',
    'en', 'Classification framework for PM artifacts by AI augmentation potential. Axes: artifact complexity × available AI maturity × project impact. Output: prioritized ranking for agentic pattern implementation.',
    'es', 'Framework de clasificación de artefactos de GP según potencial de potenciación por IA. Ejes: complejidad del artefacto × madurez de IA disponible × impacto en el proyecto. Resultado: ranking priorizado para implementación de patrones agénticos.'
  )
WHERE id = '15cac7aa-9fb7-41ed-b1ea-afabc00a887b';

UPDATE public.tribe_deliverables
SET
  title_i18n = jsonb_build_object(
    'pt', 'Implementação de 2 Padrões Agênticos em GP',
    'en', 'Implementation of 2 Agentic Patterns in PM',
    'es', 'Implementación de 2 Patrones Agénticos en GP'
  ),
  description_i18n = jsonb_build_object(
    'pt', 'Prova de conceito implementando 2 padrões agênticos selecionados da matriz. Cada padrão aplicado a um artefato real de GP com medição de eficiência (tempo, qualidade, custo). Documentação de prompts, fluxos e resultados comparativos antes/depois.',
    'en', 'Proof of concept implementing 2 agentic patterns selected from the matrix. Each pattern applied to a real PM artifact with efficiency measurement (time, quality, cost). Documentation of prompts, flows, and before/after comparative results.',
    'es', 'Prueba de concepto implementando 2 patrones agénticos seleccionados de la matriz. Cada patrón aplicado a un artefacto real de GP con medición de eficiencia (tiempo, calidad, costo). Documentación de prompts, flujos y resultados comparativos antes/después.'
  )
WHERE id = '9c49126e-2cd1-4b8b-8df2-1fb4645cf829';

UPDATE public.tribe_deliverables
SET
  title_i18n = jsonb_build_object(
    'pt', 'Artigo Acadêmico — Radar Tecnológico e Padrões Agênticos',
    'en', 'Academic Paper — Technology Radar and Agentic Patterns',
    'es', 'Artículo Académico — Radar Tecnológico y Patrones Agénticos'
  ),
  description_i18n = jsonb_build_object(
    'pt', 'Artigo acadêmico consolidando os resultados da pesquisa sobre artefatos de GP potencializáveis por IA. Inclui a matriz de classificação, os 2 pilotos agênticos e análise comparativa. Alvo: submissão para publicação PMI ou periódico indexado.',
    'en', 'Academic paper consolidating the research results on AI-augmentable PM artifacts. Includes the classification matrix, the 2 agentic pilots, and comparative analysis. Target: submission for PMI publication or indexed journal.',
    'es', 'Artículo académico consolidando los resultados de la investigación sobre artefactos de GP potenciables por IA. Incluye la matriz de clasificación, los 2 pilotos agénticos y análisis comparativo. Objetivo: envío para publicación PMI o revista indexada.'
  )
WHERE id = '13e404b1-9c36-413c-991e-c0f8ec6dac44';

NOTIFY pgrst, 'reload schema';
