-- ============================================================================
-- V4 Fix — Align legal_basis values with LGPD Art. 7
-- Context: contract_course and chapter_delegation are not LGPD terms.
--          contract_volunteer normalized to contract (Art. 7 V).
--          Candidate retention aligned with privacy policy (3 years).
-- Rollback: Restore old CHECK + UPDATE legal_basis back to old values.
-- ============================================================================

-- Step 1: Drop old CHECK
ALTER TABLE engagement_kinds DROP CONSTRAINT engagement_kinds_legal_basis_check;

-- Step 2: Normalize data (before adding new constraint)
UPDATE engagement_kinds SET legal_basis = 'contract' WHERE legal_basis IN ('contract_volunteer', 'contract_course');
UPDATE engagement_kinds SET legal_basis = 'legitimate_interest' WHERE legal_basis = 'chapter_delegation';

-- Step 3: Add new CHECK with LGPD Art. 7 compliant values only
ALTER TABLE engagement_kinds ADD CONSTRAINT engagement_kinds_legal_basis_check
  CHECK (legal_basis IN ('contract', 'consent', 'legitimate_interest'));

-- Flag 2: Candidate retention 730d → 1095d (3 years, align with privacy policy)
UPDATE engagement_kinds SET retention_days_after_end = 1095 WHERE slug = 'candidate';

NOTIFY pgrst, 'reload schema';
