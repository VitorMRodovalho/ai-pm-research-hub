-- Item 12 (handoff 25/Abr): backfill 22 records member_offboarding_records sem
-- reason_category_code + ADD CONSTRAINT NOT NULL.
-- Decision #18 A: NOT NULL + backfill com 'end_of_cycle' + reason_detail explicativo.
-- Discovery delta: handoff disse 6 batch 24/03 (PMI-GO scope); org-wide são 22.
-- Pragmatic split:
--   - Records SEM reason_detail (provavelmente batch 24/03 cleanup) → 'end_of_cycle'
--   - Records COM reason_detail rico → 'other' (preserva detail, PM recategoriza
--     depois com sweep targetado se decidir granular).

UPDATE public.member_offboarding_records
SET
  reason_category_code = 'end_of_cycle',
  reason_detail = COALESCE(
    NULLIF(trim(reason_detail), ''),
    'Cleanup automático de transição entre Ciclo 2 e Ciclo 3 (sem entrevista de saída — categoria atribuída retroativamente p77 2026-04-28)'
  ),
  updated_at = now()
WHERE reason_category_code IS NULL
  AND (reason_detail IS NULL OR length(trim(reason_detail)) = 0);

UPDATE public.member_offboarding_records
SET
  reason_category_code = 'other',
  updated_at = now()
WHERE reason_category_code IS NULL
  AND reason_detail IS NOT NULL
  AND length(trim(reason_detail)) > 0;

ALTER TABLE public.member_offboarding_records
  ALTER COLUMN reason_category_code SET NOT NULL;

NOTIFY pgrst, 'reload schema';
