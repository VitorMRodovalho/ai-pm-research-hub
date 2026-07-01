-- #987 follow-up (#1011): curation_review_log's object-level grants left `anon` holding
-- DELETE / INSERT / REFERENCES / TRIGGER / TRUNCATE / UPDATE (the Supabase default GRANT to
-- anon on new public tables). The reachable writes are ALREADY denied by RLS —
--   * curation_review_log_no_direct_select — SELECT USING (false), deny-all (#987 PR-0);
--   * curation_review_log_write — INSERT restricted to `authenticated` WITH CHECK
--     (superadmin / manage_member / write_board);
--   * no UPDATE/DELETE policy → denied for everyone;
--   * PostgREST enforces RLS, and TRUNCATE is not exposed via PostgREST —
-- so the anon grant is inert for any reachable operation. This REVOKE closes the
-- defense-in-depth gap flagged at the #987 close: an internal curation audit log must grant
-- anon nothing. `authenticated` (RLS-gated writes) and `service_role` are left untouched.
-- Grounded live 2026-07-01: anon held {DELETE, INSERT, REFERENCES, TRIGGER, TRUNCATE, UPDATE}.
REVOKE ALL ON public.curation_review_log FROM anon;

NOTIFY pgrst, 'reload schema';
