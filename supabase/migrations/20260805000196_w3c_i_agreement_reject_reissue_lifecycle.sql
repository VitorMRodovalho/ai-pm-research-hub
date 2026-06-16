-- Wave 3c-i (B8, #740 / ADR-0104) — volunteer-agreement signature lifecycle: reject + reissue.
--
-- Adds the two genuinely-new terminal states to the Termo de Voluntariado lifecycle and the
-- board/admin actions that produce them, plus a domain CHECK. PM decisions (2026-06-16):
--   (1) rejection applies BOTH pre- AND post-counter-signature (revoke+reissue a counter-signed term);
--   (2) 'superseded' arises ONLY on reissue — ending an engagement does NOT touch the term
--       (the term is historical evidence of the signed period);
--   (3) DB-first slice (this PR); admin panel + member screens + verify/summary display are 3c-ii.
--
-- DESIGN — 'countersigned' is a DERIVED sub-state, not a status value (low blast radius).
--   Counter-signing already sets counter_signed_at/by + counter_signature_hash and the FE derives
--   "counter-signed" from counter_signed_by IS NOT NULL (has_counter_signature). A valid, fully-executed
--   term stays status='issued'. Flipping to a 'countersigned' status would ripple through verify_certificate,
--   check_my_tcv_readiness, the sign() already-signed guard, and _trg_auto_link_volunteer_engagement_to_cycle_cert
--   (all key on status='issued' = "valid/signed") with NO behavioral gain. So 'issued' remains "valid (maybe
--   counter-signed)"; only the new invalidation states are added. If admin filtering by an explicit
--   'countersigned' status is later wanted, it is a cheap follow-up.
--
-- State machine (volunteer_agreement):
--   issued      — member self-signed, valid (counter-signed iff counter_signed_by IS NOT NULL).
--   rejected    — board/admin invalidated it (pre- or post-counter-sign); member must re-sign. (reject_certificate)
--   superseded  — replaced by a reissue request; member must re-sign a corrected term. (reissue_agreement)
--   (revoked/draft kept in the domain for compatibility with existing issue paths.)
-- Because check_my_tcv_readiness / verify_certificate / the sign() guard all key on status='issued',
-- a rejected/superseded term automatically reads as "not signed / not valid" — re-signing is allowed
-- (the guard finds no 'issued' term) and produces a fresh 'issued' certificate. No change to those.
--
-- ROLLBACK: ALTER TABLE public.certificates DROP CONSTRAINT IF EXISTS certificates_status_check;
--           DROP FUNCTION IF EXISTS public.reject_certificate(uuid, text);
--           DROP FUNCTION IF EXISTS public.reissue_agreement(uuid, text);
--           then re-apply the prior counter_sign_certificate / get_my_certificates / _delivery_mode_for bodies.
--
-- Cross-ref: ADR-0104, #740 Wave 3 (B8).

-- ── Self-document the existing (un-migrated) revoked_by column reject_certificate writes ─────────
-- certificates.revoked_by exists in prod (uuid, nullable, no FK — verified live) but was created
-- outside the migration history (Dashboard/bulk DDL). ADD COLUMN IF NOT EXISTS is a no-op here and
-- closes the schema-drift gap so the column is captured in a migration file. #740 Wave 3c-i.
ALTER TABLE public.certificates ADD COLUMN IF NOT EXISTS revoked_by uuid;

-- ── Domain CHECK on certificates.status ──────────────────────────────────────────────────────────
ALTER TABLE public.certificates DROP CONSTRAINT IF EXISTS certificates_status_check;
ALTER TABLE public.certificates ADD CONSTRAINT certificates_status_check
  CHECK (status IS NULL OR status IN ('draft','issued','rejected','superseded','revoked'));

