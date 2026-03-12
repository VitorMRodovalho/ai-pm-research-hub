-- CXO Directive: Fix T6 leader, clean Miro trash, populate legacy tribes
-- Date: 2026-03-16
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Fix T6 leader: Fabrício Costa → tribe_leader (was deputy_manager)
-- ═══════════════════════════════════════════════════════════════════════════
UPDATE public.members
SET operational_role = 'tribe_leader'
WHERE id = '92d26057-5550-4f15-a3bf-b00eed5f32f9'
  AND tribe_id = 6;

UPDATE public.member_cycle_history
SET operational_role = 'tribe_leader'
WHERE member_id = '92d26057-5550-4f15-a3bf-b00eed5f32f9'
  AND cycle_code = 'cycle_3'
  AND tribe_id = 6;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Soft-delete trash items from T6 board (names, meetings, short stickies)
--    Board ID: 118b55be-9dcd-4b2d-82c7-5c457fb1fc1e
-- ═══════════════════════════════════════════════════════════════════════════

-- 2a. Archive member name stickies
UPDATE public.board_items
SET status = 'archived'
WHERE board_id = '118b55be-9dcd-4b2d-82c7-5c457fb1fc1e'
  AND title IN (
    'Mayanna Duarte', 'Italo Nogueira', 'Fabricio Costa', 'Camilo',
    'Andressa Martins', 'Francisco José', 'Denis Vasconcelos',
    'Luciana Dutra', 'Rodrigo Grilo', 'Leticia Clemente',
    'João Coelho Júnior', 'Lucas De Moura Vasconcelos',
    'Cíntia Simões De Oliveira'
  );

-- 2b. Archive meeting stickies
UPDATE public.board_items
SET status = 'archived'
WHERE board_id = '118b55be-9dcd-4b2d-82c7-5c457fb1fc1e'
  AND (title ILIKE 'reunião%' OR title ILIKE 'reuniao%');

-- 2c. Archive very short stickies (< 10 chars, no URLs, likely broken fragments)
UPDATE public.board_items
SET status = 'archived'
WHERE board_id = '118b55be-9dcd-4b2d-82c7-5c457fb1fc1e'
  AND length(title) < 10
  AND title NOT LIKE '%http%'
  AND status <> 'archived';

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. Move tribo3_priorizacao items from T6 board to T3 board
--    Source board: 118b55be (T6)
--    Target board: T3's active board
--    Must temporarily disable the source_tribe integrity trigger
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE public.board_items DISABLE TRIGGER trg_enforce_board_item_source_tribe_integrity;

DO $$
DECLARE
  v_t3_board_id uuid;
BEGIN
  SELECT id INTO v_t3_board_id
  FROM public.project_boards
  WHERE tribe_id = 3 AND is_active = true
  ORDER BY updated_at DESC
  LIMIT 1;

  IF v_t3_board_id IS NOT NULL THEN
    UPDATE public.board_items
    SET board_id = v_t3_board_id
    WHERE board_id = '118b55be-9dcd-4b2d-82c7-5c457fb1fc1e'
      AND source_board = 'tribo3_priorizacao';
  END IF;
END $$;

ALTER TABLE public.board_items ENABLE TRIGGER trg_enforce_board_item_source_tribe_integrity;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. Populate legacy_tribes for the /teams page "Legado" section
--    Columns: legacy_key (unique), display_name, cycle_code, quadrant (int),
--             tribe_id (FK to current tribes), status, notes
-- ═══════════════════════════════════════════════════════════════════════════
INSERT INTO public.legacy_tribes (legacy_key, tribe_id, cycle_code, cycle_label, display_name, quadrant, status, notes)
VALUES
  ('t1_c1', 1, 'cycle_1', 'Ciclo 1', 'T1: Otimização de Recursos', 1, 'inactive', 'Continuou como T1: Radar Tecnológico no C3'),
  ('t2_c1c2', 2, 'cycle_2', 'Ciclo 1-2', 'T2: AI and Ethics', 2, 'inactive', 'Continuou como T7: Governança & Trustworthy AI no C3'),
  ('t3_c1c2', 3, 'cycle_2', 'Ciclo 1-2', 'T3: Priorização e Seleção', 3, 'inactive', 'Continuou como T6: ROI & Portfólio no C3'),
  ('t4_c1c2', 4, 'cycle_2', 'Ciclo 1-2', 'T4: Previsão de Riscos', 3, 'inactive', 'Continuou como T4: Cultura & Change no C3'),
  ('t5_c1c2', 5, 'cycle_2', 'Ciclo 1-2', 'T5: Emprego de IA para GP', 3, 'inactive', 'Continuou como T5: Talentos & Upskilling no C3'),
  ('t6_c2', 6, 'cycle_2', 'Ciclo 2', 'T6: Equipes Híbridas', 2, 'inactive', 'Continuou como T2: Agentes Autônomos no C3')
ON CONFLICT (legacy_key) DO UPDATE
  SET display_name = EXCLUDED.display_name,
      cycle_code = EXCLUDED.cycle_code,
      cycle_label = EXCLUDED.cycle_label,
      quadrant = EXCLUDED.quadrant,
      tribe_id = EXCLUDED.tribe_id,
      status = EXCLUDED.status,
      notes = EXCLUDED.notes;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. Enrich tribe_lineage with missing mappings
--    Existing: T3→T6 (renumbered_to), T6→T2 (renumbered_to)
--    Adding: T1→T1, T2→T7, T4→T4, T5→T5 (continued_as)
-- ═══════════════════════════════════════════════════════════════════════════
INSERT INTO public.tribe_lineage (legacy_tribe_id, current_tribe_id, relation_type, cycle_scope, notes, is_active)
VALUES
  (1, 1, 'continues_as', 'cycle_1->cycle_3', 'T1 Otimização de Recursos → T1 Radar Tecnológico', true),
  (2, 7, 'continues_as', 'cycle_1,cycle_2->cycle_3', 'T2 AI and Ethics → T7 Governança & Trustworthy AI', true),
  (4, 4, 'continues_as', 'cycle_1,cycle_2->cycle_3', 'T4 Previsão de Riscos → T4 Cultura & Change', true),
  (5, 5, 'continues_as', 'cycle_1,cycle_2->cycle_3', 'T5 Emprego de IA para GP → T5 Talentos & Upskilling', true)
ON CONFLICT (legacy_tribe_id, current_tribe_id, relation_type, coalesce(cycle_scope, '')) DO NOTHING;
