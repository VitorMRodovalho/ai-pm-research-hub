-- p209 / issue #226 Phase A — fix storage.objects.selection_resumes_read_view_pii
-- to use rls_can() wrapper instead of can(auth.uid(), 'view_pii') directly.
--
-- Problem (BUG-225.A, surfaced by tests/contracts/rpc-migration-coverage.test.mjs:494):
--
-- The policy referenced `can(auth.uid(), 'view_pii')` in its USING clause.
-- Two distinct defects, either of which makes the policy fail silently:
--
--   1. Type mismatch — `can(p_person_id uuid, p_action text, ...)` expects
--      a persons.id UUID. `auth.uid()` returns the auth.users.id (member.auth_id),
--      which is NOT persons.id. The lookup inside `can()` would never resolve
--      to a real authority chain.
--
--   2. EXECUTE privilege — `can()` is SECURITY DEFINER and REVOKE'd from
--      `authenticated` (and `anon`). It's only callable by `service_role`.
--      When PostgREST evaluates the policy as `authenticated`, the call
--      raises a permission error, which RLS swallows by treating the row as
--      filtered out. The bucket appears empty to authenticated users.
--
-- Fix: replace the direct `can()` call with `rls_can('view_pii')`, the
-- SECURITY DEFINER wrapper that:
--   - is GRANTed EXECUTE TO authenticated + anon
--   - internally resolves auth.uid() → persons.id and calls can()
--
-- This is the same pattern adopted by all post-V4 policies (see ADR-0007 + the
-- 14 existing public policies that use can_by_member()/rls_can()).
--
-- Behavioural change:
--   - Before: bucket appeared empty for ALL authenticated users (silent fail)
--   - After: members with view_pii authority (via engagement_kind_permissions)
--     see selection resumes; others get 0 rows (correct RLS behavior)
--
-- Rollback (only if a downstream policy regression appears):
--   DROP POLICY IF EXISTS selection_resumes_read_view_pii ON storage.objects;
--   CREATE POLICY selection_resumes_read_view_pii ON storage.objects
--     FOR SELECT TO authenticated
--     USING (bucket_id = 'selection-resumes' AND can(auth.uid(), 'view_pii'));
--   -- Note: rollback restores the BROKEN pre-fix state. Only use if the new
--   -- wrapper itself fails (e.g. rls_can dropped/renamed). Don't use rollback
--   -- to relax authority — that's a separate authority decision.

DROP POLICY IF EXISTS selection_resumes_read_view_pii ON storage.objects;

CREATE POLICY selection_resumes_read_view_pii ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'selection-resumes'
    AND rls_can('view_pii')
  );

COMMENT ON POLICY selection_resumes_read_view_pii ON storage.objects IS
  'Read access to selection-resumes bucket gated by view_pii capability. Uses rls_can() wrapper (GRANT EXECUTE TO authenticated) instead of can() (service_role only). See p209/#226 Phase A.';

-- Out-of-band Dashboard application (MCP service_role cannot ALTER storage.objects):
-- since this file is applied via Supabase Dashboard SQL editor rather than
-- `supabase db push`, the schema_migrations registry insert must happen in the
-- same SQL block. Idempotent via ON CONFLICT for safety against double-paste.
-- See code-reviewer PR #228 HIGH amendment (operational risk if PM forgets to
-- paste the INSERT block separately).
INSERT INTO supabase_migrations.schema_migrations (version, name)
VALUES ('20260802000000', 'p209_issue_226_phase_a_storage_policy_use_rls_can')
ON CONFLICT (version) DO NOTHING;

NOTIFY pgrst, 'reload schema';
