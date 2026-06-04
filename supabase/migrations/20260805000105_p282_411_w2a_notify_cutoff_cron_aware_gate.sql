-- p282 #411 Wave 2a (part 1) — cron-aware authority gate on notify_selection_cutoff_approved
--
-- WHAT: Body-only CREATE OR REPLACE of notify_selection_cutoff_approved(uuid). Adds the
--       ADR-0028 cron/service bypass so the Wave 2a/2b daily crons (running under pg_cron /
--       service_role, where auth.uid() is NULL) can dispatch the cutoff-approved invite.
--       Identical signature, return shape, routing, idempotency, email, and audit body as
--       20260805000030 EXCEPT:
--         (1) new local `v_is_cron boolean`;
--         (2) the `v_caller IS NULL` hard-RAISE becomes the ADR-0028 branch — when there is
--             no JWT (current_setting('request.jwt.claims',true) IS NULL) OR auth.role() is
--             service_role, this is a cron/service context: allow through with v_caller NULL
--             (system actor); otherwise (authenticated ghost: JWT present, no members row)
--             still RAISE 'member not found';
--         (3) the committee-lead / manage_member gate is wrapped in `IF NOT v_is_cron`;
--         (4) the admin_audit_log.metadata gains `dispatch_source` (cron|manual). actor_id
--             stays v_caller.id (NULL in cron — admin_audit_log.actor_id is nullable for
--             system rows; FK to members(id) only constrains non-null).
--
-- WHY: notify previously hard-RAISEd on NULL auth.uid(), so a cron could never call it. This
--      is the pre-condition the code-reviewer flagged for Wave 2b (the rescue cron calls
--      rescue -> notify in service-role context). The pattern mirrors the sibling selection
--      crons recompute_application_status (20260805000090) and selection_consistency_report
--      (20260805000097), and ADR-0028 (20260516490001).
--
-- SECURITY (council security-engineer + data-architect, both -> Option B): the bypass is only
--      reachable from a no-JWT (pg_cron) or service_role session. PostgREST always sets
--      request.jwt.claims for an authenticated request, so an authenticated user (incl. a
--      memberless "ghost") has a non-null auth.uid() and present claims -> never reaches the
--      bypass -> still RAISEs. notify's GRANT stays authenticated+service_role (anon excluded).
--
-- SEDIMENT-238.C: same 1-arg signature / same RETURNS jsonb / proconfig search_path=public
--      preserved. CREATE OR REPLACE (not DROP+CREATE).
--
-- ROLLBACK: replay 20260805000030_p251_355_spec_348_v1_rpc_routing.sql to revert to the
--      pre-cron body (the cron bypass + dispatch_source metadata drop; manual UI path
--      unchanged). The Wave 2a/2b crons would then fail closed (RAISE caught by their
--      per-row EXCEPTION blocks) — safe, no data corruption.

