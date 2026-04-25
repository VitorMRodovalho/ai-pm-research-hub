-- ADR-0024 — public_members view accepted risk comment.
--
-- Issue #82 Onda 2 advisor finding `security_definer_view_public_public_members`
-- documented as accepted risk per PM decision (2026-04-24). Scope memo:
-- docs/specs/SPEC_ISSUE_82_ONDA_2_3_OPTIONS.md. Decision rationale: 22 callsites
-- in 14 files, threat model accepts public roster as intentional, sensitive
-- columns (signature_url, linkedin_url, credly_url) tracked for focused slim
-- refactor in a future session. See docs/adr/ADR-0024 for the full trade-off
-- analysis and follow-up plan.

COMMENT ON VIEW public.public_members IS
  'Public member roster — accepted advisor risk per ADR-0024. SECURITY DEFINER intentional: exposes 22 community-public columns to anon for landing pages and authenticated for cross-tribe roster. Sensitive columns (signature_url, linkedin_url, credly_url) tracked for future slim refactor — see ADR-0024 §"Follow-up planejado".';
