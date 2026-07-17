-- #1397 — Harden change-request review/approve authority (align with 2-of-N manual publication).
--
-- Surfaced by the #1383 Wave 5 governance audit. Governance control-integrity fix (not an
-- anon-exploit: every path is fail-closed for anon and requires a trusted operational role).
--
-- What this migration does (owner decision 2026-07-17, Option A — keep both approval paths;
-- `approved` is a triage state, publication remains the 2-of-N control):
--   1. review_change_request: retire the unilateral `implement` branch. The approved->implemented
--      transition (publishing a Manual version) is done EXCLUSIVELY via the 2-of-N
--      propose_manual_version + confirm_manual_version flow (ADR-0044). Also removes the
--      hardcoded manual_version_to='R3'. (objectives 1 + 4)
--   2. review_change_request: return the PERSISTED status (v_new_status) instead of echoing the
--      action string (request_changes wrote under_review but reported request_changes). (objective 5)
--   3. review_change_request: notify the CR author via requested_by. The live body referenced a
--      non-existent column submitted_by, which raised "record has no field" and rolled back EVERY
--      successful action — the function was entirely non-functional, which masked the implement
--      bypass. Fixing it and retiring implement together keeps the 2-of-N control single-sourced.
--   4. approve_change_request: quorum numerator now draws from the SAME pool as the denominator
--      (active sponsors). It previously counted ALL approvers, so a non-sponsor
--      participate_in_governance_review voter inflated the numerator against the sponsor-only
--      denominator. Auth to VOTE stays V4-broad; only sponsor x sponsor approvals COUNT toward
--      quorum until the governance manual revision authorizes expansion (p179 decision). (objective 3)
--   5. get_cr_approval_status + get_governance_dashboard: align the displayed approval_count to the
--      same sponsor-only pool so the UI "{count} of {needed}" fraction matches the gate. total_votes
--      (dashboard) stays informational (all votes).
--
-- The two approval paths are intentionally kept (Option A): review_change_request drives the review
-- lifecycle; approve_change_request records the sponsor-quorum vote. Both write status='approved',
-- which only makes a CR eligible for the 2-of-N Manual publication.

