-- p162 Track B' G2b — Update cron v_has_signal + add invariantes O and P
-- v_has_signal now includes 3 new sections
-- + I_meeting_artifact_event_orphan (O) + I_tribe_initiative_bridge_complete (P)
-- Final body (replaces G2b initial + hotfix in DB; cleanly captures end state).

CREATE OR REPLACE FUNCTION public.generate_weekly_leader_digest_cron()
RETURNS TABLE(tribe_id integer, leader_id uuid, notified boolean, reason text, batch_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_t record;
  v_digest jsonb;
  v_has_signal boolean;
  v_batch_id uuid := gen_random_uuid();
  v_leader_pref text;
BEGIN
  FOR v_t IN
    SELECT t.id, t.leader_member_id, t.name FROM public.tribes t
    WHERE t.is_active = true AND t.leader_member_id IS NOT NULL
  LOOP
    SELECT notify_delivery_mode_pref INTO v_leader_pref FROM public.members WHERE id = v_t.leader_member_id;
    IF v_leader_pref = 'suppress_all' THEN
      tribe_id := v_t.id; leader_id := v_t.leader_member_id;
      notified := false; reason := 'leader_suppressed_all'; batch_id := NULL;
      RETURN NEXT; CONTINUE;
    END IF;

    v_digest := public.get_weekly_tribe_digest(v_t.id);
    v_has_signal :=
      (v_digest->'aggregates'->>'cards_overdue_total')::int > 0
      OR (v_digest->'aggregates'->>'cards_due_next_7d')::int > 0
      OR (v_digest->'aggregates'->>'cards_without_assignee')::int > 0
      OR (v_digest->'aggregates'->>'cards_without_due_date')::int > 0
      OR (v_digest->'aggregates'->>'cards_completed_window')::int > 0
      OR (v_digest->'aggregates'->'ata_pending'->>'count_events')::int > 0
      OR (v_digest->'aggregates'->'attendance_pending'->>'count')::int > 0
      OR (v_digest->'aggregates'->'champion_pending'->>'count')::int > 0;

    IF v_has_signal THEN
      INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, is_read, delivery_mode, digest_batch_id)
      VALUES (v_t.leader_member_id, 'weekly_tribe_digest_leader',
              'Resumo semanal da Tribo ' || v_t.name, v_digest::text,
              '/admin/portfolio', 'leader_digest', v_batch_id, false, 'transactional_immediate', v_batch_id);
      tribe_id := v_t.id; leader_id := v_t.leader_member_id; notified := true; reason := 'sent'; batch_id := v_batch_id;
    ELSE
      tribe_id := v_t.id; leader_id := v_t.leader_member_id; notified := false; reason := 'no_signal_skip'; batch_id := NULL;
    END IF;
    RETURN NEXT;
  END LOOP;
END;
$function$;

COMMENT ON FUNCTION public.generate_weekly_leader_digest_cron() IS
'Cron orchestrator for weekly leader digest (Sat 12:30 UTC). p162 Track B'' (ADR-0022 Amendment B): v_has_signal extended to include ata_pending + attendance_pending + champion_pending. Uses tribes.leader_member_id (V3) — V4 migration tracked as backlog #17.';

