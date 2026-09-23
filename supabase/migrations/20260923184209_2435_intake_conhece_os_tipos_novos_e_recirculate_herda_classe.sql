-- ============================================================================
-- #2435 — o intake nao conhecia os tipos novos, e a recirculacao nao passava a classe adiante
-- ============================================================================
--
-- WHAT (1): create_governance_document_intake ganha bracos explicitos para os 5 tipos que o
--   CHECK governance_documents_doc_type_check ganhou depois do intake: accession_term,
--   assignment_term, data_processing_agreement, declaration_template (legal_signature) e
--   business_case (informational).
-- WHY (1): sem os bracos, todos caiam no ELSE 'informational'. Medido em 23/09/2026: os 3
--   documentos irmaos criados em 11/06 (accession_term, data_processing_agreement,
--   declaration_template) estao 'legal_signature'; o Termo de Cessao (assignment_term) nasceria
--   'informational'. Mesma classe de defeito da #2119: lista de nomes que nao cresceu com o CHECK.
--
-- WHAT (2): recirculate_governance_doc passa a versao nova ao lock COM a change_class da versao
--   que a cadeia substituida travava (heranca). O dry-run passa a exibir a classe herdada.
-- WHY (2): o lock era chamado com 2 argumentos, entao a versao recirculada nascia com
--   change_class NULL, e trg_document_version_immutable congela a classe no lock (#571 PR-1 §9.2):
--   nao ha correcao posterior. Medido em 23/09/2026: Politica v9 e Adendo de PI v8 recirculados
--   ficaram NULL; as v0 que eles substituiram sao 'material'. Com a heranca, teriam saido
--   'material'. Heranca, e nao default fixo: a classe e juizo do rito, e o unico juizo registrado
--   e o da versao anterior; NULL herdado continua NULL, sem inventar classificacao.
--
-- Corpos base: as ultimas capturas (20260825193745 para o intake, 20260682000000 para o
--   recirculate), conferidas IGUAIS ao corpo vivo por md5 normalizado antes desta migration.
--   Assinaturas, SECURITY DEFINER, search_path, defaults e ACL preservados (CREATE OR REPLACE).
--
-- ROLLBACK: reaplicar os corpos das duas capturas base.
-- CROSS-REF: #2435 · #2119 · #571 · #632
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_governance_document_intake(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_member_id uuid;
  v_caller_org_id uuid;
  v_title text;
  v_doc_type text;
  v_author_label text;
  v_visibility_class text;
  v_description text;
  v_proposer_ack_offline boolean := COALESCE((p_payload->>'proposer_ack_offline')::boolean, false);
  v_proposer_member_id uuid := nullif(p_payload->>'proposer_member_id','')::uuid;
  v_initial_status text;
  v_acknowledgement_mode text;
  v_doc_id uuid;
BEGIN
  SELECT id, organization_id INTO v_caller_member_id, v_caller_org_id
  FROM public.members
  WHERE auth_id = auth.uid() AND is_active = true
  LIMIT 1;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no active member record' USING ERRCODE='42501';
  END IF;

  IF NOT public._can_anywhere_by_member(v_caller_member_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event capability' USING ERRCODE='42501';
  END IF;

  v_title            := nullif(trim(p_payload->>'title'), '');
  v_doc_type         := nullif(trim(p_payload->>'doc_type'), '');
  v_author_label     := nullif(trim(p_payload->>'author_label'), '');
  v_visibility_class := nullif(trim(p_payload->>'visibility_class'), '');
  v_description      := nullif(trim(p_payload->>'description'), '');
  IF v_title IS NULL OR v_doc_type IS NULL OR v_author_label IS NULL
     OR v_visibility_class IS NULL OR v_description IS NULL THEN
    RAISE EXCEPTION 'p256 intake: required fields title/doc_type/author_label/visibility_class/description';
  END IF;
  IF v_visibility_class NOT IN ('public','active_members','legal_scoped','admin_only','audit_restricted') THEN
    RAISE EXCEPTION 'p256 intake: invalid visibility_class';
  END IF;

  IF v_proposer_member_id IS NOT NULL AND v_proposer_member_id = v_caller_member_id THEN
    RAISE EXCEPTION 'p256 intake: proposer_member_id must differ from caller (GP cannot self-attest as proposer)';
  END IF;

  v_acknowledgement_mode := CASE v_doc_type
    WHEN 'manual'                  THEN 'informational'
    WHEN 'editorial_guide'         THEN 'informational'
    WHEN 'governance_guideline'    THEN 'informational'
    WHEN 'executive_summary'       THEN 'informational'
    WHEN 'framework_reference'     THEN 'informational'
    WHEN 'project_charter'         THEN 'informational'
    WHEN 'cooperation_agreement'   THEN 'legal_signature'
    WHEN 'cooperation_addendum'    THEN 'legal_signature'
    WHEN 'volunteer_term_template' THEN 'binding'
    WHEN 'volunteer_addendum'      THEN 'binding'
    WHEN 'policy'                  THEN 'binding'
    -- #2435: os tipos que o CHECK ganhou depois do intake. Sem estes bracos caiam no ELSE e
    -- nasciam 'informational', embora os irmaos de 11/06 estejam 'legal_signature'.
    WHEN 'accession_term'            THEN 'legal_signature'
    WHEN 'assignment_term'           THEN 'legal_signature'
    WHEN 'data_processing_agreement' THEN 'legal_signature'
    WHEN 'declaration_template'      THEN 'legal_signature'
    WHEN 'business_case'             THEN 'informational'
    ELSE 'informational'
  END;

  v_initial_status := CASE WHEN v_proposer_ack_offline THEN 'draft' ELSE 'pending_proposer_consent' END;

  INSERT INTO public.governance_documents (
    id, doc_type, title, description, status,
    organization_id, visibility_class, acknowledgement_mode,
    proposer_member_id,
    created_at, updated_at
  ) VALUES (
    gen_random_uuid(), v_doc_type, v_title, v_description, v_initial_status,
    v_caller_org_id, v_visibility_class, v_acknowledgement_mode,
    v_proposer_member_id,
    now(), now()
  ) RETURNING id INTO v_doc_id;

  IF v_proposer_ack_offline THEN
    INSERT INTO public.admin_audit_log (actor_id, target_type, target_id, action, metadata)
    VALUES (
      v_caller_member_id, 'governance_document', v_doc_id,
      'governance.proposer_attestation_offline',
      jsonb_build_object(
        'document_id', v_doc_id,
        'author_label', v_author_label,
        'gp_actor_id', v_caller_member_id,
        'proposer_member_id', v_proposer_member_id,
        'note', 'GP-attested proposer intake (offline) — NOT a proposer_consent signoff. Real consent flow ships Wave 1b (p261 #312-W4b sign_proposer_consent).'
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'document_id', v_doc_id,
    'status', v_initial_status,
    'acknowledgement_mode', v_acknowledgement_mode,
    'note', CASE WHEN v_proposer_ack_offline
                 THEN 'Doc in draft. GP attestation registered in admin_audit_log (NOT a proposer_consent signoff — Wave 1b ships real consent flow).'
                 ELSE 'Doc awaiting proposer in-app consent (pending_proposer_consent). Use sign_proposer_consent(document_id) once proposer authenticates.' END
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.recirculate_governance_doc(p_chain_id uuid, p_dry_run boolean DEFAULT true, p_recipient_emails text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_member record;
  v_chain record;
  v_document record;
  v_current_version record;
  v_draft record;
  v_first_gate jsonb;
  v_first_gate_kind text;
  v_recipients jsonb := '[]'::jsonb;
  v_recipient_count int := 0;
  v_send_results jsonb := '[]'::jsonb;
  v_send record;
  v_send_result jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_lock_result jsonb;
  v_new_chain_id uuid;
  v_platform_url text := 'https://nucleoia.vitormr.dev';
  v_changelog_html text;
  v_prior_resolved_count int := 0;
  v_prior_open_count int := 0;
  v_prior_summary_html text := '';
BEGIN
  SELECT m.id, m.name INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF NOT public.can_by_member(v_member.id, 'manage_member') THEN
    RAISE EXCEPTION 'Access denied: manage_member required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT ac.id, ac.document_id, ac.version_id, ac.status, ac.gates, ac.opened_at
  INTO v_chain
  FROM public.approval_chains ac WHERE ac.id = p_chain_id;
  IF v_chain.id IS NULL THEN
    RAISE EXCEPTION 'approval_chain not found (id=%)', p_chain_id USING ERRCODE = 'no_data_found';
  END IF;
  IF v_chain.status NOT IN ('review','active') THEN
    RAISE EXCEPTION 'approval_chain status=% — recirculation requires status review or active', v_chain.status
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT gd.id, gd.title, gd.doc_type INTO v_document
  FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;

  -- #2435: change_class junto, para a versao nova HERDAR a classe da que ela substitui.
  SELECT dv.id, dv.version_label, dv.version_number, dv.change_class INTO v_current_version
  FROM public.document_versions dv WHERE dv.id = v_chain.version_id;

  SELECT dv.id, dv.version_number, dv.version_label, dv.notes, dv.locked_at
  INTO v_draft
  FROM public.document_versions dv
  WHERE dv.document_id = v_chain.document_id
    AND dv.version_number > v_current_version.version_number
    AND dv.locked_at IS NULL
  ORDER BY dv.version_number ASC LIMIT 1;
  IF v_draft.id IS NULL THEN
    RAISE EXCEPTION 'no pending draft version found for document_id=% (current version_number=%)',
      v_chain.document_id, v_current_version.version_number USING ERRCODE = 'no_data_found';
  END IF;

  SELECT g INTO v_first_gate
  FROM jsonb_array_elements(v_chain.gates) g
  ORDER BY (g->>'order')::int ASC LIMIT 1;
  v_first_gate_kind := v_first_gate->>'kind';

  IF p_recipient_emails IS NOT NULL AND array_length(p_recipient_emails, 1) IS NOT NULL THEN
    SELECT jsonb_agg(jsonb_build_object(
      'email', lower(e.email),
      'first_name', split_part(COALESCE(m.name, e.email), ' ', 1),
      'member_id', m.id,
      'source', 'explicit'
    )) INTO v_recipients
    FROM unnest(p_recipient_emails) AS e(email)
    LEFT JOIN public.members m ON lower(m.email) = lower(e.email);
  ELSE
    SELECT jsonb_agg(jsonb_build_object(
      'email', lower(m.email),
      'first_name', split_part(m.name, ' ', 1),
      'member_id', m.id,
      'source', 'auto_first_gate_eligible'
    )) INTO v_recipients
    FROM public.members m
    WHERE m.is_active = true
      AND m.email IS NOT NULL
      AND public._can_sign_gate(m.id, p_chain_id, v_first_gate_kind);
  END IF;

  IF v_recipients IS NULL OR jsonb_array_length(v_recipients) = 0 THEN
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
      'code', 'no_recipients',
      'message', 'No recipients computed — execution will skip email step'
    ));
    v_recipients := '[]'::jsonb;
    v_recipient_count := 0;
  ELSE
    v_recipient_count := jsonb_array_length(v_recipients);
  END IF;

  IF v_draft.notes IS NOT NULL THEN
    v_changelog_html := '<pre style="white-space:pre-wrap; font-family:monospace; font-size:13px; background:#f9fafb; padding:12px; border-radius:6px; border:1px solid #e5e7eb;">' ||
                        replace(replace(v_draft.notes, '<', '&lt;'), '>', '&gt;') ||
                        '</pre>';
  ELSE
    v_changelog_html := '<p><em>(Sem changelog detalhado nas notes do draft.)</em></p>';
  END IF;

  SELECT
    COUNT(*) FILTER (WHERE dc.resolved_at IS NOT NULL),
    COUNT(*) FILTER (WHERE dc.resolved_at IS NULL)
  INTO v_prior_resolved_count, v_prior_open_count
  FROM public.document_comments dc
  JOIN public.document_versions dv2 ON dv2.id = dc.document_version_id
  WHERE dv2.document_id = v_document.id
    AND dv2.locked_at IS NOT NULL
    AND dv2.version_number < v_current_version.version_number;

  IF v_prior_resolved_count + v_prior_open_count > 0 THEN
    SELECT
      '<details><summary style="cursor:pointer; font-weight:600;">' ||
      'Ver detalhe (' || (v_prior_resolved_count + v_prior_open_count)::text || ' comentário(s))' ||
      '</summary><ul style="font-size:12px; margin:8px 0; padding-left:20px;">' ||
      string_agg(
        '<li style="margin:6px 0;">' ||
        CASE WHEN dc.resolved_at IS NOT NULL
          THEN '<span style="color:#059669;">✓ endereçado</span>'
          ELSE '<span style="color:#dc2626;">⚠ ainda aberto</span>'
        END ||
        ' — <strong>' || COALESCE(m.name, '?') || '</strong>' ||
        CASE WHEN dc.clause_anchor IS NOT NULL
          THEN ' (§ ' || dc.clause_anchor || ')'
          ELSE ''
        END ||
        ': <em>"' ||
        replace(replace(LEFT(dc.body, 140), '<', '&lt;'), '>', '&gt;') ||
        CASE WHEN length(dc.body) > 140 THEN '…' ELSE '' END ||
        '"</em>' ||
        '</li>',
        ''
        ORDER BY dc.resolved_at IS NULL DESC, dc.created_at DESC
      ) ||
      '</ul></details>'
    INTO v_prior_summary_html
    FROM public.document_comments dc
    JOIN public.document_versions dv2 ON dv2.id = dc.document_version_id
    LEFT JOIN public.members m ON m.id = dc.author_id
    WHERE dv2.document_id = v_document.id
      AND dv2.locked_at IS NOT NULL
      AND dv2.version_number < v_current_version.version_number
      AND dc.visibility IN ('curator_only', 'public');
  ELSE
    v_prior_summary_html := '<p style="font-size:12px; color:#6b7280; font-style:italic;">(Sem comentários em versões anteriores.)</p>';
  END IF;

  IF p_dry_run THEN
    RETURN jsonb_build_object(
      'dry_run', true,
      'valid', true,
      'document', jsonb_build_object(
        'id', v_document.id,
        'title', v_document.title,
        'doc_type', v_document.doc_type
      ),
      'current_chain', jsonb_build_object(
        'id', v_chain.id,
        'status', v_chain.status,
        'version_id', v_chain.version_id,
        'version_label', v_current_version.version_label,
        'version_number', v_current_version.version_number,
        'opened_at', v_chain.opened_at
      ),
      'draft_version', jsonb_build_object(
        'id', v_draft.id,
        'version_number', v_draft.version_number,
        'version_label', v_draft.version_label,
        'notes_present', v_draft.notes IS NOT NULL,
        'notes_length', COALESCE(length(v_draft.notes), 0)
      ),
      'gates_to_copy', v_chain.gates,
      'change_class_to_inherit', v_current_version.change_class,
      'first_gate_kind', v_first_gate_kind,
      'recipients', v_recipients,
      'recipient_count', v_recipient_count,
      'prior_comments_summary', jsonb_build_object(
        'resolved_count', v_prior_resolved_count,
        'open_count', v_prior_open_count
      ),
      'warnings', v_warnings,
      'next_step_summary', 'Execute with p_dry_run=false to: (1) supersede chain, (2) lock draft + create new chain via lock_document_version, (3) email recipients, (4) audit log.'
    );
  END IF;

  UPDATE public.approval_chains
    SET status = 'superseded',
        closed_at = now(),
        closed_by = v_member.id,
        notes = COALESCE(notes,'') || E'\n[recirculated at ' || now()::text ||
                ' by ' || v_member.name || ' — superseded by new draft v' || v_draft.version_label || ']',
        updated_at = now()
    WHERE id = p_chain_id;

  -- #2435: sem o 3o argumento a versao recirculada nascia com change_class NULL, e o
  -- trg_document_version_immutable congela a classe no lock: nao havia como corrigir depois.
  v_lock_result := public.lock_document_version(v_draft.id, v_chain.gates, v_current_version.change_class);
  IF NOT (v_lock_result->>'success')::boolean THEN
    RAISE EXCEPTION 'lock_document_version failed: %', v_lock_result::text USING ERRCODE = 'integrity_constraint_violation';
  END IF;
  v_new_chain_id := (v_lock_result->>'chain_id')::uuid;

  IF v_recipient_count > 0 THEN
    FOR v_send IN SELECT * FROM jsonb_to_recordset(v_recipients) AS x(
      email text, first_name text, member_id uuid, source text
    ) LOOP
      BEGIN
        v_send_result := public.campaign_send_one_off(
          'governance_recirculation_request',
          v_send.email,
          jsonb_build_object(
            'first_name', COALESCE(v_send.first_name, 'Curador'),
            'document_title', v_document.title,
            'version_label', v_draft.version_label,
            'new_chain_url', v_platform_url || '/admin/governance/documents/' || v_new_chain_id::text,
            'old_chain_url', v_platform_url || '/admin/governance/documents/' || p_chain_id::text,
            'changelog', v_changelog_html,
            'prior_resolved_count', v_prior_resolved_count::text,
            'prior_open_count', v_prior_open_count::text,
            'prior_addressed_summary', v_prior_summary_html,
            'platform_url', v_platform_url,
            'sender_name', v_member.name
          ),
          jsonb_build_object(
            'source', 'governance_recirculation',
            'document_id', v_document.id,
            'old_chain_id', p_chain_id,
            'new_chain_id', v_new_chain_id,
            'recipient_name', v_send.first_name
          )
        );
        v_send_results := v_send_results || jsonb_build_array(jsonb_build_object(
          'email', v_send.email,
          'send_id', v_send_result->>'send_id',
          'status', 'enqueued'
        ));
      EXCEPTION WHEN OTHERS THEN
        v_send_results := v_send_results || jsonb_build_array(jsonb_build_object(
          'email', v_send.email,
          'send_id', NULL,
          'status', 'failed',
          'error', SQLERRM
        ));
      END;
    END LOOP;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_member.id,
    'governance.recirculated',
    'governance_document',
    v_document.id,
    jsonb_build_object(
      'old_chain_id', p_chain_id,
      'new_chain_id', v_new_chain_id,
      'old_version', v_current_version.version_label,
      'new_version', v_draft.version_label,
      'recipients_count', v_recipient_count,
      'recipient_emails', (SELECT jsonb_agg(r->>'email') FROM jsonb_array_elements(v_recipients) r),
      'prior_resolved_count', v_prior_resolved_count,
      'prior_open_count', v_prior_open_count,
      'send_results', v_send_results
    ),
    jsonb_build_object(
      'doc_type', v_document.doc_type,
      'first_gate_kind', v_first_gate_kind,
      'sender_member_id', v_member.id
    )
  );

  RETURN jsonb_build_object(
    'dry_run', false,
    'success', true,
    'old_chain_id', p_chain_id,
    'new_chain_id', v_new_chain_id,
    'version_id_locked', v_draft.id,
    'document_id', v_document.id,
    'recipients_count', v_recipient_count,
    'prior_comments_summary', jsonb_build_object(
      'resolved_count', v_prior_resolved_count,
      'open_count', v_prior_open_count
    ),
    'send_results', v_send_results,
    'warnings', v_warnings
  );
END;
$$;
