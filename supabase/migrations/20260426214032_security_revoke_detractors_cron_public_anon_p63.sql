-- Security hardening (p63 follow-up): REVOKE PUBLIC + anon EXECUTE on
-- detect_and_notify_detractors_cron. Discovered during Pacote J/K audit:
-- fn is SECDEF with NO top-level auth gate, ACL grants =X/postgres (PUBLIC).
-- ANY caller (including anon) could trigger member iteration + notification
-- inserts. Defense-in-depth REVOKE applied immediately.
--
-- Full V4 conversion (proper gate + service-role bypass for cron compat)
-- deferred to service-role-bypass adapter pattern ADR (~29 fns).
--
-- Current state:
--   pg_cron: NOT scheduled (verified pre-apply)
--   Frontend callsites: NONE (only database.gen.ts types)
--   Current ACL: =X/postgres, postgres=X/postgres, service_role=X/postgres
--   Post-REVOKE: postgres=X/postgres, service_role=X/postgres (cron-safe)

REVOKE EXECUTE ON FUNCTION public.detect_and_notify_detractors_cron() FROM PUBLIC, anon;

COMMENT ON FUNCTION public.detect_and_notify_detractors_cron() IS
  'Cron orchestrator for attendance detractor detection. Security p63: REVOKE PUBLIC+anon (no top-level auth gate; full V4 gate deferred to service-role-bypass adapter pattern ADR). Currently NOT scheduled in pg_cron — may be invoked manually by service_role or external scheduler.';

NOTIFY pgrst, 'reload schema';
