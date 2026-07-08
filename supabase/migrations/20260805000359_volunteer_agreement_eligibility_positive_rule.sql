-- Fase 0 (certificates admin revamp): fix WHO must sign the Volunteer Term.
--
-- Root cause: get_volunteer_agreement_status derived the eligible set from a NEGATIVE
-- blocklist on operational_role (NOT IN sponsor/chapter_liaison/observer/candidate/visitor)
-- + current_cycle_active. That blocklist leaks: `guest` slips through, so external reviewers
-- (external_reviewer engagements — e.g. Angeline Prado, Mario Trentim) and synthetic test rows
-- were counted as "must sign the volunteer term", even though they are not active volunteers.
--
-- Fix: replace the blocklist with the POSITIVE rule the domain actually means — eligible =
-- active member (members.is_active) AND has an ACTIVE volunteer engagement (auth_engagements
-- kind='volunteer' status='active'). An active volunteer engagement is by construction the
-- current cycle's engagement (C4), so this also anchors "cycle 4 volunteer" without a brittle
-- cycle join. Measured effect (2026-07-07, live): eligible 77 -> 72 (55 signed, 17 unsigned).
--
-- PMI affiliation validity: there is no reliable membership-validity source in members/persons
-- (only pmi_id_verified, a verification-workflow flag — 11 of the 72 are unverified yet include
-- real signed tribe leaders). So affiliation is surfaced as a SIGNAL (pmi_id_verified per row +
-- not_verified in summary), NOT a hard exclusion. A hard validity gate is deferred to #1129 (VEP).
--
-- Also flips external_reviewer engagements out of the agreement pipeline (requires_agreement=FALSE):
-- external reviewers are not PMI-GO volunteers and should not be asked to sign the volunteer term.
-- study_group_owner is intentionally left in place (needs its own template, separate track).

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
      SELECT jsonb_build_object('id', gd.id, 'title', gd.title, 'version', gd.version, 'content', gd.content)
      FROM public.governance_documents gd WHERE gd.doc_type = 'volunteer_term_template' AND gd.status = 'active'
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

-- External reviewers are not PMI-GO volunteers: take them out of the agreement pipeline so they
-- are neither prompted to sign the volunteer term nor surfaced in the pending-agreement queue.
-- requires_agreement is a per-KIND config (engagement_kinds, ADR-0009 "types = admin config"),
-- surfaced read-only by the auth_engagements view via ek.requires_agreement. study_group_owner
-- and volunteer are intentionally left requiring an agreement.
UPDATE public.engagement_kinds
SET requires_agreement = false
WHERE slug = 'external_reviewer'
  AND requires_agreement IS TRUE;

NOTIFY pgrst, 'reload schema';
