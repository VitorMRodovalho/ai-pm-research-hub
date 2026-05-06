-- ARM Onda 1 #135: admin_audit_log immutability hardening
--
-- Estado pré-migration (verificado p107):
--   - RLS habilitado, 1 policy SELECT ("Superadmin can read audit log") TO authenticated
--   - 0 policies UPDATE/DELETE → default deny para roles non-bypass
--   - Grants DML over-permissive: anon (INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER),
--     authenticated (todos + SELECT)
--   - DELETE via service_role bypassa RLS (necessário para anonymize cron, mas nunca DELETE direto)
--
-- Mudanças:
--   1) RESTRICTIVE policies bloqueando DELETE e UPDATE via authenticated (defesa em profundidade
--      mesmo se policy permissive futura for adicionada por engano)
--   2) REVOKE DML mutations de anon (zero uso legítimo)
--   3) REVOKE UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER de authenticated (manter SELECT pois
--      Superadmin policy gateia rows)
--   4) NÃO toca service_role/postgres (necessário para cron jobs LGPD anonymize que mutam
--      audit log via wrappers SECDEF como admin_anonymize_member)
--
-- Rollback:
--   DROP POLICY audit_log_no_delete ON public.admin_audit_log;
--   DROP POLICY audit_log_no_update ON public.admin_audit_log;
--   GRANT INSERT, UPDATE, DELETE, REFERENCES, TRIGGER, TRUNCATE ON public.admin_audit_log
--     TO anon, authenticated;

-- 1) RESTRICTIVE policies bloqueando mutação via authenticated
DROP POLICY IF EXISTS audit_log_no_delete ON public.admin_audit_log;
CREATE POLICY audit_log_no_delete
  ON public.admin_audit_log
  AS RESTRICTIVE FOR DELETE TO authenticated
  USING (false);

DROP POLICY IF EXISTS audit_log_no_update ON public.admin_audit_log;
CREATE POLICY audit_log_no_update
  ON public.admin_audit_log
  AS RESTRICTIVE FOR UPDATE TO authenticated
  USING (false)
  WITH CHECK (false);

-- 2) REVOKE DML grants over-permissive
REVOKE INSERT, UPDATE, DELETE, REFERENCES, TRIGGER, TRUNCATE ON public.admin_audit_log FROM anon;
REVOKE UPDATE, DELETE, REFERENCES, TRIGGER, TRUNCATE ON public.admin_audit_log FROM authenticated;

-- 3) Document immutability pattern
COMMENT ON TABLE public.admin_audit_log IS
  'Immutable audit log for admin actions and LGPD/V4 governance events. RLS pattern: SELECT gated to superadmins (Superadmin can read audit log policy); UPDATE and DELETE blocked via RESTRICTIVE policies (audit_log_no_update + audit_log_no_delete). INSERT happens via SECURITY DEFINER RPCs only. service_role retains technical mutation ability for system-managed retention/anonymization wrappers (admin_anonymize_member, anonymize_inactive_members) — direct DELETE via service_role is reserved for LGPD compliance and must be wrapped in audited SECDEF functions. See docs/strategy/ARM_PILLARS_AUDIT_P107.md §R3 + ARM-8.';

NOTIFY pgrst, 'reload schema';
