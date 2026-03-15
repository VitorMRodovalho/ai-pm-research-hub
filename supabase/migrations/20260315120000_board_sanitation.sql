-- Board Sanitation: Deliverables vs Tasks
-- Rule: CARD = Deliverable/WBS. CHECKLIST ITEM = Activity/Task.
-- Converts tasks to checklists inside parent deliverables, archives legacy noise.

-- ═══════════════════════════════════════════════════════════════════
-- STEP 1: Create 'entregavel_lider' tag + assign to 56 artifacts
-- ═══════════════════════════════════════════════════════════════════

INSERT INTO tags (name, label_pt, label_en, label_es, color, tier, domain, description, display_order)
VALUES ('entregavel_lider', 'Entregável do Líder', 'Leader Deliverable', 'Entregable del Líder',
  '#DC2626', 'system', 'board_item',
  'Artefato pactuado pelo líder da tribo na apresentação do Ciclo 3', 15)
ON CONFLICT (name, domain) DO NOTHING;

-- Assign to all 56 artifacts (loaded on 2026-03-15 02:37:56 UTC)
INSERT INTO board_item_tag_assignments (board_item_id, tag_id)
SELECT bi.id, t.id
FROM board_items bi
CROSS JOIN tags t
WHERE t.name = 'entregavel_lider' AND t.domain = 'board_item'
  AND bi.created_at >= '2026-03-15 02:37:00' AND bi.created_at <= '2026-03-15 02:38:00'
  AND bi.cycle = 3
ON CONFLICT (board_item_id, tag_id) DO NOTHING;

-- ═══════════════════════════════════════════════════════════════════
-- STEP 2: T3 — Convert 18 tasks → checklist items inside deliverables
-- ═══════════════════════════════════════════════════════════════════

-- Parent: Ideação do Projeto Piloto TMO/PMO (00feaf8b)
INSERT INTO board_item_checklists (board_item_id, text, assigned_to, target_date, position, is_completed)
SELECT '00feaf8b-d2c8-462b-84e9-cccf6004a9aa', bi.title, bi.assignee_id, bi.baseline_date,
  (row_number() OVER (ORDER BY bi.position))::smallint,
  CASE WHEN bi.status IN ('done', 'review') THEN true ELSE false END
FROM board_items bi
WHERE bi.id IN (
  '0be81836-d058-4311-ac75-5c7f5d559333', -- Definir escopo do grupo
  'f1a6e8b4-fa33-4c72-bafb-5a8d46ff17c1', -- Definir o objetivo geral da pesquisa
  '6c2f55ac-704a-4071-8f7e-f0e78ad483eb', -- Definir os objetivos específicos
  '83d6305d-682d-4483-972d-9d7c850a75c0', -- Levantar as principais questões de pesquisa
  '4a7c6b69-738c-46b1-9fe1-9714f1c8d8f5', -- Decidir quantidade de artigos
  'fab09da8-d29c-4fc6-aa26-ab8051605c82'  -- Decidir os subtópicos
);

-- Parent: Arquitetura do Modelo TMO/PMO do Futuro (f669df3e)
INSERT INTO board_item_checklists (board_item_id, text, assigned_to, target_date, position, is_completed)
SELECT 'f669df3e-394b-4187-bf4f-0c3d80ef6b5c', bi.title, bi.assignee_id, bi.baseline_date,
  (row_number() OVER (ORDER BY bi.position))::smallint,
  CASE WHEN bi.status IN ('done', 'review') THEN true ELSE false END
FROM board_items bi
WHERE bi.id IN (
  '9ee8c788-5908-4408-9bfe-b8f4d5d490b6', -- Buscar materiais acadêmicos
  'ad69a540-341a-40a9-92e8-15996c93e2cb', -- Identificar ferramentas de IA
  '10989830-d79b-4ceb-a6bd-3d53b04f5e8c', -- Organizar referências
  '01956a84-3055-4154-9cb5-a8e2d590e856', -- Elaborar quadro de coerencia
  '221bcfbe-8552-4f1c-9d2a-b202d18b10e1'  -- Definir estrutura do artigo
);

-- Parent: Construção da PoC — TMO com IA (e80aae52)
INSERT INTO board_item_checklists (board_item_id, text, assigned_to, target_date, position, is_completed)
SELECT 'e80aae52-4ef6-490d-80b9-c8976467c030', bi.title, bi.assignee_id, bi.baseline_date,
  (row_number() OVER (ORDER BY bi.position))::smallint,
  CASE WHEN bi.status IN ('done', 'review') THEN true ELSE false END
