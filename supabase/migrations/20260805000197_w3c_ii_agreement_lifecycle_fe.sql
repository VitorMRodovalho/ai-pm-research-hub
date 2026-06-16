-- Wave 3c-ii (#740, B8 FE) — surface the rejected/superseded agreement lifecycle to the
-- member-facing + admin frontends. Pure read-surface + copy changes; no new state machine.
--
-- 3c-i (mig …196) added the DB lifecycle: status ∈ issued|rejected|superseded, reject_certificate,
-- reissue_agreement. This migration makes the existing read RPCs lifecycle-aware so the FE can:
--   * verify_certificate            → report rejected/superseded distinctly (not just revoked)
--   * get_all_certificates          → count rejected/superseded in the admin summary (+counter_signed_at
--                                      in the row payload, fixing a latent "awaiting director" badge)
--   * get_my_certificates           → expose the rejection reason/date to the member banner
--   * get_volunteer_agreement_status→ per-member agreement_cert_id + agreement_status, and make
--                                      "signed"/compliance count ONLY status='issued' (a rejected
--                                      term is no longer compliant → re-actionable in the panel)
--   * reject_certificate            → legal R2: formal "distrato" copy when a fully-executed
--                                      (counter-signed) bilateral term is rescinded post-countersign.
--
-- All CREATE OR REPLACE (signatures unchanged). Attributes preserved verbatim from live:
--   verify/get_my/get_all/reject: SECDEF, search_path=public,pg_temp
--   get_volunteer_agreement_status: SECDEF, STABLE, search_path='' (refs stay schema-qualified).
-- Bodies are comment-free so they stay byte-equivalent to the applied prosrc (Phase C drift gate).

CREATE OR REPLACE FUNCTION public.verify_certificate(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  cert record;
  v_member_name text;
  v_issuer_name text;
  v_countersigner_name text;
BEGIN
  SELECT c.* INTO cert
  FROM certificates c
  WHERE c.verification_code = p_code;

  IF cert IS NULL THEN
    RETURN jsonb_build_object('valid', false, 'error', 'not_found');
  END IF;

  SELECT name INTO v_member_name FROM members WHERE id = cert.member_id;

  IF cert.issued_by IS NOT NULL THEN
    SELECT name INTO v_issuer_name FROM members WHERE id = cert.issued_by;
  END IF;

  IF cert.counter_signed_by IS NOT NULL THEN
    SELECT name INTO v_countersigner_name FROM members WHERE id = cert.counter_signed_by;
  END IF;

  RETURN jsonb_build_object(
    'valid', COALESCE(cert.status, 'issued') = 'issued',
    'revoked', cert.status = 'revoked',
    'rejected', cert.status = 'rejected',
    'superseded', cert.status = 'superseded',
    'revoked_at', cert.revoked_at,
    'revoked_reason', cert.revoked_reason,
    'type', cert.type,
    'title', cert.title,
    'member_name', v_member_name,
    'issued_at', cert.issued_at,
    'issued_by', v_issuer_name,
    'counter_signed_by', v_countersigner_name,
    'counter_signed_at', cert.counter_signed_at,
    'cycle', cert.cycle,
    'period_start', cert.period_start,
    'period_end', cert.period_end,
    'function_role', cert.function_role,
    'language', cert.language,
    'verification_code', cert.verification_code
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_all_certificates(
  p_status_filter text DEFAULT NULL::text,
  p_search text DEFAULT NULL::text,
  p_include_volunteer_agreements boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller record;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND OR (
    v_caller.is_superadmin IS NOT TRUE
    AND v_caller.operational_role NOT IN ('manager', 'deputy_manager')
    AND NOT public.can_by_member(v_caller.id, 'curate_content')
  ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total', count(*) FILTER (WHERE p_include_volunteer_agreements OR c.type != 'volunteer_agreement'),
      'issued', count(*) FILTER (WHERE c.status = 'issued' AND (p_include_volunteer_agreements OR c.type != 'volunteer_agreement')),
      'draft', count(*) FILTER (WHERE c.status = 'draft' AND (p_include_volunteer_agreements OR c.type != 'volunteer_agreement')),
      'revoked', count(*) FILTER (WHERE c.status = 'revoked' AND (p_include_volunteer_agreements OR c.type != 'volunteer_agreement')),
      'rejected', count(*) FILTER (WHERE c.status = 'rejected' AND (p_include_volunteer_agreements OR c.type != 'volunteer_agreement')),
      'superseded', count(*) FILTER (WHERE c.status = 'superseded' AND (p_include_volunteer_agreements OR c.type != 'volunteer_agreement')),
      'downloaded', count(*) FILTER (WHERE c.downloaded_at IS NOT NULL AND (p_include_volunteer_agreements OR c.type != 'volunteer_agreement'))
    ),
    'certificates', (
      SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.issued_at DESC), '[]'::jsonb)
      FROM (
        SELECT
          c2.id, c2.type, c2.title, c2.description,
          c2.cycle, c2.period_start, c2.period_end,
          c2.function_role, c2.language, c2.status,
          c2.verification_code, c2.pdf_url,
          c2.issued_at, c2.downloaded_at,
          c2.revoked_at, c2.revoked_reason,
          c2.counter_signed_at,
          c2.updated_at,
          c2.issued_by,
          m.name AS member_name, m.photo_url AS member_photo,
          m.chapter AS member_chapter,
          ib.name AS issued_by_name
        FROM certificates c2
        JOIN members m ON m.id = c2.member_id
        LEFT JOIN members ib ON ib.id = c2.issued_by
        WHERE (p_status_filter IS NULL OR c2.status = p_status_filter)
          AND (p_include_volunteer_agreements OR c2.type != 'volunteer_agreement')
          AND (p_search IS NULL OR p_search = '' OR
            m.name ILIKE '%' || p_search || '%' OR
            c2.title ILIKE '%' || p_search || '%' OR
            c2.verification_code ILIKE '%' || p_search || '%'
          )
        ORDER BY c2.issued_at DESC
      ) t
    )
  ) INTO v_result
  FROM certificates c;

  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_certificates(
  p_include_volunteer_agreements boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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
    'function_role', c.function_role,
    'revoked_reason', c.revoked_reason, 'revoked_at', c.revoked_at
  ) ORDER BY c.issued_at DESC), '[]'::jsonb) INTO result
  FROM certificates c
  LEFT JOIN members ib ON ib.id = c.issued_by
  LEFT JOIN members cs ON cs.id = c.counter_signed_by
  WHERE c.member_id = v_member_id
    AND COALESCE(c.status, 'issued') NOT IN ('revoked', 'superseded')
    AND (p_include_volunteer_agreements OR c.type != 'volunteer_agreement');
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_volunteer_agreement_status()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_result jsonb;
  v_caller_id uuid;
  v_caller_chapter text;
  v_caller_person_id uuid;
  v_is_manage_member boolean;
  v_is_chapter_board boolean;
