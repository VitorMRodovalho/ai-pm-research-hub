-- #403 (BUG-268.B) — restore Tier-2 governance INSERT RPCs broken since W1a M2 (#315).
-- confirm_manual_version + link_attachment_to_governance INSERT INTO governance_documents but omit
-- three columns made NOT NULL (no default) by the W1a M2 taxonomy migration:
--   organization_id, visibility_class, acknowledgement_mode.
-- Both have been latently broken (no caller hit them since W1a M2). This patches both INSERTs:
--   - organization_id      := caller's members.organization_id (single-tenant; matches the caller-derived
--                             canonical writer create_governance_document_intake).
--   - visibility_class     := 'active_members' (100% uniform across existing governance_documents rows).
--   - acknowledgement_mode := per doc_type, mirroring existing rows:
--         confirm_manual_version (doc_type='manual')                       -> 'informational'
--         link_attachment_to_governance (doc_type='cooperation_agreement') -> 'legal_signature'
-- Verified live 2026-06-04: those 3 are the only NOT-NULL/no-default cols the INSERTs omitted; values pass
-- both CHECK domains. Body-only CREATE OR REPLACE (same signatures). #315 may later centralize the
-- per-doc_type defaults into a config table; this is the minimum-diff un-break.
-- Rollback: re-apply the pre-#403 bodies (INSERT column lists without the 3 columns).
-- NOTE: version 20260805000108 is migration p447 (get_my_application_status alt-email match), shipped on a
--       concurrent branch/PR; this migration intentionally takes 000109. Both are contiguous once merged.

