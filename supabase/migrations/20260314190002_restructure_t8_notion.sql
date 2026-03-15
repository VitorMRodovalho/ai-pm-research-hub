-- ISSUE G: Restructure T8 Notion imports
-- 1. Convert pilar-1 Notion activities into checklist items under parent artifact
-- 2. Archive Marco milestone items (redundant with artifact cards)

-- Parent artifact: "Artigo de Revisão Crítica — Cérebro Neuroatípico e IA"
-- ad17ebe4-6050-4195-a094-13c4fa1eac72

-- 1. Insert pilar-1 activities as checklist items under the parent artifact
INSERT INTO board_item_checklists (board_item_id, text, is_completed, position, assigned_to, target_date)
VALUES
  -- "Criar Mural de Ideias" (was todo, due 2026-03-17)
  ('ad17ebe4-6050-4195-a094-13c4fa1eac72', 'Criar Mural de Ideias', false, 1,
   '63b87315-78ab-43f7-bb05-cc2e89682bbf', '2026-03-17'),
  -- "Criar link para artigo colaborativo" (was done, due 2026-03-17)
  ('ad17ebe4-6050-4195-a094-13c4fa1eac72', 'Criar link para artigo colaborativo', true, 2,
   '63b87315-78ab-43f7-bb05-cc2e89682bbf', '2026-03-17'),
  -- "Pesquisa sobre TDAH e Resumo com Citações" (was todo, due 2026-03-17)
  ('ad17ebe4-6050-4195-a094-13c4fa1eac72', 'Pesquisa sobre TDAH e Resumo com Citações', false, 3,
   '63b87315-78ab-43f7-bb05-cc2e89682bbf', '2026-03-17'),
  -- "Criar catálogo de leituras para divulgação do Artigo Pilar 1" (was todo, due 2026-03-17)
  ('ad17ebe4-6050-4195-a094-13c4fa1eac72', 'Criar catálogo de leituras para divulgação do Artigo Pilar 1', false, 4,
   '63b87315-78ab-43f7-bb05-cc2e89682bbf', '2026-03-17');

-- 2. Archive the 4 pilar-1 Notion board items (now represented as checklists)
UPDATE board_items SET status = 'archived'
WHERE id IN (
  'c5d84491-836a-4231-ac47-24ec9ebafd82',  -- Criar Mural de Ideias
  '30e566e1-bf6a-4c11-a8be-e5ced376e34a',  -- Criar link para artigo colaborativo
  '0a0a5854-c9a4-4621-ade4-7bcfb3f6a78b',  -- Pesquisa sobre TDAH e Resumo com Citações
  '7286fc9f-ba1d-4111-a093-ae8ee7023828'   -- Criar catálogo de leituras
);

-- 3. Archive the 5 Marco milestone items (redundant with artifact cards)
UPDATE board_items SET status = 'archived'
WHERE id IN (
  '47f6b71f-aced-46b7-8066-c70a6df0cf3b',  -- Marco: Pilar 1 — Artefato v1
  'f1d6f054-735a-4997-9c82-d1ce915b6099',  -- Marco: Pilar 2 — Artefato
  '7ec05c37-9c92-42d4-abbd-e8a731045064',  -- Marco: Pilar 3 — Artefato
  '594ff272-0b0b-43dc-a154-a2ee651dd347',  -- Marco: Pilar 4 — Artefato
  'c2e0454e-2814-4e92-88ac-b5df914a3e92'   -- Marco: Pilar 5 — Artefato
);
