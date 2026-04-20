-- Consolida 3 fixes p35 pós-handoff (RF-III + RF-V + audit webinar triggers):
--   (a) Audit preventivo: 2 webinar triggers com NEW.tribe_id mortos
--       (log_webinar_created, notify_webinar_status_change). webinars.tribe_id
--       foi droppado em ADR-0015 Phase 3b (commit b03a337). Derivam legacy_tribe_id
--       via JOIN initiatives.
--   (b) RF-III legal-counsel: ADD COLUMN approval_signoffs.referenced_policy_version_id
--       — snapshot do current_version_id da Política no momento da assinatura.
--       Fortalece auditoria de remissão dinâmica (cláusula-modelo CC Art. 111).
--   (c) RF-V legal-counsel: sign_ip_ratification snapshot notification_read_at
--       no content_snapshot. Ato concludente CC Art. 111 requer evidência de
--       recebimento + leitura da notificação pela plataforma.

-- (a) Fix webinar triggers — derivar legacy_tribe_id via JOIN initiatives
CREATE OR REPLACE FUNCTION public.log_webinar_created()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_actor_id uuid;
  v_legacy_tribe_id int;
BEGIN
  SELECT id INTO v_actor_id FROM members WHERE auth_id = auth.uid();
  SELECT legacy_tribe_id INTO v_legacy_tribe_id
  FROM public.initiatives WHERE id = NEW.initiative_id;
  INSERT INTO webinar_lifecycle_events (webinar_id, action, actor_id, new_status, metadata)
  VALUES (NEW.id, 'created', v_actor_id, NEW.status,
    jsonb_build_object('chapter_code', NEW.chapter_code, 'legacy_tribe_id', v_legacy_tribe_id));
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_webinar_status_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_recipient uuid; v_notif_type text; v_body text; v_link text;
  v_actor_id uuid; v_legacy_tribe_id int;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN RETURN NEW; END IF;

  v_notif_type := 'webinar_status_' || NEW.status;
  v_link := '/admin/webinars';
  SELECT id INTO v_actor_id FROM members WHERE auth_id = auth.uid();

  INSERT INTO webinar_lifecycle_events (webinar_id, action, actor_id, old_status, new_status)
  VALUES (NEW.id, 'status_change', v_actor_id, OLD.status, NEW.status);

  v_body := CASE NEW.status
    WHEN 'confirmed' THEN 'Webinar "' || NEW.title || '" confirmado. Preparar logística e campanha de divulgação.'
    WHEN 'completed' THEN 'Webinar "' || NEW.title || '" realizado. Preparar follow-up, replay e materiais.'
    WHEN 'cancelled' THEN 'Webinar "' || NEW.title || '" cancelado.'
    ELSE 'Webinar "' || NEW.title || '" — status alterado para ' || NEW.status || '.'
  END;

  IF NEW.organizer_id IS NOT NULL AND NEW.organizer_id IS DISTINCT FROM v_actor_id THEN
    PERFORM create_notification(NEW.organizer_id, v_notif_type,
      'Webinar: ' || NEW.title, v_body, v_link, 'webinar', NEW.id);
  END IF;

  IF array_length(NEW.co_manager_ids, 1) > 0 THEN
    FOREACH v_recipient IN ARRAY NEW.co_manager_ids LOOP
      IF v_recipient IS DISTINCT FROM v_actor_id THEN
        PERFORM create_notification(v_recipient, v_notif_type,
          'Webinar: ' || NEW.title, v_body, v_link, 'webinar', NEW.id);
      END IF;
    END LOOP;
  END IF;

  IF NEW.status IN ('confirmed', 'completed') THEN
    FOR v_recipient IN
      SELECT id FROM members
      WHERE designations && ARRAY['comms_leader', 'comms_member']
        AND is_active = true AND id IS DISTINCT FROM v_actor_id
    LOOP
      PERFORM create_notification(v_recipient, v_notif_type,
        'Webinar: ' || NEW.title,
        CASE NEW.status
          WHEN 'confirmed' THEN 'Preparar campanha de divulgação para "' || NEW.title || '" — ' || NEW.chapter_code || '.'
          WHEN 'completed' THEN 'Preparar follow-up e divulgação de replay para "' || NEW.title || '".'
        END,
        '/admin/comms?context=webinar&title=' || NEW.title,
        'webinar', NEW.id);
    END LOOP;
  END IF;

  -- ADR-0015 Phase 3b: webinars.tribe_id droppado; derivar via initiative
  SELECT legacy_tribe_id INTO v_legacy_tribe_id
  FROM public.initiatives WHERE id = NEW.initiative_id;

  IF v_legacy_tribe_id IS NOT NULL AND NEW.status IN ('confirmed', 'completed', 'cancelled') THEN
    FOR v_recipient IN
      SELECT id FROM members
      WHERE tribe_id = v_legacy_tribe_id
        AND operational_role = 'tribe_leader'
        AND is_active = true AND id IS DISTINCT FROM v_actor_id
    LOOP
      PERFORM create_notification(v_recipient, v_notif_type,
        'Webinar da sua tribo: ' || NEW.title, v_body,
        '/tribe/' || v_legacy_tribe_id || '?tab=board',
        'webinar', NEW.id);
    END LOOP;
  END IF;

  RETURN NEW;
