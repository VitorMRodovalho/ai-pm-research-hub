-- p281 #411 Wave 1d — selection_rescue_stuck_interview RPC (F4 atomic rescue)
--
-- WHAT: New SECDEF RPC public.selection_rescue_stuck_interview(p_application_id uuid).
--       Atomically rescues a candidate whose scheduled interview lapsed (evaluator
--       never accepted the Google Calendar invite, candidate parked in
--       interview_scheduled forever). Three steps in one transaction:
--         1. Cancel the stuck interview row (status='cancelled' + audit note).
--         2. Reset the application: status -> interview_pending (so it re-enters the
--            invite queue) AND cutoff_approved_email_sent_at = NULL (clears the
--            notify idempotency guard so the invite can be re-dispatched).
--         3. Re-dispatch via notify_selection_cutoff_approved(p_application_id).
--       Returns an aggregate envelope { success, cancelled_interview_id,
--       prior_scheduled_at, redispatch:<notify envelope> }.
--
-- WHY: Issue #411 Wave 1d. Three such cases hit in cycle4 (Rafael, Bruna, Luciana —
--      scheduled 2026-05-14, never conducted, never cancelled, 12 days dark). Closed
--      one-shot via DO-block in p270; this RPC is the permanent atomic path so the
--      modal button (F4) and the Wave 2b daily cron call ONE function and get a
--      consistent result + audit trail.
--
-- ATOMICITY (SPEC risk row): the whole body is one plpgsql (sub)transaction. We do
--      NOT catch notify's exception — if re-dispatch RAISEs (e.g. CUTOFF_NO_BOOKING_URL),
--      the entire function rolls back, so the cancel + reset never persist orphaned.
--      The success audit row is inserted AFTER notify returns, so it only lands on a
--      fully-successful rescue.
--
-- CRON-AWARE GATE (council Option B, ADR-0028 pattern — same as recompute_application_status
--      / selection_consistency_report): when auth.uid() IS NULL AND the session has no JWT
--      (current_setting('request.jwt.claims', true) IS NULL) OR auth.role()='service_role',
--      this is a pg_cron/service-role context reachable only from the service_role-only Wave 2b
--      cron wrapper — bypass the per-caller authority gate and attribute the audit row to a NULL
--      actor (admin_audit_log.actor_id is nullable for system rows; FK to members(id) only
--      constrains non-null) with metadata.dispatch_source='cron'. An authenticated ghost
--      (valid JWT, no members row) has a non-null auth.uid() + present jwt.claims, so it never
--      reaches the bypass — it RAISEs 'member not found' as before.
--
-- AUTHORITY (manual/UI path): committee lead for the cycle OR can_by_member(manage_member) —
--      the SAME ladder as notify_selection_cutoff_approved.
--
-- SEDIMENT-239b.A: every FK column written by this SECDEF function is sourced from the
--      resolved caller (actor_id := v_caller.id, NOT auth.uid()), preserving the FK to
--      members(id). organization_id on no new table writes here (audit log only).
--
-- ROLLBACK: DROP FUNCTION public.selection_rescue_stuck_interview(uuid);
--
-- Cross-refs: SPEC docs/specs/SPEC_SELECTION_INTERVIEW_INVITE_LIFECYCLE.md §F4;
--      notify body 20260805000030; interview-status-transition trigger 20260805000025
--      (it only ADVANCES app status; it ignores 'cancelled', so step 2 must set status
--      back to interview_pending explicitly — mirrors mark_interview_status cancel path).

