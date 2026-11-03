-- ═══════════════════════════════════════════════════════════════════════════
-- Data Merge Healing: T4 (member B), T6 (member C), T8 (member A)
-- Resgata quadros legados e consolida dados fragmentados.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- 1. T4 (member B): Resgatar o quadro legado (Ciclo 2) e atrelar à T4
UPDATE public.project_boards
SET tribe_id = 4, board_scope = 'tribe'
WHERE board_name ILIKE '%Cultura%' AND board_name ILIKE '%Ciclo 2%';

-- 2. T6 (member C): MERGE de cards. Mover todos os cards para o quadro mais antigo ativo, desativar os demais.
WITH target_board AS (
  SELECT id FROM public.project_boards
  WHERE tribe_id = 6 AND is_active = true
  ORDER BY created_at ASC NULLS LAST
  LIMIT 1
)
UPDATE public.board_items bi
SET board_id = (SELECT id FROM target_board)
WHERE bi.board_id IN (
  SELECT pb.id FROM public.project_boards pb
  WHERE pb.tribe_id = 6 AND pb.id != (SELECT id FROM target_board)
);

WITH target_board AS (
  SELECT id FROM public.project_boards
  WHERE tribe_id = 6 AND is_active = true
  ORDER BY created_at ASC NULLS LAST
  LIMIT 1
)
UPDATE public.project_boards
SET is_active = false
WHERE tribe_id = 6 AND id != (SELECT id FROM target_board);

-- 3. T8 (member A): Garantir quadro oficial de entregas vinculado à tribo
INSERT INTO public.project_boards (board_name, tribe_id, board_scope, is_active)
SELECT 'T8: Inclusão & Comunicação - Entregas', 8, 'tribe', true
WHERE NOT EXISTS (
  SELECT 1 FROM public.project_boards
  WHERE tribe_id = 8 AND board_scope = 'tribe' AND is_active = true
);

COMMIT;
