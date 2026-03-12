-- ============================================================================
-- Ensure all tribe boards have domain_key = 'research_delivery'
-- Safety net for BoardEngine integration (Sprint 6)
-- ============================================================================

UPDATE public.project_boards
SET domain_key = 'research_delivery',
    updated_at = now()
WHERE tribe_id IS NOT NULL
  AND board_scope = 'tribe'
  AND is_active = true
  AND (domain_key IS NULL OR domain_key = '');

-- Ensure tribes 1-8 all have at least one active board
DO $$
DECLARE
  v_tribe RECORD;
BEGIN
  FOR v_tribe IN
    SELECT t.id, t.name
    FROM public.tribes t
    WHERE t.is_active IS TRUE
      AND COALESCE(t.workstream_type, 'research') = 'research'
    ORDER BY t.id
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.project_boards
      WHERE tribe_id = v_tribe.id
        AND is_active = true
        AND domain_key = 'research_delivery'
    ) THEN
      INSERT INTO public.project_boards (
        board_name, tribe_id, source, board_scope, domain_key, columns, is_active
      ) VALUES (
        format('T%s: %s - Quadro Geral', v_tribe.id, v_tribe.name),
        v_tribe.id,
        'manual',
        'tribe',
        'research_delivery',
        '["backlog","todo","in_progress","review","done"]'::jsonb,
        true
      );
    END IF;
  END LOOP;
END;
$$;
