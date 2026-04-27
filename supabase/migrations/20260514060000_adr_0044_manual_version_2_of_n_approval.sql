-- ============================================================
-- ADR-0044: generate_manual_version V3→V4 + 2-of-N approval pattern
-- Section A: New table pending_manual_version_approvals
-- Section B: propose_manual_version (creates pending; V4 manage_platform)
-- Section C: confirm_manual_version (requires 2nd signoff; V4 manage_platform)
-- Section D: cancel_manual_version_proposal (proposer-only cancel)
-- Section E: DROP legacy generate_manual_version (replaced by propose+confirm)
-- Section F: notification type governance_manual_proposed + _delivery_mode_for update
-- Cross-references: ADR-0007, ADR-0011, ADR-0016 (IP ratification 2-of-N pattern), ADR-0022 (notification catalog)
-- Rollback: DROP triggers + DROP table + DROP new fns + restore generate_manual_version
-- ============================================================

-- ── Section A: pending_manual_version_approvals table ──────
CREATE TABLE IF NOT EXISTS public.pending_manual_version_approvals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_label text NOT NULL,
  notes text,
  proposed_by uuid NOT NULL REFERENCES public.members(id),
  proposed_at timestamptz NOT NULL DEFAULT now(),
  signoff_member_id uuid REFERENCES public.members(id),
  signoff_at timestamptz,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','confirmed','expired','cancelled')),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '24 hours'),
  governance_document_id uuid REFERENCES public.governance_documents(id),
  cancelled_at timestamptz,
  cancelled_by uuid REFERENCES public.members(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pending_manual_version_approvals_status
  ON public.pending_manual_version_approvals(status, expires_at)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_pending_manual_version_approvals_proposer
  ON public.pending_manual_version_approvals(proposed_by);

ALTER TABLE public.pending_manual_version_approvals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pending_mva_select_manage_platform ON public.pending_manual_version_approvals;
CREATE POLICY pending_mva_select_manage_platform ON public.pending_manual_version_approvals
  FOR SELECT TO authenticated USING (
    public.can_by_member((SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid()), 'manage_platform')
  );

REVOKE ALL ON public.pending_manual_version_approvals FROM anon;
GRANT SELECT ON public.pending_manual_version_approvals TO authenticated;

-- ── Section F: notification catalog ────────────────────────
CREATE OR REPLACE FUNCTION public._delivery_mode_for(p_type text)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE PARALLEL SAFE
  SET search_path TO ''
AS $function$
  SELECT CASE p_type
    WHEN 'volunteer_agreement_signed'    THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_pending'  THEN 'transactional_immediate'
    WHEN 'system_alert'                  THEN 'transactional_immediate'
    WHEN 'certificate_ready'             THEN 'transactional_immediate'
    WHEN 'member_offboarded'             THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_advanced'    THEN 'transactional_immediate'
    WHEN 'ip_ratification_chain_approved'   THEN 'transactional_immediate'
    WHEN 'ip_ratification_awaiting_members' THEN 'transactional_immediate'
    WHEN 'webinar_status_confirmed'      THEN 'transactional_immediate'
    WHEN 'webinar_status_completed'      THEN 'transactional_immediate'
    WHEN 'webinar_status_cancelled'      THEN 'transactional_immediate'
    WHEN 'weekly_card_digest_member'     THEN 'transactional_immediate'
    WHEN 'governance_cr_new'             THEN 'transactional_immediate'
    WHEN 'governance_cr_vote'            THEN 'transactional_immediate'
    WHEN 'governance_cr_approved'        THEN 'transactional_immediate'
    WHEN 'sponsor_finance_entry_logged'  THEN 'transactional_immediate'
    WHEN 'governance_manual_proposed'    THEN 'transactional_immediate'
    WHEN 'attendance_detractor'          THEN 'suppress'
    WHEN 'info'                          THEN 'suppress'
    WHEN 'system'                        THEN 'suppress'
    ELSE 'digest_weekly'
  END;
$function$;

-- ── Section B: propose_manual_version ──────────────────────
CREATE OR REPLACE FUNCTION public.propose_manual_version(
  p_version_label text,
  p_notes text DEFAULT NULL::text
) RETURNS jsonb
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_proposer_id uuid;
  v_count int;
  v_existing_pending uuid;
  v_proposal_id uuid;
  v_admin_id uuid;
  v_proposer_name text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id, name INTO v_proposer_id, v_proposer_name FROM public.members WHERE auth_id = auth.uid();
  IF v_proposer_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  -- ADR-0044: V4 catalog gate (manage_platform)
  IF NOT public.can_by_member(v_proposer_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Requires manage_platform permission';
  END IF;

  IF p_version_label IS NULL OR length(trim(p_version_label)) = 0 THEN
    RETURN jsonb_build_object('error', 'version_label_required');
  END IF;

  SELECT count(*) INTO v_count FROM public.change_requests WHERE status = 'approved';
  IF v_count = 0 THEN RETURN jsonb_build_object('error', 'no_approved_crs'); END IF;

  SELECT id INTO v_existing_pending
  FROM public.pending_manual_version_approvals
  WHERE status = 'pending' AND expires_at > now()
  LIMIT 1;
  IF v_existing_pending IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'pending_proposal_exists', 'existing_proposal_id', v_existing_pending);
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.governance_documents
    WHERE doc_type = 'manual' AND version = p_version_label
  ) THEN
    RETURN jsonb_build_object('error', 'version_label_in_use', 'version_label', p_version_label);
  END IF;

  INSERT INTO public.pending_manual_version_approvals (version_label, notes, proposed_by)
  VALUES (p_version_label, p_notes, v_proposer_id)
  RETURNING id INTO v_proposal_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_proposer_id, 'manual_version_proposed', 'pending_manual_version_approval', v_proposal_id,
    jsonb_build_object('version_label', p_version_label, 'notes', p_notes, 'crs_count', v_count));

  FOR v_admin_id IN
    SELECT DISTINCT m.id
    FROM public.members m
    JOIN public.persons p ON p.legacy_member_id = m.id
    JOIN public.auth_engagements ae ON ae.person_id = p.id
    JOIN public.engagement_kind_permissions ekp
      ON ekp.kind = ae.kind AND ekp.role = ae.role AND ekp.action = 'manage_platform'
    WHERE m.is_active = true
      AND ae.is_authoritative = true
      AND m.id <> v_proposer_id
  LOOP
    PERFORM public.create_notification(
      v_admin_id,
      'governance_manual_proposed',
      'pending_manual_version_approval',
      v_proposal_id,
      'Manual ' || p_version_label || ' proposto por ' || v_proposer_name || ' — assinatura pendente',
      v_proposer_id,
      'Aguardando 2ª assinatura para confirmar (24h). ' || v_count::text || ' CRs aprovados serão incorporados.'
    );
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'proposal_id', v_proposal_id,
    'version_label', p_version_label,
    'crs_count', v_count,
    'expires_at', (now() + interval '24 hours')
  );
