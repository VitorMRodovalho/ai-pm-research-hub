-- ARM-9 Foundation (Sessão 1): G5 transition validation + G6 invariant N
-- Backfill 14 terminal members com offboarded_at NULL (pre-trigger drift)
-- Adicionar validate_status_transition helper + invariant N (defesa em profundidade complementar a L)
-- Sem mudança de comportamento user-facing: validate só bloqueia transitions truly invalid
-- (candidate ↔ terminal). alumni→active mantido permitido até Features G2 (re-engagement pipeline).
-- Rollback: DROP FUNCTION validate_status_transition; revert check_schema_invariants prior version.

-- ============================================================
-- Step 1: Backfill drift — terminal status sem offboarded_at
-- ============================================================
UPDATE public.members
SET offboarded_at = COALESCE(status_changed_at, updated_at, created_at, now())
WHERE member_status IN ('observer','alumni','inactive')
  AND offboarded_at IS NULL
  AND anonymized_at IS NULL
  AND name <> 'VP Desenvolvimento Profissional (PMI-GO)';

-- ============================================================
-- Step 2: Helper validate_status_transition(p_from, p_to)
-- ============================================================
CREATE OR REPLACE FUNCTION public.validate_status_transition(p_from text, p_to text)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  -- Self-transitions are idempotent (caller may decide to no-op)
  IF p_from = p_to THEN RETURN; END IF;

  -- candidate is pre-membership; reachable only from selection_applications acceptance
  IF p_from = 'candidate' AND p_to <> 'active' THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Invalid transition: candidate -> ' || p_to || '. Candidates only become active via selection acceptance.',
      ERRCODE = '22023';
  END IF;

  -- Terminal/active states cannot regress to candidate (pre-membership only)
  IF p_to = 'candidate' AND p_from IN ('active','observer','alumni','inactive') THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Invalid transition: ' || p_from || ' -> candidate. Candidate is pre-membership, not reachable from member states.',
      ERRCODE = '22023';
  END IF;

  -- All other transitions allowed at Foundation level.
  -- Features (G2) will enforce alumni->active goes through re_engagement_pipeline.
  RETURN;
END;
$$;

REVOKE ALL ON FUNCTION public.validate_status_transition(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_status_transition(text, text) TO authenticated, service_role;

COMMENT ON FUNCTION public.validate_status_transition(text, text) IS
'ARM-9 Foundation. State machine helper. Raises 22023 on truly invalid transitions (candidate ↔ terminal). All other transitions permitted at this layer. Re-engagement governance lives in Features (G2 re_engagement_pipeline).';

-- ============================================================
-- Step 3: Wire validate into admin_offboard_member
-- ============================================================
CREATE OR REPLACE FUNCTION public.admin_offboard_member(
  p_member_id uuid,
  p_new_status text,
  p_reason_category text,
  p_reason_detail text DEFAULT NULL::text,
  p_reassign_to uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller             record;
  v_member             record;
  v_audit_id           uuid;
  v_new_role           text;
  v_items_reassigned   integer := 0;
  v_engagements_closed integer := 0;
  v_prev_status        text;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
    RETURN jsonb_build_object('error','Unauthorized: requires manage_member permission');
  END IF;

  IF p_new_status NOT IN ('observer','alumni','inactive') THEN
    RETURN jsonb_build_object('error','Invalid status: ' || p_new_status);
  END IF;

  SELECT * INTO v_member FROM public.members WHERE id = p_member_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Member not found'); END IF;

  v_prev_status := COALESCE(v_member.member_status,'active');

  IF v_prev_status = p_new_status THEN
    RETURN jsonb_build_object('error','Member is already ' || p_new_status);
  END IF;

  -- ARM-9 G5: validate state transition (catch invalid origins)
  BEGIN
    PERFORM public.validate_status_transition(v_prev_status, p_new_status);
  EXCEPTION WHEN sqlstate '22023' THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      v_caller.id,
      'member.status_transition_blocked',
      'member',
      p_member_id,
      jsonb_build_object('attempted_from', v_prev_status, 'attempted_to', p_new_status),
      jsonb_build_object('error', SQLERRM, 'arm9_gate', 'validate_status_transition')
    );
    RETURN jsonb_build_object('error', SQLERRM, 'arm9_gate', 'validate_status_transition');
  END;

  v_new_role := CASE p_new_status
    WHEN 'alumni'   THEN 'alumni'
    WHEN 'observer' THEN 'observer'
    WHEN 'inactive' THEN 'none'
  END;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller.id,
    'member.status_transition',
    'member',
    p_member_id,
    jsonb_strip_nulls(jsonb_build_object(
      'previous_status', v_prev_status,
      'new_status', p_new_status,
      'previous_tribe_id', v_member.tribe_id
    )),
    jsonb_strip_nulls(jsonb_build_object(
      'reason_category', p_reason_category,
      'reason_detail', p_reason_detail,
      'items_reassigned_to', p_reassign_to
    ))
  )
  RETURNING id INTO v_audit_id;

  IF v_member.operational_role IS DISTINCT FROM v_new_role THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      v_caller.id,
      'member.role_change',
      'member',
      p_member_id,
      jsonb_build_object(
        'field', 'operational_role',
        'old_value', to_jsonb(v_member.operational_role),
        'new_value', to_jsonb(v_new_role),
        'effective_date', CURRENT_DATE
      ),
      jsonb_strip_nulls(jsonb_build_object(
        'change_type', 'role_changed',
        'reason', p_reason_detail,
        'authorized_by', v_caller.id
      ))
    );
  END IF;

  UPDATE public.members SET
    member_status        = p_new_status,
    operational_role     = v_new_role,
    is_active            = false,
    designations         = '{}'::text[],
    offboarded_at        = now(),
    offboarded_by        = v_caller.id,
    status_changed_at    = now(),
    status_change_reason = COALESCE(p_reason_detail, p_reason_category),
    updated_at           = now()
  WHERE id = p_member_id;

  IF v_member.person_id IS NOT NULL THEN
    UPDATE public.engagements SET
      status = 'offboarded', end_date = CURRENT_DATE,
      revoked_at = now(), revoked_by = v_caller.person_id,
      revoke_reason = COALESCE(p_reason_detail, p_reason_category),
      updated_at = now()
    WHERE person_id = v_member.person_id AND status = 'active';
    GET DIAGNOSTICS v_engagements_closed = ROW_COUNT;
  END IF;

  IF p_reassign_to IS NOT NULL THEN
    UPDATE public.board_items SET assignee_id = p_reassign_to
    WHERE assignee_id = p_member_id AND status != 'archived';
    GET DIAGNOSTICS v_items_reassigned = ROW_COUNT;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'audit_id', v_audit_id,
    'transition_id', v_audit_id,
    'member_name', v_member.name,
    'previous_status', v_prev_status,
    'new_status', p_new_status,
    'new_role', v_new_role,
    'items_reassigned', v_items_reassigned,
    'engagements_closed', v_engagements_closed,
    'designations_cleared', COALESCE(array_length(v_member.designations,1),0)
  );
