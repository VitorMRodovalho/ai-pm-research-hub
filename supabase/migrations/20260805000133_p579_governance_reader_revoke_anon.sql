-- Migration: p579 — REVOKE EXECUTE on get_governance_document_reader FROM anon
-- Issue: #579 (#459 governance-body hardening follow-up) · PR for #459 was #578
--
-- Context: the defining migration 20260805000043_p263_312_w4d ran
--     REVOKE EXECUTE ... FROM PUBLIC;  GRANT EXECUTE ... TO authenticated;
-- but Supabase's project-level ALTER DEFAULT PRIVILEGES grants the `anon` role EXECUTE on
-- new public functions DIRECTLY (not through the PUBLIC pseudo-role), so REVOKE FROM PUBLIC
-- left a residual `anon=X` grant (confirmed live: proacl {…,anon=X/postgres,…}). The RPC is
-- fail-closed (internal active-member / visibility_class gate returns document:NULL to anon),
-- so this is defense-in-depth tidy, NOT an open hole — same sediment class as the
-- #485 / #564 / #567 anon-residual REVOKEs.
--
-- Effect: anon loses EXECUTE; authenticated (member web route /governance/document/[id] +
-- the get_governance_document_body MCP tool, both via an authenticated session) and
-- service_role keep EXECUTE.
--
-- Rollback (not recommended — re-introduces the residual grant):
--     GRANT EXECUTE ON FUNCTION public.get_governance_document_reader(uuid) TO anon;
--
-- NOTIFY pgrst not required: this is a pure ACL change (no signature/return-shape change),
-- Postgres enforces the new EXECUTE privilege at call time without a PostgREST schema reload
-- (consistent with the p567 REVOKE-only migration).

REVOKE EXECUTE ON FUNCTION public.get_governance_document_reader(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_governance_document_reader(uuid) FROM PUBLIC;
