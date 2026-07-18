-- #1419: align get_governance_dashboard read gate to rls_is_authoritative_member().
--
-- Context: #1408 (defense-in-depth of #1397) narrowed the CR *approval* read surface
-- (get_cr_approval_status + the cr_approvals SELECT policy) to rls_is_authoritative_member().
-- get_governance_dashboard was still gated on the broad rls_is_member() (row-existence only,
-- no is_active filter), so any member row — including inactive/offboarded members and
-- pre-onboarding guests — could read the FULL body of every pending change request
-- (title/description/justification/proposed_changes/impact) plus the aggregate quorum stats.
-- No third-party vote or PII leaked (only my_vote + aggregate counts), but the *content* of
-- governance proposals is the same class of data #1408 tightened. This is the RPC-body analog
-- of the policy sweep in 20260805000246_rls_phase2_authoritative_member.sql, which left function
-- bodies untouched.
--
-- Change: swap the single guard rls_is_member() -> rls_is_authoritative_member() and return a
-- distinct 'not_authorized' code (the caller is authenticated but lacks a real operational_role),
-- so the frontend can show an access message instead of a misleading all-zeros dashboard.
-- The write path (approve_change_request) was already authority-gated (#1397); this closes the
-- read↔write asymmetry. Body is otherwise byte-identical to the live definition.
--
-- Note: annotations/gates here are the server SSOT; the frontend defers to this error rather
-- than duplicating the authoritative predicate in TS.

CREATE OR REPLACE FUNCTION public.get_governance_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_member_id uuid;
  v_member_name text;
  v_can_approve boolean;
  v_total_sponsors int;
  v_quorum_needed int;
  result jsonb;
BEGIN
  IF NOT public.rls_is_authoritative_member() THEN
    RETURN jsonb_build_object('error', 'not_authorized');
  END IF;

  SELECT id, name INTO v_member_id, v_member_name
  FROM public.members WHERE auth_id = auth.uid();

  -- can_approve: V4 sponsor authority OR manage_platform (superadmin path)
  -- Sponsor (kind='sponsor') is the canonical ratification authority per ADR-0016
  v_can_approve := EXISTS (
    SELECT 1 FROM public.auth_engagements ae
    WHERE ae.person_id = (SELECT person_id FROM public.persons WHERE legacy_member_id = v_member_id)
      AND ae.kind = 'sponsor' AND ae.is_authoritative = true
  ) OR public.can_by_member(v_member_id, 'manage_platform');

  SELECT count(*) INTO v_total_sponsors
  FROM public.members WHERE operational_role = 'sponsor' AND is_active = true;
  v_quorum_needed := GREATEST(CEIL(v_total_sponsors::numeric * 3 / 5), 1);

  SELECT jsonb_build_object(
    'member_name', v_member_name,
    'is_sponsor', EXISTS (
      SELECT 1 FROM public.auth_engagements ae
      WHERE ae.person_id = (SELECT person_id FROM public.persons WHERE legacy_member_id = v_member_id)
        AND ae.kind = 'sponsor' AND ae.is_authoritative = true
    ),
    'is_superadmin', public.can_by_member(v_member_id, 'manage_platform'),
    'can_approve', v_can_approve,
    'total_sponsors', v_total_sponsors,
    'quorum_needed', v_quorum_needed,
    'stats', jsonb_build_object(
      'total_crs', (SELECT count(*) FROM public.change_requests WHERE status NOT IN ('withdrawn', 'cancelled')),
      'pending', (SELECT count(*) FROM public.change_requests WHERE status IN ('submitted', 'proposed', 'under_review', 'open', 'pending_review', 'in_review')),
      'approved', (SELECT count(*) FROM public.change_requests WHERE status = 'approved'),
      'implemented', (SELECT count(*) FROM public.change_requests WHERE status = 'implemented'),
      'rejected', (SELECT count(*) FROM public.change_requests WHERE status = 'rejected')
    ),
    'pending_crs', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', cr.id, 'cr_number', cr.cr_number, 'title', cr.title,
        'category', cr.category, 'priority', cr.priority, 'status', cr.status,
        'description', cr.description, 'justification', cr.justification,
        'proposed_changes', cr.proposed_changes,
        'impact_level', cr.impact_level, 'impact_description', cr.impact_description,
        'submitted_at', cr.submitted_at,
        'my_vote', (SELECT action FROM public.cr_approvals WHERE cr_id = cr.id AND member_id = v_member_id),
        -- #1397: sponsor-only count, matching the quorum numerator in approve_change_request.
        'approval_count', (SELECT count(*) FROM public.cr_approvals a JOIN public.members m ON m.id = a.member_id
          WHERE a.cr_id = cr.id AND a.action = 'approved' AND m.is_active = true AND m.operational_role = 'sponsor'),
        'total_votes', (SELECT count(*) FROM public.cr_approvals WHERE cr_id = cr.id)
      ) ORDER BY
        CASE cr.priority WHEN 'high' THEN 1 WHEN 'medium' THEN 2 WHEN 'low' THEN 3 ELSE 4 END,
        cr.cr_number
      )
      FROM public.change_requests cr
      WHERE cr.status IN ('submitted', 'proposed', 'under_review', 'open', 'pending_review', 'in_review')
    ), '[]'::jsonb),
    'recent_approved', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', cr.id, 'cr_number', cr.cr_number, 'title', cr.title,
        'category', cr.category, 'approved_at', cr.approved_at
      ) ORDER BY cr.approved_at DESC NULLS LAST)
      FROM (SELECT * FROM public.change_requests WHERE status = 'approved' LIMIT 10) cr
    ), '[]'::jsonb)
  ) INTO result;

  RETURN result;
END;
$function$;