-- ── _delivery_mode_for: register the two new actionable notification types (ADR-0022) ────────────
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
    WHEN 'engagement_renewal_d7_urgent'  THEN 'transactional_immediate'
    -- p153 OPP-153.1: project_charter (TAP) notifications
    WHEN 'project_charter_invite'        THEN 'transactional_immediate'
    WHEN 'project_charter_approved'      THEN 'transactional_immediate'
    -- p159 S#1 T1 (2026-05-14): selection_termo_due é o "email principal" pós-VEP-Active
    WHEN 'selection_termo_due'           THEN 'transactional_immediate'
    -- p228 #260 W2 Leaf 1 (2026-05-23): Selection funnel Policy Matrix
    WHEN 'selection_approved'            THEN 'transactional_immediate'
    WHEN 'selection_interview_scheduled' THEN 'transactional_immediate'
    WHEN 'peer_review_requested'         THEN 'transactional_immediate'
    WHEN 'selection_evaluation_complete' THEN 'suppress'
    WHEN 'selection_interview_noshow'    THEN 'digest_weekly'
    -- p228 #260 W2 Leaf 2 (2026-05-23): admin reminder for overdue interviews
    WHEN 'selection_interview_overdue'   THEN 'digest_weekly'
    -- p228 #260 W2 Leaf 4 (2026-05-23): candidate invite to book interview after
    -- objective evaluations cleared + research_score >= cycle cutoff.
    WHEN 'selection_cutoff_approved'     THEN 'transactional_immediate'
    -- (end p228)
    -- #186 (2026-06-05): curation committee broadcast when an item enters curation_pending
    WHEN 'curation_item_submitted'       THEN 'transactional_immediate'
    WHEN 'engagement_renewal_d30'        THEN 'digest_weekly'
    WHEN 'engagement_renewal_d60_gp_aggregate' THEN 'digest_weekly'
    -- #625 F3 (2026-06-11): radar de renovação de filiação
    WHEN 'affiliation_renewal_d7_urgent'  THEN 'transactional_immediate'
    WHEN 'affiliation_renewal_d30'        THEN 'digest_weekly'
    WHEN 'affiliation_verification_stale' THEN 'digest_weekly'
    -- #740 Wave 3c-i (B8): agreement rejected / reissued — member must re-sign, deliver immediately
    WHEN 'volunteer_agreement_rejected'  THEN 'transactional_immediate'
    WHEN 'volunteer_agreement_reissued'  THEN 'transactional_immediate'
    WHEN 'attendance_detractor'          THEN 'suppress'
    WHEN 'info'                          THEN 'suppress'
    WHEN 'system'                        THEN 'suppress'
    ELSE 'digest_weekly'
  END;
$function$;

-- ── counter_sign_certificate: only a valid (status='issued') term is counter-signable ────────────
CREATE OR REPLACE FUNCTION public.counter_sign_certificate(p_certificate_id uuid, p_signed_ip text DEFAULT NULL::text, p_signed_user_agent text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_chapter text;
  v_caller_person_id uuid;
  v_is_manage_member boolean;
  v_is_chapter_board boolean;
  v_cert record;
  v_contracting_chapter text;
  v_hash text;
  v_signed_at timestamptz := now();
  v_ip inet := NULL;
BEGIN
  p_signed_user_agent := left(p_signed_user_agent, 500);

  SELECT m.id, m.chapter, m.person_id
    INTO v_caller_id, v_caller_chapter, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  v_is_manage_member := public.can_by_member(v_caller_id, 'manage_member');
  v_is_chapter_board := EXISTS (
    SELECT 1 FROM public.auth_engagements ae
    WHERE ae.person_id = v_caller_person_id
      AND ae.kind = 'chapter_board'
      AND ae.status = 'active'
  );

  IF NOT v_is_manage_member AND NOT v_is_chapter_board THEN
    RETURN jsonb_build_object('error', 'not_authorized');
  END IF;

  SELECT * INTO v_cert FROM public.certificates WHERE id = p_certificate_id;
  IF v_cert IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
  -- 3c-i: only a valid (issued) term is counter-signable; rejected/superseded/revoked/draft are not.
  IF v_cert.status IS DISTINCT FROM 'issued' THEN
    RETURN jsonb_build_object('error', 'not_signable', 'status', v_cert.status);
  END IF;
  IF v_cert.counter_signed_by IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'already_counter_signed');
  END IF;

  -- 3c-i (security review): the contracting party is ALWAYS the contracting chapter (PMI-GO, C3).
  -- When a legacy term's snapshot omits contracting_chapter, fall back to the registry contracting
  -- chapter — NOT the target member's chapter (which would let a board of the member's own chapter
  -- counter-sign/reject a term whose real contracting party is PMI-GO).
  v_contracting_chapter := COALESCE(
    v_cert.content_snapshot->>'contracting_chapter',
    (SELECT 'PMI-' || cr.chapter_code FROM public.chapter_registry cr
      WHERE cr.is_contracting_chapter AND cr.is_active LIMIT 1)
  );

  IF v_is_chapter_board AND NOT v_is_manage_member THEN
    IF v_contracting_chapter IS DISTINCT FROM v_caller_chapter THEN
      RETURN jsonb_build_object('error', 'not_authorized_different_chapter');
    END IF;
  END IF;

  -- 3c-i bugfix: convert_to/sha256 live in pg_catalog, not public. The prior body called
  -- public.convert_to/public.sha256 under SET search_path TO '' → unresolvable, so EVERY
  -- counter-sign raised "function public.convert_to does not exist". Unqualified names resolve
  -- via pg_catalog (always in the implicit path). The 33 counter-signed certs in prod came from
  -- bulk paths, not this RPC (only 1 counter_sign audit event existed). #740 Wave 3c-i.
  v_hash := encode(sha256(convert_to(
    COALESCE(v_cert.signature_hash,'') || v_caller_id::text || v_signed_at::text || 'nucleo-ia-countersign-salt', 'UTF8'
  )), 'hex');

  BEGIN
    IF p_signed_ip IS NOT NULL AND length(trim(p_signed_ip)) > 0 THEN
      v_ip := p_signed_ip::inet;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_ip := NULL;
  END;

  UPDATE public.certificates
  SET counter_signed_by = v_caller_id,
      counter_signed_at = v_signed_at,
      counter_signature_hash = v_hash
  WHERE id = p_certificate_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'certificate_counter_signed', 'certificate', p_certificate_id,
    jsonb_build_object(
      'verification_code', v_cert.verification_code,
      'type', v_cert.type,
      'contracting_chapter', v_contracting_chapter,
      'counter_signature_hash', v_hash,
      'counter_signed_at', v_signed_at,
      'counter_signer_ip', v_ip::text,
      'counter_signer_user_agent', p_signed_user_agent
    ));

  INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
  VALUES (v_cert.member_id, 'certificate_ready',
    'Seu ' || v_cert.title || ' esta pronto!',
    'O documento foi contra-assinado e esta disponivel. Codigo: ' || v_cert.verification_code,
    '/certificates', 'certificate', p_certificate_id,
    public._delivery_mode_for('certificate_ready'));

  RETURN jsonb_build_object(
    'success', true,
    'counter_signature_hash', v_hash,
    'counter_signed_at', v_signed_at
  );
