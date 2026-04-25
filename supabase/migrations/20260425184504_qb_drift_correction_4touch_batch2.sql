-- Track Q-B Phase B (4-touch drift diff) — drift-correction batch 2 (9 fns)
--
-- Captures live `pg_get_functiondef` body as-of 2026-04-25 for 9 of the 34
-- four-migration-touched (4-touch) functions where the live body diverged
-- from the latest migration capture. Drift rate: 9/34 = 26.5% (lower than
-- top-15 batch 1's 40%, as expected — fewer touches → less divergence
-- opportunity).
--
-- Methodology: same as batch 1 (qb_drift_correction_top6_high_touch).
-- 1. Computed normalized-whitespace MD5 of `pg_proc.prosrc` for the 34 fns.
-- 2. Extracted latest CREATE FUNCTION block hash from migration files.
-- 3. 9/34 divergent → captured in this migration.
-- 4. The remaining 25 matched — no migration needed.
--
-- Drift breakdown (9 fns):
--   create_pilot                       → 20260427180000_adr0015_phase3_drop_tribe_id_small_3
--   drop_event_instance                → 20260505030000_sweep2_stale_events_tribe_id_writers
--   get_member_cycle_xp                → 20260331030000_xp_rank_position
--   list_meeting_artifacts             → 20260427200000_adr0015_phase3b_drop_4_safe_tables
--   list_tribe_deliverables            → 20260427200000_adr0015_phase3b_drop_4_safe_tables
--   sign_ip_ratification               → 20260504040000_ip3e_rf_iii_v_audit_tribe_id_webinar_triggers
--   sync_operational_role_cache        → 20260510060000_fix_comms_leader_role_mapping
--   upsert_publication_submission_event → 20260319100043_w139_publication_submissions
--   upsert_tribe_deliverable           → 20260427200000_adr0015_phase3b_drop_4_safe_tables
--
-- 25 clean (no migration): admin_get_member_details, admin_list_members_with_pii,
-- admin_manage_publication, admin_reactivate_member, anonymize_inactive_members,
-- create_recurring_weekly_events, exec_cross_tribe_comparison, exec_cycle_report,
-- get_adoption_dashboard, get_board_by_domain, get_campaign_analytics,
-- get_curation_cross_board, get_event_detail, get_meeting_notes_compliance,
-- get_my_notifications, get_tribe_event_roster, list_curation_pending_board_items,
-- list_legacy_board_items_for_tribe, list_meetings_with_notes, list_project_boards,
-- save_presentation_snapshot, update_board_item, update_event, upsert_board_item,
-- upsert_webinar.
--
-- No behavior change — bodies are byte-equivalent to live `pg_get_functiondef`
-- output. CREATE OR REPLACE is idempotent on existing live state.
--
-- Dollar-quote tag: $$ (not $function$) to keep
-- tests/contracts/kpi-portfolio-health.test.mjs and other anchor-on-$$
-- contract tests robust. Verified: no $$ literals in any of the 9 bodies.

