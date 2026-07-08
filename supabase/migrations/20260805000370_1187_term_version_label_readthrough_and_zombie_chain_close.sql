-- #1187: "Ver Template" showed the stale v2.7 label + a zombie "Em revisão" ratification chain.
--
-- Root causes (grounded live 2026-07-08):
--   1. governance_documents.version (text) was never stamped by activate_volunteer_term_version,
--      so surfaces reading it (/admin/certificates "Ver Template", per-member agreement_version)
--      kept showing the label inherited from the last manual edit (v2.7) while the ratified body
--      is v9 (current_version_id = document_versions.version_label).
--   2. Activation never closed the previous version's approval chain: chain d72916d7 (v2.7,
--      status='review', opened 2026-05-12) lingered and /admin/governance/documents rendered it
--      as "Em revisão · Aberto há 57 dias" with "Bola em: Aceite do GP" — inviting signatures on
--      an obsolete chain. It also left the winning chain at status='approved' (historic activated
--      chains use status='active').
--
-- Fix (this migration = DDL only; the one-time data correction runs as DML alongside it):
--   a. get_volunteer_agreement_status: template.version reads through current_version_id.
--   b. activate_volunteer_term_version: stamps gd.version with the activated version_label,
--      promotes the winning chain to status='active', and supersedes sibling chains still open
--      for OLDER versions of the same document (opened_at <= winning chain's opened_at).
--
-- Latest prior captures: activate 20260805000356 · status 20260805000362.

CREATE OR REPLACE FUNCTION public.activate_volunteer_term_version(p_doc_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_actor_member uuid;
  v_doc record;
  v_html text;
  v_version_label text;
  v_deactivated int := 0;
  v_chain_id uuid;
  v_chain_opened timestamptz;
  v_superseded_chains int := 0;
BEGIN
  SELECT id INTO v_actor_member FROM members WHERE auth_id = auth.uid();
  IF v_actor_member IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  IF NOT public.can_by_member(v_actor_member, 'manage_platform', NULL, NULL) THEN
    RETURN jsonb_build_object('error', 'forbidden',
      'message', 'Apenas manage_platform pode ativar uma versão do Termo de Voluntariado.');
  END IF;

  SELECT g.id, g.doc_type, g.status, g.current_version_id, g.version
    INTO v_doc
  FROM governance_documents g WHERE g.id = p_doc_id;
  IF v_doc.id IS NULL THEN RETURN jsonb_build_object('error', 'document_not_found'); END IF;
  IF v_doc.doc_type <> 'volunteer_term_template' THEN
    RETURN jsonb_build_object('error', 'wrong_doc_type', 'doc_type', v_doc.doc_type);
  END IF;

  SELECT dv.content_html, dv.version_label INTO v_html, v_version_label
  FROM document_versions dv
  WHERE dv.id = v_doc.current_version_id AND dv.locked_at IS NOT NULL;
  IF v_html IS NULL OR length(btrim(v_html)) = 0 THEN
    RETURN jsonb_build_object('error', 'no_locked_body',
      'message', 'A versão corrente não está travada (locked) ou não tem corpo HTML. Trave a versão na cadeia antes de ativar.',
      'current_version_id', v_doc.current_version_id);
  END IF;

  UPDATE governance_documents
     SET status = 'superseded', updated_at = now()
   WHERE doc_type = 'volunteer_term_template' AND status = 'active' AND id <> p_doc_id;
  GET DIAGNOSTICS v_deactivated = ROW_COUNT;

  SELECT ac.id, ac.opened_at INTO v_chain_id, v_chain_opened
  FROM approval_chains ac
  WHERE ac.document_id = p_doc_id
    AND ac.version_id = v_doc.current_version_id
    AND ac.status = 'approved'
  ORDER BY ac.approved_at DESC NULLS LAST
  LIMIT 1;

  -- #1187: stamp the human-readable version label on the doc so admin surfaces that read
  -- governance_documents.version (certificates panel, audit log) never show a stale label.
  UPDATE governance_documents
     SET status = 'active',
         version = COALESCE(v_version_label, version),
         current_ratified_chain_id = COALESCE(v_chain_id, current_ratified_chain_id),
         updated_at = now()
   WHERE id = p_doc_id;

  IF v_chain_id IS NOT NULL THEN
    UPDATE approval_chains
       SET status = 'active', activated_at = COALESCE(activated_at, now()), updated_at = now()
     WHERE id = v_chain_id;

    -- #1187: close sibling chains left open for older versions of this doc, otherwise they
    -- linger as "Em revisão" zombies in /admin/governance/documents inviting signatures on
    -- an obsolete chain. Only chains opened up to the activated chain's opened_at are closed
    -- (a chain for a NEWER draft version opened afterwards stays alive).
    UPDATE approval_chains
       SET status = 'superseded', closed_at = COALESCE(closed_at, now()), updated_at = now()
     WHERE document_id = p_doc_id
       AND id <> v_chain_id
       AND status IN ('draft', 'review', 'approved')
       AND opened_at <= v_chain_opened;
    GET DIAGNOSTICS v_superseded_chains = ROW_COUNT;
  END IF;

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_actor_member, 'volunteer_term_activated', 'governance_document', p_doc_id,
    jsonb_build_object('version', v_doc.version, 'version_label', v_version_label,
      'current_version_id', v_doc.current_version_id,
      'superseded_count', v_deactivated, 'superseded_chains', v_superseded_chains,
      'ratified_chain_id', v_chain_id));

  RETURN jsonb_build_object('success', true, 'activated', p_doc_id,
    'version', COALESCE(v_version_label, v_doc.version), 'superseded', v_deactivated,
    'superseded_chains', v_superseded_chains, 'ratified_chain_id', v_chain_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_volunteer_agreement_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_result jsonb;
  v_caller_id uuid;
  v_caller_chapter text;
  v_caller_person_id uuid;
  v_is_manage_member boolean;
  v_is_chapter_board boolean;
  v_is_vol_director boolean;
  v_contracting_chapter text;
  v_can_counter_sign boolean;
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
  -- WS-3: sede volunteer-director designation = program-wide read of the roster (function-anchored).
  v_is_vol_director := EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.id = v_caller_id AND 'voluntariado_director' = ANY(m.designations)
  );

  IF NOT v_is_manage_member AND NOT v_is_chapter_board AND NOT v_is_vol_director THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- The contracting party is ALWAYS the contracting chapter (PMI-GO, C3). Mirror the exact
  -- authority gate of counter_sign_certificate so the panel only shows the button to callers
  -- the RPC will accept: manage_member OR a chapter_board member of the contracting chapter.
  SELECT 'PMI-' || cr.chapter_code INTO v_contracting_chapter
  FROM public.chapter_registry cr
  WHERE cr.is_contracting_chapter AND cr.is_active
  LIMIT 1;

  v_can_counter_sign := v_is_manage_member
    OR (v_is_chapter_board AND v_caller_chapter IS NOT DISTINCT FROM v_contracting_chapter);

  SELECT jsonb_build_object(
    'generated_at', now(),
    'caller_chapter', v_caller_chapter,
    'is_manager', v_is_manage_member,
    'can_counter_sign', v_can_counter_sign,
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
        'not_verified', count(*) FILTER (WHERE m.pmi_id_verified IS NOT TRUE),
        'pct', ROUND(
          count(*) FILTER (WHERE EXISTS (
            SELECT 1 FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
            AND c.status = 'issued'
            AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          ))::numeric / NULLIF(count(*), 0) * 100, 1
        )
      )
      FROM public.members m WHERE m.is_active
      AND EXISTS (
        SELECT 1 FROM public.auth_engagements ae
        WHERE ae.person_id = m.person_id AND ae.kind = 'volunteer' AND ae.status = 'active'
      )
      AND (v_is_manage_member OR v_is_vol_director OR m.chapter = v_caller_chapter)
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
        FROM public.members m WHERE m.is_active
        AND EXISTS (
          SELECT 1 FROM public.auth_engagements ae
          WHERE ae.person_id = m.person_id AND ae.kind = 'volunteer' AND ae.status = 'active'
        )
        AND (v_is_manage_member OR v_is_vol_director OR m.chapter = v_caller_chapter)
        GROUP BY m.chapter
      ) sub
    ),
    'focal_points', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', m.id, 'name', m.name, 'chapter', m.chapter, 'role', m.operational_role
      ) ORDER BY m.chapter, m.name), '[]'::jsonb)
      FROM public.members m WHERE m.is_active AND 'chapter_board' = ANY(m.designations)
      AND (v_is_manage_member OR v_is_vol_director OR m.chapter = v_caller_chapter)
    ),
    'template', (
      -- #1187: read the version label through current_version_id (SSOT of the ratified body);
      -- gd.version is a maintained cache stamped by activate_volunteer_term_version.
      SELECT jsonb_build_object('id', gd.id, 'title', gd.title,
        'version', COALESCE(dv.version_label, gd.version), 'content', gd.content)
      FROM public.governance_documents gd
      LEFT JOIN public.document_versions dv ON dv.id = gd.current_version_id
      WHERE gd.doc_type = 'volunteer_term_template' AND gd.status = 'active'
      ORDER BY gd.created_at DESC LIMIT 1
    ),
    'members', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', m.id, 'name', m.name, 'email', m.email, 'chapter', m.chapter,
        'tribe_id', m.tribe_id, 'role', m.operational_role,
        'pmi_id_verified', COALESCE(m.pmi_id_verified, false),
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
        ),
        'agreement_template_id', (
          SELECT c.template_id FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND c.status = 'issued'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          ORDER BY c.issued_at DESC LIMIT 1
        ),
        'agreement_version', (
          SELECT gd.version FROM public.certificates c
          LEFT JOIN public.governance_documents gd ON gd.id::text = c.template_id
          WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND c.status = 'issued'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          ORDER BY c.issued_at DESC LIMIT 1
        )
      ) ORDER BY m.chapter, m.name), '[]'::jsonb)
      FROM public.members m WHERE m.is_active
      AND EXISTS (
        SELECT 1 FROM public.auth_engagements ae
        WHERE ae.person_id = m.person_id AND ae.kind = 'volunteer' AND ae.status = 'active'
      )
      AND (v_is_manage_member OR v_is_vol_director OR m.chapter = v_caller_chapter)
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;
