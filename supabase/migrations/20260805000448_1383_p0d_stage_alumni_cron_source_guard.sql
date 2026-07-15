-- #1383 PR-D: scope the 'cron_new_cycle' staging source to the automated
-- cycle-open context. The auto-stage trigger trg_auto_stage_alumni_on_cycle_open
-- runs with no authenticated caller, so this source is accepted only when there is
-- no authenticated caller (or when executing inside a trigger). Interactive callers
-- use the manage_member-gated 'manual_admin' path. Body otherwise unchanged from
-- the live capture.
CREATE OR REPLACE FUNCTION public.stage_alumni_for_re_engagement(p_member_id uuid, p_cycle_code text, p_source text DEFAULT 'manual_admin'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_member record;
  v_record record;
  v_pipeline_id uuid;
  v_staged_by uuid := NULL;
BEGIN
  IF p_source NOT IN ('cron_new_cycle','manual_admin') THEN
    RETURN jsonb_build_object('error','Invalid source: ' || p_source);
  END IF;

  IF p_source = 'cron_new_cycle' THEN
    -- Automated cycle-open path (trg_auto_stage_alumni_on_cycle_open): no
    -- authenticated caller. Reject if an authenticated client outside a trigger
    -- tries to use this source to skip the manage_member gate below.
    IF auth.uid() IS NOT NULL AND pg_trigger_depth() = 0 THEN
      RETURN jsonb_build_object('error','Unauthorized: cron_new_cycle is reserved for automated cycle-open staging');
    END IF;
  ELSE
    -- manual_admin: authenticated caller with manage_member authority
    SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
    IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
    IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
      RETURN jsonb_build_object('error','Unauthorized: requires manage_member permission');
    END IF;
    v_staged_by := v_caller.id;
  END IF;

  SELECT * INTO v_member FROM public.members WHERE id = p_member_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Member not found'); END IF;

  IF v_member.member_status <> 'alumni' THEN
    RETURN jsonb_build_object('error','Member is not alumni (status: ' || COALESCE(v_member.member_status,'NULL') || ')');
  END IF;

  IF v_member.anonymized_at IS NOT NULL THEN
    RETURN jsonb_build_object('error','Cannot stage anonymized member (LGPD Art. 16 II)');
  END IF;

  -- Snapshot return_interest from offboarding record
  SELECT return_interest, reason_category_code INTO v_record
  FROM public.member_offboarding_records
  WHERE member_id = p_member_id
  ORDER BY offboarded_at DESC LIMIT 1;

  -- Idempotent: if active pipeline exists for (member,cycle), return it
  SELECT id INTO v_pipeline_id
  FROM public.re_engagement_pipeline
  WHERE member_id = p_member_id AND cycle_code = p_cycle_code
    AND state IN ('staged','invited','accepted')
  LIMIT 1;

  IF v_pipeline_id IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'pipeline_id', v_pipeline_id, 'idempotent', true);
  END IF;

  INSERT INTO public.re_engagement_pipeline (
    member_id, cycle_code, state, staged_by, staged_source,
    return_interest_snapshot, reason_category_snapshot
  ) VALUES (
    p_member_id, p_cycle_code, 'staged',
    v_staged_by,
    p_source,
    v_record.return_interest,
    v_record.reason_category_code
  )
  RETURNING id INTO v_pipeline_id;

  RETURN jsonb_build_object(
    'success', true,
    'pipeline_id', v_pipeline_id,
    'member_name', v_member.name,
    'return_interest', v_record.return_interest,
    'reason_category', v_record.reason_category_code
  );
END $function$;