-- ════════════════════════════════════════════════════════════
-- 2 new invariantes: O + P (preserves A1/A2/A3/B/C/D/E/F/J/K/L/M/N)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.check_schema_invariants()
RETURNS TABLE(invariant_name text, description text, severity text, violation_count integer, sample_ids uuid[])
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NULL
     AND current_setting('role', true) NOT IN ('service_role','postgres')
     AND current_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'Unauthorized: check_schema_invariants requires authentication';
  END IF;

  RETURN QUERY
  WITH drift AS (SELECT id AS member_id FROM public.members WHERE member_status = 'alumni' AND operational_role IS DISTINCT FROM 'alumni' AND name != 'VP Desenvolvimento Profissional (PMI-GO)')
  SELECT 'A1_alumni_role_consistency'::text, 'member_status=alumni must coerce operational_role=alumni (B7 trigger)'::text, 'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s) FROM drift;

  RETURN QUERY
  WITH drift AS (SELECT id AS member_id FROM public.members WHERE member_status = 'observer' AND operational_role NOT IN ('observer','guest','none') AND name != 'VP Desenvolvimento Profissional (PMI-GO)')
  SELECT 'A2_observer_role_consistency'::text, 'member_status=observer must coerce operational_role IN (observer,guest,none) (B7 trigger)'::text, 'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s) FROM drift;

  RETURN QUERY
  WITH computed AS (
    SELECT m.id AS member_id,
      CASE
        WHEN bool_or(ae.kind='volunteer' AND ae.role='manager') THEN 'manager'
        WHEN bool_or(ae.kind='volunteer' AND ae.role='co_gp') THEN 'manager'
        WHEN bool_or(ae.kind='volunteer' AND ae.role='deputy_manager') THEN 'deputy_manager'
        WHEN bool_or(
          (ae.kind='volunteer' AND ae.role IN ('leader','comms_leader'))
          OR (ae.kind IN ('study_group_owner','committee_coordinator','workgroup_coordinator') AND ae.role IN ('leader','co_leader','owner','coordinator'))
          OR (ae.kind IN ('committee_member','workgroup_member') AND ae.role IN ('leader','coordinator'))
        ) THEN 'tribe_leader'
        WHEN bool_or(
          (ae.kind='volunteer' AND ae.role IN ('researcher','facilitator','communicator','curator'))
          OR (ae.kind IN ('committee_member','workgroup_member','study_group_owner') AND ae.role IN ('researcher','contributor','member','participant'))
        ) THEN 'researcher'
        WHEN bool_or(ae.kind='external_signer') THEN 'external_signer'
        WHEN bool_or(ae.kind='observer') THEN 'observer'
        WHEN bool_or(ae.kind='alumni') THEN 'alumni'
        WHEN bool_or(ae.kind='sponsor') THEN 'sponsor'
        WHEN bool_or(ae.kind='chapter_board') THEN 'chapter_liaison'
        WHEN bool_or(ae.kind='candidate') THEN 'candidate'
        ELSE 'guest' END AS expected_role
    FROM public.members m LEFT JOIN public.auth_engagements ae ON ae.person_id = m.person_id AND ae.is_authoritative = true
    WHERE m.member_status='active' AND m.name != 'VP Desenvolvimento Profissional (PMI-GO)' GROUP BY m.id
  ), drift AS (SELECT c.member_id FROM computed c JOIN public.members m ON m.id = c.member_id WHERE m.operational_role IS DISTINCT FROM c.expected_role)
  SELECT 'A3_active_role_engagement_derivation'::text, 'active member operational_role must equal priority-ladder derivation from active engagements (cache trigger)'::text, 'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s) FROM drift;

  RETURN QUERY
  WITH drift AS (SELECT id AS member_id FROM public.members WHERE ((member_status='active' AND is_active=false) OR (member_status IN ('observer','alumni','inactive') AND is_active=true)) AND name != 'VP Desenvolvimento Profissional (PMI-GO)')
  SELECT 'B_is_active_status_mismatch'::text, 'members.is_active must match member_status mapping (active=true, terminal=false)'::text, 'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s) FROM drift;

  RETURN QUERY
  WITH drift AS (SELECT id AS member_id FROM public.members WHERE member_status IN ('observer','alumni','inactive') AND designations IS NOT NULL AND array_length(designations,1)>0)
  SELECT 'C_designations_in_terminal_status'::text, 'members.designations must be empty when member_status is observer/alumni/inactive'::text, 'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s) FROM drift;

  RETURN QUERY
  WITH drift AS (SELECT m.id AS member_id FROM public.members m JOIN public.persons p ON p.id = m.person_id WHERE m.auth_id IS NOT NULL AND p.auth_id IS NOT NULL AND m.auth_id IS DISTINCT FROM p.auth_id)
  SELECT 'D_auth_id_mismatch_person_member'::text, 'persons.auth_id and members.auth_id must agree when both are set (ghost resolution sync)'::text, 'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s) FROM drift;

  RETURN QUERY
  WITH drift AS (SELECT ae.engagement_id AS e_id FROM public.auth_engagements ae JOIN public.members m ON m.person_id = ae.person_id WHERE ae.status='active' AND m.member_status IN ('observer','alumni','inactive') AND ae.kind NOT IN ('observer','alumni','external_signer','sponsor','chapter_board','partner_contact'))
  SELECT 'E_engagement_active_with_terminal_member'::text, 'engagement.status=active is inconsistent with member.member_status in (observer/alumni/inactive) unless kind matches'::text, 'high'::text, COUNT(*)::integer,
         (SELECT array_agg(e_id ORDER BY e_id) FROM (SELECT e_id FROM drift LIMIT 10) s) FROM drift;

  RETURN QUERY
  WITH drift AS (SELECT i.id AS initiative_id FROM public.initiatives i WHERE i.legacy_tribe_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.tribes t WHERE t.id = i.legacy_tribe_id))
  SELECT 'F_initiative_legacy_tribe_orphan'::text, 'initiatives.legacy_tribe_id must point to an existing tribe (bridge integrity)'::text, 'low'::text, COUNT(*)::integer,
         (SELECT array_agg(initiative_id ORDER BY initiative_id) FROM (SELECT initiative_id FROM drift LIMIT 10) s) FROM drift;

  RETURN QUERY
  WITH drift AS (SELECT gd.id AS doc_id FROM public.governance_documents gd LEFT JOIN public.document_versions dv ON dv.id = gd.current_version_id WHERE gd.current_version_id IS NOT NULL AND (dv.id IS NULL OR dv.locked_at IS NULL))
  SELECT 'J_current_version_published'::text, 'governance_documents.current_version_id must point to a document_versions row with locked_at IS NOT NULL (Phase IP-1).'::text, 'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s) FROM drift;

  RETURN QUERY
  WITH drift AS (SELECT m.id AS member_id FROM public.members m WHERE m.operational_role='external_signer' AND NOT EXISTS (SELECT 1 FROM public.auth_engagements ae WHERE ae.person_id=m.person_id AND ae.kind='external_signer' AND ae.status='active' AND ae.is_authoritative=true))
  SELECT 'K_external_signer_integrity'::text, 'members.operational_role=external_signer must have an active auth_engagements row with kind=external_signer (Phase IP-1).'::text, 'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s) FROM drift;

  RETURN QUERY
  WITH drift AS (SELECT m.id AS member_id FROM public.members m WHERE m.member_status IN ('alumni','observer','inactive') AND m.anonymized_at IS NULL AND NOT EXISTS (SELECT 1 FROM public.member_offboarding_records r WHERE r.member_id=m.id))
  SELECT 'L_offboarding_record_present'::text, 'members in alumni/observer/inactive (not anonymized) must have a member_offboarding_records row (#91 G3 trigger).'::text, 'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s) FROM drift;

  RETURN QUERY
  WITH expected AS (
    SELECT a.id AS application_id, a.research_score AS cached,
      CASE WHEN e.obj_avg IS NOT NULL AND e.int_avg IS NOT NULL THEN round(e.obj_avg + e.int_avg, 2) WHEN e.obj_avg IS NOT NULL THEN round(e.obj_avg, 2) ELSE NULL END AS expected
    FROM public.selection_applications a
    CROSS JOIN LATERAL (SELECT AVG(weighted_subtotal) FILTER (WHERE evaluation_type='objective' AND submitted_at IS NOT NULL) AS obj_avg, AVG(weighted_subtotal) FILTER (WHERE evaluation_type='interview' AND submitted_at IS NOT NULL) AS int_avg FROM public.selection_evaluations WHERE application_id=a.id) e
  ), drift AS (SELECT application_id FROM expected WHERE (cached IS NULL) IS DISTINCT FROM (expected IS NULL) OR (cached IS NOT NULL AND expected IS NOT NULL AND ABS(cached - expected) > 0.01))
  SELECT 'M_application_score_consistency'::text, 'selection_applications.research_score must equal compute_application_scores(application_id) derivation (trg_recompute_application_scores).'::text, 'high'::text, COUNT(*)::integer,
         (SELECT array_agg(application_id ORDER BY application_id) FROM (SELECT application_id FROM drift LIMIT 10) s) FROM drift;

  RETURN QUERY
  WITH drift AS (SELECT id AS member_id FROM public.members WHERE member_status IN ('observer','alumni','inactive') AND offboarded_at IS NULL AND anonymized_at IS NULL AND name <> 'VP Desenvolvimento Profissional (PMI-GO)')
  SELECT 'N_terminal_status_offboarded_at_present'::text, 'members in alumni/observer/inactive (not anonymized) must have offboarded_at NOT NULL (ARM-9 G6 complement to L).'::text, 'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s) FROM drift;

  -- O NEW p162 Track B' G2b
  RETURN QUERY
  WITH drift AS (SELECT ma.id AS artifact_id FROM public.meeting_artifacts ma WHERE ma.event_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.events e WHERE e.id = ma.event_id))
  SELECT 'O_meeting_artifact_event_orphan'::text, 'meeting_artifacts.event_id must point to an existing event when not NULL (FK defense).'::text, 'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(artifact_id ORDER BY artifact_id) FROM (SELECT artifact_id FROM drift LIMIT 10) s) FROM drift;

  -- P NEW p162 Track B' G2b (sample_ids omitted: tribes.id is integer not uuid)
  RETURN QUERY
  SELECT 'P_tribe_initiative_bridge_complete'::text,
         'tribes.is_active=true must have at least one initiative.legacy_tribe_id pointing to it (V3-V4 bridge; cron leader digest depends).'::text,
         'medium'::text,
         (SELECT COUNT(*)::integer FROM public.tribes t WHERE t.is_active = true AND NOT EXISTS (SELECT 1 FROM public.initiatives i WHERE i.legacy_tribe_id = t.id)),
         NULL::uuid[];
END;
$function$;

NOTIFY pgrst, 'reload schema';