END;
$function$;

-- (b) RF-III: approval_signoffs.referenced_policy_version_id
ALTER TABLE public.approval_signoffs
  ADD COLUMN IF NOT EXISTS referenced_policy_version_id uuid
    REFERENCES public.document_versions(id);

COMMENT ON COLUMN public.approval_signoffs.referenced_policy_version_id IS
  'RF-III (legal-counsel p35): snapshot do current_version_id da Política de Publicação e PI no momento da assinatura. Fortalece auditoria de remissão dinâmica — comprova a qual versão da Política o signatário consentiu.';

CREATE INDEX IF NOT EXISTS idx_approval_signoffs_policy_version
  ON public.approval_signoffs(referenced_policy_version_id)
  WHERE referenced_policy_version_id IS NOT NULL;

-- (c) sign_ip_ratification: RF-III snapshot policy_version_id + RF-V read_at evidence
-- (Refactor completo — substitui versão anterior de 20260504010006)
CREATE OR REPLACE FUNCTION public.sign_ip_ratification(
  p_chain_id uuid, p_gate_kind text,
  p_signoff_type text DEFAULT 'approval'::text,
  p_sections_verified jsonb DEFAULT NULL::jsonb,
  p_comment_body text DEFAULT NULL::text,
  p_ue_consent_49_1_a boolean DEFAULT NULL::boolean
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
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

  SELECT ac.id, ac.status, ac.document_id, ac.version_id, ac.gates
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

  INSERT INTO public.approval_signoffs (
    approval_chain_id, gate_kind, signer_id, signoff_type,
    signed_at, signature_hash, content_snapshot, sections_verified, comment_body,
    referenced_policy_version_id
  ) VALUES (
    p_chain_id, p_gate_kind, v_member.id, p_signoff_type,
    now(), v_hash, v_snapshot, p_sections_verified, p_comment_body,
    v_policy_version_id
  ) RETURNING id INTO v_signoff_id;

  SELECT COUNT(*) INTO v_gates_remaining
  FROM jsonb_array_elements(v_chain.gates) g
  WHERE
    ((g->>'threshold') = 'all'
      AND (SELECT COUNT(*) FROM public.approval_signoffs s
           WHERE s.approval_chain_id = p_chain_id AND s.gate_kind = (g->>'kind')
             AND s.signoff_type IN ('approval','acknowledge'))
         < (SELECT COUNT(*) FROM public.members m
            WHERE m.is_active = true
              AND public._can_sign_gate(m.id, p_chain_id, g->>'kind')))
    OR
    ((g->>'threshold') ~ '^[0-9]+$'
      AND (g->>'threshold')::int > 0
      AND (SELECT COUNT(*) FROM public.approval_signoffs s
           WHERE s.approval_chain_id = p_chain_id AND s.gate_kind = (g->>'kind')
             AND s.signoff_type IN ('approval','acknowledge')) < (g->>'threshold')::int);

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

NOTIFY pgrst, 'reload schema';
