-- ARM-9 Features Post-G2: tighten validate_status_transition
-- Now that re_engagement_pipeline exists, BLOCK alumni→active direct transition.
-- Alumni→active must flow through pipeline: stage → invite → accepted → admin_reactivate_member.
-- inactive→active and observer→active remain direct (sabbatical/transition cases).
-- admin_reactivate_member adds guard: alumni source requires accepted pipeline entry.

CREATE OR REPLACE FUNCTION public.validate_status_transition(p_from text, p_to text)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF p_from = p_to THEN RETURN; END IF;

  IF p_from = 'candidate' AND p_to <> 'active' THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Invalid transition: candidate -> ' || p_to || '. Candidates only become active via selection acceptance.',
      ERRCODE = '22023';
  END IF;

  IF p_to = 'candidate' AND p_from IN ('active','observer','alumni','inactive') THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Invalid transition: ' || p_from || ' -> candidate. Candidate is pre-membership, not reachable from member states.',
      ERRCODE = '22023';
  END IF;

  -- ARM-9 Features Post-G2: alumni → active requires re-engagement pipeline path
  IF p_from = 'alumni' AND p_to = 'active' THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Invalid transition: alumni -> active. Alumni reactivation requires re-engagement pipeline (stage → invite → accepted). Use re_engagement_pipeline workflow + admin_reactivate_member.',
      ERRCODE = '22023';
  END IF;

  RETURN;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_reactivate_member(
  p_member_id uuid,
  p_tribe_id integer,
  p_role text DEFAULT 'researcher'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller   record;
  v_member   record;
  v_audit_id uuid;
  v_pipeline_id uuid;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
    RETURN jsonb_build_object('error','Unauthorized: requires manage_member permission');
  END IF;

  SELECT * INTO v_member FROM public.members WHERE id = p_member_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Member not found'); END IF;

  IF v_member.anonymized_at IS NOT NULL THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      v_caller.id, 'admin_reactivate_blocked_anonymized', 'member', p_member_id,
      jsonb_build_object(
        'anonymized_at', v_member.anonymized_at,
        'attempted_tribe_id', p_tribe_id,
        'attempted_role', p_role
      ),
      jsonb_build_object('lgpd_basis', 'Art. 16 II — anonymization is irreversible')
    );
    RETURN jsonb_build_object(
      'error','Cannot reactivate anonymized member',
      'reason','LGPD Art. 16 II — anonymization is irreversible by law',
      'anonymized_at', v_member.anonymized_at
    );
  END IF;

  IF v_member.member_status = 'active' THEN
    RETURN jsonb_build_object('error','Member is already active');
  END IF;

  -- ARM-9 Features Post-G2 guard: alumni reactivation requires accepted pipeline entry
  IF v_member.member_status = 'alumni' THEN
    SELECT id INTO v_pipeline_id
    FROM public.re_engagement_pipeline
    WHERE member_id = p_member_id AND state = 'accepted'
    ORDER BY responded_at DESC LIMIT 1;

    IF v_pipeline_id IS NULL THEN
      INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
      VALUES (
        v_caller.id, 'admin_reactivate_blocked_no_pipeline', 'member', p_member_id,
        jsonb_build_object('member_status', v_member.member_status),
        jsonb_build_object(
          'arm9_gate', 'requires_accepted_re_engagement_pipeline',
          'workflow', 'stage_alumni_for_re_engagement → invite_alumni_to_re_engage → respond_re_engagement(accepted) → admin_reactivate_member'
        )
      );
      RETURN jsonb_build_object(
        'error', 'Alumni reactivation requires accepted re-engagement pipeline entry',
        'arm9_gate', 'requires_accepted_re_engagement_pipeline',
        'workflow', 'stage → invite → accept → reactivate'
      );
    END IF;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller.id, 'member.status_transition', 'member', p_member_id,
    jsonb_strip_nulls(jsonb_build_object(
      'previous_status', v_member.member_status,
      'new_status', 'active',
      'previous_tribe_id', v_member.tribe_id,
      'new_tribe_id', p_tribe_id,
      'pipeline_id', v_pipeline_id
    )),
    jsonb_strip_nulls(jsonb_build_object('reason_category', 'return', 'pipeline_id', v_pipeline_id))
  )
  RETURNING id INTO v_audit_id;

  -- Bypass validate_status_transition for alumni (we've validated via pipeline above)
  IF v_member.member_status = 'alumni' THEN
    UPDATE public.members SET
      member_status = 'active',
      is_active = true,
      tribe_id = p_tribe_id,
      operational_role = p_role,
      status_changed_at = now(),
      offboarded_at = NULL,
      offboarded_by = NULL
    WHERE id = p_member_id;
  ELSE
    PERFORM public.validate_status_transition(v_member.member_status, 'active');
    UPDATE public.members SET
      member_status = 'active',
      is_active = true,
      tribe_id = p_tribe_id,
      operational_role = p_role,
      status_changed_at = now(),
      offboarded_at = NULL,
      offboarded_by = NULL
    WHERE id = p_member_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'audit_id', v_audit_id,
    'member_name', v_member.name,
    'new_tribe', p_tribe_id,
    'pipeline_id', v_pipeline_id
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
