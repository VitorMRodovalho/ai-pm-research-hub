-- Migration: 20260805000129_p567_meeting_artifacts_split_grant_revoke
-- Issue: #567 — Security sweep (#564 council): tighten meeting_artifacts write authority + defense-in-depth REVOKEs
-- Refs: #564, PR #565, ADR-0011, GC-162
--
-- Context (grounded LIVE 2026-06-07 against prod ldrfrvwhxsmgaabwmaik):
--   * meeting_artifacts is read via SECDEF RPC (list_meeting_artifacts) and written via SECDEF
--     RPCs (create_meeting_notes / register_showcase / meeting_close). The app does NO direct
--     PostgREST I/O on it — SECDEF runs as table owner and bypasses RLS, so the policies below
--     are pure defense-in-depth against the raw PostgREST/MCP surface. No app regression.
--   * Live `meeting_artifacts_manage` predicate uses rls_can_for_initiative('write', initiative_id)
--     (NOT rls_can_for_tribe as the issue text's stale migration reference states).
--
-- Changes:
--   1) Split the cmd=ALL `meeting_artifacts_manage` (PERMISSIVE, public) into per-command policies.
--      INSERT/UPDATE keep the initiative-write authority; DELETE is restricted to
--      manage_member / superadmin so a tribe-write member (incl. researchers) can no longer
--      bulk-DELETE the artifact history via direct PostgREST. SELECT semantics preserved
--      (managers + initiative-writers could read unpublished artifacts directly).
--   2) Defense-in-depth grant hygiene: REVOKE the residual Supabase auto-grants —
--      anon on meeting_artifacts; anon + authenticated on onboarding_tokens (bearer token) and
--      pmi_video_screenings (PII transcription). Both are rpc_only_deny_all (USING false) today;
--      removing the grants closes the exposure if RLS is ever disabled for maintenance or a 2nd
--      permissive policy is added. Reads remain available via SECDEF RPCs only.
--   3) volunteer_applications_superadmin_write: replace the legacy direct `members.is_superadmin`
--      column check with the canonical V4 `rls_is_superadmin()` helper (behavior-equivalent;
--      picks up future superadmin-logic changes). Authority is NOT expanded.
--
-- Rollback:
--   DROP POLICY meeting_artifacts_manage_read/_insert/_update/_delete; recreate
--     CREATE POLICY meeting_artifacts_manage ON public.meeting_artifacts FOR ALL TO public
--       USING (rls_is_superadmin() OR rls_can('manage_member') OR rls_can_for_initiative('write', initiative_id));
--   GRANT INSERT,UPDATE,DELETE,REFERENCES,TRIGGER,TRUNCATE ON public.meeting_artifacts TO anon; -- (anon had no SELECT pre-migration; grounded live)
--   GRANT TRUNCATE,REFERENCES,TRIGGER ON public.meeting_artifacts TO authenticated;
--   GRANT ALL ON public.onboarding_tokens TO anon, authenticated;
--   GRANT ALL ON public.pmi_video_screenings TO anon, authenticated;
--   DROP POLICY volunteer_applications_superadmin_write; recreate with the inline is_superadmin EXISTS check.

-- ============================================================================
-- 1) meeting_artifacts — split cmd=ALL manage policy into per-command
-- ============================================================================
DROP POLICY IF EXISTS meeting_artifacts_manage ON public.meeting_artifacts;

-- Preserve the read access the ALL policy previously granted (managers + initiative-writers
-- reading unpublished artifacts directly). Defense-in-depth only (app reads via SECDEF RPC).
CREATE POLICY meeting_artifacts_manage_read ON public.meeting_artifacts
  FOR SELECT TO authenticated
  USING (
    rls_is_superadmin()
    OR rls_can('manage_member')
    OR rls_can_for_initiative('write', initiative_id)
  );
-- Note: the pre-existing `meeting_artifacts_select` policy (is_published=true OR superadmin OR
-- rls_can('write')) is intentionally NOT dropped. The two SELECT policies OR together (correct):
-- _select carries the public is_published path; _manage_read adds manage_member + initiative-scoped
-- read. Do NOT delete _select thinking _manage_read superseded it.

CREATE POLICY meeting_artifacts_insert ON public.meeting_artifacts
  FOR INSERT TO authenticated
  WITH CHECK (
    rls_is_superadmin()
    OR rls_can('manage_member')
    OR rls_can_for_initiative('write', initiative_id)
  );

CREATE POLICY meeting_artifacts_update ON public.meeting_artifacts
  FOR UPDATE TO authenticated
  USING (
    rls_is_superadmin()
    OR rls_can('manage_member')
    OR rls_can_for_initiative('write', initiative_id)
  )
  WITH CHECK (
    rls_is_superadmin()
    OR rls_can('manage_member')
    OR rls_can_for_initiative('write', initiative_id)
  );

-- DELETE restricted to org admins — closes the MEDIUM "tribe-write member can bulk-DELETE
-- artifact history" hole. The org-scope RESTRICTIVE policy still ANDs on top.
CREATE POLICY meeting_artifacts_delete ON public.meeting_artifacts
  FOR DELETE TO authenticated
  USING (
    rls_is_superadmin()
    OR rls_can('manage_member')
  );

-- ============================================================================
-- 2) Defense-in-depth grant hygiene — remove residual Supabase auto-grants
-- ============================================================================
-- anon never touches meeting_artifacts (RPC-only reads/writes; SECDEF bypasses RLS).
REVOKE ALL ON public.meeting_artifacts FROM anon;
-- authenticated keeps SELECT/INSERT/UPDATE/DELETE (the per-command policies are the live gate),
-- but the non-DML residuals are stripped: TRUNCATE in particular bypasses RLS entirely (table-level
-- op, not row-gated) so an authenticated grant on it is a latent table-wipe vector. REFERENCES/TRIGGER
-- are never legitimately exercised by an app role either.
REVOKE TRUNCATE, REFERENCES, TRIGGER ON public.meeting_artifacts FROM authenticated;

-- onboarding_tokens.token (bearer credential) + pmi_video_screenings.transcription (PII):
-- rpc_only_deny_all (USING false) blocks today; remove the table grants so a future RLS lapse
-- cannot expose them. Reads happen via SECDEF RPCs (owner context), unaffected by these grants.
REVOKE ALL ON public.onboarding_tokens FROM anon, authenticated;
REVOKE ALL ON public.pmi_video_screenings FROM anon, authenticated;

-- ============================================================================
-- 3) volunteer_applications — V4 helper instead of legacy is_superadmin column check
-- ============================================================================
DROP POLICY IF EXISTS volunteer_applications_superadmin_write ON public.volunteer_applications;
CREATE POLICY volunteer_applications_superadmin_write ON public.volunteer_applications
  FOR ALL TO authenticated
  USING (rls_is_superadmin())
  WITH CHECK (rls_is_superadmin());
