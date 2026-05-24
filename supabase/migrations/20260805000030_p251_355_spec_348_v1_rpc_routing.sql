-- ============================================================
-- p251 #355 — SPEC #348 Child #2 RPC body (booking URL routing)
-- ------------------------------------------------------------
-- WHAT: Extend notify_selection_cutoff_approved(p_application_id uuid) to
--   route the {{interview_booking_url}} email variable per track:
--     - researcher track → LRD round-robin pick from committee with URLs
--                           (committee_override > member_global precedence)
--     - leader track → cycle.interview_booking_url (group/dual interview)
--     - fallback → cycle.interview_booking_url when researcher branch yields
--                   no candidate with a URL (preserves p243 behavior cycle 4)
--   Every dispatch logs a row to selection_dispatch_url_log BEFORE the
--   campaign_send_one_off call (audit + LRD lookback source).
--
-- WHY: Cycle 4 dispatch (p243) used a single cycle-level URL for everyone.
--   PM directive (#348 boot 2026-05-24): researcher → Vitor/Fabricio
--   individual; leader → Núcleo/dupla. Child #1 (p250 / #354) shipped the
--   schema; this leaf wires the routing. Per-evaluator URLs land later via
--   Child #3 admin UI (#356) and Child #4 cycle4 reseed (#357); until then
--   the cycle-level URL remains the safe fallback (researcher_branch with
--   empty committee → cycle_fallback path), so the cutoff dispatch keeps
--   working without ceremony.
--
-- SPEC DRIFT RESOLVED: SPEC §5.1 draft filtered `sc.role = 'researcher'`
--   but live schema has `selection_committee.role IN
--   ('evaluator','lead','observer')` (committee POSITION, not track).
--   PM ratified Option A 2026-05-24 p251: filter `role IN ('evaluator','lead')
--   AND can_interview=true` (excludes observer; PM-allowed evaluators of any
--   committee position can serve as researcher-track interviewer pool). Spec
--   doc amended in same commit (§5.1 query + §8 Child #4 seed). Routing
--   filter for researcher-track dispatches; leader branch DOES NOT query the
--   committee — cycle URL only by design.
--
-- PRESERVED VERBATIM:
--   - Signature: (p_application_id uuid) RETURNS jsonb (SEDIMENT-238.C — same
--     1-arg / same return type / no DEFAULTs; CREATE OR REPLACE preserves
--     proconfig search_path=public).
--   - Authority gate (committee role='lead' OR can_by_member 'manage_member').
--   - Idempotency check (cutoff_approved_email_sent_at not null → reason
--     'already_sent' early-return).
--   - email null check.
--   - Threshold sanity count (v_objective_done).
--   - first_name resolution (first_name → applicant_name first token →
--     fallback 'candidato(a)').
--   - UPDATE selection_applications SET cutoff_approved_email_sent_at = now().
--   - admin_audit_log canonical action 'selection.cutoff_approved_email_dispatched'.
--   - Return envelope keys (success, application_id, cycle_id, email_sent,
--     recipient_email_redacted, objective_done, research_score).
--
-- NEW (v1):
--   - Track-aware routing block (IF leader / ELSIF researcher / ELSE
--     defensive fallback).
--   - LRD picker with LEFT JOIN LATERAL on selection_dispatch_url_log filtered
--     to (cycle_id, track='researcher', resolved_evaluator_id), ordering by
--     dispatched_at NULLS FIRST then member_id for stable tiebreak (spec §5.2).
--   - INSERT into selection_dispatch_url_log BEFORE campaign_send_one_off
--     PERFORM (so audit row exists even if email send raises).
--   - campaign_send_one_off variable + metadata pass `v_resolved_url`
--     (was always `v_cycle.interview_booking_url`).
--   - admin_audit_log.metadata gains 3 keys: resolution_path,
--     resolved_evaluator_id, role_applied. rpc_version bumped
--     'p228_w2_leaf4' → 'p251_355'.
--   - Return envelope gains 2 keys: resolution_path, resolved_evaluator_id.
--   - CUTOFF_NO_BOOKING_URL only RAISEs when v_resolved_url is null/empty
--     (after fallback chain), with updated error string mentioning the
--     resolution attempt (cycle/role context).
--
-- ROLLBACK: replay 20260805000011_p228_260_w2_leaf4_selection_cutoff_approved.sql
--   to revert the RPC body to the pre-#348 version. selection_dispatch_url_log
--   rows remain in place (audit history is immutable). Safe because the table
--   has only insert traffic via this RPC and Child #4 hasn't seeded the
--   committee yet, so cycle_fallback path is the dominant outcome.
--
-- INVARIANTS: 19/19=0 unchanged. The new branching is additive; no schema
--   shape changes; no FK changes; no new RLS policies.
--
-- Cross-refs:
--   - Spec: docs/specs/SPEC_348_BOOKING_URL_PER_EVALUATOR.md §5.1 (amended
--     in same commit to lock the live-schema filter).
--   - Parent issue: #348 (PM 4-step booking_url roadmap)
--   - This issue: #355 (Child #2 RPC body)
--   - Predecessor: #354 (Child #1 Foundation, migration 20260805000029)
--   - Successor: #356 (Child #3 admin UI) — parallel-shippable; not blocking.
--   - Successor: #357 (Child #4 cycle4 reseed) — gated on this migration.
-- ============================================================

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
BEGIN
  -- Authority gate — same as dispatch_peer_review_invitations (committee lead OR
  -- manage_member). PM may use this manually until auto-trigger lands in p229+.
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead';

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_member'::text) THEN
    RAISE EXCEPTION 'Unauthorized: must be committee lead or have manage_member';
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
  -- (Pre-v1 RPC checked only v_cycle.interview_booking_url; v1 widens to
  -- "no resolvable URL at all" so PM gets a clear actionable error.)
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

  -- Threshold sanity (advisory; PM follow-up will add cron auto-trigger that
  -- enforces this server-side). For now, log objective_done count + research_score
  -- in audit metadata so admin can verify post-hoc.
  SELECT count(*)::int INTO v_objective_done
  FROM public.selection_evaluations
  WHERE application_id = p_application_id
    AND evaluation_type = 'objective';

  v_first_name := COALESCE(
    NULLIF(trim(v_app.first_name), ''),
    NULLIF(split_part(v_app.applicant_name, ' ', 1), ''),
    'candidato(a)'
  );

  -- Dispatch via campaign_send_one_off — pass the RESOLVED URL (pre-v1 used
  -- v_cycle.interview_booking_url unconditionally). Template variable name
  -- {{interview_booking_url}} is preserved for backward compatibility; only
  -- the substituted value is track-aware now.
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

  -- Mark idempotency post-send (best-effort — campaign_send_one_off raises on failure,
  -- which short-circuits before this UPDATE, so we never mark sent if email failed).
  UPDATE public.selection_applications
  SET cutoff_approved_email_sent_at = now(),
      updated_at = now()
  WHERE id = p_application_id;

  -- Audit log — canonical action preserved; metadata gains 3 routing fields.
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
      'rpc_version', 'p251_355'
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