END;
$function$;

-- ── get_my_certificates: hide superseded (replaced) along with revoked; keep rejected visible ────
CREATE OR REPLACE FUNCTION public.get_my_certificates(p_include_volunteer_agreements boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_member_id uuid; result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', c.id, 'type', c.type, 'title', c.title, 'cycle', c.cycle, 'status', c.status,
    'verification_code', c.verification_code, 'issued_at', c.issued_at,
    'issued_by_name', ib.name, 'counter_signed_by_name', cs.name,
    'counter_signed_at', c.counter_signed_at, 'period_start', c.period_start,
    'period_end', c.period_end, 'language', c.language,
    'has_counter_signature', c.counter_signed_by IS NOT NULL, 'signature_hash', c.signature_hash,
    'function_role', c.function_role
  ) ORDER BY c.issued_at DESC), '[]'::jsonb) INTO result
  FROM certificates c
  LEFT JOIN members ib ON ib.id = c.issued_by
  LEFT JOIN members cs ON cs.id = c.counter_signed_by
  WHERE c.member_id = v_member_id
    AND COALESCE(c.status, 'issued') NOT IN ('revoked', 'superseded')
    AND (p_include_volunteer_agreements OR c.type != 'volunteer_agreement');
  RETURN result;
END;
$function$;