CREATE OR REPLACE FUNCTION public.create_pilot(p_title text, p_hypothesis text DEFAULT NULL::text, p_problem_statement text DEFAULT NULL::text, p_scope text DEFAULT NULL::text, p_status text DEFAULT 'draft'::text, p_tribe_id integer DEFAULT NULL::integer, p_board_id uuid DEFAULT NULL::uuid, p_success_metrics jsonb DEFAULT '[]'::jsonb, p_team_member_ids uuid[] DEFAULT '{}'::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid; v_next_number integer; v_new_id uuid; v_initiative_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: not authenticated'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member permission';
  END IF;

  SELECT COALESCE(MAX(pilot_number), 0) + 1 INTO v_next_number FROM public.pilots;

  IF p_tribe_id IS NOT NULL THEN
    SELECT id INTO v_initiative_id FROM public.initiatives
    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  END IF;

  INSERT INTO public.pilots (
    pilot_number, title, hypothesis, problem_statement, scope, status,
    initiative_id,
    board_id, success_metrics, team_member_ids, created_by, started_at
  )
  VALUES (
    v_next_number, p_title, p_hypothesis, p_problem_statement, p_scope, p_status,
    v_initiative_id,
    p_board_id, p_success_metrics, p_team_member_ids, v_caller_id,
    CASE WHEN p_status = 'active' THEN CURRENT_DATE ELSE NULL END
  )
  RETURNING id INTO v_new_id;

  RETURN jsonb_build_object('success', true, 'id', v_new_id, 'pilot_number', v_next_number);
END; $$;

CREATE OR REPLACE FUNCTION public.drop_event_instance(p_event_id uuid, p_force_delete_attendance boolean DEFAULT false)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_caller_tribe int;
  v_event_tribe int;
  v_event_date date;
  v_event_title text;
  v_att_count int;
  v_blocker text;
BEGIN
  SELECT id, operational_role, tribe_id INTO v_caller_id, v_caller_role, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT i.legacy_tribe_id, e.date, e.title
    INTO v_event_tribe, v_event_date, v_event_title
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.id = p_event_id;
  IF v_event_date IS NULL THEN RAISE EXCEPTION 'Event not found'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event permission';
  END IF;
  IF v_caller_role = 'tribe_leader' AND v_caller_tribe IS DISTINCT FROM v_event_tribe THEN
    RAISE EXCEPTION 'Unauthorized: tribe_leader can only manage events of own tribe';
  END IF;

  SELECT count(*) INTO v_att_count FROM public.attendance WHERE event_id = p_event_id;
  IF v_att_count > 0 AND NOT p_force_delete_attendance THEN
    RAISE EXCEPTION 'attendance_exists:%', v_att_count USING HINT = 'Evento possui ' || v_att_count || ' presença(s) registrada(s). Re-chame com p_force_delete_attendance=true para remover.';
  END IF;

  v_blocker := '';
  IF EXISTS (SELECT 1 FROM public.meeting_artifacts WHERE event_id = p_event_id) THEN v_blocker := v_blocker || 'meeting_artifacts, '; END IF;
  IF EXISTS (SELECT 1 FROM public.cost_entries WHERE event_id = p_event_id) THEN v_blocker := v_blocker || 'cost_entries, '; END IF;
  IF EXISTS (SELECT 1 FROM public.cpmai_sessions WHERE event_id = p_event_id) THEN v_blocker := v_blocker || 'cpmai_sessions, '; END IF;
  IF EXISTS (SELECT 1 FROM public.webinars WHERE event_id = p_event_id) THEN v_blocker := v_blocker || 'webinars, '; END IF;
  IF EXISTS (SELECT 1 FROM public.event_showcases WHERE event_id = p_event_id) THEN v_blocker := v_blocker || 'event_showcases, '; END IF;
  IF EXISTS (SELECT 1 FROM public.meeting_action_items WHERE carried_to_event_id = p_event_id) THEN v_blocker := v_blocker || 'meeting_action_items (carried_to), '; END IF;
  IF v_blocker <> '' THEN
    v_blocker := rtrim(v_blocker, ', ');
    RAISE EXCEPTION 'Evento possui dependencias que impedem a exclusao: %', v_blocker;
  END IF;

  IF v_att_count > 0 AND p_force_delete_attendance THEN
    DELETE FROM public.attendance WHERE event_id = p_event_id;
  END IF;
  DELETE FROM public.events WHERE id = p_event_id;

  RETURN json_build_object('success', true, 'deleted_event_id', p_event_id, 'deleted_date', v_event_date, 'deleted_title', v_event_title, 'deleted_attendance_count', COALESCE(v_att_count, 0), 'force_used', p_force_delete_attendance);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_member_cycle_xp(p_member_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
declare
  cycle_start_date date;
  v_rank int;
  v_total int;
  result json;
begin
  select cycle_start into cycle_start_date
  from public.cycles where is_current = true limit 1;

  if cycle_start_date is null then
    cycle_start_date := '2026-01-01';
  end if;

  WITH ranked AS (
    SELECT member_id, COALESCE(SUM(points), 0) as total_pts,
           ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(points), 0) DESC) as pos
    FROM public.gamification_points
    GROUP BY member_id
  )
  SELECT pos, (SELECT COUNT(DISTINCT member_id) FROM public.gamification_points)
  INTO v_rank, v_total
  FROM ranked WHERE member_id = p_member_id;

  select json_build_object(
    'lifetime_points', coalesce(sum(points), 0)::int,
    'cycle_points', coalesce(sum(points) filter (where created_at >= cycle_start_date), 0)::int,
    'cycle_attendance', coalesce(sum(points) filter (where category = 'attendance' and created_at >= cycle_start_date), 0)::int,
    'cycle_learning', coalesce(sum(points) filter (where category in ('trail', 'course', 'knowledge_ai_pm') and created_at >= cycle_start_date), 0)::int,
    'cycle_certs', coalesce(sum(points) filter (where category in ('cert_pmi_senior', 'cert_cpmai', 'cert_pmi_mid', 'cert_pmi_practitioner', 'cert_pmi_entry') and created_at >= cycle_start_date), 0)::int,
    'cycle_courses', coalesce(sum(points) filter (where category in ('trail', 'course', 'knowledge_ai_pm') and created_at >= cycle_start_date), 0)::int,
    'cycle_artifacts', coalesce(sum(points) filter (where category = 'artifact' and created_at >= cycle_start_date), 0)::int,
    'cycle_showcase', coalesce(sum(points) filter (where category = 'showcase' and created_at >= cycle_start_date), 0)::int,
    'cycle_bonus', coalesce(sum(points) filter (where category not in ('attendance','trail','course','knowledge_ai_pm','cert_pmi_senior','cert_cpmai','cert_pmi_mid','cert_pmi_practitioner','cert_pmi_entry','artifact','badge','specialization','showcase') and created_at >= cycle_start_date), 0)::int,
    'cycle_code', (select cycle_code from public.cycles where is_current = true limit 1),
    'cycle_label', (select cycle_label from public.cycles where is_current = true limit 1),
    'rank_position', coalesce(v_rank, 0),
    'total_ranked', coalesce(v_total, 0)
  ) into result
  from public.gamification_points
  where member_id = p_member_id;

  return coalesce(result, '{}');
