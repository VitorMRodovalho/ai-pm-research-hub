-- ADR-0038 p68 cleanup batch — 3 fns
-- 1. update_governance_document_status: V3 → V4 manage_platform (zero drift)
-- 2. update_event_duration: security drift fix — parameter-based gate → auth.uid() + manage_event
-- 3. get_dropout_risk_members: security drift fix — no-gate → manage_event gate
--
-- Rollback: revert to prior CREATE OR REPLACE bodies (see git history of pg_proc snapshots).
-- pg_policy precondition: zero RLS refs verified for all 3 fns.

-- ─────────────────────────────────────────────────────────────────
-- 1. update_governance_document_status — V3 → V4 manage_platform
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.update_governance_document_status(
  p_doc_id uuid,
  p_new_status text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_doc record;
  v_valid_transitions jsonb := '{
    "draft": ["under_review"],
    "under_review": ["approved", "draft"],
    "approved": ["active", "under_review"],
    "active": ["superseded"],
    "superseded": []
  }'::jsonb;
  v_allowed jsonb;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'authentication_required');
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_platform');
  END IF;

  SELECT * INTO v_doc FROM public.governance_documents WHERE id = p_doc_id;
  IF v_doc IS NULL THEN
    RETURN jsonb_build_object('error', 'Document not found');
  END IF;

  v_allowed := v_valid_transitions->v_doc.status;
  IF v_allowed IS NULL OR NOT (v_allowed ? p_new_status) THEN
    RETURN jsonb_build_object('error', format('Invalid transition: %s -> %s. Allowed: %s', v_doc.status, p_new_status, v_allowed));
  END IF;

  UPDATE public.governance_documents SET
    status = p_new_status,
    updated_at = now()
  WHERE id = p_doc_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'governance_document_status_change', 'governance_document', p_doc_id,
    jsonb_build_object('from', v_doc.status, 'to', p_new_status, 'doc_title', v_doc.title));

  RETURN jsonb_build_object('ok', true, 'doc_id', p_doc_id, 'old_status', v_doc.status, 'new_status', p_new_status);
END;
$$;

COMMENT ON FUNCTION public.update_governance_document_status(uuid, text) IS
'V4 manage_platform gate (ADR-0038 p68). Was V3 manager/deputy/SA — zero drift.';

-- ─────────────────────────────────────────────────────────────────
-- 2. update_event_duration — auth.uid() drift fix + V4 manage_event
-- ─────────────────────────────────────────────────────────────────
-- Note: p_updated_by parameter retained for signature compat but ignored.
-- Caller now derived from auth.uid() (closes privilege escalation vector).
CREATE OR REPLACE FUNCTION public.update_event_duration(
  p_event_id uuid,
  p_duration_actual integer,
  p_updated_by uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event';
  END IF;

  UPDATE public.events SET duration_actual = p_duration_actual WHERE id = p_event_id;
  RETURN true;
END;
$$;

COMMENT ON FUNCTION public.update_event_duration(uuid, integer, uuid) IS
'p_updated_by is DEPRECATED and ignored — caller derived from auth.uid() (ADR-0038 p68 security drift fix). V4 manage_event gate.';

-- ─────────────────────────────────────────────────────────────────
-- 3. get_dropout_risk_members — add manage_event gate (was no-gate)
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_dropout_risk_members(p_threshold integer DEFAULT 3)
RETURNS TABLE(
  member_id uuid,
  member_name text,
  tribe_id integer,
  tribe_name text,
  operational_role text,
  last_attendance_date date,
  days_since_last bigint,
  missed_events integer
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN;
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH active_members AS (
    SELECT m.id, m.name, m.tribe_id, t.name as tname, m.operational_role
    FROM public.members m
    LEFT JOIN public.tribes t ON t.id = m.tribe_id
    WHERE m.is_active AND m.operational_role IN ('researcher','tribe_leader','manager')
  ),
  member_expected_events AS (
    SELECT am.id as mid, e.id as eid, e.date,
      ROW_NUMBER() OVER (PARTITION BY am.id ORDER BY e.date DESC) as rn
    FROM active_members am
    CROSS JOIN LATERAL (
      SELECT e2.id, e2.date FROM public.events e2
      LEFT JOIN public.initiatives ini ON ini.id = e2.initiative_id
      WHERE e2.date <= current_date
        AND (
          e2.type IN ('general_meeting','kickoff')
          OR (e2.type = 'tribe_meeting' AND ini.legacy_tribe_id = am.tribe_id)
          OR (e2.type = 'leadership_meeting' AND am.operational_role IN ('manager','tribe_leader'))
        )
      ORDER BY e2.date DESC
      LIMIT p_threshold
    ) e
  ),
  member_misses AS (
    SELECT mee.mid,
      count(*) FILTER (WHERE a.id IS NULL) as missed,
      count(*) as expected
    FROM member_expected_events mee
    LEFT JOIN public.attendance a ON a.event_id = mee.eid AND a.member_id = mee.mid AND a.present
    WHERE mee.rn <= p_threshold
    GROUP BY mee.mid
  ),
  last_att AS (
    SELECT a.member_id as mid, max(e.date) as last_date
    FROM public.attendance a JOIN public.events e ON e.id = a.event_id
    WHERE a.present
    GROUP BY a.member_id
  )
  SELECT am.id, am.name, am.tribe_id, am.tname, am.operational_role,
    la.last_date,
    (current_date - COALESCE(la.last_date, '2025-01-01'))::bigint,
    mm.missed::integer
  FROM active_members am
  JOIN member_misses mm ON mm.mid = am.id
  LEFT JOIN last_att la ON la.mid = am.id
  WHERE mm.missed >= p_threshold
  ORDER BY la.last_date ASC NULLS FIRST;
END;
$$;

COMMENT ON FUNCTION public.get_dropout_risk_members(integer) IS
'V4 manage_event gate (ADR-0038 p68 security drift fix). Was no-gate — closed LGPD-sensitive PII exposure.';

NOTIFY pgrst, 'reload schema';
