-- =============================================================================
-- get_governance_change_log — add p_include_payload flag for payload optimization
-- =============================================================================
-- Issue: payload jsonb column carries admin_audit_log.metadata (often large diffs
--   like changes/metadata) plus per-event context blobs. Measured on prod: 200 rows
--   default window = 146KB total, of which 87KB (60%) is payload. When callers only
--   need the event timeline (actor, target, kind, time) for LGPD Art. 37 summary
--   views, they can opt out of the payload.
--
-- Change: adiciona 3º parâmetro `p_include_payload boolean DEFAULT true`.
--   - true (default): comportamento atual (full payload jsonb) — backward-compat
--   - false: retorna payload=NULL. Outras colunas preservadas.
--
-- Signature change: DROP + CREATE (arg count increased). Exec grant preserved.
-- Rollback: CREATE OR REPLACE with 2-arg signature.
-- =============================================================================

DROP FUNCTION IF EXISTS public.get_governance_change_log(timestamptz, integer);

CREATE OR REPLACE FUNCTION public.get_governance_change_log(
  p_since timestamptz DEFAULT NULL,
  p_limit integer DEFAULT 200,
  p_include_payload boolean DEFAULT true
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
    SELECT cr.submitted_at AS event_time, 'change_request'::text AS event_source, 'cr_submitted'::text AS event_kind,
      cr.requested_by AS actor_id, am.name AS actor_name, 'change_request'::text AS target_type, cr.id AS target_id,
      ('CR#' || cr.cr_number || ' — ' || cr.title) AS target_label,
      jsonb_build_object('cr_number', cr.cr_number, 'title', cr.title, 'cr_type', cr.cr_type, 'impact_level', cr.impact_level, 'status', cr.status) AS payload
    FROM public.change_requests cr
    LEFT JOIN public.members am ON am.id = cr.requested_by
    WHERE cr.submitted_at IS NOT NULL AND cr.submitted_at >= v_since
      AND (v_is_privileged OR cr.requested_by = v_member_id OR v_member_id = ANY(cr.approved_by_members))
    UNION ALL
    SELECT cr.approved_at, 'change_request'::text, 'cr_approved'::text, NULL::uuid, NULL::text, 'change_request'::text, cr.id,
      ('CR#' || cr.cr_number || ' — ' || cr.title),
      jsonb_build_object('cr_number', cr.cr_number, 'approved_by_members', cr.approved_by_members, 'impact_level', cr.impact_level)
    FROM public.change_requests cr
    WHERE cr.approved_at IS NOT NULL AND cr.approved_at >= v_since
      AND (v_is_privileged OR cr.requested_by = v_member_id OR v_member_id = ANY(cr.approved_by_members))
    UNION ALL
    SELECT cr.reviewed_at, 'change_request'::text, 'cr_reviewed'::text, cr.reviewed_by, rm.name, 'change_request'::text, cr.id,
      ('CR#' || cr.cr_number || ' — ' || cr.title),
      jsonb_build_object('cr_number', cr.cr_number, 'review_notes', cr.review_notes)
    FROM public.change_requests cr
    LEFT JOIN public.members rm ON rm.id = cr.reviewed_by
    WHERE cr.reviewed_at IS NOT NULL AND cr.reviewed_at >= v_since
      AND (v_is_privileged OR cr.requested_by = v_member_id OR cr.reviewed_by = v_member_id)
    UNION ALL
    SELECT cr.implemented_at, 'change_request'::text, 'cr_implemented'::text, cr.implemented_by, im.name, 'change_request'::text, cr.id,
      ('CR#' || cr.cr_number || ' — ' || cr.title),
      jsonb_build_object('cr_number', cr.cr_number, 'manual_version_from', cr.manual_version_from, 'manual_version_to', cr.manual_version_to)
    FROM public.change_requests cr
    LEFT JOIN public.members im ON im.id = cr.implemented_by
    WHERE cr.implemented_at IS NOT NULL AND cr.implemented_at >= v_since
      AND (v_is_privileged OR cr.requested_by = v_member_id OR cr.implemented_by = v_member_id)
    UNION ALL
    SELECT dv.authored_at, 'document_version'::text, 'version_authored'::text, dv.authored_by, am.name, 'document_version'::text, dv.id,
      (gd.title || ' — ' || dv.version_label),
      jsonb_build_object('document_id', gd.id, 'document_title', gd.title, 'version_number', dv.version_number, 'version_label', dv.version_label, 'is_draft', (dv.locked_at IS NULL))
    FROM public.document_versions dv
    JOIN public.governance_documents gd ON gd.id = dv.document_id
    LEFT JOIN public.members am ON am.id = dv.authored_by
    WHERE dv.authored_at >= v_since AND (v_is_privileged OR dv.authored_by = v_member_id)
    UNION ALL
    SELECT dv.locked_at, 'document_version'::text, 'version_locked'::text, dv.locked_by, lm.name, 'document_version'::text, dv.id,
      (gd.title || ' — ' || dv.version_label),
      jsonb_build_object('document_id', gd.id, 'document_title', gd.title, 'version_number', dv.version_number, 'version_label', dv.version_label, 'published_at', dv.published_at)
    FROM public.document_versions dv
    JOIN public.governance_documents gd ON gd.id = dv.document_id
    LEFT JOIN public.members lm ON lm.id = dv.locked_by
    WHERE dv.locked_at IS NOT NULL AND dv.locked_at >= v_since
      AND (v_is_privileged OR dv.locked_by = v_member_id)
    UNION ALL
    SELECT ac.opened_at, 'approval_chain'::text, 'chain_opened'::text, ac.opened_by, om.name, 'approval_chain'::text, ac.id,
      (gd.title || ' — chain opened'),
      jsonb_build_object('document_id', gd.id, 'document_title', gd.title, 'version_id', ac.version_id, 'status', ac.status, 'gates_count', jsonb_array_length(ac.gates))
    FROM public.approval_chains ac
    JOIN public.governance_documents gd ON gd.id = ac.document_id
    LEFT JOIN public.members om ON om.id = ac.opened_by
    WHERE ac.opened_at IS NOT NULL AND ac.opened_at >= v_since
      AND (v_is_privileged OR ac.opened_by = v_member_id)
    UNION ALL
    SELECT ac.approved_at, 'approval_chain'::text, 'chain_approved'::text, NULL::uuid, NULL::text, 'approval_chain'::text, ac.id,
      (gd.title || ' — chain approved'),
      jsonb_build_object('document_id', gd.id, 'document_title', gd.title, 'version_id', ac.version_id)
    FROM public.approval_chains ac
    JOIN public.governance_documents gd ON gd.id = ac.document_id
    WHERE ac.approved_at IS NOT NULL AND ac.approved_at >= v_since
      AND v_is_privileged
    UNION ALL
    SELECT ac.activated_at, 'approval_chain'::text, 'chain_activated'::text, NULL::uuid, NULL::text, 'approval_chain'::text, ac.id,
      (gd.title || ' — activated'),
      jsonb_build_object('document_id', gd.id, 'document_title', gd.title, 'version_id', ac.version_id)
    FROM public.approval_chains ac
    JOIN public.governance_documents gd ON gd.id = ac.document_id
    WHERE ac.activated_at IS NOT NULL AND ac.activated_at >= v_since
      AND v_is_privileged
    UNION ALL
    SELECT s.signed_at, 'approval_signoff'::text, 'signoff_recorded'::text, s.signer_id, sm.name, 'approval_signoff'::text, s.id,
      (gd.title || ' — gate ' || s.gate_kind),
      jsonb_build_object('document_id', gd.id, 'document_title', gd.title, 'chain_id', s.approval_chain_id, 'gate_kind', s.gate_kind, 'signoff_type', s.signoff_type)
    FROM public.approval_signoffs s
    JOIN public.approval_chains ac ON ac.id = s.approval_chain_id
    JOIN public.governance_documents gd ON gd.id = ac.document_id
    LEFT JOIN public.members sm ON sm.id = s.signer_id
    WHERE s.signed_at >= v_since AND (v_is_privileged OR s.signer_id = v_member_id)
    UNION ALL
    SELECT p.accessed_at, 'pii_access'::text, 'pii_accessed'::text, p.accessor_id, am.name, 'member'::text, p.target_member_id,
      ('PII access — ' || COALESCE(tm.name, 'target') || ' via ' || COALESCE(p.context, 'unknown')),
      jsonb_build_object('fields_accessed', p.fields_accessed, 'context', p.context, 'reason', p.reason)
    FROM public.pii_access_log p
    LEFT JOIN public.members am ON am.id = p.accessor_id
    LEFT JOIN public.members tm ON tm.id = p.target_member_id
    WHERE p.accessed_at >= v_since
      AND (v_is_privileged OR p.accessor_id = v_member_id OR p.target_member_id = v_member_id)
    UNION ALL
    SELECT a.created_at, 'admin_audit'::text, a.action, a.actor_id, am.name, a.target_type, a.target_id,
      (COALESCE(a.target_type, 'entity') || ' ' || COALESCE(a.action, 'action')),
      jsonb_build_object('changes', a.changes, 'metadata', a.metadata)
    FROM public.admin_audit_log a
    LEFT JOIN public.members am ON am.id = a.actor_id
    WHERE a.created_at >= v_since AND (v_is_privileged OR a.actor_id = v_member_id)
  )
  SELECT
    e.event_time, e.event_source, e.event_kind,
    e.actor_id, e.actor_name, e.target_type, e.target_id, e.target_label,
    CASE WHEN p_include_payload THEN e.payload ELSE NULL::jsonb END AS payload
  FROM events e
  ORDER BY e.event_time DESC NULLS LAST
  LIMIT v_limit;
END;
$fn$;

COMMENT ON FUNCTION public.get_governance_change_log(timestamptz, integer, boolean) IS
  'Unified chronological feed across 6 governance sources (change_requests, document_versions, '
  'approval_chains, approval_signoffs, pii_access_log, admin_audit_log). Privileged callers '
  '(view_pii) see all events; non-privileged see only their own actor/target scope. '
  'p_include_payload=false returns payload=NULL (saves ~60% bandwidth when host only needs '
  'the timeline skeleton for LGPD Art. 37 summaries). Issue #85 Onda B P0.';

GRANT EXECUTE ON FUNCTION public.get_governance_change_log(timestamptz, integer, boolean) TO authenticated;

NOTIFY pgrst, 'reload schema';