CREATE OR REPLACE FUNCTION public.confirm_manual_version(p_proposal_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_signer_id uuid;
  v_signer_name text;
  v_proposal record;
  v_count int;
  v_approved_crs jsonb;
  v_doc_id uuid;
  v_previous_version text;
  v_recipient_id uuid;
  v_org_id uuid;                                  -- #403: caller org for required organization_id
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id, name, organization_id INTO v_signer_id, v_signer_name, v_org_id FROM public.members WHERE auth_id = auth.uid();
  IF v_signer_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  -- ADR-0044: V4 catalog gate (manage_platform)
  IF NOT public.can_by_member(v_signer_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Requires manage_platform permission';
  END IF;

  SELECT * INTO v_proposal FROM public.pending_manual_version_approvals WHERE id = p_proposal_id;
  IF v_proposal.id IS NULL THEN
    RETURN jsonb_build_object('error', 'proposal_not_found');
  END IF;

  IF v_proposal.status <> 'pending' THEN
    RETURN jsonb_build_object('error', 'proposal_not_pending', 'current_status', v_proposal.status);
  END IF;

  -- 24h window enforcement
  IF v_proposal.expires_at <= now() THEN
    UPDATE public.pending_manual_version_approvals
    SET status = 'expired', updated_at = now()
    WHERE id = p_proposal_id AND status = 'pending';
    RETURN jsonb_build_object('error', 'proposal_expired', 'expired_at', v_proposal.expires_at);
  END IF;

  -- 2-of-N: signer must be different from proposer
  IF v_signer_id = v_proposal.proposed_by THEN
    RETURN jsonb_build_object('error', 'self_signoff_forbidden',
      'message', 'Proposer cannot confirm their own proposal — 2-of-N requires different signoff');
  END IF;

  -- Re-validate approved CRs (in case some were unapproved during the 24h window)
  SELECT count(*) INTO v_count FROM public.change_requests WHERE status = 'approved';
  IF v_count = 0 THEN RETURN jsonb_build_object('error', 'no_approved_crs_at_confirm'); END IF;

  -- Re-validate version label not used since proposal
  IF EXISTS (
    SELECT 1 FROM public.governance_documents
    WHERE doc_type = 'manual' AND version = v_proposal.version_label
  ) THEN
    RETURN jsonb_build_object('error', 'version_label_now_in_use');
  END IF;

  -- Execute the actual manual version generation
  SELECT COALESCE(jsonb_agg(jsonb_build_object('cr_number', cr_number, 'title', title, 'category', category,
    'approved_at', approved_at) ORDER BY cr_number), '[]'::jsonb) INTO v_approved_crs
  FROM public.change_requests WHERE status = 'approved';

  SELECT version INTO v_previous_version FROM public.governance_documents
  WHERE doc_type = 'manual' AND status = 'active' ORDER BY created_at DESC LIMIT 1;

  UPDATE public.governance_documents SET status = 'superseded'
  WHERE doc_type = 'manual' AND status = 'active';

  INSERT INTO public.governance_documents (title, doc_type, version, status, description, valid_from,
    organization_id, visibility_class, acknowledgement_mode)
  VALUES (
    'Manual de Governança e Operações — ' || v_proposal.version_label,
    'manual',
    v_proposal.version_label,
    'active',
    'Versão gerada via 2-of-N approval (ADR-0044). ' || v_count::text ||
      ' CRs incorporados. Proposto por ' || (SELECT name FROM public.members WHERE id = v_proposal.proposed_by) ||
      '; confirmado por ' || v_signer_name || '. ' || COALESCE(v_proposal.notes, ''),
    now(),
    -- #403: required (NOT NULL, no default) since W1a M2 (#315); values mirror existing doc_type='manual' rows.
    v_org_id, 'active_members', 'informational'
  )
  RETURNING id INTO v_doc_id;

  UPDATE public.change_requests
  SET status = 'implemented',
      implemented_at = now(),
      implemented_by = v_signer_id,
      manual_version_from = COALESCE(v_previous_version, 'R2'),
      manual_version_to = v_proposal.version_label
  WHERE status = 'approved';

  -- Update proposal: status='confirmed', signoff captured
  UPDATE public.pending_manual_version_approvals
  SET status = 'confirmed',
      signoff_member_id = v_signer_id,
      signoff_at = now(),
      governance_document_id = v_doc_id,
      updated_at = now()
  WHERE id = p_proposal_id;

  -- Audit log: confirmation event with both actors
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_signer_id, 'manual_version_confirmed', 'governance_document', v_doc_id,
    jsonb_build_object(
      'proposal_id', p_proposal_id,
      'proposed_by', v_proposal.proposed_by,
      'signoff_by', v_signer_id,
      'version', v_proposal.version_label,
      'previous', v_previous_version,
      'crs_count', v_count,
      'notes', v_proposal.notes
    ));

  -- Notify chapter board members + sponsors of new manual version
  FOR v_recipient_id IN
    SELECT DISTINCT m.id
    FROM public.members m
    JOIN public.persons p ON p.legacy_member_id = m.id
    JOIN public.auth_engagements ae ON ae.person_id = p.id
    WHERE m.is_active = true
      AND ae.is_authoritative = true
      AND (
        (ae.kind = 'volunteer' AND ae.role IN ('manager','deputy_manager','co_gp'))
        OR (ae.kind = 'chapter_board' AND ae.role IN ('liaison','board_member'))
        OR (ae.kind = 'sponsor' AND ae.role = 'sponsor')
      )
  LOOP
    PERFORM public.create_notification(
      v_recipient_id,
      'governance_manual_proposed',
      'governance_document',
      v_doc_id,
      'Manual ' || v_proposal.version_label || ' publicado',
      v_signer_id,
      v_count::text || ' alterações incorporadas. Proposto e confirmado por 2-of-N approval.'
    );
  END LOOP;

  -- Announcement draft
  INSERT INTO public.announcements (title, message, type, is_active, created_by, starts_at)
  VALUES (
    'Manual de Governança ' || v_proposal.version_label || ' publicado',
    'O Manual foi atualizado com ' || v_count::text || ' alterações aprovadas pelos presidentes dos capítulos (2-of-N approval).',
    'governance',
    false,
    v_signer_id,
    now()
  );

  RETURN jsonb_build_object(
    'success', true,
    'document_id', v_doc_id,
    'version', v_proposal.version_label,
    'previous_version', v_previous_version,
    'crs_implemented', v_approved_crs,
    'proposed_by', v_proposal.proposed_by,
    'signoff_by', v_signer_id,
    'proposed_at', v_proposal.proposed_at,
    'confirmed_at', now()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.link_attachment_to_governance(p_attachment_id uuid, p_title text, p_signed_at timestamp with time zone DEFAULT now(), p_parties text[] DEFAULT '{}'::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_member_id uuid; v_attachment record; v_doc_id uuid; v_org_id uuid;
BEGIN
  SELECT id, organization_id INTO v_member_id, v_org_id FROM members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL OR NOT public.can_by_member(v_member_id, 'manage_platform'::text) THEN
    RETURN jsonb_build_object('error', 'not_authorized');
  END IF;

  SELECT * INTO v_attachment FROM partner_attachments WHERE id = p_attachment_id;
  IF v_attachment IS NULL THEN RETURN jsonb_build_object('error', 'attachment_not_found'); END IF;

  INSERT INTO governance_documents (title, doc_type, status, pdf_url, partner_entity_id, signed_at, parties, valid_from,
    organization_id, visibility_class, acknowledgement_mode)
  VALUES (p_title, 'cooperation_agreement', 'active', v_attachment.file_url,
    v_attachment.partner_entity_id, p_signed_at, p_parties, p_signed_at,
    -- #403: required since W1a M2 (#315); mirrors existing cooperation_agreement rows.
    v_org_id, 'active_members', 'legal_signature')
  RETURNING id INTO v_doc_id;

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member_id, 'attachment_linked_to_governance', 'governance_document', v_doc_id,
    jsonb_build_object('attachment_id', p_attachment_id, 'title', p_title));

  RETURN jsonb_build_object('success', true, 'governance_document_id', v_doc_id);
END;
$function$;

-- Sanity: both bodies must now reference all three previously-omitted required columns.
DO $sanity$
DECLARE v_cmv text; v_lat text;
BEGIN
  SELECT prosrc INTO v_cmv FROM pg_proc WHERE proname='confirm_manual_version' AND pronamespace='public'::regnamespace;
  SELECT prosrc INTO v_lat FROM pg_proc WHERE proname='link_attachment_to_governance' AND pronamespace='public'::regnamespace;
  IF v_cmv !~ 'organization_id' OR v_cmv !~ 'visibility_class' OR v_cmv !~ 'acknowledgement_mode' THEN
    RAISE EXCEPTION '#403: confirm_manual_version body missing one of the 3 required governance_documents columns';
  END IF;
  IF v_lat !~ 'organization_id' OR v_lat !~ 'visibility_class' OR v_lat !~ 'acknowledgement_mode' THEN
    RAISE EXCEPTION '#403: link_attachment_to_governance body missing one of the 3 required governance_documents columns';
  END IF;
END $sanity$;

NOTIFY pgrst, 'reload schema';
