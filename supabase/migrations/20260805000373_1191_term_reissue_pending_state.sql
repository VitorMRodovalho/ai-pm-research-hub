-- =====================================================================================
-- #1191 — get_volunteer_agreement_status: distinguish "reissued — awaiting re-signature"
--          from "never signed". Body-only CREATE OR REPLACE (signature/return jsonb
--          UNCHANGED); extends the #1187 body (mig 370) with, per member row:
--
--   'reissue_pending' : true when a volunteer_agreement cert of the CURRENT YEAR sits in
--                       status='superseded' (reissued by the manager) and NO issued cert
--                       exists for the year — i.e. the volunteer signed once, the term was
--                       reissued, and the re-signature is still missing.
--   'reissued_at'     : the latest such superseded cert's updated_at (the supersede moment),
--                       for the panel tooltip.
--
-- WHY (index case João, decision PM 2026-07-08 "option 1+3" — gate stays, UX explains):
-- after reissue_agreement superseded TERM-2026-9EED7D, João showed as "❌ Não assinado" +
-- role guest, indistinguishable from someone who never signed. The signature gate is BY
-- DESIGN (engagement stays correct; auth_engagements.is_authoritative=false without a
-- signed term ⇒ operational_role cache stays guest until re-signature, then F5 snapshots
-- role+period and the cache promotes alone). The panel must tell that story instead of
-- looking like a bug each time someone checks.
--
-- INVARIANTS PRESERVED (mig 359/362/370 lineage — NOT weakened):
--   - Authority gate: manage_member OR chapter_board OR voluntariado_director; fail-closed.
--   - Eligibility = positive rule (active volunteer engagement), #1173.
--   - can_counter_sign mirrors counter_sign_certificate's gate (contracting chapter).
--   - Template version label reads through current_version_id (#1187).
--
-- ROLLBACK: re-apply migration 20260805000370 (the pre-#1191 body).
-- =====================================================================================
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
        ),
        -- #1191: reissued term awaiting re-signature ≠ never signed. superseded cert of the
        -- year present + no issued cert of the year ⇒ the manager reissued and the volunteer
        -- has not re-signed yet (role cache stays guest by design until then).
        'reissue_pending', (
          EXISTS (
            SELECT 1 FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
            AND c.status = 'superseded'
            AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          )
          AND NOT EXISTS (
            SELECT 1 FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
            AND c.status = 'issued'
            AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          )
        ),
        'reissued_at', (
          SELECT c.updated_at FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND c.status = 'superseded'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          ORDER BY c.updated_at DESC LIMIT 1
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

NOTIFY pgrst, 'reload schema';
