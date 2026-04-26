-- ADR-0027 (Accepted): Governance readers V4 conversion (Opção B)
-- Phase B'' V3→V4 conversion of 3 governance reader fns.
-- See docs/adr/ADR-0027-governance-readers-v4-conversion.md
--
-- PM ratified Q1-Q4 (2026-04-26 p59):
--   Q1 (Opção A/B/C?) — B (reuse rls_is_member + manage_platform)
--   Q2 (preserve observers acesso?) — NÃO (aceitar drift correction)
--   Q3 (criar ratify_governance action separada?) — NÃO agora
--   Q4 (timing?) — p59 mesmo
--
-- Pattern: outer gate uses rls_is_member() (any active authoritative
-- engagement). Inner admin filter uses can_by_member('manage_platform')
-- for sensitive fields (signatories, draft docs, all-CR view).
--
-- Behavior change vs V3:
--   - V3 observer (member_status='observer') with V3 role check could
--     see "approved/implemented" CRs. V4 observer has no engagement
--     authoritative ⇒ rls_is_member() = false ⇒ no access.
--   - Per ADR-0027 Q2 ratify: accepted as drift correction. Observers
--     do not use governance UI in practice.

-- ============================================================
-- 1. Convert get_change_requests
-- ============================================================
DROP FUNCTION IF EXISTS public.get_change_requests(text, text);
CREATE OR REPLACE FUNCTION public.get_change_requests(p_status text, p_cr_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_member_id uuid;
  v_can_manage boolean;
  v_result jsonb;
BEGIN
  IF NOT public.rls_is_member() THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT m.id INTO v_caller_member_id
  FROM public.members m WHERE m.auth_id = auth.uid();
  v_can_manage := public.can_by_member(v_caller_member_id, 'manage_platform');

  SELECT jsonb_agg(cr_row ORDER BY cr_row->>'created_at' DESC) INTO v_result FROM (
    SELECT jsonb_build_object(
      'id', cr.id, 'cr_number', cr.cr_number, 'title', cr.title, 'description', cr.description,
      'cr_type', cr.cr_type, 'status', cr.status, 'priority', cr.priority,
      'impact_level', cr.impact_level, 'impact_description', cr.impact_description,
      'justification', cr.justification, 'proposed_changes', cr.proposed_changes,
      'gc_references', cr.gc_references, 'manual_section_ids', cr.manual_section_ids,
      'manual_version_from', cr.manual_version_from, 'manual_version_to', cr.manual_version_to,
      'requested_by', cr.requested_by, 'requested_by_role', cr.requested_by_role,
      'requested_by_name', rm.name, 'submitted_at', cr.submitted_at,
      'reviewed_by', cr.reviewed_by, 'reviewed_at', cr.reviewed_at, 'review_notes', cr.review_notes,
      'approved_by_members', cr.approved_by_members, 'approved_at', cr.approved_at,
      'implemented_at', cr.implemented_at, 'created_at', cr.created_at
    ) AS cr_row
    FROM public.change_requests cr
    LEFT JOIN public.members rm ON rm.id = cr.requested_by
    WHERE (p_status IS NULL OR cr.status = p_status)
      AND (p_cr_type IS NULL OR cr.cr_type = p_cr_type)
      AND (
        v_can_manage  -- admin tier sees all
        OR cr.status IN ('approved', 'implemented')  -- public-by-design transparency
      )
  ) sub;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_change_requests(text, text) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.get_change_requests(text, text) IS
  'Phase B'' V4 conversion (ADR-0027 Opção B, p59): rls_is_member outer gate + can_by_member(manage_platform) inner admin filter. Was V3 (operational_role/is_superadmin).';

-- ============================================================
-- 2. Convert get_governance_dashboard
-- ============================================================
DROP FUNCTION IF EXISTS public.get_governance_dashboard();
CREATE OR REPLACE FUNCTION public.get_governance_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
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
        'approval_count', (SELECT count(*) FROM public.cr_approvals WHERE cr_id = cr.id AND action = 'approved'),
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
$$;
REVOKE EXECUTE ON FUNCTION public.get_governance_dashboard() FROM PUBLIC, anon;
COMMENT ON FUNCTION public.get_governance_dashboard() IS
  'Phase B'' V4 conversion (ADR-0027 Opção B, p59): rls_is_member outer + sponsor engagement check (kind=sponsor) for can_approve + can_by_member(manage_platform) for superadmin. Was V3 (operational_role=sponsor + is_superadmin).';

-- ============================================================
-- 3. Convert get_governance_documents
-- ============================================================
DROP FUNCTION IF EXISTS public.get_governance_documents(text);
CREATE OR REPLACE FUNCTION public.get_governance_documents(p_doc_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_member_id uuid;
  v_can_manage boolean;
  v_result jsonb;
BEGIN
  IF NOT public.rls_is_member() THEN
    RETURN jsonb_build_object('error', 'authentication_required');
  END IF;

  SELECT m.id INTO v_caller_member_id
  FROM public.members m WHERE m.auth_id = auth.uid();
  v_can_manage := public.can_by_member(v_caller_member_id, 'manage_platform');

  SELECT jsonb_agg(jsonb_build_object(
    'id', gd.id,
    'doc_type', gd.doc_type,
    'title', gd.title,
    'description', gd.description,
    'content', gd.content,
    'version', gd.version,
    'parties', gd.parties,
    'docusign_envelope_id', gd.docusign_envelope_id,
    'signed_at', gd.signed_at,
    'status', gd.status,
    'valid_from', gd.valid_from,
    'exit_notice_days', gd.exit_notice_days,
    'signatories', CASE
      WHEN v_can_manage THEN gd.signatories
      ELSE NULL
    END
  ) ORDER BY gd.status ASC, gd.signed_at DESC) INTO v_result
  FROM public.governance_documents gd
  WHERE (p_doc_type IS NULL OR gd.doc_type = p_doc_type)
    AND (
      gd.status = 'active'
      OR (gd.status = 'draft' AND v_can_manage)
    );

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_governance_documents(text) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.get_governance_documents(text) IS
  'Phase B'' V4 conversion (ADR-0027 Opção B, p59): rls_is_member outer + can_by_member(manage_platform) for signatories field + draft docs visibility. Was V3 (operational_role IN manager/sponsor/chapter_liaison + is_superadmin).';

NOTIFY pgrst, 'reload schema';
