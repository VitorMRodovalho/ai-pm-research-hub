-- Security sweep Onda 1.6 — 2 more ERROR closures (4/11 → 2/11 remaining).
-- Continues p40 sweep — dead-view cleanups that don't require product pass.
--
-- 1. members_public_safe: REWRITE without is_superadmin column (privacy hygiene —
--    a column named is_superadmin should NEVER appear in a view named *_public_safe).
--    Zero callers verified (grep src/, EFs, scripts, pg_proc — all empty).
--    DROP + CREATE required because CREATE OR REPLACE cannot drop columns.
--    No anon grant (previously had one — authenticated + service_role sufficient).
--
-- 2. recurring_event_groups: flip invoker + revoke anon. Zero callers (dead view).
--    Existing meeting_link exposure concern remains (Onda 2 design pass to fully
--    decide whether meeting_link should be in this aggregate at all) — this
--    migration is purely a SECDEF → INVOKER hygiene fix for the advisor finding.

-- ==========================================================================
-- members_public_safe — drop and recreate without is_superadmin
-- ==========================================================================

DROP VIEW IF EXISTS public.members_public_safe;

CREATE VIEW public.members_public_safe WITH (security_invoker = true) AS
SELECT
  id,
  name,
  chapter,
  tribe_id,
  operational_role,
  designations,
  photo_url,
  linkedin_url,
  cpmai_certified,
  credly_badges,
  is_active,
  current_cycle_active,
  created_at,
  member_status
FROM public.members;

COMMENT ON VIEW public.members_public_safe IS
  'LGPD-safe member projection — excludes PII (email, phone, pmi_id, auth_id) and operational-privilege flags (is_superadmin removed 2026-04-23). security_invoker=true: RLS applies to caller; anon has no grant; authenticated gated by members RLS (is_active=true AND rls_is_member()). Zero callers in src/ as of rewrite — view kept as a projection contract for future self-service surfaces.';

GRANT SELECT ON public.members_public_safe TO authenticated, service_role;

-- ==========================================================================
-- recurring_event_groups — flip invoker + revoke anon
-- ==========================================================================

ALTER VIEW public.recurring_event_groups SET (security_invoker = true);
REVOKE SELECT ON public.recurring_event_groups FROM anon;
