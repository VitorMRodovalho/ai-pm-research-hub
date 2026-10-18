-- #2726: a tela de termos decide a contra-assinatura pelo mesmo predicado de counter_sign_certificate.
--
-- Metade PRODUTORA. A metade leitora (a tela lê can_counter_sign por linha, com o global como fallback)
-- foi mergeada e deployada antes desta, na PR 2727.
--
-- Muda em get_volunteer_agreement_status:
--   1. 'counter_signed' vem do termo mais recente do ano, o mesmo que 'agreement_cert_id' aponta.
--      Antes, qualquer termo do ano contra-assinado marcava a linha completa e escondia o botão do novo.
--   2. A lista inclui membro ativo com termo do ano assinado e sem contra-assinatura, mesmo sem
--      engajamento ativo de 'volunteer' (a diretoria do contratante tem chapter_board).
--   3. 'can_counter_sign' por linha, com o predicado do #2104 (via da diretoria, escalada da
--      presidência, nunca o titular); o global passa a ser "alguma via existe para o chamador".
--
-- Corpo de partida: a captura 20260805000373, idêntica ao vivo (md5 normalizado 431957b3) no dia.
--
-- ROLLBACK: reaplicar o CREATE OR REPLACE de 20260805000373_1191_term_reissue_pending_state.sql.

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
  v_can_counter_sign boolean;
  v_caller_is_contracting boolean;
  v_route_director boolean;
  v_route_president boolean;
  v_director_vacant boolean;
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

  -- #2726: mirror counter_sign_certificate as it is AFTER #2104, not the gate #2104 replaced. The
  -- term is counter-signed by the contracting chapter's volunteer director (ordinary route) or, by
  -- escalation, by the contracting chapter's presidency (chapter_board + legal_signer) when the term
  -- belongs to the director or the post is vacant; never by the holder of the term; manage_member
  -- is not a route (PM decision 30/08). The global flag says only that SOME route exists for this
  -- caller; the per-row 'can_counter_sign' in 'members' decides each term.
  v_caller_is_contracting := EXISTS (
    SELECT 1 FROM public.partner_chapters pc
    JOIN public.chapter_registry cr ON cr.chapter_code = pc.registry_chapter_code
    WHERE pc.chapter_code = v_caller_chapter
      AND cr.is_contracting_chapter);
  v_route_director := v_caller_is_contracting AND EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.id = v_caller_id
      AND 'voluntariado_director' = ANY(COALESCE(m.designations, ARRAY[]::text[])));
  v_route_president := v_caller_is_contracting AND EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.id = v_caller_id
      AND 'chapter_board' = ANY(COALESCE(m.designations, ARRAY[]::text[]))
      AND 'legal_signer' = ANY(COALESCE(m.designations, ARRAY[]::text[])));
  v_director_vacant := NOT EXISTS (
    SELECT 1 FROM public.members m3
    JOIN public.partner_chapters pc ON pc.chapter_code = m3.chapter
    JOIN public.chapter_registry cr ON cr.chapter_code = pc.registry_chapter_code
    WHERE m3.is_active
      AND cr.is_contracting_chapter
      AND 'voluntariado_director' = ANY(COALESCE(m3.designations, ARRAY[]::text[])));

  v_can_counter_sign := v_route_director OR v_route_president;

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
        -- #2726: read from the SAME term the button acts on (the most recent issued one of the
        -- year), not from any term of the year: with two issued terms, the old counter-signed one
        -- marked the row complete and hid the button for the new one.
        'counter_signed', COALESCE((
          SELECT c.counter_signed_at IS NOT NULL FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND c.status = 'issued'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          ORDER BY c.issued_at DESC LIMIT 1
        ), false),
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
        ),
        -- #2726: can THIS caller counter-sign THIS member's term? Same predicate as
        -- counter_sign_certificate: never the holder; the director route; or the presidency by
        -- escalation when the holder is the contracting chapter's director or the post is vacant.
        'can_counter_sign', (
          m.id IS DISTINCT FROM v_caller_id
          AND (
            v_route_director
            OR (v_route_president AND (
              v_director_vacant
              OR EXISTS (
                SELECT 1 FROM public.partner_chapters pc
                JOIN public.chapter_registry cr ON cr.chapter_code = pc.registry_chapter_code
                WHERE pc.chapter_code = m.chapter
                  AND cr.is_contracting_chapter
                  AND 'voluntariado_director' = ANY(COALESCE(m.designations, ARRAY[]::text[])))
            ))
          )
        )
      ) ORDER BY m.chapter, m.name), '[]'::jsonb)
      FROM public.members m WHERE m.is_active
      AND (
        EXISTS (
          SELECT 1 FROM public.auth_engagements ae
          WHERE ae.person_id = m.person_id AND ae.kind = 'volunteer' AND ae.status = 'active'
        )
        -- #2726: a signed term of the year still waiting for counter-signature is listed even when
        -- the holder has no active 'volunteer' engagement (the contracting chapter's own director
        -- holds chapter_board); otherwise nobody sees it and the escalation route has no screen.
        OR EXISTS (
          SELECT 1 FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND c.status = 'issued'
          AND c.counter_signed_at IS NULL
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
        )
      )
      AND (v_is_manage_member OR v_is_vol_director OR m.chapter = v_caller_chapter)
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

