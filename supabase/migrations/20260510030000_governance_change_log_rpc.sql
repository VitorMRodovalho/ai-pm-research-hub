-- =============================================================================
-- get_governance_change_log — unified compliance timeline
-- =============================================================================
-- Issue: #85 Onda B — unified event feed para compliance/audit
-- Context: p41 shipped PII logging + governance workflow wrappers. LGPD/audit
--   callers (DPO, auditor fiscal) precisam de single chronological feed que
--   combina multiple sources sem N queries.
--
-- Aggregates from 6 source tables, emitting a canonical event shape:
--   1. change_requests — submitted, approved, reviewed, implemented
--   2. document_versions — authored, locked
--   3. approval_chains — opened, approved, activated, closed
--   4. approval_signoffs — signature recorded
--   5. pii_access_log — PII read (LGPD Art. 37)
--   6. admin_audit_log — admin actions
--
-- Auth: SECURITY DEFINER. Requires `view_pii` authority (DPO/admin scope).
-- Non-privileged members see only events where they are actor OR target.
--
-- No schema changes. Additive RPC-only.
-- Rollback: DROP FUNCTION on both.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_governance_change_log(
  p_since timestamptz DEFAULT NULL,
  p_limit int DEFAULT 200
)
RETURNS TABLE(
  event_time timestamptz,
  event_source text,
  event_kind text,
  actor_id uuid,
  actor_name text,
  target_type text,
  target_id uuid,
  target_label text,
  payload jsonb
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_member_id uuid;
  v_is_privileged boolean;
  v_since timestamptz;
  v_limit int;
BEGIN
  SELECT m.id INTO v_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_is_privileged := public.can_by_member(v_member_id, 'view_pii');
  v_since := COALESCE(p_since, now() - interval '90 days');
  v_limit := GREATEST(1, LEAST(COALESCE(p_limit, 200), 1000));

  RETURN QUERY
  WITH events AS (
    -- change_request submitted
    SELECT
      cr.submitted_at AS event_time,
      'change_request'::text AS event_source,
      'cr_submitted'::text AS event_kind,
      cr.requested_by AS actor_id,
      am.name AS actor_name,
      'change_request'::text AS target_type,
      cr.id AS target_id,
      ('CR#' || cr.cr_number || ' — ' || cr.title) AS target_label,
      jsonb_build_object(
        'cr_number', cr.cr_number,
        'title', cr.title,
        'cr_type', cr.cr_type,
        'impact_level', cr.impact_level,
        'status', cr.status
      ) AS payload
    FROM public.change_requests cr
    LEFT JOIN public.members am ON am.id = cr.requested_by
    WHERE cr.submitted_at IS NOT NULL AND cr.submitted_at >= v_since
      AND (v_is_privileged OR cr.requested_by = v_member_id
           OR v_member_id = ANY(cr.approved_by_members))

    UNION ALL
    -- change_request approved
    SELECT
      cr.approved_at,
      'change_request'::text,
      'cr_approved'::text,
      NULL::uuid,
      NULL::text,
      'change_request'::text,
      cr.id,
      ('CR#' || cr.cr_number || ' — ' || cr.title),
      jsonb_build_object(
        'cr_number', cr.cr_number,
        'approved_by_members', cr.approved_by_members,
        'impact_level', cr.impact_level
      )
    FROM public.change_requests cr
    WHERE cr.approved_at IS NOT NULL AND cr.approved_at >= v_since
      AND (v_is_privileged OR cr.requested_by = v_member_id
           OR v_member_id = ANY(cr.approved_by_members))

    UNION ALL
    -- change_request reviewed
    SELECT
      cr.reviewed_at,
      'change_request'::text,
      'cr_reviewed'::text,
      cr.reviewed_by,
      rm.name,
      'change_request'::text,
      cr.id,
      ('CR#' || cr.cr_number || ' — ' || cr.title),
      jsonb_build_object(
        'cr_number', cr.cr_number,
        'review_notes', cr.review_notes
      )
    FROM public.change_requests cr
    LEFT JOIN public.members rm ON rm.id = cr.reviewed_by
    WHERE cr.reviewed_at IS NOT NULL AND cr.reviewed_at >= v_since
      AND (v_is_privileged OR cr.requested_by = v_member_id OR cr.reviewed_by = v_member_id)

    UNION ALL
    -- change_request implemented
    SELECT
      cr.implemented_at,
      'change_request'::text,
      'cr_implemented'::text,
      cr.implemented_by,
      im.name,
      'change_request'::text,
      cr.id,
      ('CR#' || cr.cr_number || ' — ' || cr.title),
      jsonb_build_object(
        'cr_number', cr.cr_number,
        'manual_version_from', cr.manual_version_from,
        'manual_version_to', cr.manual_version_to
      )
    FROM public.change_requests cr
    LEFT JOIN public.members im ON im.id = cr.implemented_by
    WHERE cr.implemented_at IS NOT NULL AND cr.implemented_at >= v_since
      AND (v_is_privileged OR cr.requested_by = v_member_id OR cr.implemented_by = v_member_id)

    UNION ALL
    -- document_version authored
    SELECT
      dv.authored_at,
      'document_version'::text,
      'version_authored'::text,
      dv.authored_by,
      am.name,
      'document_version'::text,
      dv.id,
      (gd.title || ' — ' || dv.version_label),
      jsonb_build_object(
        'document_id', gd.id,
        'document_title', gd.title,
        'version_number', dv.version_number,
        'version_label', dv.version_label,
        'is_draft', (dv.locked_at IS NULL)
      )
    FROM public.document_versions dv
    JOIN public.governance_documents gd ON gd.id = dv.document_id
    LEFT JOIN public.members am ON am.id = dv.authored_by
    WHERE dv.authored_at >= v_since
      AND (v_is_privileged OR dv.authored_by = v_member_id)

    UNION ALL
    -- document_version locked
    SELECT
      dv.locked_at,
      'document_version'::text,
      'version_locked'::text,
      dv.locked_by,
      lm.name,
      'document_version'::text,
      dv.id,
      (gd.title || ' — ' || dv.version_label),
      jsonb_build_object(
        'document_id', gd.id,
        'document_title', gd.title,
        'version_number', dv.version_number,
        'version_label', dv.version_label,
        'published_at', dv.published_at
      )
    FROM public.document_versions dv
    JOIN public.governance_documents gd ON gd.id = dv.document_id
    LEFT JOIN public.members lm ON lm.id = dv.locked_by
    WHERE dv.locked_at IS NOT NULL AND dv.locked_at >= v_since
      AND (v_is_privileged OR dv.locked_by = v_member_id)

    UNION ALL
    -- approval_chain opened
    SELECT
      ac.opened_at,
      'approval_chain'::text,
      'chain_opened'::text,
      ac.opened_by,
      om.name,
      'approval_chain'::text,
      ac.id,
      (gd.title || ' — chain opened'),
      jsonb_build_object(
        'document_id', gd.id,
        'document_title', gd.title,
        'version_id', ac.version_id,
        'status', ac.status,
        'gates_count', jsonb_array_length(ac.gates)
      )
    FROM public.approval_chains ac
    JOIN public.governance_documents gd ON gd.id = ac.document_id
    LEFT JOIN public.members om ON om.id = ac.opened_by
    WHERE ac.opened_at IS NOT NULL AND ac.opened_at >= v_since
      AND (v_is_privileged OR ac.opened_by = v_member_id)

    UNION ALL
    -- approval_chain approved
    SELECT
      ac.approved_at,
      'approval_chain'::text,
      'chain_approved'::text,
      NULL::uuid,
      NULL::text,
      'approval_chain'::text,
      ac.id,
      (gd.title || ' — chain approved'),
      jsonb_build_object(
        'document_id', gd.id,
        'document_title', gd.title,
        'version_id', ac.version_id
      )
    FROM public.approval_chains ac
    JOIN public.governance_documents gd ON gd.id = ac.document_id
    WHERE ac.approved_at IS NOT NULL AND ac.approved_at >= v_since
      AND v_is_privileged

    UNION ALL
    -- approval_chain activated
    SELECT
      ac.activated_at,
      'approval_chain'::text,
      'chain_activated'::text,
      NULL::uuid,
      NULL::text,
      'approval_chain'::text,
      ac.id,
      (gd.title || ' — activated'),
      jsonb_build_object(
        'document_id', gd.id,
        'document_title', gd.title,
        'version_id', ac.version_id
      )
    FROM public.approval_chains ac
    JOIN public.governance_documents gd ON gd.id = ac.document_id
    WHERE ac.activated_at IS NOT NULL AND ac.activated_at >= v_since
      AND v_is_privileged

    UNION ALL
    -- approval_signoffs — gate signatures
    SELECT
      s.signed_at,
      'approval_signoff'::text,
      'signoff_recorded'::text,
      s.signer_id,
      sm.name,
      'approval_signoff'::text,
      s.id,
      (gd.title || ' — gate ' || s.gate_kind),
      jsonb_build_object(
        'document_id', gd.id,
        'document_title', gd.title,
        'chain_id', s.approval_chain_id,
        'gate_kind', s.gate_kind,
        'signoff_type', s.signoff_type
      )
    FROM public.approval_signoffs s
    JOIN public.approval_chains ac ON ac.id = s.approval_chain_id
    JOIN public.governance_documents gd ON gd.id = ac.document_id
    LEFT JOIN public.members sm ON sm.id = s.signer_id
    WHERE s.signed_at >= v_since
      AND (v_is_privileged OR s.signer_id = v_member_id)

    UNION ALL
    -- pii_access_log — LGPD Art. 37
    SELECT
      p.accessed_at,
      'pii_access'::text,
      'pii_accessed'::text,
      p.accessor_id,
      am.name,
      'member'::text,
      p.target_member_id,
      ('PII access — ' || COALESCE(tm.name, 'target') || ' via ' || COALESCE(p.context, 'unknown')),
      jsonb_build_object(
        'fields_accessed', p.fields_accessed,
        'context', p.context,
        'reason', p.reason
      )
    FROM public.pii_access_log p
    LEFT JOIN public.members am ON am.id = p.accessor_id
    LEFT JOIN public.members tm ON tm.id = p.target_member_id
    WHERE p.accessed_at >= v_since
      AND (v_is_privileged OR p.accessor_id = v_member_id OR p.target_member_id = v_member_id)

    UNION ALL
    -- admin_audit_log — admin actions (privileged-only)
    SELECT
      a.created_at,
      'admin_audit'::text,
      a.action,
      a.actor_id,
      am.name,
      a.target_type,
      a.target_id,
      (COALESCE(a.target_type, 'entity') || ' ' || COALESCE(a.action, 'action')),
      jsonb_build_object(
        'changes', a.changes,
        'metadata', a.metadata
      )
    FROM public.admin_audit_log a
    LEFT JOIN public.members am ON am.id = a.actor_id
    WHERE a.created_at >= v_since
      AND (v_is_privileged OR a.actor_id = v_member_id)
  )
  SELECT * FROM events
  ORDER BY event_time DESC NULLS LAST
  LIMIT v_limit;
END;
$fn$;

COMMENT ON FUNCTION public.get_governance_change_log(timestamptz, int) IS
  'Unified chronological timeline across 6 governance sources (change_requests, document_versions, '
  'approval_chains, approval_signoffs, pii_access_log, admin_audit_log). Privileged callers (view_pii) '
  'see all events; non-privileged see only their own actor/target scope. Default window: 90 days. '
  'Default limit: 200 rows (max 1000). LGPD Art. 37 audit support. Issue #85 Onda B.';

GRANT EXECUTE ON FUNCTION public.get_governance_change_log(timestamptz, int) TO authenticated;

NOTIFY pgrst, 'reload schema';
