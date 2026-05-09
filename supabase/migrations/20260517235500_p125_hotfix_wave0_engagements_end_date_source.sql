-- p125 Hotfix Wave 0 — Issue D fallback strategy backfill
-- ADR-0076 Princípio 5 + Decision 8 + R1 do pre-mortem
-- TIMESTAMP placement: 20260517235500 (between current latest 20260517230000
-- and E1 migrations starting at 20260518000000) — ordering matters for dependencies
-- Wave 1 draft (council review pending Wave 2)
--
-- Backfills engagements.metadata->>'end_date_source' for the 36/94 active
-- engagements with agreement_certificate_id (immediate confidence wins).
-- The 58/94 without agreement_certificate are flagged with end_date_pending=true
-- aguardando E2 worker re-sync from PMI VEP serviceEndDateUTC.
--
-- DOES NOT populate engagements.end_date directly — that's E2 worker job.
-- This migration ONLY adds metadata flag for source-of-truth tracking.
--
-- Atomicity: independent of E1 migrations. Can apply standalone.
--
-- Rollback: UPDATE engagements SET metadata = metadata - 'end_date_source' - 'end_date_pending';

BEGIN;

-- ─── Backfill source flag for 36 with agreement_certificate ─────────────────
UPDATE public.engagements
SET metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
  'end_date_source', 'agreement',
  'end_date_source_set_at', now()::text,
  'end_date_source_set_by', 'p125_hotfix_wave_0'
)
WHERE status = 'active'
  AND agreement_certificate_id IS NOT NULL
  AND (metadata->>'end_date_source') IS NULL;

-- ─── Flag 58 without agreement_certificate as pending E2 worker ─────────────
UPDATE public.engagements
SET metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
  'end_date_source', 'pending_e2_worker',
  'end_date_pending', true,
  'end_date_source_set_at', now()::text,
  'end_date_source_set_by', 'p125_hotfix_wave_0'
)
WHERE status = 'active'
  AND agreement_certificate_id IS NULL
  AND (metadata->>'end_date_source') IS NULL;

-- ─── Verify counts via NOTICE (visible in migration apply logs) ─────────────
DO $$
DECLARE
  v_agreement_count integer;
  v_pending_count integer;
  v_total_active integer;
BEGIN
  SELECT COUNT(*) INTO v_agreement_count FROM public.engagements
  WHERE status='active' AND metadata->>'end_date_source' = 'agreement';

  SELECT COUNT(*) INTO v_pending_count FROM public.engagements
  WHERE status='active' AND metadata->>'end_date_source' = 'pending_e2_worker';

  SELECT COUNT(*) INTO v_total_active FROM public.engagements WHERE status='active';

  RAISE NOTICE '[p125 Hotfix Wave 0] active engagements with agreement source: % | pending E2 worker: % | total active: %',
    v_agreement_count, v_pending_count, v_total_active;

  -- Sanity: agreement + pending should equal total active (no other states post-backfill)
  IF v_agreement_count + v_pending_count <> v_total_active THEN
    RAISE WARNING '[p125 Hotfix Wave 0] Coverage gap: % active engagements without source flag',
      v_total_active - v_agreement_count - v_pending_count;
  END IF;
END $$;

COMMIT;

-- Post-apply checklist:
--   1. supabase migration repair --status applied 20260517235500
--   2. NO PostgREST reload needed (only DML, no schema change)
--   3. Verify: SELECT metadata->>'end_date_source', COUNT(*) FROM engagements
--             WHERE status='active' GROUP BY 1
--   4. Expected: ~36 'agreement' + ~58 'pending_e2_worker' = 94 active
--   5. E2 worker must update 'pending_e2_worker' rows to 'pmi_vep' or 'estimated' per Decision 8
