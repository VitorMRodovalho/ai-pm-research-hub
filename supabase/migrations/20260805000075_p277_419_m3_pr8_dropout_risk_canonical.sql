-- ════════════════════════════════════════════════════════════════
-- p277 / #419 (ADR-0100) metric 3 — PR8: repoint get_dropout_risk_members onto canonical eligibility (#420)
-- ════════════════════════════════════════════════════════════════
--
-- PROBLEM (live-broken): get_dropout_risk_members filtered events by the event types
-- 'general_meeting' / 'tribe_meeting' / 'leadership_meeting' — NONE of which exist live
-- (live types are geral/tribo/lideranca/kickoff/…). The candidate set collapsed to ~0
-- events, so `missed >= p_threshold` was never true and the function flagged NOBODY.
-- Both consumers (HomepageHero GP dropout alert + workspace DropoutRiskBanner) were
-- silently dead. Measured antes (as a manage_event holder): 0 flagged.
--
-- FIX: source the per-member eligible-event set from the single canonical primitive
-- public._attendance_eligible_events (type-based {geral,kickoff,tribo,lideranca}, cycles.is_current
-- window, tribo→own-tribe via get_member_tribe, lideranca→can_by_member('manage_event')) — the same
-- Canonical Eligibility Principle (SPEC §3b) every other attendance surface now uses. The dropout
-- semantic is preserved: flag a member who was ABSENT for ALL of their last p_threshold eligible
-- mandatory events. EXCUSED events are treated as NEUTRAL (removed from the window), consistent with
-- ratified decision D1 and get_attendance_engagement_rate — an org-sanctioned absence must not flag a
-- member as a dropout risk (the old body wrongly counted excused as a miss).
--
-- PRESERVED (contract): 8-col TABLE shape, p_threshold integer DEFAULT 3, the manage_event gate,
-- STABLE SECURITY DEFINER, search_path='', and the legacy members.tribe_id/tribes display columns
-- (the workspace banner leader-scopes on r.tribe_id === member.tribe_id, both legacy-sourced).
-- Eligibility uses the canonical bridge internally; display tribe stays legacy — no contract break.
--
-- Measured depois (manage_event holder, threshold 3): 0 → 4 flagged (Maria Luiza T8, Andressa Martins T2,
-- Gustavo Batista Ferreira T2, Débora Moura T2-leader). Two T4 researchers excused in-window correctly
-- do NOT flag. Same signature ⇒ CREATE OR REPLACE (GC-097); ACL preserved (authenticated, no anon).
--
-- ROLLBACK: re-apply migration 20260319100038_w134c_dropout_risk.sql (restores the dead-type body).
-- ════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_dropout_risk_members(p_threshold integer DEFAULT 3)
 RETURNS TABLE(member_id uuid, member_name text, tribe_id integer, tribe_name text, operational_role text, last_attendance_date date, days_since_last bigint, missed_events integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    SELECT m.id, m.name, m.tribe_id, t.name AS tname, m.operational_role
    FROM public.members m
    LEFT JOIN public.tribes t ON t.id = m.tribe_id
    WHERE m.is_active AND m.operational_role IN ('researcher','tribe_leader','manager')
  ),
  -- canonical eligible events per member; excused removed (D1 neutral); most-recent-first rank
  member_eligible AS (
    SELECT am.id AS mid, el.event_date AS edate,
           (att.present IS TRUE) AS was_present,
           ROW_NUMBER() OVER (PARTITION BY am.id ORDER BY el.event_date DESC, el.event_id DESC) AS rn
    FROM active_members am
    CROSS JOIN LATERAL public._attendance_eligible_events(am.id, NULL) el
    LEFT JOIN public.attendance att ON att.event_id = el.event_id AND att.member_id = am.id
    WHERE att.excused IS NOT TRUE
  ),
  -- of the last p_threshold non-excused eligible events, how many were absent (no present row)
  member_recent AS (
    SELECT me.mid, count(*) FILTER (WHERE NOT me.was_present) AS missed
    FROM member_eligible me
    WHERE me.rn <= p_threshold
    GROUP BY me.mid
  ),
  -- most recent present attendance over the member's full eligible set
  member_last AS (
    SELECT me.mid, max(me.edate) FILTER (WHERE me.was_present) AS last_date
    FROM member_eligible me
    GROUP BY me.mid
  )
  SELECT am.id, am.name, am.tribe_id, am.tname, am.operational_role,
         ml.last_date,
         (CURRENT_DATE - COALESCE(ml.last_date, DATE '2025-01-01'))::bigint,
         mr.missed::integer
  FROM active_members am
  JOIN member_recent mr ON mr.mid = am.id
  LEFT JOIN member_last ml ON ml.mid = am.id
  WHERE mr.missed >= p_threshold
  ORDER BY ml.last_date ASC NULLS FIRST;
END;
$function$;

NOTIFY pgrst, 'reload schema';