END;
$function$;

-- ── Section C: confirm_manual_version ──────────────────────
CREATE OR REPLACE FUNCTION public.confirm_manual_version(
  p_proposal_id uuid
) RETURNS jsonb
  LANGUAGE plpgsql SECURITY DEFINER
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
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id, name INTO v_signer_id, v_signer_name FROM public.members WHERE auth_id = auth.uid();
  IF v_signer_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

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

  IF v_proposal.expires_at <= now() THEN
    UPDATE public.pending_manual_version_approvals
    SET status = 'expired', updated_at = now()
    WHERE id = p_proposal_id AND status = 'pending';
    RETURN jsonb_build_object('error', 'proposal_expired', 'expired_at', v_proposal.expires_at);
  END IF;

  IF v_signer_id = v_proposal.proposed_by THEN
    RETURN jsonb_build_object('error', 'self_signoff_forbidden',
      'message', 'Proposer cannot confirm their own proposal — 2-of-N requires different signoff');
  END IF;

  SELECT count(*) INTO v_count FROM public.change_requests WHERE status = 'approved';
  IF v_count = 0 THEN RETURN jsonb_build_object('error', 'no_approved_crs_at_confirm'); END IF;

  IF EXISTS (
    SELECT 1 FROM public.governance_documents
    WHERE doc_type = 'manual' AND version = v_proposal.version_label
  ) THEN
    RETURN jsonb_build_object('error', 'version_label_now_in_use');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('cr_number', cr_number, 'title', title, 'category', category,
    'approved_at', approved_at) ORDER BY cr_number), '[]'::jsonb) INTO v_approved_crs
  FROM public.change_requests WHERE status = 'approved';

  SELECT version INTO v_previous_version FROM public.governance_documents
  WHERE doc_type = 'manual' AND status = 'active' ORDER BY created_at DESC LIMIT 1;

  UPDATE public.governance_documents SET status = 'superseded'
  WHERE doc_type = 'manual' AND status = 'active';

  INSERT INTO public.governance_documents (title, doc_type, version, status, description, valid_from)
  VALUES (
    'Manual de Governança e Operações — ' || v_proposal.version_label,
    'manual',
    v_proposal.version_label,
    'active',
    'Versão gerada via 2-of-N approval (ADR-0044). ' || v_count::text ||
      ' CRs incorporados. Proposto por ' || (SELECT name FROM public.members WHERE id = v_proposal.proposed_by) ||
      '; confirmado por ' || v_signer_name || '. ' || COALESCE(v_proposal.notes, ''),
    now()
  )
  RETURNING id INTO v_doc_id;

  UPDATE public.change_requests
  SET status = 'implemented',
      implemented_at = now(),
      implemented_by = v_signer_id,
      manual_version_from = COALESCE(v_previous_version, 'R2'),
      manual_version_to = v_proposal.version_label
  WHERE status = 'approved';

  UPDATE public.pending_manual_version_approvals
  SET status = 'confirmed',
      signoff_member_id = v_signer_id,
      signoff_at = now(),
      governance_document_id = v_doc_id,
      updated_at = now()
  WHERE id = p_proposal_id;

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