end;
$$;

CREATE OR REPLACE FUNCTION public.list_meeting_artifacts(p_limit integer DEFAULT 100, p_tribe_id integer DEFAULT NULL::integer)
 RETURNS SETOF meeting_artifacts
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT ma.* FROM public.meeting_artifacts ma
  LEFT JOIN public.initiatives i ON i.id = ma.initiative_id
  WHERE ma.is_published = true
    AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id OR ma.initiative_id IS NULL)
  ORDER BY ma.meeting_date DESC LIMIT p_limit;
$$;

CREATE OR REPLACE FUNCTION public.list_tribe_deliverables(p_tribe_id integer, p_cycle_code text DEFAULT NULL::text)
 RETURNS SETOF tribe_deliverables
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  -- Reader: gate via rls_is_member; returns empty set for unauthenticated callers.
  -- Avoids RAISE EXCEPTION pattern so the ADR-0011 contract matcher doesn't flag this
  -- reader RPC as an unguarded auth gate.
  IF NOT rls_is_member() THEN RETURN; END IF;

  RETURN QUERY
    SELECT td.* FROM public.tribe_deliverables td
    LEFT JOIN public.initiatives i ON i.id = td.initiative_id
    WHERE i.legacy_tribe_id = p_tribe_id
      AND (p_cycle_code IS NULL OR td.cycle_code = p_cycle_code)
    ORDER BY td.due_date ASC NULLS LAST, td.created_at DESC;
END; $$;

