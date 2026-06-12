-- 20260805000154_654_sequential_gate_write_path_guard.sql
--
-- #654 — enforce sequential gate ordering on the WRITE path of IP ratification.
--
-- The read-path (#653, migration 20260805000153_pending_ratifications_sequential_gating)
-- hides out-of-order gates from get_pending_ratifications. But the WRITE path
-- (sign_ip_ratification -> _can_sign_gate) had NO ordering check: any member
-- eligible for a later gate (e.g. `volunteers_in_role_active`, order 5) could call
-- sign_ip_ratification before submitter_acceptance (order 3) / president_go (order 4)
-- were signed and — because that gate sets v_is_member_ratify = true — mint a
-- premature IPRAT certificate + member_document_signatures row, with the term not
-- yet presidentially approved. Same leak class as #648/#653, on the write surface.
--
-- Live repro (prod, 2026-06-12), chain d72916d7 (volunteer term):
--   _can_sign_gate(<active volunteer>, chain, 'volunteers_in_role_active') = TRUE
--   while submitter_acceptance & president_go had 0 signoffs (priors UNMET).
--
-- ── Why NOT make _can_sign_gate itself ordering-aware (issue Option B nuance) ──
-- _can_sign_gate is the PURE authority predicate and is reused as the
-- 'all'-threshold DENOMINATOR (count of members who *could* sign a gate) inside
-- get_pending_ratifications, sign_ip_ratification.v_gates_remaining and the new
-- _gate_threshold_met below. If it became ordering-aware, that denominator would
-- collapse to 0 while priors are unmet, making `count(signoffs)=0 >= eligible=0`
-- FALSELY report an 'all' gate as met (and recurse). So the ordering check must
-- live OUTSIDE the authority predicate — exactly as the read-path does it.
--
-- Fix: extract the duplicated "threshold met?" + "prior gates satisfied?" logic
-- into two shared helpers, then consume them at all three sites (single source):
--   (1) sign_ip_ratification: reject out-of-order signatures (the actual fix);
--   (2) sign_ip_ratification.v_gates_remaining: via _gate_threshold_met;
--   (3) get_pending_ratifications: via _prior_gates_satisfied (behaviour
--       byte-identical to migration 153 — proven by a (chain x gate) differential).

-- ── helper 1: is a single gate's threshold met? (single source of truth) ──────
-- Body below is verbatim pg_get_functiondef() from live (GC-097 file==live;
-- inline rationale lives in the block comment above + COMMENT ON FUNCTION below).
CREATE OR REPLACE FUNCTION public._gate_threshold_met(p_chain_id uuid, p_gate jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
    WHEN (p_gate->>'threshold') = 'all' THEN
      (SELECT count(*) FROM public.approval_signoffs s
         WHERE s.approval_chain_id = p_chain_id AND s.gate_kind = (p_gate->>'kind')
           AND s.signoff_type IN ('approval','acknowledge'))
      >= (SELECT count(*) FROM public.members m
          WHERE m.is_active AND public._can_sign_gate(m.id, p_chain_id, p_gate->>'kind'))
    WHEN (p_gate->>'threshold') ~ '^[0-9]+$' AND (p_gate->>'threshold')::int > 0 THEN
      (SELECT count(*) FROM public.approval_signoffs s
         WHERE s.approval_chain_id = p_chain_id AND s.gate_kind = (p_gate->>'kind')
           AND s.signoff_type IN ('approval','acknowledge'))
      >= (p_gate->>'threshold')::int
    ELSE true
  END;
$function$;

COMMENT ON FUNCTION public._gate_threshold_met(uuid, jsonb) IS
  '#654 single-source: TRUE when the given gate (jsonb element of approval_chains.gates) has met its threshold on the chain. threshold all = all authorized signers signed; numeric N = >=N signoffs; 0/non-numeric = trivially met. Uses the PURE _can_sign_gate as the all-threshold denominator (do not make _can_sign_gate ordering-aware or this collapses).';

-- ── helper 2: are all lower-ordered gates satisfied for this target gate? ──────
-- Body below is verbatim pg_get_functiondef() from live (GC-097 file==live).
-- TRUE unless some gate with a strictly-lower `order` than the target gate has NOT
-- met its threshold — mirrors the read-path NOT EXISTS guard in get_pending_ratifications.
-- Absent target / no priors -> empty inner set -> TRUE (caller _can_sign_gate already
-- rejects absent gates).
CREATE OR REPLACE FUNCTION public._prior_gates_satisfied(p_chain_id uuid, p_gate_kind text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT NOT EXISTS (
    SELECT 1
    FROM public.approval_chains ac,
         jsonb_array_elements(ac.gates) gp
    WHERE ac.id = p_chain_id
      AND (gp->>'order')::int < (
        SELECT (g->>'order')::int
        FROM public.approval_chains ac2, jsonb_array_elements(ac2.gates) g
        WHERE ac2.id = p_chain_id AND g->>'kind' = p_gate_kind
        LIMIT 1)
      AND NOT public._gate_threshold_met(p_chain_id, gp)
  );
$function$;

COMMENT ON FUNCTION public._prior_gates_satisfied(uuid, text) IS
  '#654 single-source: TRUE when every gate ordered before p_gate_kind on the chain has met its threshold (_gate_threshold_met). Consumed by the write guard in sign_ip_ratification and the read-path get_pending_ratifications so display and write agree on ordering.';

-- Mirror the hardened grant surface of the sibling _can_sign_gate: the project's
-- ALTER DEFAULT PRIVILEGES auto-grants new public functions to PUBLIC/anon, which
-- would let an anon/ghost caller probe gate-progress booleans. Revoke that and keep
-- only authenticated + service_role (postgres = owner). Upholds the "anon/ghost gets
-- NOTHING" invariant (CLAUDE.md auth decision #6).
REVOKE EXECUTE ON FUNCTION public._gate_threshold_met(uuid, jsonb) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public._prior_gates_satisfied(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._gate_threshold_met(uuid, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._prior_gates_satisfied(uuid, text) TO authenticated, service_role;

-- ── (1)+(2): write-path guard + single-sourced v_gates_remaining ──────────────
-- Full body = verbatim live sign_ip_ratification with exactly two edits:
--   * NEW _prior_gates_satisfied guard right after the _can_sign_gate authority check;
--   * v_gates_remaining rewritten to use _gate_threshold_met (behaviour-equivalent).
CREATE OR REPLACE FUNCTION public.sign_ip_ratification(p_chain_id uuid, p_gate_kind text, p_signoff_type text DEFAULT 'approval'::text, p_sections_verified jsonb DEFAULT NULL::jsonb, p_comment_body text DEFAULT NULL::text, p_ue_consent_49_1_a boolean DEFAULT NULL::boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record; v_chain record; v_version record; v_doc record;
  v_signoff_id uuid; v_hash text; v_snapshot jsonb; v_existing uuid;
  v_all_satisfied boolean; v_cert_id uuid; v_cert_code text;
  v_gates_remaining int; v_mbr_signature_id uuid;
  v_is_eu boolean := false; v_ue_consent_required boolean := false;
  v_is_member_ratify boolean := false;
  v_policy_version_id uuid;
  v_policy_version_label text;
  v_notif_read_at timestamptz;
  v_notif_created_at timestamptz;
  v_notif_id uuid;
  v_ue_docs text[] := ARRAY[
    'Termo de Compromisso de Voluntário — Núcleo de IA & GP',
    'Adendo Retificativo ao Termo de Compromisso de Voluntario'];
BEGIN
  SELECT m.id, m.name, m.email, m.operational_role, m.pmi_id, m.chapter,
         m.designations, m.member_status, m.person_id
  INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN RETURN jsonb_build_object('error','not_authenticated'); END IF;

  IF NOT public._can_sign_gate(v_member.id, p_chain_id, p_gate_kind) THEN
    RETURN jsonb_build_object('error','access_denied','message','Member not authorized for gate_kind=' || p_gate_kind);
  END IF;

  -- #654: sequential gate ordering on the WRITE path (mirrors the read-path guard
  -- in get_pending_ratifications). A gate is signable only once every lower-ordered
  -- gate has met its threshold — blocks a later-gate-eligible member (e.g.
  -- volunteers_in_role_active) from minting a premature IPRAT certificate before
  -- submitter_acceptance / president_go have signed.
  IF NOT public._prior_gates_satisfied(p_chain_id, p_gate_kind) THEN
    RETURN jsonb_build_object('error','gate_order_not_satisfied',
      'message','Prior gates must meet their threshold before gate_kind=' || p_gate_kind || ' can be signed.');
  END IF;

  -- SEDIMENT-268.A fix: also select ac.organization_id so the INSERT below
  -- can satisfy approval_signoffs.organization_id NOT NULL (p256 W1a M1).
  SELECT ac.id, ac.status, ac.document_id, ac.version_id, ac.gates, ac.organization_id
  INTO v_chain FROM public.approval_chains ac WHERE ac.id = p_chain_id;
  IF v_chain.id IS NULL THEN RETURN jsonb_build_object('error','chain_not_found'); END IF;

  SELECT dv.id, dv.version_number, dv.version_label, dv.content_html, dv.locked_at
  INTO v_version FROM public.document_versions dv WHERE dv.id = v_chain.version_id;

  SELECT gd.id, gd.title, gd.doc_type INTO v_doc
  FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;

  SELECT id INTO v_existing FROM public.approval_signoffs
  WHERE approval_chain_id = p_chain_id AND gate_kind = p_gate_kind AND signer_id = v_member.id;
  IF v_existing IS NOT NULL THEN RETURN jsonb_build_object('error','already_signed','signoff_id',v_existing); END IF;

  v_is_member_ratify := (p_gate_kind IN ('member_ratification','volunteers_in_role_active'));

  IF v_is_member_ratify AND v_doc.title = ANY(v_ue_docs) THEN
    v_is_eu := public.is_eu_resident(v_member.person_id);
    IF v_is_eu THEN
      v_ue_consent_required := true;
      IF p_ue_consent_49_1_a IS NULL OR p_ue_consent_49_1_a = false THEN
        RETURN jsonb_build_object(
          'error', 'ue_consent_required',
          'message', 'EU resident must explicitly consent to Art. 49(1)(a) GDPR data transfer.',
          'document_title', v_doc.title,
          'applicable_clause', CASE
            WHEN v_doc.title = 'Termo de Compromisso de Voluntário — Núcleo de IA & GP' THEN 'Clausula 14'
            ELSE 'Art. 8' END);
      END IF;
    END IF;
  END IF;

  -- RF-III: snapshot Política vigente (current_version_id do doc_type=policy)
  SELECT gd.current_version_id, dv.version_label INTO v_policy_version_id, v_policy_version_label
  FROM public.governance_documents gd
  LEFT JOIN public.document_versions dv ON dv.id = gd.current_version_id
  WHERE gd.doc_type = 'policy' AND gd.status IN ('active','under_review')
  ORDER BY CASE WHEN gd.status='active' THEN 0 ELSE 1 END LIMIT 1;

  -- RF-V: evidence de ato concludente — read_at da notificação relacionada
  SELECT n.id, n.read_at, n.created_at
    INTO v_notif_id, v_notif_read_at, v_notif_created_at
  FROM public.notifications n
  WHERE n.recipient_id = v_member.id
    AND n.source_type = 'approval_chain'
    AND n.source_id::text = p_chain_id::text
    AND n.type LIKE 'ip_ratification_%'
  ORDER BY n.created_at DESC LIMIT 1;

  v_snapshot := jsonb_build_object(
    'document_id', v_doc.id, 'document_title', v_doc.title, 'doc_type', v_doc.doc_type,
    'version_id', v_version.id, 'version_number', v_version.version_number, 'version_label', v_version.version_label,
    'version_locked_at', v_version.locked_at,
    'signer_id', v_member.id, 'signer_name', v_member.name, 'signer_email', v_member.email,
    'signer_role', v_member.operational_role, 'signer_chapter', v_member.chapter,
    'signer_pmi_id', v_member.pmi_id, 'signer_designations', to_jsonb(v_member.designations),
    'gate_kind', p_gate_kind, 'signoff_type', p_signoff_type, 'signed_at', now(),
    'signer_is_eu_resident', v_is_eu,
    'ue_consent_recorded', COALESCE(p_ue_consent_49_1_a, false),
    'ue_consent_required_by_policy', v_ue_consent_required,
    'referenced_policy_version_id', v_policy_version_id,
    'referenced_policy_version_label', v_policy_version_label,
    'notification_id', v_notif_id,
    'notification_created_at', v_notif_created_at,
    'notification_read_at', v_notif_read_at,
    'notification_read_evidence', CASE WHEN v_notif_read_at IS NOT NULL THEN true ELSE false END
  );

  v_hash := encode(sha256(convert_to(v_snapshot::text || v_member.id::text || now()::text || 'nucleo-ia-ip-ratify-salt', 'UTF8')), 'hex');

  -- SEDIMENT-268.A fix: include organization_id (NOT NULL post-W1a M1) sourced
  -- from v_chain.organization_id (parent approval_chains row), preserving tenant
  -- integrity via FK chain.
  INSERT INTO public.approval_signoffs (
    approval_chain_id, organization_id, gate_kind, signer_id, signoff_type,
    signed_at, signature_hash, content_snapshot, sections_verified, comment_body,
    referenced_policy_version_id
  ) VALUES (
    p_chain_id, v_chain.organization_id, p_gate_kind, v_member.id, p_signoff_type,
    now(), v_hash, v_snapshot, p_sections_verified, p_comment_body,
    v_policy_version_id
  ) RETURNING id INTO v_signoff_id;

  -- #654: single-source the "gate not yet satisfied" test via _gate_threshold_met
  -- (behaviour-equivalent to the prior inline all/numeric counting).
  SELECT COUNT(*) INTO v_gates_remaining
  FROM jsonb_array_elements(v_chain.gates) g
  WHERE NOT public._gate_threshold_met(p_chain_id, g);

  v_all_satisfied := (v_gates_remaining = 0);

  IF v_is_member_ratify AND p_signoff_type = 'approval' THEN
    v_cert_code := 'IPRAT-' || EXTRACT(YEAR FROM now())::text || '-' || UPPER(SUBSTRING(gen_random_uuid()::text FROM 1 FOR 6));

    INSERT INTO public.certificates (
      member_id, type, title, description, cycle, issued_at, issued_by, verification_code,
      function_role, language, status, signature_hash, content_snapshot, template_id
    ) VALUES (
      v_member.id, 'ip_ratification',
      'Ratificacao IP — ' || v_doc.title,
      'Ratificacao do documento ' || v_doc.title || ' versao ' || v_version.version_label,
      EXTRACT(YEAR FROM now())::int, now(), v_member.id, v_cert_code,
      v_member.operational_role, 'pt-BR', 'issued', v_hash, v_snapshot, v_doc.id::text
    ) RETURNING id INTO v_cert_id;

    INSERT INTO public.member_document_signatures (
      member_id, document_id, signed_version_id, approval_chain_id,
      signoff_id, certificate_id, signed_at, is_current
    ) VALUES (v_member.id, v_doc.id, v_version.id, p_chain_id, v_signoff_id, v_cert_id, now(), true)
    RETURNING id INTO v_mbr_signature_id;
  END IF;

  IF v_all_satisfied AND v_chain.status = 'review' THEN
    UPDATE public.approval_chains SET status = 'approved', approved_at = now(), updated_at = now()
      WHERE id = p_chain_id;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member.id, 'ip_ratification_signoff', 'approval_signoff', v_signoff_id,
    jsonb_build_object('chain_id', p_chain_id, 'gate_kind', p_gate_kind, 'signoff_type', p_signoff_type,
      'document_id', v_doc.id, 'document_title', v_doc.title, 'version_label', v_version.version_label,
      'chain_satisfied', v_all_satisfied, 'certificate_id', v_cert_id,
      'signer_is_eu_resident', v_is_eu,
      'ue_consent_recorded', COALESCE(p_ue_consent_49_1_a, false),
      'referenced_policy_version_id', v_policy_version_id,
      'notification_read_evidence', (v_notif_read_at IS NOT NULL)));

  RETURN jsonb_build_object('success', true, 'signoff_id', v_signoff_id, 'signature_hash', v_hash,
    'gates_remaining', v_gates_remaining, 'chain_satisfied', v_all_satisfied,
    'certificate_id', v_cert_id, 'certificate_code', v_cert_code,
    'member_signature_id', v_mbr_signature_id, 'signed_at', now(),
    'signer_is_eu_resident', v_is_eu,
    'ue_consent_recorded', COALESCE(p_ue_consent_49_1_a, false),
    'referenced_policy_version_id', v_policy_version_id,
    'notification_read_evidence', (v_notif_read_at IS NOT NULL));
END;
$function$;

-- ── (3): read-path single-sourcing — get_pending_ratifications now calls the
-- shared _prior_gates_satisfied helper instead of an inline NOT EXISTS. The
-- replaced block is byte-for-byte the same predicate, so output is unchanged
-- (asserted by a (chain x gate) differential before this migration was finalised).
CREATE OR REPLACE FUNCTION public.get_pending_ratifications()
 RETURNS TABLE(chain_id uuid, document_id uuid, document_title text, doc_type text, version_id uuid, version_label text, version_locked_at timestamp with time zone, gates jsonb, opened_at timestamp with time zone, status text, eligible_gates text[])
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT m.id INTO v_member_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  WITH base AS (
    SELECT ac.id AS chain_id, gd.id AS document_id, gd.title AS document_title, gd.doc_type,
      dv.id AS version_id, dv.version_label, dv.locked_at AS version_locked_at,
      ac.gates, ac.opened_at, ac.status, ac.created_at AS created_at,
      (SELECT ARRAY_AGG(g->>'kind' ORDER BY (g->>'order')::int)
       FROM jsonb_array_elements(ac.gates) g
       WHERE public._can_sign_gate(v_member_id, ac.id, g->>'kind')
         AND NOT EXISTS (SELECT 1 FROM public.approval_signoffs s
           WHERE s.approval_chain_id = ac.id AND s.gate_kind = g->>'kind' AND s.signer_id = v_member_id)
         AND public._prior_gates_satisfied(ac.id, g->>'kind')
      ) AS eligible_gates
    FROM public.approval_chains ac
    JOIN public.governance_documents gd ON gd.id = ac.document_id
    JOIN public.document_versions dv ON dv.id = ac.version_id
    WHERE ac.status IN ('review','approved')
  )
  SELECT b.chain_id, b.document_id, b.document_title, b.doc_type, b.version_id, b.version_label,
    b.version_locked_at, b.gates, b.opened_at, b.status, b.eligible_gates
  FROM base b
  WHERE b.eligible_gates IS NOT NULL AND array_length(b.eligible_gates, 1) > 0
  ORDER BY b.opened_at DESC NULLS LAST, b.created_at DESC;
END;
$function$;

NOTIFY pgrst, 'reload schema';