-- ── reject_certificate(p_certificate_id, p_reason) — board/admin invalidates a term → 'rejected' ──
-- Authority mirrors counter_sign_certificate: manage_member OR PMI-GO chapter_board (same contracting
-- chapter). Applies to a valid (issued) term whether or not it is already counter-signed (PM decision:
-- rejection works pre- AND post-counter-sign). Records the invalidation in revoked_at/by/reason, unlinks
-- the engagement so the volunteer reads as needing to re-sign, and notifies the member to re-sign.
CREATE OR REPLACE FUNCTION public.reject_certificate(p_certificate_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_chapter text;
  v_caller_person_id uuid;
  v_is_manage_member boolean;
  v_is_chapter_board boolean;
  v_cert record;
  v_contracting_chapter text;
BEGIN
  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RETURN jsonb_build_object('error', 'reason_required');
  END IF;
  p_reason := left(trim(p_reason), 500);  -- 3c-i (security review): cap free-text reason

  SELECT m.id, m.chapter, m.person_id
    INTO v_caller_id, v_caller_chapter, v_caller_person_id
  FROM members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  v_is_manage_member := public.can_by_member(v_caller_id, 'manage_member');
  v_is_chapter_board := EXISTS (
    SELECT 1 FROM auth_engagements ae
    WHERE ae.person_id = v_caller_person_id AND ae.kind = 'chapter_board' AND ae.status = 'active'
  );
  IF NOT v_is_manage_member AND NOT v_is_chapter_board THEN
    RETURN jsonb_build_object('error', 'not_authorized');
  END IF;

  SELECT * INTO v_cert FROM certificates WHERE id = p_certificate_id;
  IF v_cert IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
  IF v_cert.type != 'volunteer_agreement' THEN RETURN jsonb_build_object('error', 'not_an_agreement'); END IF;
  IF v_cert.status IS DISTINCT FROM 'issued' THEN
    RETURN jsonb_build_object('error', 'not_rejectable', 'status', v_cert.status);
  END IF;

  -- 3c-i (security review): fall back to the registry contracting chapter (PMI-GO, C3), not the
  -- target member's chapter, so a board cannot reject a term whose real contracting party is PMI-GO.
  v_contracting_chapter := COALESCE(
    v_cert.content_snapshot->>'contracting_chapter',
    (SELECT 'PMI-' || chapter_code FROM chapter_registry WHERE is_contracting_chapter AND is_active LIMIT 1)
  );
  IF v_is_chapter_board AND NOT v_is_manage_member
     AND v_contracting_chapter IS DISTINCT FROM v_caller_chapter THEN
    RETURN jsonb_build_object('error', 'not_authorized_different_chapter');
  END IF;

  UPDATE certificates
     SET status = 'rejected', revoked_at = now(), revoked_by = v_caller_id,
         revoked_reason = p_reason, updated_at = now()
   WHERE id = p_certificate_id;

  -- Unlink the engagement so check/readiness/digests read the volunteer as unsigned again.
  UPDATE engagements SET agreement_certificate_id = NULL
   WHERE agreement_certificate_id = p_certificate_id;

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'volunteer_agreement_rejected', 'certificate', p_certificate_id,
    jsonb_build_object(
      'verification_code', v_cert.verification_code, 'reason', p_reason,
      'was_counter_signed', v_cert.counter_signed_by IS NOT NULL,
      'counter_signature_hash', v_cert.counter_signature_hash,
      'contracting_chapter', v_contracting_chapter, 'member_id', v_cert.member_id));

  INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
  VALUES (v_cert.member_id, 'volunteer_agreement_rejected',
    'Seu Termo de Voluntariado precisa ser reassinado',
    'Motivo: ' || p_reason || '. Por favor revise seus dados e assine novamente.',
    '/volunteer-agreement', 'certificate', p_certificate_id,
    public._delivery_mode_for('volunteer_agreement_rejected'));

  RETURN jsonb_build_object('success', true, 'certificate_id', p_certificate_id, 'status', 'rejected');
END;
$function$;

-- ── reissue_agreement(p_member_id, p_reason) — admin supersedes a member's term → 'superseded' ───
-- Authority: manage_member (operational admin correction; e.g. template updated, data correction).
-- Marks the member's current valid (issued) cycle term as 'superseded', unlinks the engagement, and
-- notifies the member to re-sign. The member's next sign_volunteer_agreement creates a fresh 'issued'
-- term (its already-signed guard finds no 'issued' term once this one is superseded).
CREATE OR REPLACE FUNCTION public.reissue_agreement(p_member_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cert record;
  v_cycle int := EXTRACT(YEAR FROM now())::int;
BEGIN
  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RETURN jsonb_build_object('error', 'reason_required');
  END IF;
  p_reason := left(trim(p_reason), 500);  -- 3c-i (security review): cap free-text reason

  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RETURN jsonb_build_object('error', 'not_authorized');
  END IF;

  SELECT * INTO v_cert FROM certificates
   WHERE member_id = p_member_id AND type = 'volunteer_agreement'
     AND status = 'issued' AND cycle = v_cycle
   ORDER BY issued_at DESC LIMIT 1;
  IF v_cert IS NULL THEN RETURN jsonb_build_object('error', 'no_active_agreement'); END IF;

  UPDATE certificates SET status = 'superseded', updated_at = now() WHERE id = v_cert.id;

  UPDATE engagements SET agreement_certificate_id = NULL
   WHERE agreement_certificate_id = v_cert.id;

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'volunteer_agreement_reissued', 'certificate', v_cert.id,
    jsonb_build_object(
      'verification_code', v_cert.verification_code, 'reason', p_reason,
      'was_counter_signed', v_cert.counter_signed_by IS NOT NULL,
      'cycle', v_cycle, 'member_id', p_member_id));

  INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
  VALUES (p_member_id, 'volunteer_agreement_reissued',
    'Reassine seu Termo de Voluntariado',
    'Seu termo precisa ser reemitido. Motivo: ' || p_reason || '. Por favor assine novamente.',
    '/volunteer-agreement', 'certificate', v_cert.id,
    public._delivery_mode_for('volunteer_agreement_reissued'));

  RETURN jsonb_build_object('success', true, 'superseded_certificate_id', v_cert.id, 'status', 'superseded');
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.reject_certificate(uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.reissue_agreement(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.reject_certificate(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reissue_agreement(uuid, text) TO authenticated;
-- Re-issue grants for the CREATE OR REPLACE'd functions so the migration is self-documenting
-- (CREATE OR REPLACE preserves existing grants, but the repo convention re-states them).
GRANT EXECUTE ON FUNCTION public.counter_sign_certificate(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_certificates(boolean) TO authenticated;

NOTIFY pgrst, 'reload schema';