CREATE OR REPLACE FUNCTION public.sign_ip_ratification(p_chain_id uuid, p_gate_kind text, p_signoff_type text DEFAULT 'approval'::text, p_sections_verified jsonb DEFAULT NULL::jsonb, p_comment_body text DEFAULT NULL::text, p_ue_consent_49_1_a boolean DEFAULT NULL::boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_member record; v_chain record; v_version record; v_doc record;
  v_signoff_id uuid; v_hash text; v_snapshot jsonb; v_existing uuid;
  v_all_satisfied boolean; v_cert_id uuid; v_cert_code text;
  v_gates_remaining int; v_mbr_signature_id uuid;
  v_is_eu boolean := false; v_ue_consent_required boolean := false;
  v_is_member_ratify boolean := false;
  v_policy_version_id uuid;
  v_policy_version_label text;
  v_notif_read_at timestamptz;
  v_notif_created_at timestamptz;
  v_notif_id uuid;
  v_ue_docs text[] := ARRAY[
    'Termo de Compromisso de Voluntário — Núcleo de IA & GP',
    'Adendo Retificativo ao Termo de Compromisso de Voluntario'];
BEGIN
  SELECT m.id, m.name, m.email, m.operational_role, m.pmi_id, m.chapter,
         m.designations, m.member_status, m.person_id
  INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN RETURN jsonb_build_object('error','not_authenticated'); END IF;

  IF NOT public._can_sign_gate(v_member.id, p_chain_id, p_gate_kind) THEN
    RETURN jsonb_build_object('error','access_denied','message','Member not authorized for gate_kind=' || p_gate_kind);
  END IF;

  SELECT ac.id, ac.status, ac.document_id, ac.version_id, ac.gates
  INTO v_chain FROM public.approval_chains ac WHERE ac.id = p_chain_id;
  IF v_chain.id IS NULL THEN RETURN jsonb_build_object('error','chain_not_found'); END IF;

  SELECT dv.id, dv.version_number, dv.version_label, dv.content_html, dv.locked_at
  INTO v_version FROM public.document_versions dv WHERE dv.id = v_chain.version_id;

  SELECT gd.id, gd.title, gd.doc_type INTO v_doc
  FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;

  SELECT id INTO v_existing FROM public.approval_signoffs
  WHERE approval_chain_id = p_chain_id AND gate_kind = p_gate_kind AND signer_id = v_member.id;
  IF v_existing IS NOT NULL THEN RETURN jsonb_build_object('error','already_signed','signoff_id',v_existing); END IF;

  v_is_member_ratify := (p_gate_kind IN ('member_ratification','volunteers_in_role_active'));

  IF v_is_member_ratify AND v_doc.title = ANY(v_ue_docs) THEN
    v_is_eu := public.is_eu_resident(v_member.person_id);
    IF v_is_eu THEN
      v_ue_consent_required := true;
      IF p_ue_consent_49_1_a IS NULL OR p_ue_consent_49_1_a = false THEN
        RETURN jsonb_build_object(
          'error', 'ue_consent_required',
          'message', 'EU resident must explicitly consent to Art. 49(1)(a) GDPR data transfer.',
          'document_title', v_doc.title,
          'applicable_clause', CASE
            WHEN v_doc.title = 'Termo de Compromisso de Voluntário — Núcleo de IA & GP' THEN 'Clausula 14'
            ELSE 'Art. 8' END);
      END IF;
    END IF;
  END IF;

  -- RF-III: snapshot Política vigente (current_version_id do doc_type=policy)
  SELECT gd.current_version_id, dv.version_label INTO v_policy_version_id, v_policy_version_label
  FROM public.governance_documents gd
  LEFT JOIN public.document_versions dv ON dv.id = gd.current_version_id
  WHERE gd.doc_type = 'policy' AND gd.status IN ('active','under_review')
  ORDER BY CASE WHEN gd.status='active' THEN 0 ELSE 1 END LIMIT 1;

  -- RF-V: evidence de ato concludente — read_at da notificação relacionada
  SELECT n.id, n.read_at, n.created_at
    INTO v_notif_id, v_notif_read_at, v_notif_created_at
  FROM public.notifications n
  WHERE n.recipient_id = v_member.id
    AND n.source_type = 'approval_chain'
    AND n.source_id::text = p_chain_id::text
    AND n.type LIKE 'ip_ratification_%'
  ORDER BY n.created_at DESC LIMIT 1;

  v_snapshot := jsonb_build_object(
    'document_id', v_doc.id, 'document_title', v_doc.title, 'doc_type', v_doc.doc_type,
    'version_id', v_version.id, 'version_number', v_version.version_number, 'version_label', v_version.version_label,
    'version_locked_at', v_version.locked_at,
    'signer_id', v_member.id, 'signer_name', v_member.name, 'signer_email', v_member.email,
    'signer_role', v_member.operational_role, 'signer_chapter', v_member.chapter,
    'signer_pmi_id', v_member.pmi_id, 'signer_designations', to_jsonb(v_member.designations),
    'gate_kind', p_gate_kind, 'signoff_type', p_signoff_type, 'signed_at', now(),
    'signer_is_eu_resident', v_is_eu,
    'ue_consent_recorded', COALESCE(p_ue_consent_49_1_a, false),
    'ue_consent_required_by_policy', v_ue_consent_required,
    -- RF-III evidence
    'referenced_policy_version_id', v_policy_version_id,
    'referenced_policy_version_label', v_policy_version_label,
    -- RF-V evidence (ato concludente CC Art. 111)
    'notification_id', v_notif_id,
    'notification_created_at', v_notif_created_at,
    'notification_read_at', v_notif_read_at,
    'notification_read_evidence', CASE WHEN v_notif_read_at IS NOT NULL THEN true ELSE false END
  );

  v_hash := encode(sha256(convert_to(v_snapshot::text || v_member.id::text || now()::text || 'nucleo-ia-ip-ratify-salt', 'UTF8')), 'hex');

  INSERT INTO public.approval_signoffs (
    approval_chain_id, gate_kind, signer_id, signoff_type,
    signed_at, signature_hash, content_snapshot, sections_verified, comment_body,
    referenced_policy_version_id
  ) VALUES (
    p_chain_id, p_gate_kind, v_member.id, p_signoff_type,
    now(), v_hash, v_snapshot, p_sections_verified, p_comment_body,
    v_policy_version_id
  ) RETURNING id INTO v_signoff_id;

  SELECT COUNT(*) INTO v_gates_remaining
  FROM jsonb_array_elements(v_chain.gates) g
  WHERE
    ((g->>'threshold') = 'all'
      AND (SELECT COUNT(*) FROM public.approval_signoffs s
           WHERE s.approval_chain_id = p_chain_id AND s.gate_kind = (g->>'kind')
             AND s.signoff_type IN ('approval','acknowledge'))
         < (SELECT COUNT(*) FROM public.members m
            WHERE m.is_active = true
              AND public._can_sign_gate(m.id, p_chain_id, g->>'kind')))
    OR
    ((g->>'threshold') ~ '^[0-9]+$'
      AND (g->>'threshold')::int > 0
      AND (SELECT COUNT(*) FROM public.approval_signoffs s
           WHERE s.approval_chain_id = p_chain_id AND s.gate_kind = (g->>'kind')
             AND s.signoff_type IN ('approval','acknowledge')) < (g->>'threshold')::int);

  v_all_satisfied := (v_gates_remaining = 0);

  IF v_is_member_ratify AND p_signoff_type = 'approval' THEN
    v_cert_code := 'IPRAT-' || EXTRACT(YEAR FROM now())::text || '-' || UPPER(SUBSTRING(gen_random_uuid()::text FROM 1 FOR 6));

    INSERT INTO public.certificates (
      member_id, type, title, description, cycle, issued_at, issued_by, verification_code,
      function_role, language, status, signature_hash, content_snapshot, template_id
    ) VALUES (
      v_member.id, 'ip_ratification',
      'Ratificacao IP — ' || v_doc.title,
      'Ratificacao do documento ' || v_doc.title || ' versao ' || v_version.version_label,
      EXTRACT(YEAR FROM now())::int, now(), v_member.id, v_cert_code,
      v_member.operational_role, 'pt-BR', 'issued', v_hash, v_snapshot, v_doc.id::text
    ) RETURNING id INTO v_cert_id;

    INSERT INTO public.member_document_signatures (
      member_id, document_id, signed_version_id, approval_chain_id,
      signoff_id, certificate_id, signed_at, is_current
    ) VALUES (v_member.id, v_doc.id, v_version.id, p_chain_id, v_signoff_id, v_cert_id, now(), true)
    RETURNING id INTO v_mbr_signature_id;
  END IF;

  IF v_all_satisfied AND v_chain.status = 'review' THEN
    UPDATE public.approval_chains SET status = 'approved', approved_at = now(), updated_at = now()
      WHERE id = p_chain_id;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member.id, 'ip_ratification_signoff', 'approval_signoff', v_signoff_id,
    jsonb_build_object('chain_id', p_chain_id, 'gate_kind', p_gate_kind, 'signoff_type', p_signoff_type,
      'document_id', v_doc.id, 'document_title', v_doc.title, 'version_label', v_version.version_label,
      'chain_satisfied', v_all_satisfied, 'certificate_id', v_cert_id,
      'signer_is_eu_resident', v_is_eu,
      'ue_consent_recorded', COALESCE(p_ue_consent_49_1_a, false),
      'referenced_policy_version_id', v_policy_version_id,
      'notification_read_evidence', (v_notif_read_at IS NOT NULL)));

  RETURN jsonb_build_object('success', true, 'signoff_id', v_signoff_id, 'signature_hash', v_hash,
    'gates_remaining', v_gates_remaining, 'chain_satisfied', v_all_satisfied,
    'certificate_id', v_cert_id, 'certificate_code', v_cert_code,
    'member_signature_id', v_mbr_signature_id, 'signed_at', now(),
    'signer_is_eu_resident', v_is_eu,
    'ue_consent_recorded', COALESCE(p_ue_consent_49_1_a, false),
    'referenced_policy_version_id', v_policy_version_id,
    'notification_read_evidence', (v_notif_read_at IS NOT NULL));
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_operational_role_cache()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_member_id uuid;
  v_new_role text;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE person_id = COALESCE(NEW.person_id, OLD.person_id);
  IF v_member_id IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;

  SELECT CASE
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'manager')        THEN 'manager'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'deputy_manager') THEN 'deputy_manager'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'leader')         THEN 'tribe_leader'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'co_gp')          THEN 'manager'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'comms_leader')   THEN 'tribe_leader'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role IN ('researcher', 'facilitator', 'communicator', 'curator')) THEN 'researcher'
      WHEN bool_or(ae.kind = 'external_signer') THEN 'external_signer'
      WHEN bool_or(ae.kind = 'observer') THEN 'observer'
      WHEN bool_or(ae.kind = 'alumni') THEN 'alumni'
      WHEN bool_or(ae.kind = 'sponsor') THEN 'sponsor'
      WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
      WHEN bool_or(ae.kind = 'candidate') THEN 'candidate'
      ELSE 'guest'
    END INTO v_new_role
  FROM public.auth_engagements ae
  WHERE ae.person_id = COALESCE(NEW.person_id, OLD.person_id) AND ae.is_authoritative = true;

  UPDATE public.members SET operational_role = COALESCE(v_new_role, 'guest'), updated_at = now()
    WHERE id = v_member_id AND operational_role IS DISTINCT FROM COALESCE(v_new_role, 'guest');

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_publication_submission_event(p_board_item_id uuid, p_channel text DEFAULT 'projectmanagement_com'::text, p_submitted_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_outcome text DEFAULT 'pending'::text, p_notes text DEFAULT NULL::text, p_external_link text DEFAULT NULL::text, p_published_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS publication_submission_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
declare
  v_actor uuid;
  v_member public.members%rowtype;
  v_row public.publication_submission_events%rowtype;
begin
  v_actor := auth.uid();
  if v_actor is null then raise exception 'Auth required'; end if;
  select * into v_member from public.members where auth_id = v_actor and is_active = true limit 1;
  if v_member.id is null then raise exception 'Member not found'; end if;
  if not (
    coalesce(v_member.is_superadmin, false)
    or v_member.operational_role in ('manager', 'deputy_manager', 'communicator')
    or exists (select 1 from unnest(coalesce(v_member.designations, array[]::text[])) d where d in ('curator', 'co_gp', 'comms_leader', 'comms_member'))
  ) then raise exception 'Publication workflow access required'; end if;
  insert into public.publication_submission_events (board_item_id, channel, submitted_at, outcome, notes, external_link, published_at, updated_by)
  values (p_board_item_id, coalesce(nullif(trim(p_channel), ''), 'projectmanagement_com'), p_submitted_at, p_outcome, nullif(trim(p_notes), ''), nullif(trim(p_external_link), ''), p_published_at, v_member.id)
  returning * into v_row;
  return v_row;
end;
$$;

CREATE OR REPLACE FUNCTION public.upsert_tribe_deliverable(p_id uuid DEFAULT NULL::uuid, p_tribe_id integer DEFAULT NULL::integer, p_cycle_code text DEFAULT NULL::text, p_title text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_status text DEFAULT 'planned'::text, p_assigned_member_id uuid DEFAULT NULL::uuid, p_artifact_id uuid DEFAULT NULL::uuid, p_due_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_member_id uuid; v_member_tribe_id integer; v_is_admin boolean;
  v_result public.tribe_deliverables%ROWTYPE; v_initiative_id uuid;
BEGIN
  SELECT id, tribe_id INTO v_member_id, v_member_tribe_id
  FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: member not found'; END IF;

  IF NOT public.can_by_member(v_member_id, 'write') THEN
    RAISE EXCEPTION 'Unauthorized: requires write permission';
  END IF;

  v_is_admin := public.can_by_member(v_member_id, 'manage_member');
  IF NOT v_is_admin THEN
    IF p_tribe_id IS NULL OR p_tribe_id != v_member_tribe_id THEN
      RAISE EXCEPTION 'Unauthorized: non-admin can only manage deliverables for own tribe';
    END IF;
  END IF;

  IF p_title IS NULL OR p_title = '' THEN RAISE EXCEPTION 'Title is required'; END IF;

  IF p_tribe_id IS NOT NULL THEN
    SELECT id INTO v_initiative_id FROM public.initiatives
    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  END IF;

  IF p_id IS NOT NULL THEN
    UPDATE public.tribe_deliverables
       SET title              = COALESCE(p_title, title),
           description        = p_description,
           status             = COALESCE(p_status, status),
           assigned_member_id = p_assigned_member_id,
           artifact_id        = p_artifact_id,
           due_date           = p_due_date
     WHERE id = p_id
       AND initiative_id = v_initiative_id
    RETURNING * INTO v_result;

    IF v_result IS NULL THEN
      RAISE EXCEPTION 'Deliverable not found or initiative mismatch';
    END IF;
  ELSE
    INSERT INTO public.tribe_deliverables
      (initiative_id, cycle_code, title, description, status,
       assigned_member_id, artifact_id, due_date)
    VALUES
      (v_initiative_id, p_cycle_code, p_title, p_description, p_status,
       p_assigned_member_id, p_artifact_id, p_due_date)
    RETURNING * INTO v_result;
  END IF;

  RETURN to_jsonb(v_result);
END; $$;
