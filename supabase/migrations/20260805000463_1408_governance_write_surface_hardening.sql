-- #1408: Harden governance write-table surface to SECDEF-RPC-only + gate CR approval reads.
-- Refs #1408 #1397 #1383
--
-- Grounded live (2026-07-17) before applying:
--   * anon + authenticated both hold INSERT/UPDATE/DELETE/TRUNCATE on change_requests,
--     cr_approvals, governance_documents; authenticated also on pending_manual_version_approvals.
--   * Reachable write residues: change_requests INSERT (permissive "Auth create CRs", any
--     authenticated, no status lock) and cr_approvals INSERT (permissive for superadmin/
--     manage_partner). All UPDATE/DELETE are already fail-closed (RESTRICTIVE org-scope, no
--     permissive U/D policy; governance_documents carries explicit deny policies).
--   * Every legitimate write goes through a SECURITY DEFINER RPC; zero direct-table write
--     call sites exist in src/ or the edge functions.
--
-- Item 3 of #1408 (structural-CR approval asymmetry in review_change_request) is intentionally
-- NOT changed here: post-#1397 an 'approve' is triage only (publication is the 2-of-N
-- confirm_manual_version flow), and sponsors hold ratification authority (ADR-0016). The
-- asymmetry is documented as intentional on #1408; no code change.

-- Item 1 -- revoke the unused/residual DML, forcing every write through the SECDEF RPCs.
-- SECDEF functions run as the definer and keep their own privileges, so the RPCs are unaffected.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE
  public.change_requests,
  public.cr_approvals,
  public.governance_documents,
  public.pending_manual_version_approvals
FROM anon, authenticated;

-- Item 2a -- tighten the CR-deliberation read. cr_approvals.SELECT was USING(true), so any
-- authenticated principal could read sponsor votes/comments directly via PostgREST. Restrict
-- to authoritative members (matching the cr_read_members policy on change_requests). The app
-- reads cr_approvals only through get_cr_approval_status (no direct .from('cr_approvals')).
ALTER POLICY cr_approvals_read_authenticated ON public.cr_approvals
  USING (rls_is_authoritative_member());

-- Item 2b -- add the same caller gate inside the SECDEF RPC (defense in depth: SECDEF bypasses
-- RLS, so the policy above does not cover it). Body is otherwise byte-identical to the live
-- definition captured via pg_get_functiondef.
CREATE OR REPLACE FUNCTION public.get_cr_approval_status(p_cr_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_total_sponsors int;
  v_quorum_needed int;
  result jsonb;
BEGIN
  -- #1408: gate CR deliberation reads (sponsor names, votes, comments) to authoritative
  -- members, matching the cr_read_members SELECT policy on change_requests. Previously any
  -- authenticated principal (including a ghost with no members row) could read this.
  IF NOT rls_is_authoritative_member() THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT count(*) INTO v_total_sponsors FROM members WHERE operational_role = 'sponsor' AND is_active = true;
  v_quorum_needed := GREATEST(CEIL(v_total_sponsors::numeric * 3 / 5), 1);

  SELECT jsonb_build_object(
    'cr_id', p_cr_id,
    'total_sponsors', v_total_sponsors,
    'quorum_needed', v_quorum_needed,
    -- #1397: sponsor-only count, matching the quorum numerator in approve_change_request.
    'approval_count', (SELECT count(*) FROM cr_approvals a JOIN members m ON m.id = a.member_id
      WHERE a.cr_id = p_cr_id AND a.action = 'approved' AND m.is_active = true AND m.operational_role = 'sponsor'),
    'sponsors', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'member_id', m.id,
        'name', m.name,
        'has_voted', EXISTS (SELECT 1 FROM cr_approvals a WHERE a.cr_id = p_cr_id AND a.member_id = m.id),
        'vote', (SELECT a.action FROM cr_approvals a WHERE a.cr_id = p_cr_id AND a.member_id = m.id),
        'comment', (SELECT a.comment FROM cr_approvals a WHERE a.cr_id = p_cr_id AND a.member_id = m.id),
        'signed_at', (SELECT a.created_at FROM cr_approvals a WHERE a.cr_id = p_cr_id AND a.member_id = m.id)
      ) ORDER BY m.name)
      FROM members m
      WHERE m.operational_role = 'sponsor' AND m.is_active = true
    ), '[]'::jsonb)
  ) INTO result;

  RETURN result;
END;
$function$;
