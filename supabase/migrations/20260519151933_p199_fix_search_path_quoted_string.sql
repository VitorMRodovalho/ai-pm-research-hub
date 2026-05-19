-- p199 BUG-199.A: 4 functions had `SET search_path = 'public, pg_temp'`
-- (single quoted string treated as ONE schema literally named "public, pg_temp")
-- instead of `SET search_path = public, pg_temp` (list of two schemas).
--
-- Symptom: function crashed with `42P01 relation "<table>" does not exist`
-- for any caller that reached unqualified table references in the body.
-- For admin_get_anomaly_report, this surfaced as PostgREST 404 on the
-- /admin/data-health page (only triggered after the auth gate passed,
-- which is why service_role smoke tests missed it since `auth.uid()` IS NULL
-- short-circuits to the Unauthorized branch before reaching unqualified refs).
--
-- History:
--   - p52 (20260423040000_harden_function_search_path.sql) correctly set
--     `SET search_path = public, pg_temp` via ALTER FUNCTION
--   - p60 (20260426190940_phase_bpp_pacote_h_admin_exec_8_fns_p60.sql)
--     CREATE OR REPLACE with the quoted form, silently overriding p52
--   - Bug has been live for ~3 weeks until p199 user report
--
-- Rollback: re-apply quoted form (not recommended — it's the bug).
ALTER FUNCTION public.admin_get_anomaly_report() SET search_path = public, pg_temp;
ALTER FUNCTION public.exec_chapter_comparison() SET search_path = public, pg_temp;
ALTER FUNCTION public.platform_activity_summary() SET search_path = public, pg_temp;
ALTER FUNCTION public.get_onboarding_dashboard() SET search_path = public, pg_temp;
