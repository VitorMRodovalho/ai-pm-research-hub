-- ═══════════════════════════════════════════════════════════════
-- Security: active_members view — explicit column list + REVOKE anon
-- Why:
--   1. SELECT * exposes any future PII column added to members
--      (e.g., if we add tax_id, address2, date_of_birth variants).
--      Explicit list = structural safeguard against accidental exposure.
--   2. GRANT anon on members-backed view violates LGPD: member records
--      (name, chapter, credly, linkedin) should require authentication.
--      Public-facing member data has dedicated safe views
--      (public_members, members_public_safe).
-- Consumers verified (2026-04-18):
--   - src/components/islands/BoardEngine.tsx:97 — selects id, name
--   - src/components/workspace/AttendanceForm.tsx:98 — id, name, tribe_id, operational_role
--   - src/pages/workspace.astro:371 — select id (count head:true), filter tribe_id
-- All consumers run under authenticated sessions; REVOKE anon is safe.
-- Rollback:
--   DROP VIEW IF EXISTS public.active_members; CREATE VIEW public.active_members AS SELECT * FROM public.members WHERE is_active = true;
--   GRANT SELECT ON public.active_members TO anon;
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW public.active_members AS
SELECT
  m.id,
  m.name,
  m.tribe_id,
  m.chapter,
  m.state,
  m.country,
  m.operational_role,
  m.designations,
  m.member_status,
  m.status_changed_at,
  m.is_active,
  m.current_cycle_active,
  m.cycles,
  m.photo_url,
  m.linkedin_url,
  m.credly_url,
  m.credly_badges,
  m.credly_verified_at,
  m.cpmai_certified,
  m.cpmai_certified_at,
  m.share_whatsapp,
  m.share_address,
  m.share_birth_date,
  m.profile_completed_at,
  m.onboarding_dismissed_at,
  m.last_seen_at,
  m.total_sessions,
  m.last_active_pages,
  m.organization_id,
  m.initiative_id,
  m.person_id,
  m.created_at,
  m.updated_at
FROM public.members m
WHERE m.is_active = true;

-- Revoke anon access (LGPD: member data requires authentication)
REVOKE ALL ON public.active_members FROM anon;

-- Preserve authenticated access (only path for frontend consumers)
GRANT SELECT ON public.active_members TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMENT ON VIEW public.active_members IS 'W139 + security hardening 20260428: active members (is_active=true). Explicit column list excludes PII (email, phone, pmi_id, auth_id, phone_encrypted, pmi_id_encrypted, birth_date, address, city, secondary_emails, signature_url, secondary_auth_ids) and admin-only fields (is_superadmin, inactivated_at, anonymized_*, offboarded_*). anon access revoked per LGPD.';