BEGIN
  SELECT m.id, m.chapter, m.person_id
    INTO v_caller_id, v_caller_chapter, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  v_is_manage_member := public.can_by_member(v_caller_id, 'manage_member');
  v_is_chapter_board := EXISTS (
    SELECT 1 FROM public.auth_engagements ae
    WHERE ae.person_id = v_caller_person_id
      AND ae.kind = 'chapter_board'
      AND ae.status = 'active'
  );

  IF NOT v_is_manage_member AND NOT v_is_chapter_board THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT jsonb_build_object(
    'generated_at', now(),
    'caller_chapter', v_caller_chapter,
    'is_manager', v_is_manage_member,
    'summary', (
      SELECT jsonb_build_object(
        'total_eligible', count(*),
        'signed', count(*) FILTER (WHERE EXISTS (
          SELECT 1 FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND c.status = 'issued'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
        )),
        'unsigned', count(*) FILTER (WHERE NOT EXISTS (
          SELECT 1 FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND c.status = 'issued'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
        )),
        'pct', ROUND(
          count(*) FILTER (WHERE EXISTS (
            SELECT 1 FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
            AND c.status = 'issued'
            AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          ))::numeric / NULLIF(count(*), 0) * 100, 1
        )
      )
      FROM public.members m WHERE m.is_active AND m.current_cycle_active
      AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'observer', 'candidate', 'visitor')
      AND (v_is_manage_member OR m.chapter = v_caller_chapter)
    ),
    'by_chapter', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'chapter', sub.chapter, 'total', sub.total, 'signed', sub.signed, 'unsigned', sub.total - sub.signed
      ) ORDER BY sub.chapter), '[]'::jsonb)
      FROM (
        SELECT m.chapter, count(*) as total,
          count(*) FILTER (WHERE EXISTS (
            SELECT 1 FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
            AND c.status = 'issued'
            AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          )) as signed
        FROM public.members m WHERE m.is_active AND m.current_cycle_active
        AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'observer', 'candidate', 'visitor')
        AND (v_is_manage_member OR m.chapter = v_caller_chapter)
        GROUP BY m.chapter
      ) sub
    ),
    'focal_points', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', m.id, 'name', m.name, 'chapter', m.chapter, 'role', m.operational_role
      ) ORDER BY m.chapter, m.name), '[]'::jsonb)
      FROM public.members m WHERE m.is_active AND 'chapter_board' = ANY(m.designations)
      AND (v_is_manage_member OR m.chapter = v_caller_chapter)
    ),
    'template', (
      SELECT jsonb_build_object('id', gd.id, 'title', gd.title, 'version', gd.version, 'content', gd.content)
      FROM public.governance_documents gd WHERE gd.doc_type = 'volunteer_term_template' AND gd.status = 'active'
      ORDER BY gd.created_at DESC LIMIT 1
    ),
    'members', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', m.id, 'name', m.name, 'email', m.email, 'chapter', m.chapter,
        'tribe_id', m.tribe_id, 'role', m.operational_role,
        'cycle_code', (
          SELECT mch.cycle_code FROM public.member_cycle_history mch
          WHERE mch.member_id = m.id AND mch.is_active
          ORDER BY mch.cycle_start DESC LIMIT 1
        ),
        'cycle_start', (
          SELECT mch.cycle_start FROM public.member_cycle_history mch
          WHERE mch.member_id = m.id AND mch.is_active
          ORDER BY mch.cycle_start DESC LIMIT 1
        ),
        'cycle_end', (
          SELECT mch.cycle_end FROM public.member_cycle_history mch
          WHERE mch.member_id = m.id AND mch.is_active
          ORDER BY mch.cycle_start DESC LIMIT 1
        ),
        'contract_start', (
          SELECT c.period_start FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND c.status = 'issued'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          ORDER BY c.issued_at DESC LIMIT 1
        ),
        'contract_end', (
          SELECT c.period_end FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND c.status = 'issued'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          ORDER BY c.issued_at DESC LIMIT 1
        ),
        'signed', EXISTS (
          SELECT 1 FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND c.status = 'issued'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
        ),
        'signed_at', (
          SELECT c.issued_at FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND c.status = 'issued'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          ORDER BY c.issued_at DESC LIMIT 1
        ),
        'counter_signed', EXISTS (
          SELECT 1 FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND c.status = 'issued'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          AND c.counter_signed_at IS NOT NULL
        ),
        'counter_signed_at', (
          SELECT c.counter_signed_at FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND c.status = 'issued'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          ORDER BY c.issued_at DESC LIMIT 1
        ),
        'verification_code', (
          SELECT c.verification_code FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND c.status = 'issued'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          ORDER BY c.issued_at DESC LIMIT 1
        ),
        'agreement_cert_id', (
          SELECT c.id FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND c.status IN ('issued', 'rejected')
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          ORDER BY c.issued_at DESC LIMIT 1
        ),
        'agreement_status', (
          SELECT c.status FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND c.status IN ('issued', 'rejected')
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          ORDER BY c.issued_at DESC LIMIT 1
        )
      ) ORDER BY m.chapter, m.name), '[]'::jsonb)
      FROM public.members m WHERE m.is_active AND m.current_cycle_active
      AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'observer', 'candidate', 'visitor')
      AND (v_is_manage_member OR m.chapter = v_caller_chapter)
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- reject_certificate — legal R2: a counter-signed term is a fully-executed bilateral act → its
-- rescission is a formal "distrato", not a routine "please re-sign". Logic otherwise identical to
-- 3c-i (…196). The in-app notification already emails via the send-notification-emails cron.
CREATE OR REPLACE FUNCTION public.reject_certificate(p_certificate_id uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_chapter text;
  v_caller_person_id uuid;
  v_is_manage_member boolean;
  v_is_chapter_board boolean;
  v_cert record;
  v_contracting_chapter text;
  v_was_counter_signed boolean;
  v_notif_title text;
  v_notif_body text;
BEGIN
  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RETURN jsonb_build_object('error', 'reason_required');
  END IF;
  p_reason := left(trim(p_reason), 500);

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

  v_contracting_chapter := COALESCE(
    v_cert.content_snapshot->>'contracting_chapter',
    (SELECT 'PMI-' || chapter_code FROM chapter_registry WHERE is_contracting_chapter AND is_active LIMIT 1)
  );
  IF v_is_chapter_board AND NOT v_is_manage_member
     AND v_contracting_chapter IS DISTINCT FROM v_caller_chapter THEN
    RETURN jsonb_build_object('error', 'not_authorized_different_chapter');
  END IF;

  v_was_counter_signed := v_cert.counter_signed_by IS NOT NULL;

  UPDATE certificates
     SET status = 'rejected', revoked_at = now(), revoked_by = v_caller_id,
         revoked_reason = p_reason, updated_at = now()
   WHERE id = p_certificate_id;

  UPDATE engagements SET agreement_certificate_id = NULL
   WHERE agreement_certificate_id = p_certificate_id;

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'volunteer_agreement_rejected', 'certificate', p_certificate_id,
    jsonb_build_object(
      'verification_code', v_cert.verification_code, 'reason', p_reason,
      'was_counter_signed', v_was_counter_signed,
      'counter_signature_hash', v_cert.counter_signature_hash,
      'contracting_chapter', v_contracting_chapter, 'member_id', v_cert.member_id));

  IF v_was_counter_signed THEN
    v_notif_title := 'Distrato do seu Termo de Voluntariado';
    v_notif_body := 'Seu Termo de Voluntariado (ciclo ' || v_cert.cycle::text || '), firmado por ambas as '
      || 'partes em ' || to_char(v_cert.counter_signed_at, 'DD/MM/YYYY') || ', foi formalmente '
      || 'rescindido (distrato) em ' || to_char(now(), 'DD/MM/YYYY') || '. Motivo: ' || p_reason
      || '. Para retomar seu vínculo voluntário, um novo termo deverá ser assinado.';
  ELSE
    v_notif_title := 'Seu Termo de Voluntariado precisa ser reassinado';
    v_notif_body := 'Motivo: ' || p_reason || '. Por favor revise seus dados e assine novamente.';
  END IF;

  INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
  VALUES (v_cert.member_id, 'volunteer_agreement_rejected',
    v_notif_title, v_notif_body,
    '/volunteer-agreement', 'certificate', p_certificate_id,
    public._delivery_mode_for('volunteer_agreement_rejected'));

  RETURN jsonb_build_object('success', true, 'certificate_id', p_certificate_id, 'status', 'rejected',
    'was_counter_signed', v_was_counter_signed);
END;
$$;

GRANT EXECUTE ON FUNCTION public.verify_certificate(text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_certificates(boolean) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_all_certificates(text, text, boolean) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_volunteer_agreement_status() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reject_certificate(uuid, text) TO authenticated, service_role;
