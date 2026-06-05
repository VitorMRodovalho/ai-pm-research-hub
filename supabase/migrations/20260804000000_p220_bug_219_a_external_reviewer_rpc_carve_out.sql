-- ============================================================
-- p220 BUG-219.A Phase 2: wire participate_in_governance_review carve-out
-- into get_chain_for_pdf + get_chain_audit_report
-- ============================================================
-- WHAT: broaden the auth gate in both read RPCs from strict
-- can_by_member('manage_member') to:
--   can_by_member('manage_member') OR can_by_member('participate_in_governance_review')
--
-- The carve-out already exists in public.can() (migration
-- 20260710000000_p195_can_carve_out_governance_review.sql), but consumer
-- RPCs were never updated to consume it. p195 shipped half the contract;
-- this migration completes the wire.
--
-- WHY: external legal counsel (advogada Angelina, kind=external_reviewer)
-- needs to download the PDF + audit report of governance chains under
-- review for legal review, WITHOUT having to sign the platform's
-- Volunteer Term first (she is not a volunteer — she is a Bar-licensed
-- external attorney bound by OAB Art. 7 confidentiality duty). The p195
-- carve-out enables participate_in_governance_review for non-authoritative
-- engagements (status='active', is_authoritative=false); this migration
-- completes the wiring at the consumer surface.
--
-- READ-only scope: only these two endpoints are broadened. Write/
-- destructive RPCs (lock_document_version, recirculate_governance_doc,
-- delete_document_version_draft) keep strict manage_member. Sign gates
-- enumerate independently via _can_sign_gate() per gate kind.
-- Comment RPCs (create_document_comment, list_document_comments,
-- resolve_document_comment) already accept the carve-out and are
-- unchanged here.
--
-- LGPD note: get_chain_audit_report exposes signer PII (pmi_id, email,
-- designations). External reviewers are Bar-licensed attorneys bound by
-- OAB Art. 7 confidentiality. The carve-out is bounded by the engagement
-- kind seed at engagement_kind_permissions:
--   (kind=external_reviewer, role=reviewer, action=participate_in_governance_review)
-- which is created only by admin onboarding. Future hardening could
-- redact emails when caller has ONLY the carve-out — deferred (see GH).
--
-- POST-DEPLOY VALIDATION (smoked inline):
--   can_by_member(angelina, 'participate_in_governance_review') = true
--   can_by_member(angelina, 'manage_member') = false
--   get_chain_for_pdf as Angelina returns the chain (was: 'Access denied')
--   get_chain_audit_report as Angelina returns the chain (was: 'Access denied')
--   get_chain_for_pdf as random member (no carve-out, no manage_member) still raises
--
-- ROLLBACK: re-apply prior bodies reverting both gates to:
--   IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
--     RAISE EXCEPTION 'Access denied: requires manage_member';
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_chain_for_pdf(p_chain_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_chain record;
  v_doc record;
  v_version record;
  v_submitter record;
  v_gates_detail jsonb;
  v_policy_version record;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- p220 BUG-219.A: accept manage_member OR participate_in_governance_review (p195 carve-out)
  IF NOT (public.can_by_member(v_caller_id, 'manage_member')
          OR public.can_by_member(v_caller_id, 'participate_in_governance_review')) THEN
    RAISE EXCEPTION 'Access denied: requires manage_member or participate_in_governance_review' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT ac.id, ac.status, ac.gates, ac.document_id, ac.version_id,
         ac.opened_at, ac.opened_by, ac.approved_at, ac.closed_at, ac.notes
  INTO v_chain FROM public.approval_chains ac WHERE ac.id = p_chain_id;
  IF v_chain.id IS NULL THEN RETURN jsonb_build_object('error','chain_not_found'); END IF;

  SELECT gd.id, gd.title, gd.doc_type, gd.status AS doc_status, gd.description
  INTO v_doc FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;

  SELECT dv.id, dv.version_number, dv.version_label, dv.content_html,
         dv.locked_at, dv.published_at, dv.notes AS version_notes
  INTO v_version FROM public.document_versions dv WHERE dv.id = v_chain.version_id;

  SELECT m.id, m.name, m.email, m.chapter, m.operational_role
  INTO v_submitter FROM public.members m WHERE m.id = v_chain.opened_by;

  -- Para cada gate, agregar signers com evidence trail completo
  SELECT jsonb_agg(
    jsonb_build_object(
      'kind', g->>'kind',
      'order', (g->>'order')::int,
      'threshold', g->>'threshold',
      'label', CASE g->>'kind'
        WHEN 'curator' THEN 'Curadoria'
        WHEN 'leader_awareness' THEN 'Ciência das lideranças'
        WHEN 'submitter_acceptance' THEN 'Aceite do GP'
        WHEN 'chapter_witness' THEN 'Testemunho de capítulo'
        WHEN 'president_go' THEN 'Presidência PMI-GO'
        WHEN 'president_others' THEN 'Presidências outros capítulos'
        WHEN 'volunteers_in_role_active' THEN 'Ratificação voluntários em função'
        WHEN 'member_ratification' THEN 'Ratificação membros'
        WHEN 'external_signer' THEN 'Signatário externo'
        ELSE g->>'kind'
      END,
      'signers', (
        SELECT COALESCE(jsonb_agg(
          jsonb_build_object(
            'signoff_id', s.id,
            'signer_id', s.signer_id,
            'signer_name', m.name,
            'signer_chapter', m.chapter,
            'signer_role', m.operational_role,
            'signoff_type', s.signoff_type,
            'signed_at', s.signed_at,
            'signature_hash_short', SUBSTRING(s.signature_hash FROM 1 FOR 12),
            'comment_body', s.comment_body,
            'sections_verified_count', COALESCE(jsonb_array_length(s.sections_verified), 0),
            'notification_read_at', s.content_snapshot->>'notification_read_at',
            'notification_read_evidence', COALESCE((s.content_snapshot->>'notification_read_evidence')::boolean, false),
            'referenced_policy_version_label', s.content_snapshot->>'referenced_policy_version_label',
            'ue_consent_recorded', COALESCE((s.content_snapshot->>'ue_consent_recorded')::boolean, false)
          ) ORDER BY s.signed_at
        ), '[]'::jsonb)
        FROM public.approval_signoffs s
        LEFT JOIN public.members m ON m.id = s.signer_id
        WHERE s.approval_chain_id = v_chain.id AND s.gate_kind = g->>'kind'
      )
    ) ORDER BY (g->>'order')::int
  )
  INTO v_gates_detail
  FROM jsonb_array_elements(v_chain.gates) g;

  -- Política vigente no momento da geração do PDF (para header)
  SELECT gd.id, dv.version_label, dv.locked_at
  INTO v_policy_version
  FROM public.governance_documents gd
  LEFT JOIN public.document_versions dv ON dv.id = gd.current_version_id
  WHERE gd.doc_type = 'policy' AND gd.status IN ('active','under_review')
  ORDER BY CASE WHEN gd.status='active' THEN 0 ELSE 1 END LIMIT 1;

  RETURN jsonb_build_object(
    'chain_id', v_chain.id,
    'chain_status', v_chain.status,
    'chain_opened_at', v_chain.opened_at,
    'chain_approved_at', v_chain.approved_at,
    'chain_closed_at', v_chain.closed_at,
    'chain_notes', v_chain.notes,
    'document', jsonb_build_object(
      'id', v_doc.id,
      'title', v_doc.title,
      'doc_type', v_doc.doc_type,
      'status', v_doc.doc_status,
      'description', v_doc.description
    ),
    'version', jsonb_build_object(
      'id', v_version.id,
      'number', v_version.version_number,
      'label', v_version.version_label,
      'content_html', v_version.content_html,
      'locked_at', v_version.locked_at,
      'published_at', v_version.published_at,
      'notes', v_version.version_notes
    ),
    'submitter', jsonb_build_object(
      'id', v_submitter.id,
      'name', v_submitter.name,
      'email', v_submitter.email,
      'chapter', v_submitter.chapter,
      'role', v_submitter.operational_role
    ),
    'gates', COALESCE(v_gates_detail, '[]'::jsonb),
    'policy_at_pdf_generation', CASE
      WHEN v_policy_version.id IS NOT NULL THEN
        jsonb_build_object(
          'document_id', v_policy_version.id,
          'version_label', v_policy_version.version_label,
          'locked_at', v_policy_version.locked_at
        )
      ELSE NULL
    END,
    'generated_at', now(),
    'generated_by', jsonb_build_object('id', v_caller_id)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_chain_audit_report(p_chain_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_chain record;
  v_doc record;
  v_version record;
  v_submitter record;
  v_timeline jsonb;
  v_signoffs_full jsonb;
  v_audit_entries jsonb;
  v_integrity_summary jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- p220 BUG-219.A: accept manage_member OR participate_in_governance_review (p195 carve-out)
  IF NOT (public.can_by_member(v_caller_id, 'manage_member')
          OR public.can_by_member(v_caller_id, 'participate_in_governance_review')) THEN
    RAISE EXCEPTION 'Access denied: requires manage_member or participate_in_governance_review' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT ac.id, ac.status, ac.gates, ac.document_id, ac.version_id,
         ac.opened_at, ac.opened_by, ac.approved_at, ac.closed_at, ac.closed_by, ac.notes
  INTO v_chain FROM public.approval_chains ac WHERE ac.id = p_chain_id;
  IF v_chain.id IS NULL THEN RETURN jsonb_build_object('error','chain_not_found'); END IF;

  SELECT gd.id, gd.title, gd.doc_type, gd.status AS doc_status
  INTO v_doc FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;

  SELECT dv.id, dv.version_number, dv.version_label, dv.locked_at, dv.locked_by,
         dv.published_at, dv.published_by, dv.authored_by, dv.authored_at
  INTO v_version FROM public.document_versions dv WHERE dv.id = v_chain.version_id;

  SELECT m.id, m.name, m.email, m.chapter, m.operational_role
  INTO v_submitter FROM public.members m WHERE m.id = v_chain.opened_by;

  -- Timeline cronológica: merge eventos de múltiplas fontes
  WITH events AS (
    SELECT 'version_authored' AS kind, v_version.authored_at AS at_ts,
           jsonb_build_object(
             'actor', (SELECT jsonb_build_object('id', m.id, 'name', m.name) FROM public.members m WHERE m.id = v_version.authored_by),
             'version_label', v_version.version_label
           ) AS data
    WHERE v_version.authored_at IS NOT NULL
    UNION ALL
    SELECT 'version_locked', v_version.locked_at,
           jsonb_build_object(
             'actor', (SELECT jsonb_build_object('id', m.id, 'name', m.name) FROM public.members m WHERE m.id = v_version.locked_by),
             'version_label', v_version.version_label
           )
    WHERE v_version.locked_at IS NOT NULL
    UNION ALL
    SELECT 'chain_opened', v_chain.opened_at,
           jsonb_build_object(
             'actor', jsonb_build_object('id', v_submitter.id, 'name', v_submitter.name, 'chapter', v_submitter.chapter),
             'gates_count', jsonb_array_length(v_chain.gates)
           )
    WHERE v_chain.opened_at IS NOT NULL
    UNION ALL
    SELECT 'signoff_recorded', s.signed_at,
           jsonb_build_object(
             'actor', jsonb_build_object('id', m.id, 'name', m.name, 'chapter', m.chapter, 'role', m.operational_role),
             'gate_kind', s.gate_kind,
             'signoff_type', s.signoff_type,
             'signoff_id', s.id,
             'hash_short', SUBSTRING(s.signature_hash FROM 1 FOR 12)
           )
    FROM public.approval_signoffs s
    LEFT JOIN public.members m ON m.id = s.signer_id
    WHERE s.approval_chain_id = v_chain.id
    UNION ALL
    SELECT 'chain_approved', v_chain.approved_at,
           jsonb_build_object('status_transition', jsonb_build_object('from','review','to','approved'))
    WHERE v_chain.approved_at IS NOT NULL
    UNION ALL
    SELECT 'chain_closed', v_chain.closed_at,
           jsonb_build_object(
             'actor', (SELECT jsonb_build_object('id', m.id, 'name', m.name) FROM public.members m WHERE m.id = v_chain.closed_by)
           )
    WHERE v_chain.closed_at IS NOT NULL
  )
  SELECT jsonb_agg(
    jsonb_build_object('kind', kind, 'at', at_ts, 'data', data)
    ORDER BY at_ts
  ) INTO v_timeline FROM events;

  -- Signoffs completos com sections_verified + full content_snapshot
  SELECT jsonb_agg(
    jsonb_build_object(
      'signoff_id', s.id,
      'gate_kind', s.gate_kind,
      'signoff_type', s.signoff_type,
      'signer', jsonb_build_object(
        'id', s.signer_id,
        'name', m.name,
        'email', m.email,
        'chapter', m.chapter,
        'role', m.operational_role,
        'pmi_id', m.pmi_id,
        'designations', m.designations
      ),
      'signed_at', s.signed_at,
      'signature_hash', s.signature_hash,
      'signature_hash_short', SUBSTRING(s.signature_hash FROM 1 FOR 16),
      'sections_verified', s.sections_verified,
      'sections_verified_count', COALESCE(jsonb_array_length(s.sections_verified), 0),
      'comment_body', s.comment_body,
      'content_snapshot', s.content_snapshot,
      'referenced_policy_version_id', s.referenced_policy_version_id
    ) ORDER BY s.signed_at
  )
  INTO v_signoffs_full
  FROM public.approval_signoffs s
  LEFT JOIN public.members m ON m.id = s.signer_id
  WHERE s.approval_chain_id = v_chain.id;

  -- admin_audit_log correlacionado (chain + signoffs + version)
  SELECT jsonb_agg(
    jsonb_build_object(
      'log_id', aal.id,
      'timestamp', aal.created_at,
      'actor', (SELECT jsonb_build_object('id', m.id, 'name', m.name) FROM public.members m WHERE m.id = aal.actor_id),
      'action', aal.action,
      'target_type', aal.target_type,
      'target_id', aal.target_id,
      'metadata', aal.metadata,
      'changes', aal.changes
    ) ORDER BY aal.created_at
  )
  INTO v_audit_entries
  FROM public.admin_audit_log aal
  WHERE aal.target_id = p_chain_id
     OR aal.target_id = v_chain.version_id
     OR aal.target_id = v_chain.document_id
     OR (aal.target_type = 'approval_signoff'
         AND aal.target_id IN (SELECT id FROM public.approval_signoffs WHERE approval_chain_id = p_chain_id));

  -- Integrity summary: count signoffs + hashes presence
  SELECT jsonb_build_object(
    'total_signoffs', COUNT(*),
    'with_hash', COUNT(*) FILTER (WHERE signature_hash IS NOT NULL AND LENGTH(signature_hash) > 0),
    'with_snapshot', COUNT(*) FILTER (WHERE content_snapshot IS NOT NULL),
    'with_policy_version_ref', COUNT(*) FILTER (WHERE referenced_policy_version_id IS NOT NULL),
    'with_notification_read_evidence', COUNT(*) FILTER (WHERE (content_snapshot->>'notification_read_evidence')::boolean = true),
    'with_sections_verified', COUNT(*) FILTER (WHERE sections_verified IS NOT NULL AND jsonb_array_length(sections_verified) > 0)
  )
  INTO v_integrity_summary
  FROM public.approval_signoffs
  WHERE approval_chain_id = p_chain_id;

  RETURN jsonb_build_object(
    'chain_id', v_chain.id,
    'chain_status', v_chain.status,
    'chain_opened_at', v_chain.opened_at,
    'chain_approved_at', v_chain.approved_at,
    'chain_closed_at', v_chain.closed_at,
    'chain_notes', v_chain.notes,
    'gates_config', v_chain.gates,
    'document', jsonb_build_object(
      'id', v_doc.id, 'title', v_doc.title, 'doc_type', v_doc.doc_type, 'status', v_doc.doc_status
    ),
    'version', jsonb_build_object(
      'id', v_version.id, 'number', v_version.version_number, 'label', v_version.version_label,
      'locked_at', v_version.locked_at, 'published_at', v_version.published_at
    ),
    'submitter', jsonb_build_object(
      'id', v_submitter.id, 'name', v_submitter.name, 'email', v_submitter.email,
      'chapter', v_submitter.chapter, 'role', v_submitter.operational_role
    ),
    'timeline', COALESCE(v_timeline, '[]'::jsonb),
    'signoffs', COALESCE(v_signoffs_full, '[]'::jsonb),
    'audit_log_entries', COALESCE(v_audit_entries, '[]'::jsonb),
    'integrity_summary', v_integrity_summary,
    'generated_at', now(),
    'generated_by', jsonb_build_object('id', v_caller_id,
      'name', (SELECT name FROM public.members WHERE id = v_caller_id))
  );
END;
$function$;
