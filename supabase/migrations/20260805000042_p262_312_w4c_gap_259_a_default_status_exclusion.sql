-- WHAT: Wave 1b leaf #312-W4c (p262 — #379 SHIPS, GAP-259.A close) — list_governance_library
-- default-status exclusion. Currently RPC returns all docs matching visibility predicate
-- regardless of status; STATUS_FILTER_OPTIONS dropdown in GovernanceLibrary.tsx hides 4 statuses
-- but unfiltered call leaks them. After p261/p262 the Frontiers fixture is in `draft`; without
-- this fix, an active member browsing /governance/documents would see it.
--
-- WHY: p259 PM-ratified Option (a) + p262 PM #379 prompt + p262 PM ratification of 4-status
-- default include set: biblioteca membro represents docs consultaveis/vigentes, NOT intake/review
-- queue. Member library must show only 'active' + 'approved' + 'under_review' + 'superseded'
-- by default; explicit p_filters.status override remains available for admin/audit context.
--
-- SPEC: p259 evidence doc + p260 audit doc §10.1 + PM #379 prompt + Option A ratification.
--
-- SCOPE LOCK: 1 RPC body change (single new WHERE clause line). No new tables, columns, RLS,
-- invariants. STATUS_FILTER_OPTIONS dropdown in GovernanceLibrary.tsx remains unchanged
-- (already lists 4 statuses matching new default).
--
-- ROLLBACK: CREATE OR REPLACE FUNCTION public.list_governance_library(jsonb DEFAULT '{}'::jsonb)
-- with body equal to live state pre-p262.W4c (no v_filter_status IS NOT NULL OR clause).
--
-- INVARIANTS: No change. V'_prime continues to report violation_count=0 (RPC is a read helper,
-- doesn't touch governed table state). The Frontiers fixture is now hidden from member library
-- default but its underlying row is unchanged.
--
-- CROSS-REF: #312 audit umbrella + #315 Governance Documents v1 + #96 Frontiers + #379
-- (this child) + #378 (predecessor sequence 2/7) + #377 (sequence 1/7) + p259 GAP-259.A
-- PM Option (a) ratification + p262 PM #379 4-status confirm.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.list_governance_library(p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_member_id uuid;
  v_is_admin boolean;
  v_is_platform_admin boolean;
  v_filter_doc_type text;
  v_filter_status text;
  v_result jsonb;
BEGIN
  -- Active membership gate
  SELECT id INTO v_caller_member_id
  FROM public.members
  WHERE auth_id = auth.uid() AND is_active = true
  LIMIT 1;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no active member record' USING ERRCODE='42501';
  END IF;

  v_is_admin          := public.can_by_member(v_caller_member_id, 'manage_member');
  v_is_platform_admin := public.can_by_member(v_caller_member_id, 'manage_platform');

  v_filter_doc_type := nullif(p_filters->>'doc_type', '');
  v_filter_status   := nullif(p_filters->>'status', '');

  -- Build result jsonb. P0-Q8 FORWARD-DEFENSE: response shape NEVER includes
  -- file_id, drive_url, content, or pdf_url — those go through a separate
  -- artifact-handle resolver (Wave 5).
  SELECT jsonb_build_object(
    'documents', COALESCE(jsonb_agg(d ORDER BY d->>'title'), '[]'::jsonb),
    'total', count(*)
  )
  INTO v_result
  FROM (
    SELECT jsonb_build_object(
      'id', gd.id,
      'title', gd.title,
      'description', gd.description,
      'doc_type', gd.doc_type,
      'status', gd.status,
      'visibility_class', gd.visibility_class,
      'acknowledgement_mode', gd.acknowledgement_mode,
      'effective_from', gd.effective_from,
      'effective_until', gd.effective_until,
      'approved_at', gd.approved_at,
      'current_ratified_version_id', gd.current_ratified_version_id,
      'current_version_id', gd.current_version_id
    ) AS d
    FROM public.governance_documents gd
    WHERE
      (v_filter_doc_type IS NULL OR gd.doc_type = v_filter_doc_type)
      AND (v_filter_status IS NULL OR gd.status = v_filter_status)
      AND (v_filter_status IS NOT NULL OR gd.status IN ('active','approved','under_review','superseded'))
      AND gd.visibility_class IS NOT NULL
      AND (
        gd.visibility_class = 'public'
        OR gd.visibility_class = 'active_members'
        OR (gd.visibility_class = 'legal_scoped' AND (
            v_is_admin
            OR EXISTS (
              SELECT 1 FROM public.member_document_signatures mds
              WHERE mds.member_id = v_caller_member_id
                AND mds.document_id = gd.id
                AND mds.is_current = true
            )))
        OR (gd.visibility_class = 'admin_only' AND v_is_admin)
        OR (gd.visibility_class = 'audit_restricted' AND v_is_platform_admin)
      )
  ) sub;

  RETURN COALESCE(v_result, jsonb_build_object('documents', '[]'::jsonb, 'total', 0));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.list_governance_library(jsonb) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.list_governance_library(jsonb) TO authenticated;

NOTIFY pgrst, 'reload schema';
