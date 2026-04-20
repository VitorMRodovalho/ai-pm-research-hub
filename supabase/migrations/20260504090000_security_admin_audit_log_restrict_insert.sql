-- Security P1 tier 3 (security-engineer audit p28): admin_audit_log INSERT unrestricted.
-- Policy anterior "Authenticated can insert audit log" permitia qualquer member
-- inserir entries contanto que actor_id fosse o próprio. Vulnerabilidade: action
-- value arbitrário (fake audits tipo 'member.offboarded' ou 'privacy_consent_accepted').
--
-- Fix (defense-in-depth):
-- (a) DROP policy permissive → SECURITY DEFINER RPCs continuam OK (bypassa RLS)
-- (b) CHECK constraint em action pattern allowlist — previne valores arbitrários
--     mesmo via service_role (integridade mesmo sob compromise)

DROP POLICY IF EXISTS "Authenticated can insert audit log" ON public.admin_audit_log;

ALTER TABLE public.admin_audit_log
  DROP CONSTRAINT IF EXISTS admin_audit_log_action_pattern;

ALTER TABLE public.admin_audit_log
  ADD CONSTRAINT admin_audit_log_action_pattern
  CHECK (action ~ '^[a-z][a-z0-9_]*(\.[a-z0-9_]+)*$' AND length(action) <= 80);

COMMENT ON CONSTRAINT admin_audit_log_action_pattern ON public.admin_audit_log IS
  'Security P1 (security-engineer tier 3 audit p28): action must be lowercase segments (a-z0-9_) separated by dots. Allowlist pattern prevents arbitrary action values even if RLS is bypassed. Defense-in-depth com RLS restriction.';

NOTIFY pgrst, 'reload schema';