FROM board_items bi
WHERE bi.id IN (
  '154dbd10-25b9-42b1-b19a-d14b5bbc459a', -- Distribuir seções
  '003393df-066a-4c13-a444-7bc567603fb4', -- Redigir rascunhos
  '57069f95-f78c-4514-8c78-7f8e6bd7a094', -- Refinar conteúdo
  '39910596-ca4b-46f2-9e22-f23ebafe6565'  -- Criar doc no drive
);

-- Parent: Relatório / Artigo Final TMO com IA (e0142a94)
INSERT INTO board_item_checklists (board_item_id, text, assigned_to, target_date, position, is_completed)
SELECT 'e0142a94-09a8-4ecf-8cfc-0328c5631f7e', bi.title, bi.assignee_id, bi.baseline_date,
  (row_number() OVER (ORDER BY bi.position))::smallint,
  CASE WHEN bi.status IN ('done', 'review') THEN true ELSE false END
FROM board_items bi
WHERE bi.id IN (
  '750975ce-63d6-4bcf-944c-763ebf972ed6', -- Revisão geral do texto
  '3a3963e3-d7e3-4a1f-ad3c-053cf378af32', -- Submeter para revisão
  'c6c95d8c-f8be-4eb0-8551-144bb1d5fee5', -- Revisão pelo núcleo
  'a073217c-af8f-42da-aea2-ce4278566ca3', -- Preparar versão final
  '6cf9edff-3e8e-4bc3-ab40-3798b6d56e4d', -- Criar apresentação/resumo
  '06ecca5d-f9d0-4450-864c-e9a209474238'  -- Submissão final
);

-- ═══════════════════════════════════════════════════════════════════
-- STEP 3: T3 — Archive ALL non-deliverable items (tasks + C2 legacy)
-- ═══════════════════════════════════════════════════════════════════

UPDATE board_items SET status = 'archived'
WHERE board_id = '50474fd3-adbc-4980-ba2e-6dffec420321'
  AND id NOT IN (
    '00feaf8b-d2c8-462b-84e9-cccf6004a9aa', -- Ideação
    'f669df3e-394b-4187-bf4f-0c3d80ef6b5c', -- Arquitetura
    'e80aae52-4ef6-490d-80b9-c8976467c030', -- Construção PoC
    '3c5344a7-9749-4cb1-823d-01f4a61973a9', -- Execução e Validação
    'e0142a94-09a8-4ecf-8cfc-0328c5631f7e'  -- Relatório Final
  )
  AND status <> 'archived';

-- ═══════════════════════════════════════════════════════════════════
-- STEP 4: T4 — Archive 52 C2 miro-import items
-- ═══════════════════════════════════════════════════════════════════

UPDATE board_items SET status = 'archived'
WHERE board_id = 'e62bf41c-a762-4e07-8a18-4f8fff23c2f7'
  AND cycle = 2
  AND status <> 'archived';

-- ═══════════════════════════════════════════════════════════════════
-- STEP 5: T6 — Archive 142 C2 miro-import items
-- ═══════════════════════════════════════════════════════════════════

UPDATE board_items SET status = 'archived'
WHERE board_id = '118b55be-9dcd-4b2d-82c7-5c457fb1fc1e'
  AND cycle = 2
  AND status <> 'archived';

-- ═══════════════════════════════════════════════════════════════════
-- STEP 6: Comms — Tag C2 posts with 'ciclo-2' in text tags array
-- ═══════════════════════════════════════════════════════════════════

UPDATE board_items
SET tags = array_append(tags, 'ciclo-2')
WHERE board_id = 'a6b78238-11aa-476a-b7e2-a674d224fd79'
  AND (title LIKE '%POST 1]%' OR title LIKE '%POST 2]%'
    OR title LIKE '%POST 3]%' OR title LIKE '%POST 4]%' OR title LIKE '%POST 5]%'
    OR title LIKE '%POST 6]%' OR title LIKE '%POST 7]%' OR title LIKE '%POST 8]%'
    OR title LIKE '%POST 9]%' OR title LIKE '%POST 10]%' OR title LIKE '%POST 11]%'
    OR title LIKE '%POST 12]%' OR title LIKE '%POST 13]%')
  AND NOT (tags @> ARRAY['ciclo-2']);

-- ═══════════════════════════════════════════════════════════════════
-- STEP 7: Publicações — Archive instruction + placeholder cards
-- ═══════════════════════════════════════════════════════════════════

UPDATE board_items SET status = 'archived'
WHERE board_id = '86a8959c-ddd0-4a7f-b45f-bf828230f949'
  AND (title LIKE 'Purpose:%' OR title LIKE 'How to use:%')
  AND status <> 'archived';

UPDATE board_items SET status = 'archived'
WHERE board_id = '86a8959c-ddd0-4a7f-b45f-bf828230f949'
  AND title IN ('Article 1', 'Article 2', 'Trello Guide Article')
  AND status <> 'archived';
