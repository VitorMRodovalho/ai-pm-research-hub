-- WHAT: Wave 1a M1 — ADR-0004 organization_id backfill across 4 governance tables
-- (governance_documents, document_versions, approval_chains, approval_signoffs).
--
-- WHY: P0-Q5 (Wave 0 ratification, #315) requires organization_id NOT NULL on every
-- governance table BEFORE any new DDL piggy-backs onto the chain workflow. ADR-0004
-- closure across the governance surface unblocks Wave 1a M2 (taxonomy + visibility
-- + status + RLS swap + V' invariant) and Wave 2 (#310 admin intake) downstream.
--
-- SPEC: docs/specs/SPEC_GOVERNANCE_DOCUMENTS_END_TO_END.md §19.5 (Wave 1a footprint
-- M1) — ratified PM 2026-05-24 in PR #364 (Wave 0 close).
--
-- IMMUTABILITY TRIGGER HANDLING: approval_signoffs has trg_approval_signoff_immutable
-- (hard RAISE on any UPDATE — append-only governance evidence). This migration
-- temporarily DISABLES that trigger ONLY during backfill, then re-enables it.
-- document_versions also has trg_document_version_immutable but it only protects
-- content-bearing columns (content_html/content_markdown/version_number/version_label
-- /document_id/locked_at) — organization_id UPDATE passes through cleanly.
--
-- ROLLBACK (idempotent):
--   ALTER TABLE approval_signoffs DISABLE TRIGGER trg_approval_signoff_immutable;
--   ALTER TABLE governance_documents DROP CONSTRAINT governance_documents_organization_id_fkey;
--   ALTER TABLE governance_documents ALTER COLUMN organization_id DROP NOT NULL;
--   ALTER TABLE governance_documents DROP COLUMN organization_id;
--   -- repeat for document_versions, approval_chains, approval_signoffs.
--   ALTER TABLE approval_signoffs ENABLE TRIGGER trg_approval_signoff_immutable;
--
-- INVARIANTS: no invariant change in M1; M2 introduces V' (status=pending_proposer_consent
-- → no non-cancelled approval_chains). V (status/chain coherence) DEFERRED to Wave 1b
-- first leaf — 7 legacy pre-chain docs (status=active, current_ratified_chain_id IS NULL,
-- zero approval_chains rows) need synthetic-chain backfill with PM-designated
-- signer-of-record convention before V can enforce without permanent carve-out.
--
-- CROSS-REF: #315 Wave 0 ratification (comment-4530613476); SPEC §19.5; ADR-0004;
-- session p256 (post-p255 bundle close 12ae885c → Wave 0 ratify decb35a9 → Wave 1a M1).
-- ============================================================================

-- 1) ADD COLUMN (nullable to allow backfill)
ALTER TABLE public.governance_documents ADD COLUMN organization_id uuid;
ALTER TABLE public.document_versions    ADD COLUMN organization_id uuid;
ALTER TABLE public.approval_chains      ADD COLUMN organization_id uuid;
ALTER TABLE public.approval_signoffs    ADD COLUMN organization_id uuid;

-- 2) Temporarily disable append-only trigger on approval_signoffs for backfill
ALTER TABLE public.approval_signoffs DISABLE TRIGGER trg_approval_signoff_immutable;

-- 3) Backfill — single tenant today (Núcleo IA)
UPDATE public.governance_documents
   SET organization_id = '2b4f58ab-7c45-4170-8718-b77ee69ff906'
 WHERE organization_id IS NULL;

UPDATE public.document_versions
   SET organization_id = '2b4f58ab-7c45-4170-8718-b77ee69ff906'
 WHERE organization_id IS NULL;

UPDATE public.approval_chains
   SET organization_id = '2b4f58ab-7c45-4170-8718-b77ee69ff906'
 WHERE organization_id IS NULL;

UPDATE public.approval_signoffs
   SET organization_id = '2b4f58ab-7c45-4170-8718-b77ee69ff906'
 WHERE organization_id IS NULL;

-- 4) Re-enable append-only trigger
ALTER TABLE public.approval_signoffs ENABLE TRIGGER trg_approval_signoff_immutable;

-- 5) Sanity DO — RAISES if any row left NULL
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.governance_documents WHERE organization_id IS NULL) THEN
    RAISE EXCEPTION 'p256 M1: governance_documents.organization_id backfill incomplete';
  END IF;
  IF EXISTS (SELECT 1 FROM public.document_versions WHERE organization_id IS NULL) THEN
    RAISE EXCEPTION 'p256 M1: document_versions.organization_id backfill incomplete';
  END IF;
  IF EXISTS (SELECT 1 FROM public.approval_chains WHERE organization_id IS NULL) THEN
    RAISE EXCEPTION 'p256 M1: approval_chains.organization_id backfill incomplete';
  END IF;
  IF EXISTS (SELECT 1 FROM public.approval_signoffs WHERE organization_id IS NULL) THEN
    RAISE EXCEPTION 'p256 M1: approval_signoffs.organization_id backfill incomplete';
  END IF;
END $$;

-- 6) NOT NULL gate + FK ON DELETE RESTRICT (matches canonical pattern from members/tribes/engagements)
ALTER TABLE public.governance_documents
  ALTER COLUMN organization_id SET NOT NULL,
  ADD CONSTRAINT governance_documents_organization_id_fkey
    FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;

ALTER TABLE public.document_versions
  ALTER COLUMN organization_id SET NOT NULL,
  ADD CONSTRAINT document_versions_organization_id_fkey
    FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;

ALTER TABLE public.approval_chains
  ALTER COLUMN organization_id SET NOT NULL,
  ADD CONSTRAINT approval_chains_organization_id_fkey
    FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;

ALTER TABLE public.approval_signoffs
  ALTER COLUMN organization_id SET NOT NULL,
  ADD CONSTRAINT approval_signoffs_organization_id_fkey
    FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;

NOTIFY pgrst, 'reload schema';
