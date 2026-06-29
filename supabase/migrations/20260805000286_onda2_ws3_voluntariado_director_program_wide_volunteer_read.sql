-- Onda 2 — WS-3: the SEDE voluntariado_director sees ALL volunteers (program-wide, read-only).
--
-- Carry-over from Wave 1: the `voluntariado_director` designation grants only `admin.access` +
-- `admin.voluntarios` (the nav/panel), but get_volunteer_agreement_status — the volunteer roster
-- RPC — gated ONLY on `manage_member` (GP-only) OR an active `chapter_board` engagement (Path-3,
-- chapter-scoped to the caller's own chapter). So the sede volunteer director saw volunteers ONLY
-- via an INCIDENTAL chapter_board engagement (Lorena Souza happens to have one → PMI-GO only), and a
-- future director WITHOUT that engagement would see nothing. Not function-anchored.
--
-- Fix (V4 Path-2, designation gate): recognize `voluntariado_director` as a read authority on the
-- roster, with PROGRAM-WIDE scope. The volunteer-director is a SEDE program office overseeing
-- volunteering across the whole program (PM decision #2: sede + GP see all; partner chapters see
-- their own). READ ONLY — this RPC is STABLE; no write/manage is granted (term counter-signing stays
-- in the existing _can_sign_gate Path-2). The `is_manager` flag stays false for the director, so the
-- panel exposes no GP-only write controls.
--
-- Forward note (FU-2, chapter-scope hardening): if a PARTNER chapter is ever given a
-- voluntariado_director, this program-wide grant must be re-scoped to that chapter. Today the office
-- exists only at the sede (PMI-GO), so program-wide is the correct sede semantics.
--
-- Changes vs live body: +1 DECLARE (v_is_vol_director), +1 compute, +1 gate term, scope OR-term in
-- the 4 member subqueries (summary / by_chapter / focal_points / members). No other line changed.
-- Cross-ref: docs/reference/V4_AUTHORITY_MODEL.md (Caminho 2), handoff pt6 WS-3.

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
        FROM public.members m WHERE m.is_active AND m.current_cycle_active
        AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'observer', 'candidate', 'visitor')
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
      AND (v_is_manage_member OR v_is_vol_director OR m.chapter = v_caller_chapter)
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;