CREATE OR REPLACE FUNCTION public.notify_selection_cutoff_approved(p_application_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller record;
  v_app record;
  v_cycle record;
  v_committee record;
  v_first_name text;
  v_objective_done int;
  -- v1 routing locals (#355)
  v_resolved_url text;
  v_resolution_path text;
  v_resolved_evaluator_id uuid;
  -- p282 #411 W2a: cron/service context flag (ADR-0028)
  v_is_cron boolean := false;
BEGIN
  -- Authority gate — same as dispatch_peer_review_invitations (committee lead OR
  -- manage_member). PM may use this manually; the Wave 2a/2b crons use the ADR-0028
  -- cron bypass below.
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    -- ADR-0028 cron/service bypass: a no-JWT (pg_cron) or service_role session is the
    -- automated dispatch path. An authenticated ghost (JWT present, no members row) has a
    -- non-null auth.uid() + present claims, so it skips this branch and RAISEs below.
    IF current_setting('request.jwt.claims', true) IS NULL OR auth.role() = 'service_role' THEN
      v_is_cron := true;  -- v_caller stays NULL → actor_id NULL (system row)
    ELSE
      RAISE EXCEPTION 'Unauthorized: member not found';
    END IF;
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  -- Per-caller authority gate — skipped in cron/service context (the service_role-only
  -- cron wrapper is itself the gate).
  IF NOT v_is_cron THEN
    SELECT * INTO v_committee
    FROM public.selection_committee
    WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead';

    IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_member'::text) THEN
      RAISE EXCEPTION 'Unauthorized: must be committee lead or have manage_member';
    END IF;
  END IF;

  -- Idempotency: single-fire per application
  IF v_app.cutoff_approved_email_sent_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'application_id', p_application_id,
      'email_sent', false,
      'reason', 'already_sent',
      'previously_sent_at', v_app.cutoff_approved_email_sent_at
    );
  END IF;

  IF v_app.email IS NULL THEN
    RAISE EXCEPTION 'Application has no email — cannot dispatch';
  END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  -- ============================================================
  -- SPEC #348 v1 (#355): track-aware booking URL routing
  -- ------------------------------------------------------------
  -- Researcher → LRD round-robin over committee evaluators/leads with a
  -- resolvable URL (committee_override > member_global).
  -- Leader → cycle.interview_booking_url (group/dual interview semantics;
  -- never queries committee per PM directive).
  -- Fallback → cycle.interview_booking_url when researcher branch yields no
  -- candidate (preserves p243 Cycle 4 behavior while committee unseeded).
  -- ============================================================
  IF v_app.role_applied = 'leader' THEN
    v_resolved_url := v_cycle.interview_booking_url;
    v_resolution_path := 'cycle_fallback';
    v_resolved_evaluator_id := NULL;

  ELSIF v_app.role_applied = 'researcher' THEN
    -- LRD picker — pick the committee member with the oldest last-dispatched
    -- timestamp (NULLS FIRST so never-used evaluators come first). Tiebreak
    -- by member_id for stable ordering. Live-schema filter per PM-ratified
    -- Option A (2026-05-24 p251): role IN ('evaluator','lead') excludes
    -- observer; committee POSITION is independent of candidate TRACK.
    SELECT
      sc.member_id,
      COALESCE(sc.interview_booking_url, m.interview_booking_url),
      CASE
        WHEN sc.interview_booking_url IS NOT NULL THEN 'committee_override'
        ELSE 'member_global'
      END
    INTO
      v_resolved_evaluator_id,
      v_resolved_url,
      v_resolution_path
    FROM public.selection_committee sc
    JOIN public.members m ON m.id = sc.member_id
    LEFT JOIN LATERAL (
      SELECT MAX(dispatched_at) AS last_dispatched
      FROM public.selection_dispatch_url_log l
      WHERE l.cycle_id = v_cycle.id
        AND l.track = 'researcher'
        AND l.resolved_evaluator_id = sc.member_id
    ) lrd ON true
    WHERE sc.cycle_id = v_cycle.id
      AND sc.role IN ('evaluator', 'lead')
      AND sc.can_interview = true
      AND COALESCE(sc.interview_booking_url, m.interview_booking_url) IS NOT NULL
    ORDER BY lrd.last_dispatched NULLS FIRST, sc.member_id
    LIMIT 1;

    -- Fallback: no committee member with a URL → cycle URL.
    IF v_resolved_url IS NULL THEN
      v_resolved_url := v_cycle.interview_booking_url;
      v_resolution_path := 'cycle_fallback';
      v_resolved_evaluator_id := NULL;
    END IF;

  ELSE
    -- Defensive fallback for any unknown role_applied (today: only
    -- 'researcher' and 'leader' exist in production data).
    v_resolved_url := v_cycle.interview_booking_url;
    v_resolution_path := 'cycle_fallback';
    v_resolved_evaluator_id := NULL;
  END IF;

  -- Single gate: raise only if BOTH per-evaluator and cycle URLs are absent.
  IF v_resolved_url IS NULL OR length(trim(v_resolved_url)) = 0 THEN
    RAISE EXCEPTION 'CUTOFF_NO_BOOKING_URL: no resolvable booking URL for application % (cycle %, role %); set selection_cycles.interview_booking_url or seed selection_committee with per-evaluator URLs',
      p_application_id, v_app.cycle_id, v_app.role_applied USING ERRCODE = 'P0020';
  END IF;

  -- Dispatch audit row BEFORE campaign_send_one_off — captures which URL +
  -- which precedence path produced it. Becomes the LRD lookback source for
  -- subsequent researcher-track dispatches in the same cycle.
  INSERT INTO public.selection_dispatch_url_log (
    application_id,
    cycle_id,
    track,
    resolved_url,
    resolution_path,
    resolved_evaluator_id,
    organization_id
  ) VALUES (
    p_application_id,
    v_app.cycle_id,
    v_app.role_applied,
    v_resolved_url,
    v_resolution_path,
    v_resolved_evaluator_id,
    v_app.organization_id
  );

  -- Threshold sanity (advisory).
  SELECT count(*)::int INTO v_objective_done
  FROM public.selection_evaluations
  WHERE application_id = p_application_id
    AND evaluation_type = 'objective';

  v_first_name := COALESCE(
    NULLIF(trim(v_app.first_name), ''),
    NULLIF(split_part(v_app.applicant_name, ' ', 1), ''),
    'candidato(a)'
  );

  -- Dispatch via campaign_send_one_off — pass the RESOLVED URL.
  PERFORM public.campaign_send_one_off(
    p_template_slug := 'selection_cutoff_approved',
    p_to_email := v_app.email,
    p_variables := jsonb_build_object(
      'first_name', v_first_name,
      'interview_booking_url', v_resolved_url
    ),
    p_metadata := jsonb_build_object(
      'source', 'notify_selection_cutoff_approved',
      'application_id', p_application_id,
      'cycle_id', v_app.cycle_id,
      'cycle_code', v_cycle.cycle_code,
      'objective_done', v_objective_done,
      'research_score', v_app.research_score,
      'resolution_path', v_resolution_path,
      'resolved_evaluator_id', v_resolved_evaluator_id
    )
  );

  -- Mark idempotency post-send.
  UPDATE public.selection_applications
  SET cutoff_approved_email_sent_at = now(),
      updated_at = now()
  WHERE id = p_application_id;

  -- Audit log — canonical action preserved; metadata gains dispatch_source (p282 W2a).
  INSERT INTO public.admin_audit_log (
    actor_id, action, target_type, target_id, changes, metadata
  ) VALUES (
    v_caller.id,
    'selection.cutoff_approved_email_dispatched',
    'selection_application',
    p_application_id,
    jsonb_build_object(
      'cutoff_approved_email_sent_at_before', NULL,
      'cutoff_approved_email_sent_at_after', now(),
      'recipient_email', v_app.email
    ),
    jsonb_build_object(
      'cycle_id', v_app.cycle_id,
      'cycle_code', v_cycle.cycle_code,
      'objective_done', v_objective_done,
      'research_score', v_app.research_score,
      'interview_booking_url', v_resolved_url,
      'resolution_path', v_resolution_path,
      'resolved_evaluator_id', v_resolved_evaluator_id,
      'role_applied', v_app.role_applied,
      'dispatch_source', CASE WHEN v_is_cron THEN 'cron' ELSE 'manual' END,
      'rpc_version', 'p282_411'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'application_id', p_application_id,
    'cycle_id', v_app.cycle_id,
    'email_sent', true,
    'recipient_email_redacted', LEFT(v_app.email, 2) || '***' || RIGHT(v_app.email, 4),
    'objective_done', v_objective_done,
    'research_score', v_app.research_score,
    'resolution_path', v_resolution_path,
    'resolved_evaluator_id', v_resolved_evaluator_id
  );
END;
$$;

NOTIFY pgrst, 'reload schema';
