-- Migration: add FK constraint member_emails.organization_id → organizations(id)
-- Issue: #205 (GAP-205.B per P162 #117) — council Tier 1 PR #240 LOW finding
-- Migration: 20260802000011 (follow-up to 20260802000008-10)
--
-- ROLLBACK:
--   ALTER TABLE public.member_emails DROP CONSTRAINT IF EXISTS member_emails_organization_id_fkey;
--
-- Rationale: ADR-0095 §1 lists organization_id as part of member_emails schema
-- but the original migration 20260802000008 did not declare a FK constraint.
-- Other multi-tenant tables (members, tribes, engagements) all use
-- ON DELETE RESTRICT for organization_id FKs. This migration brings
-- member_emails to parity.
--
-- Why RESTRICT (not CASCADE/SET NULL):
--   - Canonical pattern across the codebase
--   - SET NULL would interact badly with the RESTRICTIVE org_scope policy
--     `(organization_id = auth_org()) OR (organization_id IS NULL)` —
--     orphaned rows would become visible to all tenants
--   - CASCADE would silently drop email history on org deletion
--   - RESTRICT forces a deliberate cleanup path before org deletion
--
-- Pre-flight (verified at apply time): 0 dangling org refs in member_emails.

BEGIN;

-- Safety check: no dangling org references
DO $$
DECLARE
  v_dangling int;
BEGIN
  SELECT count(*) INTO v_dangling
  FROM public.member_emails me
  WHERE organization_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.organizations o WHERE o.id = me.organization_id);

  IF v_dangling > 0 THEN
    RAISE EXCEPTION 'Cannot add FK constraint: % dangling org_id refs found in member_emails. Resolve before applying.', v_dangling;
  END IF;
END $$;

ALTER TABLE public.member_emails
  ADD CONSTRAINT member_emails_organization_id_fkey
  FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;

COMMIT;
