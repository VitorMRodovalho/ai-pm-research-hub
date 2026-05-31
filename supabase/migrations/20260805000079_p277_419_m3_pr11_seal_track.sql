-- ════════════════════════════════════════════════════════════════
-- p277 / #419 (ADR-0100) metric 3 — PR11: roster seal track (events.roster_sealed_at + seal_event_attendance)
-- ════════════════════════════════════════════════════════════════
--
-- WHY (SPEC §7 PR11 + §2.2/§3 grounding): the RELIABILITY metric (get_attendance_rate / *Confiabilidade de
-- registro*) is structurally pinned near 100% because absences are never written — a no-show simply leaves no
-- attendance row, so the recorded denominator collapses to the present count (live antes: avg 0.9911, only 5
-- genuine absent rows cycle-wide). ENGAGEMENT (*Participação*, the headline) already counts an eligible no-show
-- as a miss, so it is the honest signal (live antes: avg 0.7991). The fix that lets reliability become
-- meaningful — and eventually converge to engagement — is to SEAL an event's roster: materialize an explicit
-- absent row (present=false, excused=false) for every eligible member who left no row. Education attendance
-- (chronic-absenteeism / ADA) is the direct precedent: a system is required to RECORD an absence, not just a
-- presence.
--
-- WHAT THIS MIGRATION SHIPS (the mechanism only — reliability is NOT promoted to a shown headline here; it
-- stays a self/admin diagnostic gated by D10 + the PR10 hard-gate until real seal coverage exists):
--
--   1. events.roster_sealed_at timestamptz — marks an event whose roster has been sealed (first-seal time).
--
--   2. seal_event_attendance(p_event_id uuid) -> jsonb — for one past, non-cancelled, attendance-bearing event
--      (type IN {geral,kickoff,tribo,lideranca}), INSERT an absent row for every eligible no-show in the
--      operational cohort (is_active AND current_cycle_active AND operational_role IN {researcher,tribe_leader,
--      manager} — IDENTICAL to get_attendance_engagement_summary's 'global' cohort, so reliability converges
--      onto engagement over the same population). Eligibility is resolved ONLY through the canonical primitive
--      public._attendance_eligible_events (SPEC §3b — no parallel eligibility model). ON CONFLICT (event_id,
--      member_id) DO NOTHING makes it idempotent and non-destructive (never overwrites a real present/excused
--      row). Gated by can_by_member(caller,'manage_event'), fail-closed. Sets roster_sealed_at = COALESCE(prior,
--      now()). Returns {success, event_id/title/type/date, eligible_cohort_n, sealed_absent_count,
--      already_recorded_count, roster_sealed_at}.
--
--   3. ONBOARDING-COMPLETION sealing-safety — GUARDED with present=true (both attendance->first_meeting paths):
--      a) auto_complete_first_meeting() — the AFTER INSERT trigger on attendance completed a member's
--         'first_meeting' onboarding step on their first-EVER attendance row, silently assuming every row is a
--         presence (true only while absences were never written). It now fires on the first PRESENT row only.
--      b) auto_detect_onboarding_completions() — the batch twin (its 'first_meeting' INSERT did SELECT ... FROM
--         attendance with no present filter) now filters WHERE a.present = true.
--      Both are minimal diffs; behaviour is identical for the historical present-first case, and a sealed ABSENT
--      row can no longer complete onboarding via either path.
--
-- COORDINATION — verified already sealing-safe, NO body change (live bodies read + the demonstrator seal
-- simulated+rolled-back this session):
--   * sync_attendance_points awards XP only WHERE a.present = true -> sealed absent rows (present=false) earn
--     NO XP by construction. No change; the contract test forward-defends the present=true predicate.
--   * detect_and_notify_detractors's "missed" predicate is already NOT EXISTS(... a.present = true ...) -> a
--     sealed absent row is NOT mistaken for attendance, so detection stays correct after sealing. No change.
--     (The handoff note "re-point predicate at present=true" is already satisfied in the live body.)
--
-- ⚠ PRESENT-BLIND CONSUMERS — NOT fixed here; a GATING PRECONDITION before any REAL seal coverage is run.
-- The seal RPC is a MANUAL write that nothing auto-invokes, so merging this migration corrupts nothing on its
-- own. But three consumers read row-EXISTENCE / row-ABSENCE as attendance and WOULD regress the moment a roster
-- is sealed. They belong to ADJACENT tracks (per SPEC §5) and are tracked for repointing to present-aware
-- semantics BEFORE the operator seals real events (see issue/#420 follow-up):
--   * get_public_impact_data (anon/LGPD-public) — total_attendance_hours + impact_hours SUM attendance JOIN
--     events with NO present filter -> sealed absents inflate PUBLIC impact hours (SPEC §5 "PR2 sibling").
--   * get_member_attendance_hours (member self-view + view_pii) — final hours/events aggregate has no present
--     filter AND the streak loop keys on row-existence -> sealed absents inflate hours and falsely extend a
--     streak (SPEC §5 "*_attendance_hours -> metric-2").
--   * get_admin_dashboard — the dropout alert (NOT IN ... attendance last 60d, no present filter) and the
--     detractor "missed" subquery (NOT EXISTS row) key absence on row-ABSENCE -> sealing makes both alerts
--     UNDER-report (the count(row)=attended anti-pattern PR8 fixed in get_dropout_risk_members; #420 Bucket A).
--
-- SEALING DOES NOT MOVE ENGAGEMENT (by design): get_attendance_engagement_rate already buckets an eligible
-- no-show (NULL row, excused IS NOT TRUE) into the denominator as a miss; a sealed (present=false,excused=false)
-- row lands in the identical bucket. Sealing moves only RELIABILITY (recorded denominator), converging it down
-- toward engagement. This is the load-bearing reason reliability — not engagement — is the gated diagnostic.
--
-- GRANT: write RPC. REVOKE PUBLIC/anon; GRANT authenticated + service_role. The manage_event gate is the
-- security boundary (fail-closed for no-member / non-manager callers), never anon.
--
-- ROLLBACK: DROP FUNCTION public.seal_event_attendance(uuid); restore auto_complete_first_meeting() from its
-- prior capture in migration 20260425143511_qa_orphan_recovery_triggers_legacy_compute.sql and
-- auto_detect_onboarding_completions() from 20260426001848_track_q_d_secdef_public_revoke_batch1.sql;
-- ALTER TABLE public.events DROP COLUMN roster_sealed_at.
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.events ADD COLUMN IF NOT EXISTS roster_sealed_at timestamptz;
COMMENT ON COLUMN public.events.roster_sealed_at IS
  'Timestamp the event roster was sealed via seal_event_attendance (absent rows materialized for eligible no-shows). NULL = not sealed. Reliability (Confiabilidade de registro) only becomes meaningful for an event once it is sealed (SPEC #419 m3 §7 PR11).';

CREATE OR REPLACE FUNCTION public.seal_event_attendance(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_type      text;
  v_status    text;
  v_date      date;
  v_title     text;
  v_org       uuid;
  v_sealed_at timestamptz;
  v_eligible  int := 0;
  v_sealed    int := 0;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Acesso negado: requer manage_event');
  END IF;

  SELECT e.type, e.status, e.date, e.title, e.organization_id, e.roster_sealed_at
    INTO v_type, v_status, v_date, v_title, v_org, v_sealed_at
  FROM public.events e WHERE e.id = p_event_id;

  IF v_type IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Evento não encontrado', 'event_id', p_event_id);
  END IF;
  IF v_type NOT IN ('geral','kickoff','tribo','lideranca') THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Tipo de evento não elegível para presença (' || v_type || ')', 'event_id', p_event_id);
  END IF;
  IF v_status = 'cancelled' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Evento cancelado não pode ser selado', 'event_id', p_event_id);
  END IF;
  IF v_date > CURRENT_DATE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Evento futuro não pode ser selado', 'event_id', p_event_id);
  END IF;

  -- eligible operational cohort for THIS event (canonical eligibility only — SPEC §3b)
  SELECT count(*) INTO v_eligible
  FROM public.members m
  WHERE m.is_active = true AND m.current_cycle_active = true
    AND m.operational_role IN ('researcher','tribe_leader','manager')
    AND EXISTS (
      SELECT 1 FROM public._attendance_eligible_events(m.id, NULL) ee WHERE ee.event_id = p_event_id
    );

  -- materialize an absent row for every eligible no-show (no existing row) — idempotent, non-destructive
  INSERT INTO public.attendance (event_id, member_id, present, excused, organization_id, notes, registered_by, marked_by, checked_in_at)
  SELECT p_event_id, m.id, false, false, v_org,
         '[roster_seal] no-show materializado (PR11 seal track)', v_caller_id, v_caller_id, NULL
  FROM public.members m
  WHERE m.is_active = true AND m.current_cycle_active = true
    AND m.operational_role IN ('researcher','tribe_leader','manager')
    AND EXISTS (
      SELECT 1 FROM public._attendance_eligible_events(m.id, NULL) ee WHERE ee.event_id = p_event_id
    )
  ON CONFLICT (event_id, member_id) DO NOTHING;
  GET DIAGNOSTICS v_sealed = ROW_COUNT;

  UPDATE public.events SET roster_sealed_at = COALESCE(roster_sealed_at, now())
  WHERE id = p_event_id
  RETURNING roster_sealed_at INTO v_sealed_at;

  RETURN jsonb_build_object(
    'success', true,
    'event_id', p_event_id,
    'event_title', v_title,
    'event_type', v_type,
    'event_date', v_date,
    'eligible_cohort_n', v_eligible,
    'sealed_absent_count', v_sealed,
    'already_recorded_count', GREATEST(v_eligible - v_sealed, 0),
    'roster_sealed_at', v_sealed_at
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.seal_event_attendance(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.seal_event_attendance(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.auto_complete_first_meeting()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Fire only on the member's first PRESENT attendance. Sealing (PR11) materializes absent rows
  -- (present=false) for eligible no-shows; an absence must NOT complete the 'first_meeting' onboarding step.
  IF NEW.present = true AND NOT EXISTS (
    SELECT 1 FROM attendance a WHERE a.member_id = NEW.member_id AND a.id != NEW.id AND a.present = true
  ) THEN
    UPDATE onboarding_progress SET status = 'completed', completed_at = now()
    WHERE member_id = NEW.member_id AND step_key = 'first_meeting' AND status != 'completed';
  END IF;
  RETURN NEW;
END;
$function$;

-- Batch twin of the trigger guard: the 'first_meeting' INSERT now requires a PRESENT row (sealing-safety).
CREATE OR REPLACE FUNCTION public.auto_detect_onboarding_completions()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  INSERT INTO onboarding_progress (member_id, step_key, status, completed_at)
  SELECT m.id, 'complete_profile', 'completed', now()
  FROM members m WHERE m.is_active AND (
    (m.name IS NOT NULL AND m.name != '')::int + (m.photo_url IS NOT NULL AND m.photo_url != '')::int +
    (m.state IS NOT NULL AND m.state != '')::int + (m.country IS NOT NULL AND m.country != '')::int +
    (m.linkedin_url IS NOT NULL AND m.linkedin_url != '')::int + (m.pmi_id IS NOT NULL)::int
  ) >= 4
  ON CONFLICT (member_id, step_key) DO UPDATE SET status = 'completed', completed_at = now() WHERE onboarding_progress.status != 'completed';

  INSERT INTO onboarding_progress (member_id, step_key, status, completed_at)
  SELECT DISTINCT gp.member_id, 'start_trail', 'completed', now()
  FROM gamification_points gp WHERE gp.category = 'trail'
  ON CONFLICT (member_id, step_key) DO UPDATE SET status = 'completed', completed_at = now() WHERE onboarding_progress.status != 'completed';

  -- PR11 sealing-safety: 'first_meeting' completes only on a PRESENT row (the batch twin of the
  -- auto_complete_first_meeting trigger guard) — a sealed absent row must not complete onboarding.
  INSERT INTO onboarding_progress (member_id, step_key, status, completed_at)
  SELECT DISTINCT a.member_id, 'first_meeting', 'completed', now()
  FROM attendance a
  WHERE a.present = true
  ON CONFLICT (member_id, step_key) DO UPDATE SET status = 'completed', completed_at = now() WHERE onboarding_progress.status != 'completed';
END; $function$;

NOTIFY pgrst, 'reload schema';
