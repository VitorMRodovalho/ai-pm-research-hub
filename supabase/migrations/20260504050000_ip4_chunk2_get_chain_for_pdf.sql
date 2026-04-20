-- IP-4 Chunk 2: RPC get_chain_for_pdf — retorna dados estruturados para exportação PDF
-- Usado pela página /admin/governance/documents/[chainId]/export-pdf + ChainPDFDocument.tsx
-- Agrega: doc metadata + content_html + chain status + signers por gate + evidence trail completo
-- (signature_hash, notification_read_at CC Art. 111, referenced_policy_version, UE consent)

CREATE OR REPLACE FUNCTION public.get_chain_for_pdf(p_chain_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
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
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Access denied: requires manage_member' USING ERRCODE = 'insufficient_privilege';
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
      'id', v_doc.id, 'title', v_doc.title, 'doc_type', v_doc.doc_type,
      'status', v_doc.doc_status, 'description', v_doc.description
    ),
    'version', jsonb_build_object(
      'id', v_version.id, 'number', v_version.version_number, 'label', v_version.version_label,
      'content_html', v_version.content_html,
      'locked_at', v_version.locked_at, 'published_at', v_version.published_at,
      'notes', v_version.version_notes
    ),
    'submitter', jsonb_build_object(
      'id', v_submitter.id, 'name', v_submitter.name, 'email', v_submitter.email,
      'chapter', v_submitter.chapter, 'role', v_submitter.operational_role
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

GRANT EXECUTE ON FUNCTION public.get_chain_for_pdf(uuid) TO authenticated;

COMMENT ON FUNCTION public.get_chain_for_pdf(uuid) IS
  'IP-4 Chunk 2: agrega dados estruturados de approval_chain + signoffs para exportação PDF via @react-pdf/renderer. Inclui evidence trail (hash, read_at, policy_version_label, UE consent).';

NOTIFY pgrst, 'reload schema';
