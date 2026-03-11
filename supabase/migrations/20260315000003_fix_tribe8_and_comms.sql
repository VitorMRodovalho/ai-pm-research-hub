-- ============================================================================
-- Data Sanity: Resgate da Tribo 8 (Pesquisa) e desvinculação dos boards Comms
-- A Tribo 8 é "Inclusão & Colaboração & Comunicação" (Pesquisa), não operações
-- Date: 2026-03-15
-- ============================================================================

BEGIN;

-- 1. Devolve a Tribo 8 para o status de Pesquisa e com seu nome real
UPDATE public.tribes
SET
  workstream_type = 'research',
  name = 'Inclusão & Colaboração & Comunicação'
WHERE id = 8;

-- 2. Desvincula os quadros de Comms da Tribo 8
-- Muda para board_scope = 'global' (operational exige tribe_id por constraint)
-- São plataforma-wide, não pertencem a tribe específica
UPDATE public.project_boards
SET tribe_id = NULL,
    board_scope = 'global'
WHERE domain_key = 'communication'
  AND tribe_id = 8;

COMMIT;
