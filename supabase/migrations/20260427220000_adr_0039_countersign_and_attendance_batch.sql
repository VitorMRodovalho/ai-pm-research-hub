-- ADR-0039: Volunteer-agreement countersign subsystem 100% V4 + register_attendance_batch security drift fix
-- Section A (3 fns): countersign cluster — V3 (manager OR chapter_board designation) → V4 (manage_member OR Path Y chapter_board engagement)
-- Section B (1 fn): register_attendance_batch — parameter-based gate → auth.uid()-derived + manage_event (mirrors ADR-0038 update_event_duration fix)
-- pg_policy precondition: zero RLS refs verified for all 4 fns.

-- ─────────────────────────────────────────────────────────────────
-- Section A.1: counter_sign_certificate
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.counter_sign_certificate(p_certificate_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_chapter text;
  v_caller_person_id uuid;
  v_is_manage_member boolean;
  v_is_chapter_board boolean;
  v_cert record;
  v_contracting_chapter text;
  v_hash text;
BEGIN
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
  IF v_cert.counter_signed_by IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'already_counter_signed');
  END IF;

  v_contracting_chapter := COALESCE(
    v_cert.content_snapshot->>'contracting_chapter',
    (SELECT m.chapter FROM public.members m WHERE m.id = v_cert.member_id)
  );

  IF v_is_chapter_board AND NOT v_is_manage_member THEN
    IF v_contracting_chapter IS DISTINCT FROM v_caller_chapter THEN
      RETURN jsonb_build_object('error', 'not_authorized_different_chapter');
    END IF;
  END IF;

  v_hash := encode(sha256(convert_to(
    COALESCE(v_cert.signature_hash,'') || v_caller_id::text || now()::text || 'nucleo-ia-countersign-salt', 'UTF8'
  )), 'hex');

  UPDATE public.certificates SET counter_signed_by = v_caller_id, counter_signed_at = now() WHERE id = p_certificate_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'certificate_counter_signed', 'certificate', p_certificate_id,
    jsonb_build_object('verification_code', v_cert.verification_code, 'type', v_cert.type, 'contracting_chapter', v_contracting_chapter));

  INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
  VALUES (v_cert.member_id, 'certificate_ready',
    'Seu ' || v_cert.title || ' esta pronto!',
    'O documento foi contra-assinado e esta disponivel. Codigo: ' || v_cert.verification_code,
    '/certificates', 'certificate', p_certificate_id,
    public._delivery_mode_for('certificate_ready'));

  RETURN jsonb_build_object('success', true, 'counter_signature_hash', v_hash, 'counter_signed_at', now());
END;
$$;

COMMENT ON FUNCTION public.counter_sign_certificate(uuid) IS
'V4 manage_member OR Path Y chapter_board engagement (ADR-0039 p69). Was V3 (manager OR chapter_board designation) — gains 3 (engagement-without-designation drift correction), zero losses.';

-- ─────────────────────────────────────────────────────────────────
-- Section A.2: get_pending_countersign
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_pending_countersign()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_chapter text;
  v_caller_person_id uuid;
  v_is_manage_member boolean;
  v_is_chapter_board boolean;
  v_result jsonb;
BEGIN
  SELECT m.id, m.chapter, m.person_id
    INTO v_caller_id, v_caller_chapter, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN RETURN '[]'::jsonb; END IF;

  v_is_manage_member := public.can_by_member(v_caller_id, 'manage_member');
  v_is_chapter_board := EXISTS (
    SELECT 1 FROM public.auth_engagements ae
    WHERE ae.person_id = v_caller_person_id
      AND ae.kind = 'chapter_board'
      AND ae.status = 'active'
  );

  IF NOT v_is_manage_member AND NOT v_is_chapter_board THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', c.id, 'type', c.type, 'title', c.title, 'member_name', m.name, 'member_email', m.email,
    'member_role', m.operational_role, 'member_chapter', m.chapter, 'tribe_name', t.name, 'cycle', c.cycle,
    'verification_code', c.verification_code, 'issued_at', c.issued_at,
    'signature_hash', c.signature_hash
  ) ORDER BY c.issued_at DESC), '[]'::jsonb) INTO v_result
  FROM public.certificates c
  JOIN public.members m ON m.id = c.member_id
  LEFT JOIN public.tribes t ON t.id = m.tribe_id
  WHERE c.counter_signed_by IS NULL
    AND COALESCE(c.status, 'issued') = 'issued'
    AND c.type != 'volunteer_agreement'
    AND (v_is_manage_member OR m.chapter = v_caller_chapter);

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.get_pending_countersign() IS
'V4 manage_member OR Path Y chapter_board engagement (ADR-0039 p69). Was V3 (manager OR chapter_board designation).';

-- ─────────────────────────────────────────────────────────────────
-- Section A.3: get_volunteer_agreement_status
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_volunteer_agreement_status()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
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
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
        )),
        'unsigned', count(*) FILTER (WHERE NOT EXISTS (
          SELECT 1 FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
        )),
        'pct', ROUND(
          count(*) FILTER (WHERE EXISTS (
            SELECT 1 FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
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
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          ORDER BY c.issued_at DESC LIMIT 1
        ),
        'contract_end', (
          SELECT c.period_end FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          ORDER BY c.issued_at DESC LIMIT 1
        ),
        'signed', EXISTS (
          SELECT 1 FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
        ),
        'signed_at', (
          SELECT c.issued_at FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          ORDER BY c.issued_at DESC LIMIT 1
        ),
        'counter_signed', EXISTS (
          SELECT 1 FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          AND c.counter_signed_at IS NOT NULL
        ),
        'counter_signed_at', (
          SELECT c.counter_signed_at FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
          AND EXTRACT(YEAR FROM c.issued_at) = EXTRACT(YEAR FROM now())
          ORDER BY c.issued_at DESC LIMIT 1
        ),
        'verification_code', (
          SELECT c.verification_code FROM public.certificates c WHERE c.member_id = m.id AND c.type = 'volunteer_agreement'
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

COMMENT ON FUNCTION public.get_volunteer_agreement_status() IS
'V4 manage_member OR Path Y chapter_board engagement (ADR-0039 p69). Was V3 (manager OR chapter_board designation).';

-- ─────────────────────────────────────────────────────────────────
-- Section B: register_attendance_batch — parameter-gate fix (mirrors ADR-0038 update_event_duration)
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.register_attendance_batch(
  p_event_id uuid,
  p_member_ids uuid[],
  p_registered_by uuid DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  inserted integer;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event';
  END IF;

  INSERT INTO public.attendance (event_id, member_id, present, registered_by)
  SELECT p_event_id, unnest(p_member_ids), true, v_caller_id
  ON CONFLICT (event_id, member_id)
  DO UPDATE SET present = true, registered_by = v_caller_id, updated_at = now();
  GET DIAGNOSTICS inserted = ROW_COUNT;
  RETURN inserted;
END;
$$;

COMMENT ON FUNCTION public.register_attendance_batch(uuid, uuid[], uuid) IS
'p_registered_by is DEPRECATED and ignored — caller derived from auth.uid() (ADR-0039 p69 security drift fix mirroring ADR-0038 update_event_duration). V4 manage_event gate.';

NOTIFY pgrst, 'reload schema';