-- ── Section D: cancel_manual_version_proposal ──────────────
CREATE OR REPLACE FUNCTION public.cancel_manual_version_proposal(
  p_proposal_id uuid,
  p_reason text DEFAULT NULL::text
) RETURNS jsonb
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_proposal record;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Requires manage_platform permission';
  END IF;

  SELECT * INTO v_proposal FROM public.pending_manual_version_approvals WHERE id = p_proposal_id;
  IF v_proposal.id IS NULL THEN
    RETURN jsonb_build_object('error', 'proposal_not_found');
  END IF;
  IF v_proposal.status <> 'pending' THEN
    RETURN jsonb_build_object('error', 'proposal_not_pending', 'current_status', v_proposal.status);
  END IF;

  UPDATE public.pending_manual_version_approvals
  SET status = 'cancelled',
      cancelled_at = now(),
      cancelled_by = v_caller_id,
      notes = COALESCE(notes, '') || E'\n\nCancelled: ' || COALESCE(p_reason, '(no reason provided)'),
      updated_at = now()
  WHERE id = p_proposal_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'manual_version_proposal_cancelled', 'pending_manual_version_approval', p_proposal_id,
    jsonb_build_object('reason', p_reason, 'proposed_by', v_proposal.proposed_by, 'version_label', v_proposal.version_label));

  RETURN jsonb_build_object('success', true, 'proposal_id', p_proposal_id, 'cancelled_at', now());
END;
$function$;

-- ── Section E: DROP legacy generate_manual_version ─────────
DROP FUNCTION IF EXISTS public.generate_manual_version(text, text);

-- ── Defense-in-depth REVOKE ────────────────────────────────
REVOKE EXECUTE ON FUNCTION public.propose_manual_version(text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.confirm_manual_version(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.cancel_manual_version_proposal(uuid, text) FROM anon;

-- ── Cache reload ───────────────────────────────────────────
NOTIFY pgrst, 'reload schema';