-- 1) review_change_request — retire implement, fix status label, fix author notification column.
CREATE OR REPLACE FUNCTION public.review_change_request(p_cr_id uuid, p_action text, p_notes text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller record; v_mid uuid; v_cr record; v_new_status text;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id=auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  v_mid := v_caller.id;
  SELECT * INTO v_cr FROM change_requests WHERE id=p_cr_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','CR not found'); END IF;
  -- p178 ADR-0011 inline V4 refactor: top-level authority via can_by_member(manage_platform).
  -- Covers superadmin + manager + deputy_manager + co_gp (per engagement_kind_permissions seed).
  -- p200 ADR-0087: curator V3 designation -> V4 can_by_member('curate_content').
  -- sponsor/chapter_liaison legacy paths preserved as fallback for the review lifecycle only.
  -- #1397: this authority governs the review lifecycle (approve/reject/request_changes/withdraw/
  -- resubmit) only. Publishing a Manual version -- the approved->implemented transition -- is done
  -- EXCLUSIVELY via the 2-of-N propose_manual_version + confirm_manual_version flow (ADR-0044).
  IF NOT can_by_member(v_mid, 'manage_platform') THEN
    IF can_by_member(v_mid, 'curate_content') THEN
      IF v_cr.cr_type='structural' AND p_action='approve' THEN
        RETURN jsonb_build_object('error','Curators cannot approve structural CRs'); END IF;
    ELSIF v_caller.operational_role IN ('sponsor','chapter_liaison') THEN NULL;
    ELSE RETURN jsonb_build_object('error','Unauthorized'); END IF;
  END IF;
  IF p_action='approve' THEN
    UPDATE change_requests SET status='approved',reviewed_by=v_mid,reviewed_at=now(),
      review_notes=COALESCE(p_notes,review_notes),
      approved_by_members=array_append(COALESCE(approved_by_members,'{}'),v_mid),
      approved_at=now(),updated_at=now() WHERE id=p_cr_id;
    v_new_status := 'approved';
  ELSIF p_action='reject' THEN
    UPDATE change_requests SET status='rejected',reviewed_by=v_mid,reviewed_at=now(),
      review_notes=p_notes,updated_at=now() WHERE id=p_cr_id;
    v_new_status := 'rejected';
  ELSIF p_action='request_changes' THEN
    UPDATE change_requests SET status='under_review',reviewed_by=v_mid,reviewed_at=now(),
      review_notes=p_notes,updated_at=now() WHERE id=p_cr_id;
    v_new_status := 'under_review';
  ELSIF p_action='implement' THEN
    -- #1397: unilateral implement retired. approved->implemented happens ONLY via the 2-of-N
    -- manual-version flow (propose_manual_version + confirm_manual_version, ADR-0044), which
    -- publishes the governance_document and locks manual_version_from/to across all approved CRs.
    RETURN jsonb_build_object('error','implement_via_2_of_n',
      'message','Implementar CRs aprovados e feito publicando uma versao do Manual via 2-of-N: propose_manual_version + confirm_manual_version (ADR-0044).');
  ELSIF p_action = 'withdraw' THEN
    IF v_cr.status NOT IN ('draft', 'submitted', 'under_review') THEN
      RETURN jsonb_build_object('error', 'Cannot withdraw approved/implemented CR'); END IF;
    UPDATE change_requests SET status = 'withdrawn', review_notes = COALESCE(p_notes, review_notes), updated_at = now() WHERE id = p_cr_id;
    v_new_status := 'withdrawn';
  ELSIF p_action = 'resubmit' THEN
    IF v_cr.status != 'under_review' THEN
      RETURN jsonb_build_object('error', 'Can only resubmit CRs under review'); END IF;
    UPDATE change_requests SET status = 'submitted', submitted_at = now(), review_notes = COALESCE(p_notes, review_notes), updated_at = now() WHERE id = p_cr_id;
    v_new_status := 'submitted';
  ELSE RETURN jsonb_build_object('error','Invalid action'); END IF;

  -- #1397: notify the CR author. The author column is requested_by; the prior reference to a
  -- non-existent submitted_by column raised at runtime and rolled back every successful action.
  -- The trailing NULL::text pins the 7-arg (…, p_actor_id, p_body) overload of create_notification
  -- (a bare 6-arg call is ambiguous against the 6-arg overload once this line is actually reached).
  IF v_cr.requested_by IS NOT NULL AND v_cr.requested_by != v_mid THEN
    PERFORM create_notification(v_cr.requested_by, 'cr_status_changed', 'change_request', p_cr_id, v_cr.title, v_mid, NULL::text);
  END IF;

  RETURN jsonb_build_object('success',true,'cr_number',v_cr.cr_number,'new_status',v_new_status);
END;
$function$;

