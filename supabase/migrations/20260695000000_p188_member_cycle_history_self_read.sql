-- p188 GAP-181.B: enable authenticated members to read own cycle history
--
-- Rollback: DROP POLICY mch_self_read ON public.member_cycle_history;
--           (Reverts to pre-fix state: only mch_superadmin_write covers SELECT
--            → non-superadmin members lose self-read access again. Acceptable
--            mitigation if a security review later requires more restrictive
--            scope; otherwise prefer ALTER POLICY over DROP+CREATE.)
--
-- Background: member_cycle_history had only the mch_superadmin_write policy
-- (USING rls_is_superadmin(), polcmd=ALL — covers SELECT but only for
-- superadmins). Authenticated members hold GRANT SELECT but RLS blocked
-- every non-superadmin read.
--
-- Frontend impact (pre-fix, latent):
--   - gamification.astro:1012 — sb.from('member_cycle_history').select('cycle_code').eq('member_id', MEMBER.id)
--   - profile.astro:367 — sb.from('member_cycle_history').select('*').eq('member_id', MEMBER.id).order('cycle_start', ...)
-- Both filter to self-scope via .eq() at query time, but PostgREST ran the
-- filter AFTER RLS denial — non-superadmin members got empty arrays silently.
-- Profile journey panel + gamification cycle-count check both rendered
-- "0 cycles" instead of the actual member history (pre-existing bug since
-- the table was defined; not regressed by p181 V4 swap).
--
-- Scope decision: self-only (strict). The notes column may contain
-- admin-authored context, so we keep visibility tight rather than mirroring
-- course_progress's all-members read pattern. Cross-member visibility
-- remains gated to mch_superadmin_write (already covers SELECT via
-- polcmd=ALL — superadmins continue to read across all members).
--
-- Pre-fix smoke (p188 boot, MCP execute_sql JWT-simulated as Sarah,
-- non-superadmin, 4 history rows): sarah_own_filter = 0 rows. Confirms gap.
-- Post-fix smoke (same JWT): sarah_total_visible = 4 (own), sarah_sees_antonios = 0.

CREATE POLICY mch_self_read ON public.member_cycle_history
FOR SELECT TO authenticated
USING (
  member_id IN (SELECT id FROM public.members WHERE auth_id = auth.uid())
);

COMMENT ON POLICY mch_self_read ON public.member_cycle_history IS
  'p188 GAP-181.B: members may SELECT own member_cycle_history rows '
  '(member_id maps to auth.uid() via members.auth_id). Strict self-scope — '
  'notes column may contain admin-authored context. Cross-member visibility '
  'remains gated to mch_superadmin_write (polcmd=ALL covers SELECT).';
