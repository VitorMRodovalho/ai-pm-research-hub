-- =====================================================================
-- p198 OPP-196.D MVP — Seed 3 starter cards for Comitê workspace
-- =====================================================================
-- Bootstrap content so curators see a non-empty board on first login.
-- Cards are guidance, not blocking work. Curators can edit/delete/move.
--
-- created_by = Fabricio (committee leader, member 92d26057...)
-- All in 'backlog' status (curators pull what they want into todo).
-- =====================================================================

INSERT INTO public.board_items (board_id, title, description, status, position, tags, created_by, organization_id)
SELECT
  pb.id,
  '📋 Pipeline de Curadoria — fila ao vivo',
  E'O Comitê de Curadoria avalia conteúdo submetido pelas tribos via página dedicada:\n\n👉 **/admin/curatorship**\n\nLá vocês veem:\n• Cards `curation_pending` aguardando avaliação\n• SLA badge (deadline 7 dias)\n• Aplicar rúbrica (5 critérios: clarity, originality, adherence, relevance, ethics)\n• Decisão: aprovar / devolver com feedback / arquivar\n\nO botão "Submeter para Curadoria" foi lançado em p197 — tribe leaders agora têm caminho canônico (não precisam mais atribuir 3 curadores nominalmente).\n\nQuando alguém da tribo submeter, vocês recebem notificação in-app automaticamente.',
  'backlog', 1,
  ARRAY['workspace', 'pipeline', 'pinned'],
  '92d26057-5550-4f15-a3bf-b00eed5f32f9'::uuid,
  pb.organization_id
FROM public.project_boards pb
WHERE pb.id = '41b8b25d-0f76-4f62-b1e3-292ca895ab73'::uuid;

INSERT INTO public.board_items (board_id, title, description, status, position, tags, created_by, organization_id)
SELECT
  pb.id,
  '📅 Agendar 1ª reunião do Comitê (cadência sugerida: quinzenal)',
  E'**Primeiros passos sugeridos:**\n\n1. Definir dia/horário fixo para reuniões (ex: quinzenais, 1h)\n2. Criar event no Núcleo via /admin/events (ou tab Reuniões deste workspace quando disponível)\n3. Definir cadência: revisar pipeline pendente + decisões editoriais\n4. Registrar atas via EventMinutesIsland (link no card do event)\n\nAttendance dos curadores é tracked automaticamente quando o event é vinculado a esta iniciativa.',
  'backlog', 2,
  ARRAY['workspace', 'meeting-setup'],
  '92d26057-5550-4f15-a3bf-b00eed5f32f9'::uuid,
  pb.organization_id
FROM public.project_boards pb
WHERE pb.id = '41b8b25d-0f76-4f62-b1e3-292ca895ab73'::uuid;

INSERT INTO public.board_items (board_id, title, description, status, position, tags, created_by, organization_id)
SELECT
  pb.id,
  '✏️ Definir critérios de aprovação + protocolo de revisão',
  E'**Objetivo:** alinhar consistência entre os 3 curadores (Fabricio, Sarah, Roberto) na aplicação da rúbrica.\n\n**Tópicos sugeridos:**\n• Critérios da rúbrica (clarity, originality, adherence, relevance, ethics) — exemplos por nível\n• Quando aprovar solo vs pedir 2º parecer\n• Como escrever feedback construtivo em devoluções\n• Critérios para arquivamento (vs devolver para revisão)\n• Padronização do registro institucional (Manual §4.3)\n\n**Referência:** Manual de Governança §3.6 + §4.2 + §5.1 + ADR-0086 (peer review colegiado, leader review nominal, waiver path).',
  'backlog', 3,
  ARRAY['workspace', 'process'],
  '92d26057-5550-4f15-a3bf-b00eed5f32f9'::uuid,
  pb.organization_id
FROM public.project_boards pb
WHERE pb.id = '41b8b25d-0f76-4f62-b1e3-292ca895ab73'::uuid;
