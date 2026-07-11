-- #1104: admin_roll_cycle_membership — governed roll-forward of member_cycle_history
-- at cycle turnover. Ends the era of hand-written INSERT migrations (C2->C3, C3->C4
-- were run by hand; see 20260316120000 and 20260805000343_c4_roll_forward).
--
-- WHAT IT DOES (period-membership SSOT only):
--   * reads cycle metadata (label / start / end) from the `cycles` dimension — NO hardcoded
--     dates (smart-code rule; the dimension is the single source of truth).
--   * cohort = "continuers": active member with an ACTIVE from_cycle history row AND an
--     active, non-revoked volunteer engagement still vigente at the NEW cycle's start date
--     (end_date NULL or >= to_cycle.cycle_start), that does NOT already have a to_cycle row.
--   * on apply: closes still-open from_cycle history rows (cycle_end := from_cycle.cycle_end
--     from the dimension — SKIPPED while the from period is still open, i.e. cycle_end NULL)
--     then INSERTs a to_cycle snapshot row (live tribe/role/designations/chapter) per continuer.
--   * idempotent: NOT EXISTS guard on (member, to_cycle); re-running inserts/closes nothing new.
--   * dry_run default TRUE: returns the cohort count + a sample, writes nothing.
--   * audit row in admin_audit_log.
--
-- WHAT IT DOES NOT DO (by design, ratified 2026-07-10):
--   * it does NOT append to members.cycles[]. That array uses the SELECTION namespace
--     (selection_cycles.cycle_code, e.g. 'cycle4-2026'), maintained by the selection-approval
--     path — a different namespace from the PERIOD dimension ('cycle_4') this RPC rolls, with
--     no clean 1:1 map (a period can have 0..2 selection batches). Mixing them would duplicate
--     period membership into a selection-keyed projection. member_cycle_history stays the SSOT.
--
-- RUNBOOK DEPENDENCY (#809): to close the outgoing period's open history rows, set the outgoing
-- cycle's cycle_end in `cycles` FIRST (a governance act), then call this RPC with p_dry_run=false.
--
-- Authority: manage_platform (public.can). SECURITY DEFINER; self-gated; anon has no grant.

CREATE OR REPLACE FUNCTION public.admin_roll_cycle_membership(
  p_from_cycle text,
  p_to_cycle text,
  p_dry_run boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_person_id uuid;
  v_to_label text;
  v_to_start date;
  v_from_end date;
  v_from_found boolean;
  v_to_found boolean;
  v_ids uuid[];
  v_cohort_size int;
  v_inserted int := 0;
  v_closed int := 0;
  v_open_from int;
  v_sample jsonb;
BEGIN
  -- authn
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;
  SELECT id INTO v_person_id FROM public.persons WHERE legacy_member_id = v_member_id;

  -- authz
  IF NOT public.can(v_person_id, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized: manage_platform required');
  END IF;

  -- resolve the two cycles from the period dimension (SSOT for dates/labels)
  SELECT true, cycle_end INTO v_from_found, v_from_end
  FROM public.cycles WHERE cycle_code = p_from_cycle;
  IF v_from_found IS NULL THEN
    RETURN jsonb_build_object('error', format('from_cycle %s not found in cycles', p_from_cycle));
  END IF;

  SELECT true, cycle_label, cycle_start INTO v_to_found, v_to_label, v_to_start
  FROM public.cycles WHERE cycle_code = p_to_cycle;
  IF v_to_found IS NULL THEN
    RETURN jsonb_build_object('error', format('to_cycle %s not found in cycles', p_to_cycle));
  END IF;
  IF v_to_start IS NULL THEN
    RETURN jsonb_build_object('error', format('to_cycle %s has no cycle_start in cycles', p_to_cycle));
  END IF;

  -- cohort (compute the heavy join once): continuers not already rolled into to_cycle
  SELECT array_agg(DISTINCT m.id) INTO v_ids
  FROM public.members m
  JOIN public.member_cycle_history h
    ON h.member_id = m.id AND h.cycle_code = p_from_cycle AND h.is_active
  JOIN public.persons p ON p.legacy_member_id = m.id
  JOIN public.engagements e
    ON e.person_id = p.id AND e.kind = 'volunteer' AND e.status = 'active'
   AND e.revoked_at IS NULL
   AND (e.end_date IS NULL OR e.end_date >= v_to_start)
  WHERE m.is_active = true
    AND NOT EXISTS (
      SELECT 1 FROM public.member_cycle_history h2
      WHERE h2.member_id = m.id AND h2.cycle_code = p_to_cycle
    );

  v_cohort_size := COALESCE(array_length(v_ids, 1), 0);
  SELECT count(*) INTO v_open_from
    FROM public.member_cycle_history WHERE cycle_code = p_from_cycle AND cycle_end IS NULL;

  SELECT COALESCE(jsonb_agg(row_to_json(s)::jsonb ORDER BY s.name), '[]'::jsonb) INTO v_sample
  FROM (
    SELECT m.id AS member_id, m.name, m.tribe_id, m.operational_role
    FROM public.members m WHERE m.id = ANY(v_ids)
    ORDER BY m.name LIMIT 20
  ) s;

  IF p_dry_run THEN
    RETURN jsonb_build_object(
      'dry_run', true,
      'from_cycle', p_from_cycle,
      'to_cycle', p_to_cycle,
      'to_cycle_label', v_to_label,
      'to_cycle_start', v_to_start,
      'from_cycle_end', v_from_end,
      'cohort_size', v_cohort_size,
      'open_from_rows', v_open_from,
      'would_close_from_rows', CASE WHEN v_from_end IS NULL THEN 0 ELSE v_open_from END,
      'sample', v_sample
    );
  END IF;

  -- APPLY (idempotent). 1) close still-open from_cycle rows, only if the period is closed.
  IF v_from_end IS NOT NULL THEN
    UPDATE public.member_cycle_history
    SET cycle_end = v_from_end
    WHERE cycle_code = p_from_cycle AND cycle_end IS NULL;
    GET DIAGNOSTICS v_closed = ROW_COUNT;
  END IF;

  -- 2) insert to_cycle snapshot rows for the cohort (belt-and-suspenders NOT EXISTS guard)
  INSERT INTO public.member_cycle_history
    (member_id, member_name_snapshot, cycle_code, cycle_label, cycle_start, cycle_end,
     operational_role, designations, tribe_id, tribe_name, chapter, is_active, notes)
  SELECT m.id, m.name, p_to_cycle, v_to_label, v_to_start, NULL,
         m.operational_role, m.designations, m.tribe_id, t.name, m.chapter, true,
         format('roll-forward %s->%s via admin_roll_cycle_membership', p_from_cycle, p_to_cycle)
  FROM public.members m
  LEFT JOIN public.tribes t ON t.id = m.tribe_id
  WHERE m.id = ANY(v_ids)
    AND NOT EXISTS (
      SELECT 1 FROM public.member_cycle_history h3
      WHERE h3.member_id = m.id AND h3.cycle_code = p_to_cycle
    );
  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  -- 3) audit
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_member_id, 'cycle.membership_rolled', 'cycle', NULL,
    jsonb_build_object('from_cycle', p_from_cycle, 'to_cycle', p_to_cycle,
                       'inserted', v_inserted, 'closed_from_rows', v_closed,
                       'cohort_size', v_cohort_size),
    jsonb_build_object('to_cycle_label', v_to_label, 'to_cycle_start', v_to_start,
                       'from_cycle_end', v_from_end)
  );

  RETURN jsonb_build_object(
    'dry_run', false,
    'from_cycle', p_from_cycle,
    'to_cycle', p_to_cycle,
    'to_cycle_label', v_to_label,
    'to_cycle_start', v_to_start,
    'cohort_size', v_cohort_size,
    'inserted', v_inserted,
    'closed_from_rows', v_closed,
    'sample', v_sample
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.admin_roll_cycle_membership(text, text, boolean) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.admin_roll_cycle_membership(text, text, boolean) TO authenticated, service_role;