-- 2) approve_change_request — sponsor-only quorum numerator (align with sponsor-only denominator).
CREATE OR REPLACE FUNCTION public.approve_change_request(p_cr_id uuid, p_action text, p_comment text DEFAULT NULL::text, p_ip inet DEFAULT NULL::inet, p_user_agent text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_member_name text;
  v_cr record;
  v_hash text;
  v_total_sponsors int;
  v_total_approvals int;
  v_quorum_needed int;
  v_quorum_met boolean;
BEGIN
  SELECT id, name
  INTO v_member_id, v_member_name
  FROM members WHERE auth_id = auth.uid();

  IF v_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- p179 ADR-0011 V4 refactor: top-level authority via V4 can_by_member.
  -- Covers sponsor × sponsor (seeded p179), volunteer × {co_gp, deputy_manager,
  -- manager}, observer × {curator, reviewer}, chapter_board × liaison,
  -- external_reviewer × reviewer. Superadmin auto-passes via can() chain.
  IF NOT can_by_member(v_member_id, 'participate_in_governance_review') THEN
    RETURN jsonb_build_object('error', 'not_authorized');
  END IF;

  IF p_action NOT IN ('approved', 'rejected', 'abstained') THEN
    RETURN jsonb_build_object('error', 'invalid_action');
  END IF;

  SELECT * INTO v_cr FROM change_requests WHERE id = p_cr_id;
  IF v_cr IS NULL THEN
    RETURN jsonb_build_object('error', 'cr_not_found');
  END IF;

  IF v_cr.status NOT IN ('submitted', 'proposed', 'under_review', 'open', 'pending_review', 'in_review') THEN
    RETURN jsonb_build_object('error', 'cr_not_approvable', 'status', v_cr.status);
  END IF;

  v_hash := encode(sha256(convert_to(
    p_cr_id::text || v_member_id::text || p_action || now()::text || 'nucleo-ia-governance-salt', 'UTF8'
  )), 'hex');

  INSERT INTO cr_approvals (cr_id, member_id, action, comment, signature_hash, signed_ip, signed_user_agent)
  VALUES (p_cr_id, v_member_id, p_action, p_comment, v_hash, p_ip, p_user_agent)
  ON CONFLICT (cr_id, member_id)
  DO UPDATE SET action = EXCLUDED.action, comment = EXCLUDED.comment,
    signature_hash = EXCLUDED.signature_hash, signed_ip = EXCLUDED.signed_ip,
    signed_user_agent = EXCLUDED.signed_user_agent, created_at = now();

  UPDATE change_requests
  SET approved_by_members = (
    SELECT array_agg(DISTINCT member_id) FROM cr_approvals WHERE cr_id = p_cr_id AND action = 'approved'
  ),
  status = CASE
    WHEN status IN ('submitted', 'open', 'pending_review') THEN 'under_review'
    ELSE status
  END
  WHERE id = p_cr_id;

  -- p179 PM decision (2026-05-17): quorum count remains V3 sponsor-only until
  -- the governance manual revision formally authorizes expansion to the
  -- broader V4 voter pool (curators/reviewers/etc.). Auth gate is V4
  -- (can_by_member above) — V4 capable members can vote, but only sponsor ×
  -- sponsor engagements count toward quorum denominator. When manual v3
  -- revision lands, swap to `can_by_member(m.id, 'participate_in_governance_review')`.
  SELECT count(*) INTO v_total_sponsors
  FROM members m
  WHERE m.is_active = true
    AND m.operational_role = 'sponsor';
  -- #1397: numerator must draw from the SAME pool as the denominator. Previously counted ALL
  -- approvers, so a non-sponsor participate_in_governance_review voter inflated the numerator
  -- against the sponsor-only denominator (quorum could read "met" without sponsor consensus).
  SELECT count(*) INTO v_total_approvals
  FROM cr_approvals ca
  JOIN members m ON m.id = ca.member_id
  WHERE ca.cr_id = p_cr_id AND ca.action = 'approved'
    AND m.is_active = true AND m.operational_role = 'sponsor';

  v_quorum_needed := GREATEST(CEIL(v_total_sponsors::numeric * 3 / 5), 1);
  v_quorum_met := v_total_approvals >= v_quorum_needed;

  IF v_quorum_met THEN
    UPDATE change_requests SET status = 'approved', approved_at = now()
    WHERE id = p_cr_id AND status != 'approved';

    INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
    VALUES (v_member_id, 'cr_approved_quorum', 'change_request', p_cr_id,
      jsonb_build_object('cr_number', v_cr.cr_number, 'approvals', v_total_approvals, 'quorum', v_quorum_needed));

    -- p179 ADR-0011 V4: notify everyone with governance review capability + platform admins.
    INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id)
    SELECT m.id, 'governance_cr_approved',
      v_cr.cr_number || ' aprovado por quorum!',
      v_cr.title || ' aprovado com ' || v_total_approvals || '/' || v_quorum_needed || ' votos.',
      '/governance', 'change_request', p_cr_id
    FROM members m
    WHERE m.is_active = true
      AND (can_by_member(m.id, 'participate_in_governance_review')
           OR can_by_member(m.id, 'manage_platform'));
  ELSE
    -- p179 ADR-0011 V4: notify other governance reviewers about the vote.
    INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id)
    SELECT m.id, 'governance_cr_vote',
      v_cr.cr_number || ': ' || v_member_name || ' votou ' || p_action,
      v_cr.title, '/governance', 'change_request', p_cr_id
    FROM members m
    WHERE m.is_active = true
      AND m.id != v_member_id
      AND can_by_member(m.id, 'participate_in_governance_review');
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'action', p_action, 'signature_hash', v_hash,
    'approvals', v_total_approvals, 'quorum_needed', v_quorum_needed,
    'quorum_met', v_quorum_met,
    'cr_status', CASE WHEN v_quorum_met THEN 'approved' ELSE 'under_review' END
  );
END;
$function$;

-- 3) get_cr_approval_status — display approval_count uses the sponsor-only quorum pool.
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

-- 4) get_governance_dashboard — display approval_count uses the sponsor-only quorum pool
--    (total_votes stays informational: all votes). search_path='' so all names are qualified.
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
  IF NOT public.rls_is_member() THEN
    RETURN jsonb_build_object('error', 'authentication_required');
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

NOTIFY pgrst, 'reload schema';