CREATE OR REPLACE FUNCTION public.selection_rescue_stuck_interview(p_application_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller    public.members%ROWTYPE;
  v_is_cron   boolean := false;
  v_app       public.selection_applications%ROWTYPE;
  v_interview public.selection_interviews%ROWTYPE;
  v_notify    jsonb;
BEGIN
  -- Caller resolution + cron-aware gate (council Option B / ADR-0028).
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    IF current_setting('request.jwt.claims', true) IS NULL OR auth.role() = 'service_role' THEN
      v_is_cron := true;  -- pg_cron / service-role context; v_caller stays NULL (system actor)
    ELSE
      RAISE EXCEPTION 'Unauthorized: member not found';
    END IF;
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  -- Authority gate — skip in cron/service context (the service_role-only wrapper IS the gate).
  IF NOT v_is_cron THEN
    IF NOT (
      public.can_by_member(v_caller.id, 'manage_member'::text)
      OR EXISTS (
        SELECT 1 FROM public.selection_committee
        WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead'
      )
    ) THEN
      RAISE EXCEPTION 'Unauthorized: must be committee lead or have manage_member';
    END IF;
  END IF;

  -- Rescue is valid ONLY for a genuinely stuck application (status interview_scheduled).
  -- Guards against re-inviting an app that already advanced (interview_done / final_eval /
  -- approved / rejected / waitlist) but still carries a stale past-scheduled interview row —
  -- which would otherwise discard completed scoring and email a decided candidate. Matches the
  -- meta.interview_stuck predicate (mig 103) that gates the F2 chip + F4 button, and the Wave 2b
  -- cron must filter app.status='interview_scheduled' to avoid calling into this RAISE.
  IF v_app.status <> 'interview_scheduled' THEN
    RAISE EXCEPTION 'Application % is in status % — rescue only valid from interview_scheduled', p_application_id, v_app.status
      USING ERRCODE = 'P0023';
  END IF;

  -- Find the stuck interview: latest scheduled, past, never conducted.
  SELECT * INTO v_interview
  FROM public.selection_interviews
  WHERE application_id = p_application_id
    AND status = 'scheduled'
    AND conducted_at IS NULL
    AND scheduled_at IS NOT NULL
    AND scheduled_at < now()
  ORDER BY scheduled_at DESC
  LIMIT 1;

  IF v_interview IS NULL THEN
    RAISE EXCEPTION 'No stuck interview for application % (need a scheduled, past, not-conducted interview row)', p_application_id
      USING ERRCODE = 'P0022';
  END IF;

  -- Step 1: cancel the stuck interview (the transition trigger ignores 'cancelled').
  UPDATE public.selection_interviews
  SET status = 'cancelled',
      notes = COALESCE(notes || E'\n', '') ||
              '[rescue ' || to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'DD/MM HH24:MI') ||
              ': convite não aceito — reenvio automático do convite de agendamento]'
  WHERE id = v_interview.id;

  -- Step 2a: send the application back to interview_pending so it re-enters the invite queue
  -- (mirrors mark_interview_status cancel path). The status guard above already pinned the app
  -- to interview_scheduled, so this only ever moves interview_scheduled -> interview_pending.
  UPDATE public.selection_applications
  SET status = 'interview_pending', updated_at = now()
  WHERE id = p_application_id
    AND status = 'interview_scheduled';

  -- Step 2b: clear the notify idempotency guard so the invite can be re-dispatched.
  UPDATE public.selection_applications
  SET cutoff_approved_email_sent_at = NULL, updated_at = now()
  WHERE id = p_application_id;

  -- Step 3: re-dispatch. Not wrapped in EXCEPTION — if notify RAISEs, the whole rescue
  -- rolls back (atomic), so the cancel + reset never persist orphaned.
  v_notify := public.notify_selection_cutoff_approved(p_application_id);

  -- Success audit row (lands only on full success; actor NULL in cron context).
  INSERT INTO public.admin_audit_log (
    actor_id, action, target_type, target_id, changes, metadata
  ) VALUES (
    v_caller.id,
    'selection.stuck_interview_rescued',
    'selection_application',
    p_application_id,
    jsonb_build_object(
      'interview_id', v_interview.id,
      'interview_status_before', 'scheduled',
      'interview_status_after', 'cancelled'
    ),
    jsonb_build_object(
      'interview_id', v_interview.id,
      'prior_scheduled_at', v_interview.scheduled_at,
      'cycle_id', v_app.cycle_id,
      'new_dispatch_path', v_notify->>'resolution_path',
      'resolved_evaluator_id', v_notify->>'resolved_evaluator_id',
      'dispatch_source', CASE WHEN v_is_cron THEN 'cron' ELSE 'manual' END,
      'rpc_version', 'p281_411_w1d'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'application_id', p_application_id,
    'cancelled_interview_id', v_interview.id,
    'prior_scheduled_at', v_interview.scheduled_at,
    'dispatch_source', CASE WHEN v_is_cron THEN 'cron' ELSE 'manual' END,
    'redispatch', v_notify
  );
END;
$$;

REVOKE ALL ON FUNCTION public.selection_rescue_stuck_interview(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.selection_rescue_stuck_interview(uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.selection_rescue_stuck_interview(uuid) IS
'p281 #411 Wave 1d: atomically rescue a candidate whose scheduled interview lapsed — cancel the '
'stuck interview, reset the application to interview_pending + clear cutoff_approved_email_sent_at, '
'then re-dispatch via notify_selection_cutoff_approved. Authority: committee lead OR manage_member '
'(cron/service-role bypass per ADR-0028, actor_id NULL + metadata.dispatch_source=cron). Atomic: a '
'notify failure rolls the whole rescue back. Audit action selection.stuck_interview_rescued.';

NOTIFY pgrst, 'reload schema';
