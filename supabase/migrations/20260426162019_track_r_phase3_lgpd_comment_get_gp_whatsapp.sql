-- Track R Phase R3 follow-up — LGPD legal basis for get_gp_whatsapp
-- Per security-engineer council review (p59):
-- "get_gp_whatsapp() exposes individual phone number (PII per LGPD Art.
--  5, I) belonging to named individual. Need documented legal basis,
--  not just 'public route' rationale."
--
-- Legal basis: LGPD Art. 7/V (consent) + Art. 7/IX (legitimate interest)
-- - Consent: GP role is voluntary; phone exposure is part of role
--   acceptance documented in volunteer agreement (signed via
--   sign_volunteer_agreement RPC).
-- - Legitimate interest: PMI Núcleo IA institutional support flow
--   requires GP contactability for prospective members and visitors
--   seeking onboarding info via help.astro.
--
-- Data minimization: only the GP's phone is exposed (not address, email,
-- or other PII). The function returns regexp_replaced phone (digits only)
-- + name + source label — no extended PII surface.

COMMENT ON FUNCTION public.get_gp_whatsapp() IS
  'Public-by-design (LGPD Art. 7/V + Art. 7/IX): exposes the active GP''s WhatsApp number for help.astro support contact. Legal basis: consent (volunteer agreement signs role-based contactability) + legitimate interest (PMI institutional support flow). Data minimized to phone + name + source label. Track R Phase R3 (p59) — see docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md and ADR-0024 pattern.';

NOTIFY pgrst, 'reload schema';