END;
$function$;

-- ============================================================
-- Step 4: Add invariant N (terminal_status_offboarded_at_present)
-- ============================================================
CREATE OR REPLACE FUNCTION public.check_schema_invariants()
 RETURNS TABLE(invariant_name text, description text, severity text, violation_count integer, sample_ids uuid[])
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NULL
     AND current_setting('role', true) NOT IN ('service_role', 'postgres')
     AND current_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Unauthorized: check_schema_invariants requires authentication';
  END IF;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status = 'alumni'
      AND operational_role IS DISTINCT FROM 'alumni'
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
  )
  SELECT 'A1_alumni_role_consistency'::text,
         'member_status=alumni must coerce operational_role=alumni (B7 trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status = 'observer'
      AND operational_role NOT IN ('observer', 'guest', 'none')
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
  )
  SELECT 'A2_observer_role_consistency'::text,
         'member_status=observer must coerce operational_role IN (observer,guest,none) (B7 trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH computed AS (
    SELECT m.id AS member_id,
      CASE
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'manager')        THEN 'manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'deputy_manager') THEN 'deputy_manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'leader')         THEN 'tribe_leader'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'co_gp')          THEN 'manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'comms_leader')   THEN 'tribe_leader'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role IN ('researcher','facilitator','communicator','curator')) THEN 'researcher'
        WHEN bool_or(ae.kind = 'external_signer') THEN 'external_signer'
        WHEN bool_or(ae.kind = 'observer')      THEN 'observer'
        WHEN bool_or(ae.kind = 'alumni')        THEN 'alumni'
        WHEN bool_or(ae.kind = 'sponsor')       THEN 'sponsor'
        WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
        WHEN bool_or(ae.kind = 'candidate')     THEN 'candidate'
        ELSE 'guest'
      END AS expected_role
    FROM public.members m
    LEFT JOIN public.auth_engagements ae
      ON ae.person_id = m.person_id AND ae.is_authoritative = true
    WHERE m.member_status = 'active'
      AND m.name != 'VP Desenvolvimento Profissional (PMI-GO)'
    GROUP BY m.id
  ),
  drift AS (
    SELECT c.member_id FROM computed c
    JOIN public.members m ON m.id = c.member_id
    WHERE m.operational_role IS DISTINCT FROM c.expected_role
  )
  SELECT 'A3_active_role_engagement_derivation'::text,
         'active member operational_role must equal priority-ladder derivation from active engagements (cache trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE ((member_status = 'active' AND is_active = false)
        OR (member_status IN ('observer','alumni','inactive') AND is_active = true))
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
  )
  SELECT 'B_is_active_status_mismatch'::text,
         'members.is_active must match member_status mapping (active=true, terminal=false)'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive')
      AND designations IS NOT NULL
      AND array_length(designations, 1) > 0
  )
  SELECT 'C_designations_in_terminal_status'::text,
         'members.designations must be empty when member_status is observer/alumni/inactive'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    JOIN public.persons p ON p.id = m.person_id
    WHERE m.auth_id IS NOT NULL AND p.auth_id IS NOT NULL
      AND m.auth_id IS DISTINCT FROM p.auth_id
  )
  SELECT 'D_auth_id_mismatch_person_member'::text,
         'persons.auth_id and members.auth_id must agree when both are set (ghost resolution sync)'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT ae.engagement_id AS e_id FROM public.auth_engagements ae
    JOIN public.members m ON m.person_id = ae.person_id
    WHERE ae.status = 'active'
      AND m.member_status IN ('observer','alumni','inactive')
      AND ae.kind NOT IN ('observer','alumni','external_signer','sponsor','chapter_board','partner_contact')
  )
  SELECT 'E_engagement_active_with_terminal_member'::text,
         'engagement.status=active is inconsistent with member.member_status in (observer/alumni/inactive) unless kind matches'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(e_id ORDER BY e_id) FROM (SELECT e_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT i.id AS initiative_id FROM public.initiatives i
    WHERE i.legacy_tribe_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.tribes t WHERE t.id = i.legacy_tribe_id)
  )
  SELECT 'F_initiative_legacy_tribe_orphan'::text,
         'initiatives.legacy_tribe_id must point to an existing tribe (bridge integrity)'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(initiative_id ORDER BY initiative_id) FROM (SELECT initiative_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    LEFT JOIN public.document_versions dv ON dv.id = gd.current_version_id
    WHERE gd.current_version_id IS NOT NULL
      AND (dv.id IS NULL OR dv.locked_at IS NULL)
  )
  SELECT 'J_current_version_published'::text,
         'governance_documents.current_version_id must point to a document_versions row with locked_at IS NOT NULL (Phase IP-1).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    WHERE m.operational_role = 'external_signer'
      AND NOT EXISTS (
        SELECT 1 FROM public.auth_engagements ae
        WHERE ae.person_id = m.person_id AND ae.kind = 'external_signer'
          AND ae.status = 'active' AND ae.is_authoritative = true
      )
  )
  SELECT 'K_external_signer_integrity'::text,
         'members.operational_role=external_signer must have an active auth_engagements row with kind=external_signer (Phase IP-1).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    WHERE m.member_status IN ('alumni','observer','inactive')
      AND m.anonymized_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM public.member_offboarding_records r WHERE r.member_id = m.id)
  )
  SELECT 'L_offboarding_record_present'::text,
         'members in alumni/observer/inactive (not anonymized) must have a member_offboarding_records row (#91 G3 trigger).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- M_application_score_consistency (#140)
  RETURN QUERY
  WITH expected AS (
    SELECT
      a.id AS application_id,
      a.research_score AS cached,
      CASE
        WHEN e.obj_avg IS NOT NULL AND e.int_avg IS NOT NULL THEN round(e.obj_avg + e.int_avg, 2)
        WHEN e.obj_avg IS NOT NULL THEN round(e.obj_avg, 2)
        ELSE NULL
      END AS expected
    FROM public.selection_applications a
    CROSS JOIN LATERAL (
      SELECT
        AVG(weighted_subtotal) FILTER (WHERE evaluation_type = 'objective' AND submitted_at IS NOT NULL) AS obj_avg,
        AVG(weighted_subtotal) FILTER (WHERE evaluation_type = 'interview' AND submitted_at IS NOT NULL) AS int_avg
      FROM public.selection_evaluations
      WHERE application_id = a.id
    ) e
  ),
  drift AS (
    SELECT application_id FROM expected
    WHERE (cached IS NULL) IS DISTINCT FROM (expected IS NULL)
       OR (cached IS NOT NULL AND expected IS NOT NULL AND ABS(cached - expected) > 0.01)
  )
  SELECT 'M_application_score_consistency'::text,
         'selection_applications.research_score must equal compute_application_scores(application_id) derivation from selection_evaluations.weighted_subtotal (sync trigger trg_recompute_application_scores).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(application_id ORDER BY application_id) FROM (SELECT application_id FROM drift LIMIT 10) s)
  FROM drift;

  -- ARM-9 G6: N_terminal_status_offboarded_at_present (defense-in-depth complement to L)
  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive')
      AND offboarded_at IS NULL
      AND anonymized_at IS NULL
      AND name <> 'VP Desenvolvimento Profissional (PMI-GO)'
  )
  SELECT 'N_terminal_status_offboarded_at_present'::text,
         'members in alumni/observer/inactive (not anonymized) must have offboarded_at NOT NULL (ARM-9 G6 defense-in-depth complement to L).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

END;
$function$;

NOTIFY pgrst, 'reload schema';
