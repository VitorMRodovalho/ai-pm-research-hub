-- ============================================================
-- p218 WATCH-257.A — Accept LGPD-canonical `contract` value in engagements.legal_basis
-- ============================================================
--
-- Background: 2026-04-13 migration 20260413320000 created constraint with runtime-specific
-- `contract_volunteer` (Lei 9.608). 2026-04-15 migration 20260415100000 updated ONLY
-- engagement_kinds catalog to LGPD-canonical `contract` (LGPD Art. 7 V). Engagements
-- constraint never updated → catalog↔runtime asymmetry. 3 catalog rows hold `contract`;
-- engagements rejects `contract`. p218 #257 INSERT hit this exact rejection.
--
-- Decision (Option α minimal, PM-approved 2026-05-22): additive — accept BOTH values.
-- No row migration; no consumer changes. Future cleanup normalizes legacy rows.
--
-- Rollback: ALTER TABLE public.engagements DROP CONSTRAINT engagements_legal_basis_check;
-- ALTER TABLE public.engagements ADD CONSTRAINT engagements_legal_basis_check
--   CHECK (legal_basis IN ('contract_volunteer','consent','legitimate_interest'));
-- Currently lossless (zero rows use `contract`); becomes lossy once any row does.
--
-- Refs: P162 WATCH-257.A, ADR-0006, LGPD Art. 7 V, migrations 20260413320000 + 20260415100000.

ALTER TABLE public.engagements DROP CONSTRAINT IF EXISTS engagements_legal_basis_check;

ALTER TABLE public.engagements
  ADD CONSTRAINT engagements_legal_basis_check
  CHECK (legal_basis IN ('contract', 'contract_volunteer', 'consent', 'legitimate_interest'));

COMMENT ON COLUMN public.engagements.legal_basis IS
  'LGPD-canonical values (contract, consent, legitimate_interest) per Art. 7. contract_volunteer is the legacy workflow-specific value kept for backward-compat with engagement rows pre-dating the 2026-04-15 LGPD compliance fix (migration 20260415100000). Prefer contract for new rows; engagement_kinds catalog uses contract. Future cleanup will normalize legacy rows and drop contract_volunteer. p218 WATCH-257.A.';

-- Smoke: ensure constraint accepts both terms
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'engagements_legal_basis_check'
      AND pg_get_constraintdef(oid) LIKE '%''contract''%'
      AND pg_get_constraintdef(oid) LIKE '%''contract_volunteer''%'
  ) THEN
    RAISE EXCEPTION 'Post-migration check failed: new constraint must accept both contract and contract_volunteer';
  END IF;
END $$;
