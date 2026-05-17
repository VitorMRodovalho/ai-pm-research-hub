-- Phase B drift capture — 4+3-touch bucket (40 fns)
-- Session: p176 (2026-05-17)
-- Strategy: Idempotent capture. Live body IS the canonical reference; this migration
--           writes the live body into a migration file so the Phase C body-hash audit
--           contract test (tests/contracts/rpc-migration-coverage.test.mjs) accepts it.
-- Apply via: supabase migration repair --status applied 20260681000000 (no apply_migration
--            needed since live IS canonical; running CREATE OR REPLACE on identical body
--            is a no-op).
-- Allowlist impact: 225 → 185 (40 fns removed from baseline).
-- Per p175 sediment: this is the recommended cadence — bucket-by-bucket ratchet DOWN.
-- Captured via pg_get_functiondef + canonical dollar-quote normalization
--   (AS $function$ → AS $$, except when the body itself contains $$).

-- ============================================================
-- 4-touch bucket (18 functions)
-- ============================================================

CREATE OR REPLACE FUNCTION public._can_manage_event(p_event_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller record;
  v_event record;
  v_event_tribe_id int;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN false; END IF;

  -- ADR-0042: V4 catalog source-of-truth for org-tier event management
  IF public.can_by_member(v_caller.id, 'manage_event') THEN RETURN true; END IF;

  -- Path Y: tribe-scoped management (tribe_leader / researcher own-tribe events)
  -- and event-creator self-management — preserved from V3 body.
  SELECT * INTO v_event FROM public.events WHERE id = p_event_id;
  IF NOT FOUND THEN RETURN false; END IF;

  v_event_tribe_id := public.resolve_tribe_id(v_event.initiative_id);

  IF v_caller.operational_role = 'tribe_leader' AND v_event_tribe_id = v_caller.tribe_id THEN RETURN true; END IF;
  IF v_caller.operational_role = 'researcher'   AND v_event_tribe_id = v_caller.tribe_id THEN RETURN true; END IF;
  IF v_event.created_by = v_caller.id THEN RETURN true; END IF;
  RETURN false;
END;
$$


CREATE OR REPLACE FUNCTION public.admin_reactivate_member(p_member_id uuid, p_tribe_id integer, p_role text DEFAULT 'researcher'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
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

  -- ARM #136 guard: cannot reactivate anonymized member (LGPD Art. 16 II)
  IF v_member.anonymized_at IS NOT NULL THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      v_caller.id,
      'admin_reactivate_blocked_anonymized',
      'member',
      p_member_id,
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
        v_caller.id,
        'admin_reactivate_blocked_no_pipeline',
        'member',
        p_member_id,
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
    v_caller.id,
    'member.status_transition',
    'member',
    p_member_id,
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
    -- Non-alumni: validate transition
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
$$


CREATE OR REPLACE FUNCTION public.counter_sign_certificate(p_certificate_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_chapter text;
  v_caller_person_id uuid;
  v_is_manage_member boolean;
  v_is_chapter_board boolean;
  v_cert record;
  v_contracting_chapter text;
  v_hash text;
BEGIN
  SELECT m.id, m.chapter, m.person_id
    INTO v_caller_id, v_caller_chapter, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  v_is_manage_member := public.can_by_member(v_caller_id, 'manage_member');
  v_is_chapter_board := EXISTS (
    SELECT 1 FROM public.auth_engagements ae
    WHERE ae.person_id = v_caller_person_id
      AND ae.kind = 'chapter_board'
      AND ae.status = 'active'
  );

  IF NOT v_is_manage_member AND NOT v_is_chapter_board THEN
    RETURN jsonb_build_object('error', 'not_authorized');
  END IF;

  SELECT * INTO v_cert FROM public.certificates WHERE id = p_certificate_id;
  IF v_cert IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
  IF v_cert.counter_signed_by IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'already_counter_signed');
  END IF;

  v_contracting_chapter := COALESCE(
    v_cert.content_snapshot->>'contracting_chapter',
    (SELECT m.chapter FROM public.members m WHERE m.id = v_cert.member_id)
  );

  IF v_is_chapter_board AND NOT v_is_manage_member THEN
    IF v_contracting_chapter IS DISTINCT FROM v_caller_chapter THEN
      RETURN jsonb_build_object('error', 'not_authorized_different_chapter');
    END IF;
  END IF;

  v_hash := encode(sha256(convert_to(
    COALESCE(v_cert.signature_hash,'') || v_caller_id::text || now()::text || 'nucleo-ia-countersign-salt', 'UTF8'
  )), 'hex');

  UPDATE public.certificates SET counter_signed_by = v_caller_id, counter_signed_at = now() WHERE id = p_certificate_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'certificate_counter_signed', 'certificate', p_certificate_id,
    jsonb_build_object('verification_code', v_cert.verification_code, 'type', v_cert.type, 'contracting_chapter', v_contracting_chapter));

  INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
  VALUES (v_cert.member_id, 'certificate_ready',
    'Seu ' || v_cert.title || ' esta pronto!',
    'O documento foi contra-assinado e esta disponivel. Codigo: ' || v_cert.verification_code,
    '/certificates', 'certificate', p_certificate_id,
    public._delivery_mode_for('certificate_ready'));

  RETURN jsonb_build_object('success', true, 'counter_signature_hash', v_hash, 'counter_signed_at', now());
END;
$$


CREATE OR REPLACE FUNCTION public.exec_cross_tribe_comparison(p_cycle text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_cycle_start date := '2026-03-01';
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  -- ADR-0042: V4 catalog (manage_platform writes; view_chapter_dashboards reads)
  IF NOT (public.can_by_member(v_caller_id, 'manage_platform')
          OR public.can_by_member(v_caller_id, 'view_chapter_dashboards')) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform or view_chapter_dashboards permission';
  END IF;

  SELECT jsonb_build_object(
    'tribes', (
      SELECT jsonb_agg(jsonb_build_object(
        'tribe_id', t.id,
        'tribe_name', t.name,
        'quadrant', t.quadrant_name,
        'leader', (SELECT name FROM members WHERE id = t.leader_member_id),
        'member_count', (
          SELECT COUNT(*) FROM public.members m
          WHERE m.is_active
            AND EXISTS (
              SELECT 1 FROM public.engagements e
              JOIN public.initiatives i ON i.id = e.initiative_id
              WHERE e.person_id = m.person_id
                AND e.kind = 'volunteer' AND e.status = 'active'
                AND i.kind = 'research_tribe' AND i.legacy_tribe_id = t.id
            )
        ),
        'members_inactive_30d', (
          SELECT COUNT(*) FROM public.members m
          WHERE m.is_active
            AND EXISTS (
              SELECT 1 FROM public.engagements e
              JOIN public.initiatives i ON i.id = e.initiative_id
              WHERE e.person_id = m.person_id
                AND e.kind = 'volunteer' AND e.status = 'active'
                AND i.kind = 'research_tribe' AND i.legacy_tribe_id = t.id
            )
            AND m.id NOT IN (
              SELECT DISTINCT a.member_id FROM public.attendance a
              JOIN public.events e2 ON e2.id = a.event_id
              WHERE e2.date >= (current_date - 30) AND e2.date <= CURRENT_DATE
            )
        ),
        'total_cards', (
          SELECT COUNT(*) FROM board_items bi
          JOIN project_boards pb ON pb.id = bi.board_id
          JOIN initiatives ti ON ti.id = pb.initiative_id
          WHERE ti.legacy_tribe_id = t.id
        ),
        'cards_completed', (
          SELECT COUNT(*) FROM board_items bi
          JOIN project_boards pb ON pb.id = bi.board_id
          JOIN initiatives ti ON ti.id = pb.initiative_id
          WHERE ti.legacy_tribe_id = t.id AND bi.status IN ('done','approved','published')
        ),
        'articles_submitted', (
          SELECT COUNT(*) FROM board_lifecycle_events ble
          JOIN board_items bi ON bi.id = ble.item_id
          JOIN project_boards pb ON pb.id = bi.board_id
          JOIN initiatives ti ON ti.id = pb.initiative_id
          WHERE ti.legacy_tribe_id = t.id AND ble.action = 'submission'
        ),
        'attendance_rate', (
          SELECT COALESCE(
            ROUND(
              COUNT(*) FILTER (WHERE EXISTS (
                SELECT 1 FROM attendance a2
                WHERE a2.event_id = e.id
                  AND a2.member_id IN (
                    SELECT m2.id FROM public.members m2
                    WHERE m2.is_active
                      AND EXISTS (
                        SELECT 1 FROM public.engagements e3
                        JOIN public.initiatives i3 ON i3.id = e3.initiative_id
                        WHERE e3.person_id = m2.person_id
                          AND e3.kind = 'volunteer' AND e3.status = 'active'
                          AND i3.kind = 'research_tribe' AND i3.legacy_tribe_id = t.id
                      )
                  )
              ))::numeric
              / NULLIF(
                (
                  SELECT COUNT(*)::numeric FROM public.members m4
                  WHERE m4.is_active
                    AND EXISTS (
                      SELECT 1 FROM public.engagements e4
                      JOIN public.initiatives i4 ON i4.id = e4.initiative_id
                      WHERE e4.person_id = m4.person_id
                        AND e4.kind = 'volunteer' AND e4.status = 'active'
                        AND i4.kind = 'research_tribe' AND i4.legacy_tribe_id = t.id
                    )
                ) * COUNT(DISTINCT e.id), 0)
            , 2), 0)
          FROM events e
          LEFT JOIN initiatives i ON i.id = e.initiative_id
          WHERE (i.legacy_tribe_id = t.id OR e.initiative_id IS NULL) AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE
        ),
        'total_hours', (
          SELECT COALESCE(SUM(e.duration_minutes / 60.0), 0)
          FROM attendance a JOIN events e ON e.id = a.event_id
          WHERE a.member_id IN (
            SELECT m5.id FROM public.members m5
            WHERE m5.is_active
              AND EXISTS (
                SELECT 1 FROM public.engagements e5
                JOIN public.initiatives i5 ON i5.id = e5.initiative_id
                WHERE e5.person_id = m5.person_id
                  AND e5.kind = 'volunteer' AND e5.status = 'active'
                  AND i5.kind = 'research_tribe' AND i5.legacy_tribe_id = t.id
              )
          )
          AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE
        ),
        'meetings_count', (
          SELECT COUNT(*) FROM events e
          JOIN initiatives i ON i.id = e.initiative_id
          WHERE i.legacy_tribe_id = t.id AND e.date >= v_cycle_start AND e.date <= CURRENT_DATE
        ),
        'total_xp', (
          SELECT COALESCE(SUM(gp.points), 0) FROM gamification_points gp
          WHERE gp.member_id IN (
            SELECT m6.id FROM public.members m6
            WHERE m6.is_active
              AND EXISTS (
                SELECT 1 FROM public.engagements e6
                JOIN public.initiatives i6 ON i6.id = e6.initiative_id
                WHERE e6.person_id = m6.person_id
                  AND e6.kind = 'volunteer' AND e6.status = 'active'
                  AND i6.kind = 'research_tribe' AND i6.legacy_tribe_id = t.id
              )
          )
        ),
        'avg_xp', (
          SELECT COALESCE(ROUND(AVG(sub.total)::numeric, 1), 0)
          FROM (
            SELECT SUM(gp.points) AS total
            FROM gamification_points gp
            WHERE gp.member_id IN (
              SELECT m7.id FROM public.members m7
              WHERE m7.is_active
                AND EXISTS (
                  SELECT 1 FROM public.engagements e7
                  JOIN public.initiatives i7 ON i7.id = e7.initiative_id
                  WHERE e7.person_id = m7.person_id
                    AND e7.kind = 'volunteer' AND e7.status = 'active'
                    AND i7.kind = 'research_tribe' AND i7.legacy_tribe_id = t.id
                )
            )
            GROUP BY gp.member_id
          ) sub
        ),
        'last_meeting_date', (
          SELECT MAX(e.date) FROM events e
          JOIN initiatives i ON i.id = e.initiative_id
          WHERE i.legacy_tribe_id = t.id AND e.date <= CURRENT_DATE
        ),
        'days_since_last_meeting', (
          SELECT EXTRACT(DAY FROM now() - MAX(e.date)::timestamp)::int
          FROM events e
          JOIN initiatives i ON i.id = e.initiative_id
          WHERE i.legacy_tribe_id = t.id AND e.date <= CURRENT_DATE
        )
      ) ORDER BY t.id)
      FROM tribes t
    ),
    'generated_at', now()
  ) INTO v_result;

  RETURN v_result;
END;
$$


CREATE OR REPLACE FUNCTION public.exec_cycle_report(p_cycle_code text DEFAULT 'cycle3-2026'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb; v_kpis jsonb; v_members jsonb; v_tribes jsonb;
  v_production jsonb; v_engagement jsonb; v_curation jsonb; v_cycle jsonb; v_attendance jsonb;
  v_total_members int; v_active_members int;
  v_start date := '2026-01-01';
  v_end date := '2026-06-30';
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  -- ADR-0042: V4 catalog (manage_platform writes; view_chapter_dashboards reads)
  IF NOT (public.can_by_member(v_caller_id, 'manage_platform')
          OR public.can_by_member(v_caller_id, 'view_chapter_dashboards')) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform or view_chapter_dashboards permission';
  END IF;

  SELECT jsonb_build_object(
    'code', COALESCE(c.cycle_code, p_cycle_code),
    'name', COALESCE(c.cycle_label, 'Ciclo 3 — 2026/1'),
    'start_date', c.cycle_start, 'end_date', c.cycle_end
  ) INTO v_cycle FROM public.cycles c WHERE c.cycle_code = p_cycle_code OR c.is_current = true LIMIT 1;
  IF v_cycle IS NULL THEN v_cycle := jsonb_build_object('code', p_cycle_code, 'name', 'Ciclo 3', 'start_date', v_start, 'end_date', v_end); END IF;

  v_kpis := public.get_kpi_dashboard(v_start, v_end);

  SELECT COUNT(*) INTO v_total_members FROM public.members;
  SELECT COUNT(*) INTO v_active_members FROM public.members WHERE current_cycle_active = true;

  SELECT jsonb_build_object(
    'total', v_total_members, 'active', v_active_members,
    'by_chapter', COALESCE((SELECT jsonb_agg(jsonb_build_object('chapter', chapter, 'count', cnt) ORDER BY cnt DESC) FROM (SELECT chapter, count(*) AS cnt FROM public.members WHERE current_cycle_active = true AND chapter IS NOT NULL GROUP BY chapter) sub), '[]'::jsonb),
    'by_role', COALESCE((SELECT jsonb_agg(jsonb_build_object('role', operational_role, 'count', cnt) ORDER BY cnt DESC) FROM (SELECT COALESCE(operational_role, 'none') AS operational_role, count(*) AS cnt FROM public.members WHERE current_cycle_active = true GROUP BY operational_role) sub), '[]'::jsonb),
    'retention_rate', ROUND(COALESCE((SELECT COUNT(*) FILTER (WHERE COALESCE(array_length(cycles, 1), 0) > 1)::numeric * 100 / NULLIF(COUNT(*), 0) FROM public.members WHERE current_cycle_active = true AND cycles IS NOT NULL), 0)),
    'new_this_cycle', (SELECT COUNT(*) FROM public.members WHERE current_cycle_active = true AND (cycles IS NULL OR COALESCE(array_length(cycles, 1), 0) <= 1))
  ) INTO v_members;

  SELECT COALESCE(jsonb_agg(tribe_data ORDER BY tribe_data->>'name'), '[]'::jsonb) INTO v_tribes
  FROM (SELECT jsonb_build_object('id', t.id, 'name', t.name,
    'leader', COALESCE((SELECT m.name FROM public.members m WHERE m.tribe_id = t.id AND m.operational_role = 'tribe_leader' LIMIT 1), '—'),
    'member_count', (SELECT COUNT(*) FROM public.members m WHERE m.tribe_id = t.id AND m.current_cycle_active = true),
    'board_items_total', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = t.id AND bi.status != 'archived'), 0),
    'board_items_completed', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = t.id AND bi.status = 'done'), 0),
    'completion_pct', COALESCE((SELECT ROUND(COUNT(*) FILTER (WHERE bi.status = 'done')::numeric * 100 / NULLIF(COUNT(*), 0)) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = t.id AND bi.status != 'archived'), 0),
    'articles_produced', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id JOIN public.initiatives i ON i.id = pb.initiative_id WHERE i.legacy_tribe_id = t.id AND bi.status IN ('done', 'published') AND (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%')), 0)
  ) AS tribe_data FROM public.tribes t WHERE t.is_active = true) sub;

  SELECT jsonb_build_object(
    'articles_submitted', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%')), 0),
    'articles_published', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%') AND bi.status IN ('done', 'published')), 0),
    'articles_in_review', COALESCE((SELECT COUNT(*) FROM public.board_items bi JOIN public.project_boards pb ON pb.id = bi.board_id WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%') AND bi.status IN ('review', 'in_progress')), 0),
    'webinars_completed', (SELECT COUNT(*) FROM public.events WHERE type = 'webinar' AND date <= now()),
    'webinars_planned', (SELECT COUNT(*) FROM public.events WHERE type = 'webinar' AND date > now())
  ) INTO v_production;

  SELECT jsonb_build_object(
    'total_events', (SELECT COUNT(*) FROM public.events WHERE date BETWEEN v_start AND v_end),
    'total_attendance_hours', COALESCE((SELECT round(sum(COALESCE(e.duration_actual, e.duration_minutes, 60)::numeric * (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present)) / 60) FROM events e WHERE e.date BETWEEN v_start AND v_end), 0),
    'avg_attendance_per_event', COALESCE((SELECT ROUND(AVG(ac)) FROM (SELECT COUNT(*) AS ac FROM public.attendance a JOIN events e ON e.id = a.event_id WHERE a.present = true AND e.date BETWEEN v_start AND v_end GROUP BY a.event_id) sub), 0),
    'total_attendance_records', (SELECT COUNT(*) FROM public.attendance WHERE present = true),
    'certification_completion_rate', ROUND(COALESCE((SELECT COUNT(*) FILTER (WHERE cpmai_certified = true)::numeric * 100 / NULLIF(COUNT(*), 0) FROM public.members WHERE current_cycle_active = true), 0))
  ) INTO v_engagement;

  SELECT jsonb_build_object(
    'items_submitted', COALESCE((SELECT COUNT(*) FROM public.curation_review_log), 0),
    'items_approved', COALESCE((SELECT COUNT(*) FROM public.curation_review_log WHERE decision = 'approved'), 0),
    'items_in_review', COALESCE((SELECT COUNT(*) FROM public.board_items WHERE status = 'review'), 0),
    'avg_review_days', COALESCE((SELECT ROUND(AVG(EXTRACT(EPOCH FROM (completed_at - created_at)) / 86400)::numeric, 1) FROM public.curation_review_log), 0),
    'sla_compliance_rate', COALESCE((SELECT ROUND(COUNT(*) FILTER (WHERE completed_at <= due_date)::numeric * 100 / NULLIF(COUNT(*) FILTER (WHERE due_date IS NOT NULL), 0)) FROM public.curation_review_log), 0)
  ) INTO v_curation;

  SELECT COALESCE(jsonb_agg(att_row ORDER BY att_row->>'tribe_name'), '[]'::jsonb) INTO v_attendance
  FROM (SELECT jsonb_build_object('tribe_id', t.id, 'tribe_name', t.name,
    'members_count', (SELECT count(*) FROM members m WHERE m.tribe_id = t.id AND m.is_active AND m.operational_role NOT IN ('sponsor','chapter_liaison','guest','none')),
    'avg_geral_pct', COALESCE((SELECT round(avg(sub.geral_pct), 1) FROM get_attendance_summary(v_start, v_end, t.id) sub), 0),
    'avg_tribe_pct', COALESCE((SELECT round(avg(sub.tribe_pct), 1) FROM get_attendance_summary(v_start, v_end, t.id) sub), 0),
    'avg_combined_pct', COALESCE((SELECT round(avg(sub.combined_pct), 1) FROM get_attendance_summary(v_start, v_end, t.id) sub), 0),
    'at_risk_count', COALESCE((SELECT count(*) FROM get_attendance_summary(v_start, v_end, t.id) sub WHERE sub.combined_pct < 50 AND sub.combined_pct > 0), 0)
  ) AS att_row FROM tribes t WHERE t.is_active = true) sub;

  v_result := jsonb_build_object('cycle', v_cycle, 'kpis', v_kpis, 'members', v_members, 'tribes', v_tribes, 'production', v_production, 'engagement', v_engagement, 'curation', v_curation, 'attendance', v_attendance);
  RETURN v_result;
END; $$


CREATE OR REPLACE FUNCTION public.fork_idea_to_channel(p_idea_id uuid, p_channel text, p_payload_hint jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_idea public.publication_ideas%ROWTYPE;
  v_is_committee boolean;
  v_existing_blog_id uuid;
  v_new_blog_id uuid;
  v_blog_slug text;
  v_existing_template_id uuid;
  v_new_template_id uuid;
  v_template_slug text;
  v_existing_slug_count int;
  v_idea_title text;
  v_idea_summary text;
  v_blog_created boolean := false;
  v_template_created boolean := false;
  v_brief_recorded boolean := false;
  v_brief_jsonb jsonb;
  v_normalized_channel text;
  v_social_channels text[] := ARRAY['social','linkedin','instagram','twitter','youtube','tiktok','facebook','medium','dev_to']::text[];
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF p_channel IS NULL OR length(trim(p_channel)) = 0 THEN
    RAISE EXCEPTION 'channel is required';
  END IF;

  v_normalized_channel := lower(trim(p_channel));

  SELECT * INTO v_idea FROM public.publication_ideas WHERE id = p_idea_id;
  IF v_idea.id IS NULL THEN RAISE EXCEPTION 'Idea not found: %', p_idea_id; END IF;

  v_is_committee := public.can_by_member(v_caller_id, 'manage_event')
                 OR public.can_by_member(v_caller_id, 'manage_member');
  IF v_caller_id <> v_idea.proposer_member_id AND NOT v_is_committee THEN
    RAISE EXCEPTION 'Unauthorized: only proposer or comitê can fork to channel';
  END IF;

  IF v_idea.stage IN ('archived') THEN
    RAISE EXCEPTION 'Cannot fork from archived idea';
  END IF;

  IF NOT (v_idea.proposed_channels @> ARRAY[p_channel]::text[]) THEN
    UPDATE public.publication_ideas
       SET proposed_channels = array_append(COALESCE(proposed_channels, '{}'::text[]), p_channel)
     WHERE id = p_idea_id;
  END IF;

  v_idea_title := COALESCE(v_idea.title, 'untitled');
  v_idea_summary := COALESCE(v_idea.summary, '');

  IF v_normalized_channel IN ('blog','blog_post') AND v_idea.stage IN ('approved','published') THEN
    SELECT id INTO v_existing_blog_id
    FROM public.blog_posts
    WHERE source_idea_id = p_idea_id
    LIMIT 1;

    IF v_existing_blog_id IS NULL THEN
      v_blog_slug := lower(regexp_replace(
        regexp_replace(
          translate(v_idea_title,
            'áàâãäåçéèêëíìîïñóòôõöúùûüýÿÁÀÂÃÄÅÇÉÈÊËÍÌÎÏÑÓÒÔÕÖÚÙÛÜÝŸ',
            'aaaaaaceeeeiiiinooooouuuuyyAAAAAACEEEEIIIINOOOOOUUUUYY'
          ),
          '[^a-zA-Z0-9\s-]+', '', 'g'
        ),
        '\s+', '-', 'g'
      ));
      v_blog_slug := substring(v_blog_slug from 1 for 80);
      v_blog_slug := trim(both '-' from v_blog_slug);
      IF length(v_blog_slug) = 0 THEN v_blog_slug := 'untitled-' || substring(p_idea_id::text from 1 for 8); END IF;

      SELECT count(*) INTO v_existing_slug_count FROM public.blog_posts WHERE slug = v_blog_slug;
      IF v_existing_slug_count > 0 THEN
        v_blog_slug := v_blog_slug || '-' || substring(p_idea_id::text from 1 for 6);
      END IF;

      INSERT INTO public.blog_posts (
        slug, title, excerpt, body_html,
        author_member_id, category, status, tags,
        series_id, series_position, source_idea_id, organization_id
      )
      VALUES (
        v_blog_slug,
        jsonb_build_object('pt-BR', v_idea_title),
        jsonb_build_object('pt-BR', v_idea_summary),
        jsonb_build_object('pt-BR', '<p>' || COALESCE(NULLIF(v_idea_summary, ''), '<i>Rascunho criado a partir de publication_idea ' || p_idea_id || '. Edite o body_html.</i>') || '</p>'),
        v_idea.proposer_member_id,
        'deep-dive',
        'draft',
        COALESCE(v_idea.themes, '{}'::text[]),
        v_idea.series_id,
        v_idea.series_position,
        p_idea_id,
        v_idea.organization_id
      )
      RETURNING id INTO v_new_blog_id;

      v_blog_created := true;
      v_existing_blog_id := v_new_blog_id;
    END IF;
  END IF;

  IF v_normalized_channel IN ('newsletter','email') AND v_idea.stage IN ('approved','published') THEN
    SELECT id INTO v_existing_template_id
    FROM public.campaign_templates
    WHERE source_idea_id = p_idea_id
    LIMIT 1;

    IF v_existing_template_id IS NULL THEN
      v_template_slug := lower(regexp_replace(
        regexp_replace(
          translate(v_idea_title,
            'áàâãäåçéèêëíìîïñóòôõöúùûüýÿÁÀÂÃÄÅÇÉÈÊËÍÌÎÏÑÓÒÔÕÖÚÙÛÜÝŸ',
            'aaaaaaceeeeiiiinooooouuuuyyAAAAAACEEEEIIIINOOOOOUUUUYY'
          ),
          '[^a-zA-Z0-9\s_-]+', '', 'g'
        ),
        '[\s-]+', '_', 'g'
      ));
      v_template_slug := substring(v_template_slug from 1 for 80);
      v_template_slug := trim(both '_' from v_template_slug);
      IF length(v_template_slug) = 0 THEN v_template_slug := 'idea_' || substring(p_idea_id::text from 1 for 8); END IF;
      v_template_slug := 'idea_' || v_template_slug;

      SELECT count(*) INTO v_existing_slug_count FROM public.campaign_templates WHERE slug = v_template_slug;
      IF v_existing_slug_count > 0 THEN
        v_template_slug := v_template_slug || '_' || substring(p_idea_id::text from 1 for 6);
      END IF;

      INSERT INTO public.campaign_templates (
        slug, name, subject, body_html, body_text, category,
        target_audience, variables, source_idea_id, created_by
      )
      VALUES (
        v_template_slug,
        substring(v_idea_title from 1 for 200),
        jsonb_build_object('pt-BR', v_idea_title),
        jsonb_build_object('pt-BR', '<p>' || COALESCE(NULLIF(v_idea_summary, ''), '<i>Newsletter draft scaffolded from publication_idea ' || p_idea_id || '. Edit body_html before sending.</i>') || '</p>'),
        jsonb_build_object('pt-BR', COALESCE(NULLIF(v_idea_summary, ''), 'Newsletter draft from idea ' || p_idea_id)),
        'newsletter',
        '{"all": false, "roles": [], "chapters": [], "designations": []}'::jsonb,
        '["member.name", "member.tribe", "member.chapter", "platform.url", "unsubscribe_url"]'::jsonb,
        p_idea_id,
        v_caller_id
      )
      RETURNING id INTO v_new_template_id;

      v_template_created := true;
      v_existing_template_id := v_new_template_id;
    END IF;
  END IF;

  -- W3.3 Opção B: social channels record brief in idea.metadata.briefs[channel]
  -- Use || merge to avoid jsonb_set intermediate-path bug
  IF v_normalized_channel = ANY(v_social_channels) AND v_idea.stage IN ('approved','published') THEN
    v_brief_jsonb := jsonb_build_object(
      'channel', v_normalized_channel,
      'scaffolded_at', now(),
      'scaffolded_by', v_caller_id,
      'proposed_caption_pt', COALESCE(NULLIF(v_idea_summary, ''), v_idea_title),
      'hashtags', COALESCE(v_idea.themes, '{}'::text[]),
      'payload_hint', p_payload_hint,
      'note', 'V1 brief stored in metadata.briefs. V2 (Opção A) pode migrar para tabela comms_briefs dedicada.'
    );

    UPDATE public.publication_ideas
       SET metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
         'briefs',
         COALESCE(metadata->'briefs', '{}'::jsonb) || jsonb_build_object(v_normalized_channel, v_brief_jsonb)
       )
     WHERE id = p_idea_id;

    v_brief_recorded := true;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller_id, 'fork_idea_to_channel', 'publication_idea', p_idea_id,
    jsonb_build_object(
      'channel', p_channel,
      'payload_hint', p_payload_hint,
      'stage_at_fork', v_idea.stage,
      'blog_post_created', v_blog_created,
      'blog_post_id', v_existing_blog_id,
      'template_created', v_template_created,
      'campaign_template_id', v_existing_template_id,
      'brief_recorded', v_brief_recorded
    ),
    jsonb_build_object('source','mcp','issue','#94','wave','W3.3-OpcaoB')
  );

  RETURN jsonb_build_object(
    'success', true,
    'idea_id', p_idea_id,
    'channel', p_channel,
    'blog_post_id', v_existing_blog_id,
    'blog_post_created', v_blog_created,
    'campaign_template_id', v_existing_template_id,
    'template_created', v_template_created,
    'brief_recorded', v_brief_recorded,
    'note', CASE
      WHEN v_blog_created THEN 'Auto-scaffold: blog_posts draft created. Edit body_html via existing tools.'
      WHEN v_template_created THEN 'Auto-scaffold: campaign_templates draft created (newsletter). Edit subject/body_html before sending.'
      WHEN v_brief_recorded THEN 'Brief social registrado em idea.metadata.briefs.' || v_normalized_channel || '. V2 (Opção A) pode migrar para tabela dedicada.'
      WHEN v_existing_blog_id IS NOT NULL THEN 'Existing blog_posts row found (idempotent return).'
      WHEN v_existing_template_id IS NOT NULL THEN 'Existing campaign_template row found (idempotent return).'
      ELSE 'Fork intent recorded para canal não-orchestrated.'
    END
  );
END; $$


CREATE OR REPLACE FUNCTION public.get_adoption_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  -- ADR-0042: V4 catalog (manage_platform writes; view_chapter_dashboards reads)
  IF NOT (public.can_by_member(v_caller_id, 'manage_platform')
          OR public.can_by_member(v_caller_id, 'view_chapter_dashboards')) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform or view_chapter_dashboards permission';
  END IF;

  WITH tier_stats AS (
    SELECT operational_role, count(*)::integer as total,
      count(*) FILTER (WHERE last_seen_at > now() - interval '7 days')::integer as seen_7d,
      count(*) FILTER (WHERE last_seen_at > now() - interval '30 days')::integer as seen_30d,
      count(*) FILTER (WHERE last_seen_at IS NULL)::integer as never,
      ROUND(AVG(total_sessions)::numeric, 1) as avg_sessions
    FROM members WHERE is_active = true GROUP BY operational_role
  ),
  tribe_stats AS (
    SELECT t.id as tribe_id, t.name as tribe_name,
      count(m.id)::integer as total,
      count(m.id) FILTER (WHERE m.last_seen_at > now() - interval '7 days')::integer as seen_7d,
      count(m.id) FILTER (WHERE m.last_seen_at > now() - interval '30 days')::integer as seen_30d,
      count(m.id) FILTER (WHERE m.last_seen_at IS NULL)::integer as never,
      ROUND(AVG(m.total_sessions)::numeric, 1) as avg_sessions
    FROM tribes t
    LEFT JOIN members m ON public.get_member_tribe(m.id) = t.id AND m.is_active = true
    WHERE t.is_active = true GROUP BY t.id, t.name
  ),
  daily AS (
    SELECT session_date, count(DISTINCT member_id)::integer as cnt, sum(pages_visited)::integer as pvs
    FROM member_activity_sessions WHERE session_date > CURRENT_DATE - 30 GROUP BY session_date
  )
  SELECT jsonb_build_object(
    'generated_at', now(),
    'summary', jsonb_build_object(
      'total_active', (SELECT count(*) FROM members WHERE is_active = true AND current_cycle_active = true),
      'total_registered', (SELECT count(*) FROM members),
      'ever_logged_in', (SELECT count(*) FROM members WHERE is_active = true AND auth_id IS NOT NULL),
      'seen_last_7d', (SELECT count(*) FROM members WHERE is_active = true AND last_seen_at > now() - interval '7 days'),
      'seen_last_30d', (SELECT count(*) FROM members WHERE is_active = true AND last_seen_at > now() - interval '30 days'),
      'never_seen', (SELECT count(*) FROM members WHERE is_active = true AND last_seen_at IS NULL),
      'adoption_pct_7d', (SELECT ROUND(count(*) FILTER (WHERE last_seen_at > now() - interval '7 days')::numeric / NULLIF(count(*) FILTER (WHERE is_active = true), 0) * 100, 1) FROM members),
      'adoption_pct_30d', (SELECT ROUND(count(*) FILTER (WHERE last_seen_at > now() - interval '30 days')::numeric / NULLIF(count(*) FILTER (WHERE is_active = true), 0) * 100, 1) FROM members),
      'avg_sessions_per_member', (SELECT ROUND(AVG(total_sessions)::numeric, 1) FROM members WHERE is_active = true AND total_sessions > 0)
    ),
    'lifecycle', jsonb_build_object(
      'total_ever', (SELECT count(*) FROM members),
      'active_c3', (SELECT count(*) FROM members WHERE is_active AND current_cycle_active),
      'alumni', (SELECT count(*) FROM members WHERE member_status = 'alumni' OR (NOT is_active AND operational_role IN ('alumni','observer','guest'))),
      'observers_active', (SELECT count(*) FROM members WHERE is_active AND operational_role = 'observer'),
      'founders_total', (SELECT count(*) FROM members WHERE 'founder' = ANY(designations)),
      'founders_active', (SELECT count(*) FROM members WHERE 'founder' = ANY(designations) AND is_active AND current_cycle_active),
      'founders_with_auth', (SELECT count(*) FROM members WHERE 'founder' = ANY(designations) AND auth_id IS NOT NULL),
      'sponsors_total', (SELECT count(*) FROM members WHERE operational_role = 'sponsor' AND is_active),
      'sponsors_with_auth', (SELECT count(*) FROM members WHERE operational_role = 'sponsor' AND is_active AND auth_id IS NOT NULL),
      'liaisons_total', (SELECT count(*) FROM members WHERE operational_role = 'chapter_liaison' AND is_active),
      'liaisons_with_auth', (SELECT count(*) FROM members WHERE operational_role = 'chapter_liaison' AND is_active AND auth_id IS NOT NULL),
      'retention_c2_c3', (SELECT ROUND(
        count(DISTINCT mh3.member_id)::numeric * 100 / NULLIF(count(DISTINCT mh2.member_id), 0), 1)
        FROM member_cycle_history mh2
        LEFT JOIN member_cycle_history mh3 ON mh3.member_id = mh2.member_id AND mh3.cycle_code = 'cycle_3'
        WHERE mh2.cycle_code = 'cycle_2')
    ),
    'by_tier', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'tier', ts.operational_role, 'total', ts.total, 'seen_7d', ts.seen_7d,
      'seen_30d', ts.seen_30d, 'never', ts.never, 'avg_sessions', ts.avg_sessions
    )), '[]'::jsonb) FROM tier_stats ts),
    'by_tribe', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'tribe_id', ts.tribe_id, 'tribe_name', ts.tribe_name, 'total', ts.total,
      'seen_7d', ts.seen_7d, 'seen_30d', ts.seen_30d, 'never', ts.never,
      'avg_sessions', ts.avg_sessions
    ) ORDER BY ts.tribe_id), '[]'::jsonb) FROM tribe_stats ts),
    'daily_activity', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'date', d.dt::text, 'unique_members', COALESCE(dy.cnt, 0),
      'total_pageviews', COALESCE(dy.pvs, 0)
    ) ORDER BY d.dt), '[]'::jsonb)
    FROM generate_series(CURRENT_DATE - 30, CURRENT_DATE, '1 day') d(dt)
    LEFT JOIN daily dy ON dy.session_date = d.dt),
    'members', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', m.id, 'name', m.name, 'tier', m.operational_role,
      'designations', m.designations,
      'tribe_id', public.get_member_tribe(m.id), 'tribe_name', t.name,
      'has_auth', m.auth_id IS NOT NULL, 'last_seen', m.last_seen_at,
      'total_sessions', m.total_sessions, 'last_pages', m.last_active_pages,
      'is_founder', 'founder' = ANY(m.designations),
      'status', CASE
        WHEN m.last_seen_at IS NULL THEN 'never'
        WHEN m.last_seen_at > now() - interval '7 days' THEN 'active'
        WHEN m.last_seen_at > now() - interval '30 days' THEN 'inactive'
        ELSE 'dormant' END
    ) ORDER BY m.last_seen_at DESC NULLS LAST), '[]'::jsonb)
    FROM members m LEFT JOIN tribes t ON t.id = public.get_member_tribe(m.id)
    WHERE m.is_active = true),
    'mcp_usage', (SELECT get_mcp_adoption_stats()),
    'auth_providers', (SELECT get_auth_provider_stats()),
    'designation_counts', (
      SELECT COALESCE(jsonb_object_agg(d, cnt), '{}'::jsonb) FROM (
        SELECT unnest(designations) as d, count(*) as cnt
        FROM members WHERE is_active = true AND designations != '{}'
        GROUP BY d
      ) x
    )
  ) INTO v_result;
  RETURN v_result;
END;
$$


CREATE OR REPLACE FUNCTION public.get_attendance_panel(p_cycle_start date DEFAULT '2026-01-01'::date, p_cycle_end date DEFAULT '2026-06-30'::date)
 RETURNS TABLE(member_id uuid, member_name text, tribe_name text, tribe_id integer, operational_role text, general_mandatory integer, general_attended integer, general_pct numeric, tribe_mandatory integer, tribe_attended integer, tribe_pct numeric, combined_pct numeric, last_attendance date, dropout_risk boolean, typology text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  RETURN QUERY
  WITH general_events AS (
    SELECT DISTINCT e.id as event_id, e.date::date as event_date
    FROM public.events e JOIN public.event_tag_assignments eta ON eta.event_id = e.id
    JOIN public.tags t ON t.id = eta.tag_id AND t.name = 'general_meeting'
    WHERE e.date::date BETWEEN p_cycle_start AND LEAST(p_cycle_end, CURRENT_DATE)
      AND (e.status IS NULL OR e.status != 'cancelled')
  ),
  tribe_events AS (
    SELECT DISTINCT e.id as event_id, e.date::date as event_date
    FROM public.events e JOIN public.event_tag_assignments eta ON eta.event_id = e.id
    JOIN public.tags t ON t.id = eta.tag_id AND t.name = 'tribe_meeting'
    WHERE e.date::date BETWEEN p_cycle_start AND LEAST(p_cycle_end, CURRENT_DATE)
      AND (e.status IS NULL OR e.status != 'cancelled')
  ),
  active AS (
    SELECT m.id, m.name as m_name, tr.name as t_name, m.tribe_id as t_id,
           m.operational_role as op_role, m.created_at::date as member_start,
           (m.designations IS NOT NULL AND m.designations @> ARRAY['curator']::text[]) AS is_curator
    FROM public.members m LEFT JOIN public.tribes tr ON tr.id = m.tribe_id
    WHERE m.is_active = true
  ),
  gscores AS (
    SELECT a.id as mid,
      count(*) FILTER (WHERE ge.event_date >= a.member_start AND public.is_event_mandatory_for_member(ge.event_id, a.id)) as mand,
      count(*) FILTER (WHERE ge.event_date >= a.member_start AND att.id IS NOT NULL AND public.is_event_mandatory_for_member(ge.event_id, a.id)) as att
    FROM active a CROSS JOIN general_events ge
    LEFT JOIN public.attendance att ON att.event_id = ge.event_id AND att.member_id = a.id AND att.present = true
    GROUP BY a.id
  ),
  tscores AS (
    SELECT a.id as mid,
      count(*) FILTER (WHERE te.event_date >= a.member_start AND public.is_event_mandatory_for_member(te.event_id, a.id)) as mand,
      count(*) FILTER (WHERE te.event_date >= a.member_start AND att.id IS NOT NULL AND public.is_event_mandatory_for_member(te.event_id, a.id)) as att
    FROM active a CROSS JOIN tribe_events te
    LEFT JOIN public.attendance att ON att.event_id = te.event_id AND att.member_id = a.id AND att.present = true
    GROUP BY a.id
  ),
  last_att AS (
    SELECT a.member_id, MAX(e.date::date) as last_date
    FROM public.attendance a JOIN public.events e ON e.id = a.event_id
    WHERE a.present = true GROUP BY a.member_id
  ),
  computed AS (
    SELECT a.id, a.m_name, a.t_name, a.t_id, a.op_role, a.is_curator,
      COALESCE(gs.mand,0) AS g_mand, COALESCE(gs.att,0) AS g_att,
      CASE WHEN COALESCE(gs.mand,0)>0 THEN ROUND(gs.att::numeric/gs.mand*100,1) ELSE 0 END AS g_pct,
      COALESCE(ts.mand,0) AS t_mand, COALESCE(ts.att,0) AS t_att,
      CASE WHEN COALESCE(ts.mand,0)>0 THEN ROUND(ts.att::numeric/ts.mand*100,1) ELSE 0 END AS t_pct,
      CASE WHEN COALESCE(gs.mand,0)+COALESCE(ts.mand,0)>0
        THEN ROUND((COALESCE(gs.att,0)+COALESCE(ts.att,0))::numeric/(COALESCE(gs.mand,0)+COALESCE(ts.mand,0))*100,1)
        ELSE 0 END AS c_pct,
      la.last_date
    FROM active a
    LEFT JOIN gscores gs ON gs.mid = a.id
    LEFT JOIN tscores ts ON ts.mid = a.id
    LEFT JOIN last_att la ON la.member_id = a.id
  )
  SELECT c.id, c.m_name, c.t_name, c.t_id, c.op_role,
    c.g_mand::int, c.g_att::int, c.g_pct, c.t_mand::int, c.t_att::int, c.t_pct,
    c.c_pct, c.last_date,
    (NOT c.is_curator AND (c.g_mand + c.t_mand) > 0 AND c.c_pct < 50) AS dropout_risk,
    CASE
      WHEN c.is_curator                               THEN 'curator'
      WHEN c.g_mand + c.t_mand = 0                    THEN 'no-data'
      WHEN c.c_pct >= 70                              THEN 'healthy'
      WHEN c.c_pct >= 50                              THEN 'borderline'
      WHEN c.g_pct < 30 AND c.t_pct >= 50             THEN 'missing-general'
      WHEN c.t_pct < 30 AND c.g_pct >= 50             THEN 'missing-tribe'
      WHEN c.c_pct < 30                               THEN 'missing-both'
      ELSE 'balanced-low'
    END AS typology
  FROM computed c
  ORDER BY c.m_name;
END;
$$


CREATE OR REPLACE FUNCTION public.get_campaign_analytics(p_send_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  -- ADR-0042: V4 catalog (manage_platform writes; view_chapter_dashboards reads)
  IF NOT (public.can_by_member(v_caller_id, 'manage_platform')
          OR public.can_by_member(v_caller_id, 'view_chapter_dashboards')) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform or view_chapter_dashboards permission';
  END IF;

  IF p_send_id IS NOT NULL THEN
    SELECT jsonb_build_object(
      'send', (
        SELECT jsonb_build_object(
          'id', cs.id, 'template_name', ct.name, 'subject', ct.subject,
          'sent_at', cs.sent_at, 'created_at', cs.created_at, 'status', cs.status
        )
        FROM campaign_sends cs JOIN campaign_templates ct ON ct.id = cs.template_id
        WHERE cs.id = p_send_id
      ),
      'funnel', jsonb_build_object(
        'total', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id),
        'delivered', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND (delivered_at IS NOT NULL OR delivered = true)),
        'opened', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND (opened_at IS NOT NULL OR opened = true)),
        'human_opened', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false),
        'bot_opened', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND (opened_at IS NOT NULL OR opened = true) AND bot_suspected = true),
        'clicked', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND clicked_at IS NOT NULL),
        'bounced', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND bounced_at IS NOT NULL),
        'complained', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND complained_at IS NOT NULL)
      ),
      'rates', jsonb_build_object(
        'delivery_rate', (
          SELECT ROUND(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true)::numeric / NULLIF(count(*), 0) * 100, 1)
          FROM campaign_recipients WHERE send_id = p_send_id
        ),
        'open_rate', (
          SELECT ROUND(count(*) FILTER (WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false)::numeric
            / NULLIF(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true), 0) * 100, 1)
          FROM campaign_recipients WHERE send_id = p_send_id
        ),
        'open_rate_total', (
          SELECT ROUND(count(*) FILTER (WHERE opened_at IS NOT NULL OR opened = true)::numeric
            / NULLIF(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true), 0) * 100, 1)
          FROM campaign_recipients WHERE send_id = p_send_id
        ),
        'click_rate', (
          SELECT ROUND(count(*) FILTER (WHERE clicked_at IS NOT NULL)::numeric
            / NULLIF(count(*) FILTER (WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false), 0) * 100, 1)
          FROM campaign_recipients WHERE send_id = p_send_id
        )
      ),
      'recipients', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'member_name', COALESCE(m.name, cr.external_name, ''),
          'email', COALESCE(m.email, cr.external_email, ''),
          'role', m.operational_role, 'tribe_name', t.name,
          'delivered', (cr.delivered_at IS NOT NULL OR cr.delivered = true),
          'opened', (cr.opened_at IS NOT NULL OR cr.opened = true),
          'open_count', cr.open_count, 'bot_suspected', cr.bot_suspected,
          'clicked', cr.clicked_at IS NOT NULL, 'click_count', cr.click_count,
          'bounced', cr.bounced_at IS NOT NULL, 'bounce_type', cr.bounce_type,
          'complained', cr.complained_at IS NOT NULL,
          'status', CASE
            WHEN cr.complained_at IS NOT NULL THEN 'complained'
            WHEN cr.bounced_at IS NOT NULL THEN 'bounced'
            WHEN cr.clicked_at IS NOT NULL THEN 'clicked'
            WHEN (cr.opened_at IS NOT NULL OR cr.opened = true) AND cr.bot_suspected = false THEN 'opened'
            WHEN (cr.opened_at IS NOT NULL OR cr.opened = true) AND cr.bot_suspected = true THEN 'bot_opened'
            WHEN cr.delivered_at IS NOT NULL OR cr.delivered = true THEN 'delivered'
            ELSE 'sent'
          END
        ) ORDER BY cr.delivered_at DESC NULLS LAST), '[]'::jsonb)
        FROM campaign_recipients cr
        LEFT JOIN members m ON m.id = cr.member_id
        LEFT JOIN tribes t ON t.id = public.get_member_tribe(m.id)
        WHERE cr.send_id = p_send_id
      ),
      'by_role', (
        SELECT COALESCE(jsonb_agg(sub), '[]'::jsonb) FROM (
          SELECT jsonb_build_object(
            'role', COALESCE(m.operational_role, 'external'),
            'total', count(*),
            'delivered', count(*) FILTER (WHERE cr.delivered_at IS NOT NULL OR cr.delivered = true),
            'opened', count(*) FILTER (WHERE (cr.opened_at IS NOT NULL OR cr.opened = true) AND cr.bot_suspected = false),
            'bot_opened', count(*) FILTER (WHERE (cr.opened_at IS NOT NULL OR cr.opened = true) AND cr.bot_suspected = true),
            'clicked', count(*) FILTER (WHERE cr.clicked_at IS NOT NULL)
          ) AS sub
          FROM campaign_recipients cr LEFT JOIN members m ON m.id = cr.member_id
          WHERE cr.send_id = p_send_id
          GROUP BY COALESCE(m.operational_role, 'external')
        ) agg
      )
    ) INTO v_result;
  ELSE
    SELECT jsonb_build_object(
      'total_sends', (SELECT count(*) FROM campaign_sends WHERE status = 'sent'),
      'total_recipients', (SELECT count(*) FROM campaign_recipients),
      'total_delivered', (SELECT count(*) FROM campaign_recipients WHERE delivered_at IS NOT NULL OR delivered = true),
      'total_opened', (SELECT count(*) FROM campaign_recipients WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false),
      'total_opened_incl_bots', (SELECT count(*) FROM campaign_recipients WHERE opened_at IS NOT NULL OR opened = true),
      'total_bot_opens', (SELECT count(*) FROM campaign_recipients WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = true),
      'total_clicked', (SELECT count(*) FROM campaign_recipients WHERE clicked_at IS NOT NULL),
      'total_bounced', (SELECT count(*) FROM campaign_recipients WHERE bounced_at IS NOT NULL),
      'overall_rates', jsonb_build_object(
        'delivery_rate', (SELECT ROUND(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true)::numeric / NULLIF(count(*), 0) * 100, 1) FROM campaign_recipients),
        'open_rate', (SELECT ROUND(count(*) FILTER (WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false)::numeric / NULLIF(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true), 0) * 100, 1) FROM campaign_recipients),
        'open_rate_total', (SELECT ROUND(count(*) FILTER (WHERE opened_at IS NOT NULL OR opened = true)::numeric / NULLIF(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true), 0) * 100, 1) FROM campaign_recipients),
        'click_rate', (SELECT ROUND(count(*) FILTER (WHERE clicked_at IS NOT NULL)::numeric / NULLIF(count(*) FILTER (WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false), 0) * 100, 1) FROM campaign_recipients)
      ),
      'recent_sends', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'id', cs.id, 'template_name', ct.name, 'sent_at', cs.sent_at, 'created_at', cs.created_at,
          'total', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id),
          'delivered', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND (delivered_at IS NOT NULL OR delivered = true)),
          'opened', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false),
          'bot_opened', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND (opened_at IS NOT NULL OR opened = true) AND bot_suspected = true),
          'clicked', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND clicked_at IS NOT NULL),
          'bounced', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND bounced_at IS NOT NULL)
        ) ORDER BY cs.created_at DESC), '[]'::jsonb)
        FROM campaign_sends cs JOIN campaign_templates ct ON ct.id = cs.template_id
        WHERE cs.status = 'sent' LIMIT 20
      )
    ) INTO v_result;
  END IF;

  RETURN v_result;
END;
$$


CREATE OR REPLACE FUNCTION public.get_initiative_gamification(p_initiative_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_caller record;
  v_tribe_id int;
  v_result jsonb;
  v_cycle_start date;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  v_tribe_id := public.resolve_tribe_id(p_initiative_id);

  IF v_tribe_id IS NOT NULL THEN
    RETURN public.get_tribe_gamification(v_tribe_id);
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM cycles WHERE is_current = true LIMIT 1;

  WITH init_members AS (
    SELECT DISTINCT m.id, m.name, m.cpmai_certified, m.credly_badges
    FROM engagements eng
    JOIN members m ON m.person_id = eng.person_id
    WHERE eng.initiative_id = p_initiative_id AND eng.status = 'active'
  ),
  points_per_member AS (
    SELECT
      gp.member_id,
      SUM(gp.points)::int AS total_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gp.created_at >= v_cycle_start), 0)::int AS cycle_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'presenca'), 0)::int AS attendance_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'certificacoes' AND gr.slug LIKE 'cert_%'), 0)::int AS cert_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.slug = 'badge'), 0)::int AS badge_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'trilha'), 0)::int AS learning_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'producao'), 0)::int AS producao_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'curadoria'), 0)::int AS curadoria_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'champions'), 0)::int AS champions_points
    FROM gamification_points gp
    JOIN init_members im ON im.id = gp.member_id
    LEFT JOIN gamification_rules gr
      ON gr.organization_id = gp.organization_id
     AND gr.slug = gp.category
    GROUP BY gp.member_id
  ),
  member_data AS (
    SELECT im.id, im.name,
           COALESCE(p.total_points, 0) AS total_points,
           COALESCE(p.cycle_points, 0) AS cycle_points,
           COALESCE(p.attendance_points, 0) AS attendance_points,
           COALESCE(p.cert_points, 0) AS cert_points,
           COALESCE(p.badge_points, 0) AS badge_points,
           COALESCE(p.learning_points, 0) AS learning_points,
           COALESCE(p.producao_points, 0) AS producao_points,
           COALESCE(p.curadoria_points, 0) AS curadoria_points,
           COALESCE(p.champions_points, 0) AS champions_points,
           COALESCE(jsonb_array_length(im.credly_badges), 0) AS credly_badge_count,
           COALESCE(im.cpmai_certified, false) AS has_cpmai,
           (SELECT count(*) FROM gamification_points gp2 WHERE gp2.member_id = im.id AND gp2.category = 'trail') AS trail_progress
    FROM init_members im
    LEFT JOIN points_per_member p ON p.member_id = im.id
  ),
  v_members AS (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', md.id, 'name', md.name,
      'total_points', md.total_points, 'cycle_points', md.cycle_points,
      'attendance_points', md.attendance_points, 'cert_points', md.cert_points,
      'badge_points', md.badge_points, 'learning_points', md.learning_points,
      'producao_points', md.producao_points, 'curadoria_points', md.curadoria_points,
      'champions_points', md.champions_points,
      'credly_badge_count', md.credly_badge_count,
      'has_cpmai', md.has_cpmai,
      'trail_progress', md.trail_progress
    ) ORDER BY md.total_points DESC), '[]'::jsonb) AS members_json
    FROM member_data md
  ),
  v_trend AS (
    SELECT COALESCE(jsonb_agg(jsonb_build_object('month', to_char(month, 'YYYY-MM'), 'xp', month_xp) ORDER BY month), '[]'::jsonb) AS trend_json
    FROM (
      SELECT date_trunc('month', gp.created_at) AS month, SUM(gp.points) AS month_xp
      FROM gamification_points gp
      JOIN init_members im ON im.id = gp.member_id
      WHERE gp.created_at >= v_cycle_start
      GROUP BY date_trunc('month', gp.created_at)
    ) sub
  )
  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total_xp', COALESCE((SELECT SUM(total_points) FROM member_data), 0),
      'avg_xp', CASE WHEN (SELECT count(*) FROM member_data) > 0
                THEN ROUND((SELECT SUM(total_points) FROM member_data)::numeric / (SELECT count(*) FROM member_data))
                ELSE 0 END,
      'tribe_rank', NULL,
      'cert_coverage', CASE WHEN (SELECT count(*) FROM member_data) > 0
                       THEN ROUND((SELECT count(*) FROM member_data WHERE has_cpmai OR credly_badge_count > 0)::numeric / (SELECT count(*) FROM member_data), 2)
                       ELSE 0 END,
      'trail_completion', 0
    ),
    'members', (SELECT members_json FROM v_members),
    'tribe_ranking', '[]'::jsonb,
    'monthly_trend', (SELECT trend_json FROM v_trend)
  ) INTO v_result;

  RETURN v_result;
END;
$$


CREATE OR REPLACE FUNCTION public.get_pilots_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_agg(jsonb_build_object(
    'id', p.id,
    'pilot_number', p.pilot_number,
    'title', p.title,
    'status', p.status,
    'started_at', p.started_at,
    'completed_at', p.completed_at,
    'hypothesis', p.hypothesis,
    'problem_statement', p.problem_statement,
    'scope', p.scope,
    'tribe_name', i.title,
    'board_id', p.board_id,
    'days_active', CASE WHEN p.started_at IS NOT NULL
      THEN CURRENT_DATE - p.started_at ELSE 0 END,
    'success_metrics', COALESCE(p.success_metrics, '[]'::jsonb),
    'metrics_count', jsonb_array_length(COALESCE(p.success_metrics, '[]'::jsonb)),
    'team_count', COALESCE(array_length(p.team_member_ids, 1), 0)
  ) ORDER BY p.pilot_number)
  INTO v_result
  FROM public.pilots p
  LEFT JOIN public.initiatives i ON i.id = p.initiative_id;

  RETURN jsonb_build_object(
    'pilots', COALESCE(v_result, '[]'::jsonb),
    'total', (SELECT count(*) FROM public.pilots),
    'active', (SELECT count(*) FROM public.pilots WHERE status = 'active'),
    'target', 3,
    'progress_pct', ROUND((SELECT count(*) FROM public.pilots WHERE status IN ('active','completed'))::numeric / 3 * 100, 0)
  );
END;
$$


CREATE OR REPLACE FUNCTION public.get_tribe_gamification(p_tribe_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller record;
  v_result jsonb;
  v_summary jsonb;
  v_members jsonb;
  v_ranking jsonb;
  v_trend jsonb;
  v_total_xp bigint;
  v_member_count int;
  v_cycle_start date;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  IF NOT (
    v_caller.tribe_id = p_tribe_id
    OR public.can_by_member(v_caller.id, 'view_internal_analytics')
  ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM cycles WHERE is_current = true LIMIT 1;

  SELECT count(*) INTO v_member_count FROM members WHERE tribe_id = p_tribe_id AND is_active = true;

  WITH points_per_member AS (
    SELECT
      gp.member_id,
      SUM(gp.points)::int AS total_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gp.created_at >= v_cycle_start), 0)::int AS cycle_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'presenca'), 0)::int AS attendance_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'certificacoes' AND gr.slug LIKE 'cert_%'), 0)::int AS cert_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.slug = 'badge'), 0)::int AS badge_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'trilha'), 0)::int AS learning_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'producao'), 0)::int AS producao_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'curadoria'), 0)::int AS curadoria_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'champions'), 0)::int AS champions_points
    FROM gamification_points gp
    LEFT JOIN gamification_rules gr
      ON gr.organization_id = gp.organization_id
     AND gr.slug = gp.category
    GROUP BY gp.member_id
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', m.id, 'name', m.name,
    'total_points', COALESCE(p.total_points, 0),
    'cycle_points', COALESCE(p.cycle_points, 0),
    'attendance_points', COALESCE(p.attendance_points, 0),
    'cert_points', COALESCE(p.cert_points, 0),
    'badge_points', COALESCE(p.badge_points, 0),
    'learning_points', COALESCE(p.learning_points, 0),
    'producao_points', COALESCE(p.producao_points, 0),
    'curadoria_points', COALESCE(p.curadoria_points, 0),
    'champions_points', COALESCE(p.champions_points, 0),
    'credly_badge_count', COALESCE(jsonb_array_length(m.credly_badges), 0),
    'has_cpmai', COALESCE(m.cpmai_certified, false),
    'trail_progress', (SELECT count(*) FROM gamification_points gp WHERE gp.member_id = m.id AND gp.category = 'trail')
  ) ORDER BY COALESCE(p.total_points, 0) DESC), '[]'::jsonb)
  INTO v_members
  FROM members m
  LEFT JOIN points_per_member p ON p.member_id = m.id
  WHERE m.tribe_id = p_tribe_id AND m.is_active = true;

  SELECT COALESCE(SUM((elem->>'total_points')::bigint), 0)
  INTO v_total_xp
  FROM jsonb_array_elements(v_members) elem;

  v_summary := jsonb_build_object(
    'total_xp', v_total_xp,
    'avg_xp', CASE WHEN v_member_count > 0 THEN ROUND(v_total_xp::numeric / v_member_count) ELSE 0 END,
    'tribe_rank', (
      WITH tribe_totals AS (
        SELECT t.id AS tid, COALESCE(SUM(gp.points), 0) AS txp
        FROM tribes t
        LEFT JOIN members m2 ON m2.tribe_id = t.id AND m2.is_active = true
        LEFT JOIN gamification_points gp ON gp.member_id = m2.id
        WHERE t.is_active = true
        GROUP BY t.id
      ),
      ranked AS (
        SELECT tid, RANK() OVER (ORDER BY txp DESC) AS rk FROM tribe_totals
      )
      SELECT rk FROM ranked WHERE tid = p_tribe_id
    ),
    'cert_coverage', CASE WHEN v_member_count > 0 THEN ROUND(
      (SELECT count(*) FROM members
        WHERE tribe_id = p_tribe_id AND is_active = true
        AND (cpmai_certified = true OR jsonb_array_length(COALESCE(credly_badges, '[]'::jsonb)) > 0)
      )::numeric / v_member_count, 2
    ) ELSE 0 END,
    'trail_completion', 0
  );

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'tribe_id', sub.tid,
      'tribe_name', sub.tname,
      'tribe_name_i18n', sub.tname_i18n,
      'total_xp', sub.txp
    )
    ORDER BY sub.txp DESC
  ), '[]'::jsonb)
  INTO v_ranking
  FROM (
    SELECT t.id AS tid, t.name AS tname, t.name_i18n AS tname_i18n, COALESCE(SUM(gp.points), 0) AS txp
    FROM tribes t
    LEFT JOIN members m4 ON m4.tribe_id = t.id AND m4.is_active = true
    LEFT JOIN gamification_points gp ON gp.member_id = m4.id
    WHERE t.is_active = true
    GROUP BY t.id, t.name, t.name_i18n
  ) sub;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('month', to_char(month, 'YYYY-MM'), 'xp', month_xp) ORDER BY month), '[]'::jsonb)
  INTO v_trend
  FROM (
    SELECT date_trunc('month', gp.created_at) AS month, SUM(gp.points) AS month_xp
    FROM gamification_points gp
    JOIN members m5 ON m5.id = gp.member_id
    WHERE m5.tribe_id = p_tribe_id AND m5.is_active = true
      AND gp.created_at >= v_cycle_start
    GROUP BY date_trunc('month', gp.created_at)
  ) sub;

  RETURN jsonb_build_object('summary', v_summary, 'members', v_members, 'tribe_ranking', v_ranking, 'monthly_trend', v_trend);
END;
$$


CREATE OR REPLACE FUNCTION public.import_vep_applications(p_cycle_id uuid, p_rows jsonb, p_opportunity_id text DEFAULT NULL::text, p_role text DEFAULT 'researcher'::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_row jsonb; v_imported int := 0; v_skipped_dedup int := 0;
  v_skipped_declined int := 0; v_skipped_active int := 0;
  v_flagged_review int := 0; v_updated_snapshots int := 0; v_returning int := 0;
  v_app_id uuid; v_vep_app_id text; v_vep_status text; v_email text;
  v_membership text; v_chapters text[]; v_has_partner boolean;
  v_existing_app_id uuid; v_existing_member record;
  v_prev_cycles text[]; v_app_count int; v_partner_codes text[];
  v_primary_chapter text; v_cycle record; v_essay_mapping jsonb;
  v_opp record; v_app_date date;
  v_motivation text; v_areas text; v_availability text;
  v_academic text; v_proposed text; v_leadership text; v_chapter_aff text;
  v_field text; v_essay_val text;
  v_is_returning_offboarded boolean;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform permission for VEP import';
  END IF;

  SELECT array_agg(chapter_code) INTO v_partner_codes FROM partner_chapters WHERE is_active = true;
  SELECT * INTO v_cycle FROM selection_cycles WHERE id = p_cycle_id;
  SELECT * INTO v_opp FROM vep_opportunities WHERE opportunity_id = p_opportunity_id;
  v_essay_mapping := coalesce(v_opp.essay_mapping, '{"1":"essay_q1","2":"essay_q2","3":"essay_q3","4":"essay_q4","5":"essay_q5"}'::jsonb);
  IF v_opp.role_default IS NOT NULL THEN p_role := v_opp.role_default; END IF;

  FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows)
  LOOP
    v_vep_app_id := v_row->>'application_id';
    v_vep_status := v_row->>'app_status';
    v_email := lower(trim(v_row->>'email'));
    v_membership := v_row->>'membership_status';

    IF v_vep_status IN ('OfferNotExtended', 'Declined', 'Withdrawn') THEN
      v_skipped_declined := v_skipped_declined + 1; CONTINUE;
    END IF;

    v_chapters := parse_vep_chapters(v_membership);
    v_has_partner := v_chapters && v_partner_codes;

    IF v_vep_status IN ('Active', 'Complete') THEN
      SELECT id INTO v_existing_app_id FROM selection_applications WHERE lower(email) = v_email LIMIT 1;
      IF v_existing_app_id IS NOT NULL THEN
        INSERT INTO selection_membership_snapshots (application_id, membership_status, chapter_affiliations, certifications, is_partner_chapter, source)
        VALUES (v_existing_app_id, v_membership, v_chapters, v_row->>'certifications', v_has_partner, 'csv_active_snapshot');
        v_updated_snapshots := v_updated_snapshots + 1;
      END IF;
      v_skipped_active := v_skipped_active + 1; CONTINUE;
    END IF;

    SELECT id INTO v_existing_app_id FROM selection_applications WHERE vep_application_id = v_vep_app_id;
    IF v_existing_app_id IS NOT NULL THEN
      INSERT INTO selection_membership_snapshots (application_id, membership_status, chapter_affiliations, certifications, is_partner_chapter, source)
      VALUES (v_existing_app_id, v_membership, v_chapters, v_row->>'certifications', v_has_partner, 'csv_reimport');
      v_updated_snapshots := v_updated_snapshots + 1;
      v_skipped_dedup := v_skipped_dedup + 1; CONTINUE;
    END IF;

    SELECT id, is_active, operational_role, offboarded_at, chapter INTO v_existing_member
    FROM members WHERE lower(email) = v_email LIMIT 1;

    v_is_returning_offboarded := v_existing_member.id IS NOT NULL AND EXISTS (
      SELECT 1 FROM member_offboarding_records mor WHERE mor.member_id = v_existing_member.id
    );

    IF v_existing_member.id IS NOT NULL AND v_existing_member.is_active = false THEN
      IF v_existing_member.offboarded_at IS NOT NULL
         AND v_existing_member.offboarded_at >= coalesce(v_cycle.open_date, '2026-01-01')::timestamptz THEN
        INSERT INTO data_anomaly_log (anomaly_type, severity, message, details)
        VALUES ('selection_import_flagged_current_cycle', 'high',
          'Candidato inativado no ciclo corrente: ' || (v_row->>'first_name') || ' ' || (v_row->>'last_name'),
          jsonb_build_object('email', v_email, 'member_id', v_existing_member.id,
            'offboarded_at', v_existing_member.offboarded_at, 'vep_app_id', v_vep_app_id));
        v_flagged_review := v_flagged_review + 1; CONTINUE;
      END IF;
    END IF;

    v_primary_chapter := NULL;
    IF v_existing_member.id IS NOT NULL AND v_existing_member.chapter IS NOT NULL THEN
      v_primary_chapter := v_existing_member.chapter;
    ELSIF array_length(v_chapters, 1) > 0 THEN
      SELECT unnest INTO v_primary_chapter FROM unnest(v_chapters)
      WHERE unnest = ANY(v_partner_codes) LIMIT 1;
      IF v_primary_chapter IS NULL THEN v_primary_chapter := v_chapters[1]; END IF;
    END IF;

    SELECT count(*), array_agg(DISTINCT sc.cycle_code)
    INTO v_app_count, v_prev_cycles
    FROM selection_applications sa JOIN selection_cycles sc ON sc.id = sa.cycle_id
    WHERE lower(sa.email) = v_email;
    v_app_count := coalesce(v_app_count, 0) + 1;

    BEGIN
      v_app_date := NULLIF(trim(v_row->>'application_date'), '')::date;
    EXCEPTION WHEN OTHERS THEN v_app_date := NULL; END;

    v_motivation := NULL; v_areas := NULL; v_availability := NULL;
    v_academic := NULL; v_proposed := NULL; v_leadership := NULL; v_chapter_aff := NULL;

    FOR i IN 1..5 LOOP
      v_field := get_essay_field(v_essay_mapping, i::text);
      v_essay_val := v_row->>('essay_q' || i::text);
      IF v_field IS NOT NULL AND v_essay_val IS NOT NULL AND v_essay_val != '' THEN
        CASE v_field
          WHEN 'motivation_letter' THEN v_motivation := v_essay_val;
          WHEN 'chapter_affiliation' THEN v_chapter_aff := v_essay_val;
          WHEN 'areas_of_interest' THEN v_areas := v_essay_val;
          WHEN 'availability_declared' THEN v_availability := v_essay_val;
          WHEN 'academic_background' THEN v_academic := v_essay_val;
          WHEN 'proposed_theme' THEN v_proposed := v_essay_val;
          WHEN 'leadership_experience' THEN v_leadership := v_essay_val;
          ELSE NULL;
        END CASE;
      END IF;
    END LOOP;

    IF v_motivation IS NULL THEN v_motivation := v_row->>'reason_for_applying'; END IF;
    IF v_areas IS NULL THEN v_areas := v_row->>'areas_of_interest'; END IF;

    INSERT INTO selection_applications (
      cycle_id, vep_application_id, vep_opportunity_id,
      applicant_name, first_name, last_name, email, pmi_id,
      chapter, state, country, membership_status, certifications,
      resume_url, role_applied,
      motivation_letter, reason_for_applying, chapter_affiliation,
      areas_of_interest, availability_declared,
      academic_background, proposed_theme, leadership_experience,
      industry, application_date,
      is_returning_member, previous_cycles, application_count,
      imported_at, status
    ) VALUES (
      p_cycle_id, v_vep_app_id, p_opportunity_id,
      trim(coalesce(v_row->>'first_name', '')) || ' ' || trim(coalesce(v_row->>'last_name', '')),
      v_row->>'first_name', v_row->>'last_name', v_email, v_row->>'pmi_id',
      v_primary_chapter, v_row->>'state', v_row->>'country',
      v_membership, v_row->>'certifications',
      v_row->>'resume_url', p_role,
      v_motivation, v_row->>'reason_for_applying', v_chapter_aff,
      v_areas, v_availability,
      v_academic, v_proposed, v_leadership,
      v_row->>'industry', v_app_date,
      v_is_returning_offboarded,
      v_prev_cycles, v_app_count,
      now(), 'submitted'
    ) RETURNING id INTO v_app_id;

    INSERT INTO selection_membership_snapshots (application_id, membership_status, chapter_affiliations, certifications, is_partner_chapter, source)
    VALUES (v_app_id, v_membership, v_chapters, v_row->>'certifications', v_has_partner, 'csv_import');

    v_imported := v_imported + 1;
    IF v_is_returning_offboarded THEN v_returning := v_returning + 1; END IF;
  END LOOP;

  RETURN json_build_object(
    'imported', v_imported, 'skipped_dedup', v_skipped_dedup,
    'skipped_declined', v_skipped_declined, 'skipped_active', v_skipped_active,
    'flagged_review', v_flagged_review,
    'updated_snapshots', v_updated_snapshots, 'returning_members', v_returning,
    'cycle_id', p_cycle_id, 'opportunity_id', p_opportunity_id
  );
END;
$$


CREATE OR REPLACE FUNCTION public.list_initiative_meeting_artifacts(p_limit integer DEFAULT 100, p_initiative_id uuid DEFAULT NULL::uuid)
 RETURNS SETOF meeting_artifacts
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF p_initiative_id IS NOT NULL THEN
    PERFORM public.assert_initiative_capability(p_initiative_id, 'has_meeting_notes');
  END IF;

  RETURN QUERY
    SELECT *
    FROM public.meeting_artifacts ma
    WHERE ma.is_published = true
      AND (
        p_initiative_id IS NULL
        OR ma.initiative_id = p_initiative_id
        OR ma.initiative_id IS NULL
      )
    ORDER BY ma.meeting_date DESC
    LIMIT p_limit;
END;
$$


CREATE OR REPLACE FUNCTION public.mark_interview_status(p_interview_id uuid, p_status text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_caller record;
  v_interview record;
  v_app record;
  v_cycle record;
  v_new_app_status text;
  v_prior_status text;
  v_first_name text;
  v_booking_url text;
  v_deadline_date text;
  v_send_result jsonb := NULL;
  v_noshow_count int;
  v_two_strike_applied boolean := false;
  v_two_strike_send jsonb := NULL;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  IF p_status NOT IN ('noshow', 'cancelled', 'rescheduled', 'completed') THEN
    RAISE EXCEPTION 'Invalid interview status: %', p_status;
  END IF;

  SELECT * INTO v_interview FROM public.selection_interviews WHERE id = p_interview_id;
  IF v_interview IS NULL THEN
    RAISE EXCEPTION 'Interview not found';
  END IF;

  v_prior_status := v_interview.status;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = v_interview.application_id;
  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  IF NOT (
    v_caller.id = ANY(v_interview.interviewer_ids)
    OR public.can_by_member(v_caller.id, 'manage_platform'::text)
    OR EXISTS (
      SELECT 1 FROM public.selection_committee
      WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead'
    )
  ) THEN
    RAISE EXCEPTION 'Unauthorized: must be interviewer, committee lead, or platform admin';
  END IF;

  UPDATE public.selection_interviews
  SET status = p_status,
      notes = COALESCE(p_notes, notes),
      conducted_at = CASE WHEN p_status = 'completed' THEN now() ELSE conducted_at END
  WHERE id = p_interview_id;

  v_new_app_status := CASE p_status
    WHEN 'noshow' THEN 'interview_noshow'
    WHEN 'cancelled' THEN 'interview_pending'
    WHEN 'rescheduled' THEN 'interview_pending'
    WHEN 'completed' THEN 'interview_done'
    ELSE v_app.status
  END;

  UPDATE public.selection_applications
  SET status = v_new_app_status, updated_at = now()
  WHERE id = v_interview.application_id
    AND status IN ('interview_scheduled', 'interview_done');

  IF p_status = 'noshow' AND v_prior_status IS DISTINCT FROM 'noshow' THEN
    v_first_name := COALESCE(
      NULLIF(trim(v_app.first_name), ''),
      NULLIF(split_part(v_app.applicant_name, ' ', 1), ''),
      'candidato(a)'
    );

    -- Count noshows for this application (after the UPDATE above)
    SELECT count(*) INTO v_noshow_count
    FROM public.selection_interviews
    WHERE application_id = v_interview.application_id
      AND status = 'noshow';

    IF v_noshow_count >= 2 THEN
      -- 2-strike auto-close: rejected status + close email + skip soft reschedule
      UPDATE public.selection_applications
      SET status = 'rejected',
          feedback = COALESCE(feedback, '') || E'\n[p152 auto-close ' || to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI') || ' BRT] Encerrado automaticamente após ' || v_noshow_count || ' no-shows na entrevista.',
          updated_at = now()
      WHERE id = v_interview.application_id;

      BEGIN
        v_two_strike_send := public.campaign_send_one_off(
          'interview_two_strike_close',
          v_app.email,
          jsonb_build_object('first_name', v_first_name),
          jsonb_build_object(
            'language', 'pt',
            'recipient_name', COALESCE(v_app.first_name, v_app.applicant_name),
            'source', 'mark_interview_status:two_strike_close',
            'noshow_count', v_noshow_count
          )
        );
      EXCEPTION WHEN OTHERS THEN
        v_two_strike_send := jsonb_build_object('error', SQLERRM);
      END;

      v_two_strike_applied := true;

      -- Notify PM in-platform
      PERFORM public.create_notification(
        sc.member_id,
        'selection_application_two_strike_closed',
        '2-strike encerrado: ' || v_app.applicant_name,
        v_app.applicant_name || ' teve ' || v_noshow_count || ' no-shows. Processo encerrado automaticamente + email enviado. Override manual via Status select.',
        '/admin/selection',
        'selection_application',
        v_interview.application_id
      )
      FROM public.selection_committee sc
      WHERE sc.cycle_id = v_app.cycle_id AND sc.role = 'lead';
    ELSE
      -- 1st noshow: soft reschedule email (P1 path)
      v_booking_url := COALESCE(
        NULLIF(trim(v_cycle.interview_booking_url), ''),
        'https://calendar.app.google/gh9WjefjcmisVLoh7'
      );
      v_deadline_date := to_char((now() + interval '7 days') AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY');

      BEGIN
        v_send_result := public.campaign_send_one_off(
          'interview_noshow_soft_reschedule',
          v_app.email,
          jsonb_build_object(
            'first_name', v_first_name,
            'booking_url', v_booking_url,
            'deadline_date', v_deadline_date
          ),
          jsonb_build_object(
            'language', 'pt',
            'recipient_name', COALESCE(v_app.first_name, v_app.applicant_name),
            'source', 'mark_interview_status:noshow'
          )
        );
      EXCEPTION WHEN OTHERS THEN
        v_send_result := jsonb_build_object('error', SQLERRM);
      END;
    END IF;
  END IF;

  IF p_status = 'noshow' AND NOT v_two_strike_applied THEN
    PERFORM public.create_notification(
      sc.member_id,
      'selection_interview_noshow',
      'No-show: ' || v_app.applicant_name,
      v_app.applicant_name || ' (' || COALESCE(v_app.chapter, '') || ') não compareceu à entrevista agendada.',
      '/admin/selection',
      'selection_interview',
      p_interview_id
    )
    FROM public.selection_committee sc
    WHERE sc.cycle_id = v_app.cycle_id AND sc.role = 'lead';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'interview_status', p_status,
    'application_status', CASE WHEN v_two_strike_applied THEN 'rejected' ELSE v_new_app_status END,
    'email_dispatched', v_send_result IS NOT NULL AND (v_send_result ? 'send_id'),
    'email_send_result', v_send_result,
    'two_strike_applied', v_two_strike_applied,
    'noshow_count', v_noshow_count,
    'two_strike_email', v_two_strike_send
  );
END;
$$


CREATE OR REPLACE FUNCTION public.move_board_item(p_item_id uuid, p_new_status text, p_new_position integer DEFAULT 0, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_old_status text;
  v_board_id uuid;
  v_actor record;
  v_board record;
  v_board_legacy_tribe_id int;
  v_is_gp boolean;
  v_is_leader boolean;
  v_is_card_owner boolean;
  v_is_comms_for_domain boolean;
BEGIN
  SELECT status, board_id INTO v_old_status, v_board_id FROM board_items WHERE id = p_item_id;
  IF v_old_status IS NULL THEN RAISE EXCEPTION 'Item not found'; END IF;
  SELECT * INTO v_actor FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_board FROM project_boards WHERE id = v_board_id;

  SELECT legacy_tribe_id INTO v_board_legacy_tribe_id
  FROM public.initiatives WHERE id = v_board.initiative_id;

  v_is_gp := coalesce(v_actor.is_superadmin, false) OR v_actor.operational_role IN ('manager','deputy_manager') OR coalesce('co_gp' = ANY(v_actor.designations), false);
  v_is_leader := v_actor.operational_role = 'tribe_leader' AND v_actor.tribe_id = v_board_legacy_tribe_id;

  v_is_card_owner := EXISTS (SELECT 1 FROM board_items WHERE id = p_item_id AND (created_by = v_actor.id OR assignee_id = v_actor.id))
    OR EXISTS (SELECT 1 FROM board_item_assignments WHERE item_id = p_item_id AND member_id = v_actor.id);

  v_is_comms_for_domain := coalesce(v_board.domain_key, '') = 'communication' AND (
    v_actor.operational_role = 'communicator'
    OR coalesce('comms_team' = ANY(v_actor.designations), false)
    OR coalesce('comms_leader' = ANY(v_actor.designations), false)
    OR coalesce('comms_member' = ANY(v_actor.designations), false)
  );

  -- Item 05 fix (Decision #5 B): card owner can mark as done.
  -- Audit trail in board_lifecycle_events; GP/Leader can reabrir if discordam.
  IF p_new_status = 'done' AND NOT v_is_gp AND NOT v_is_leader AND NOT v_is_card_owner AND NOT v_is_comms_for_domain THEN
    RAISE EXCEPTION 'Only Leader, GP, card owner, or comms team (in communication board) can mark as completed';
  END IF;

  IF NOT public.can_by_member(v_actor.id, 'write_board') AND NOT v_is_card_owner AND NOT v_is_comms_for_domain THEN
    RAISE EXCEPTION 'Unauthorized: requires write_board permission, card ownership, or comms team in communication board';
  END IF;

  UPDATE board_items SET position = position + 1
  WHERE board_id = v_board_id AND status = p_new_status AND position >= p_new_position AND id != p_item_id;

  UPDATE board_items SET status = p_new_status, position = p_new_position,
    actual_completion_date = CASE WHEN p_new_status = 'done' THEN CURRENT_DATE ELSE actual_completion_date END,
    updated_at = now()
  WHERE id = p_item_id;

  IF v_old_status != p_new_status THEN
    INSERT INTO board_lifecycle_events (board_id, item_id, action, previous_status, new_status, reason, actor_member_id)
    VALUES (v_board_id, p_item_id, 'status_change', v_old_status, p_new_status, p_reason, v_actor.id);
    INSERT INTO notifications (recipient_id, type, source_type, source_id, title, actor_id)
    SELECT bia.member_id,
      CASE WHEN p_new_status = 'review' THEN 'review_requested' ELSE 'card_status_changed' END,
      'board_item', p_item_id, (SELECT title FROM board_items WHERE id = p_item_id), v_actor.id
    FROM board_item_assignments bia WHERE bia.item_id = p_item_id AND bia.member_id != v_actor.id;
  END IF;
END;
$$


CREATE OR REPLACE FUNCTION public.notify_webinar_status_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_recipient uuid;
  v_notif_type text;
  v_body text;
  v_link text;
  v_actor_id uuid;
  v_legacy_tribe_id int;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN RETURN NEW; END IF;

  v_notif_type := 'webinar_status_' || NEW.status;
  v_link := '/admin/webinars';

  SELECT id INTO v_actor_id FROM members WHERE auth_id = auth.uid();

  INSERT INTO webinar_lifecycle_events (webinar_id, action, actor_id, old_status, new_status)
  VALUES (NEW.id, 'status_change', v_actor_id, OLD.status, NEW.status);

  v_body := CASE NEW.status
    WHEN 'confirmed' THEN 'Webinar "' || NEW.title || '" confirmado. Preparar logística e campanha de divulgação.'
    WHEN 'completed' THEN 'Webinar "' || NEW.title || '" realizado. Preparar follow-up, replay e materiais.'
    WHEN 'cancelled' THEN 'Webinar "' || NEW.title || '" cancelado.'
    ELSE 'Webinar "' || NEW.title || '" — status alterado para ' || NEW.status || '.'
  END;

  IF NEW.organizer_id IS NOT NULL AND NEW.organizer_id IS DISTINCT FROM v_actor_id THEN
    PERFORM create_notification(
      NEW.organizer_id, v_notif_type,
      'Webinar: ' || NEW.title, v_body, v_link, 'webinar', NEW.id
    );
  END IF;

  IF array_length(NEW.co_manager_ids, 1) > 0 THEN
    FOREACH v_recipient IN ARRAY NEW.co_manager_ids LOOP
      IF v_recipient IS DISTINCT FROM v_actor_id THEN
        PERFORM create_notification(
          v_recipient, v_notif_type,
          'Webinar: ' || NEW.title, v_body, v_link, 'webinar', NEW.id
        );
      END IF;
    END LOOP;
  END IF;

  IF NEW.status IN ('confirmed', 'completed') THEN
    FOR v_recipient IN
      SELECT id FROM members
      WHERE designations && ARRAY['comms_leader', 'comms_member']
        AND is_active = true AND id IS DISTINCT FROM v_actor_id
    LOOP
      PERFORM create_notification(
        v_recipient, v_notif_type,
        'Webinar: ' || NEW.title,
        CASE NEW.status
          WHEN 'confirmed' THEN 'Preparar campanha de divulgação para "' || NEW.title || '" — ' || NEW.chapter_code || '.'
          WHEN 'completed' THEN 'Preparar follow-up e divulgação de replay para "' || NEW.title || '".'
        END,
        '/admin/comms?context=webinar&title=' || NEW.title,
        'webinar', NEW.id
      );
    END LOOP;
  END IF;

  -- ADR-0015 Phase 3b: webinars.tribe_id droppado; derivar via initiative
  SELECT legacy_tribe_id INTO v_legacy_tribe_id
  FROM public.initiatives WHERE id = NEW.initiative_id;

  IF v_legacy_tribe_id IS NOT NULL AND NEW.status IN ('confirmed', 'completed', 'cancelled') THEN
    FOR v_recipient IN
      SELECT id FROM members
      WHERE tribe_id = v_legacy_tribe_id
        AND operational_role = 'tribe_leader'
        AND is_active = true AND id IS DISTINCT FROM v_actor_id
    LOOP
      PERFORM create_notification(
        v_recipient, v_notif_type,
        'Webinar da sua tribo: ' || NEW.title, v_body,
        '/tribe/' || v_legacy_tribe_id || '?tab=board',
        'webinar', NEW.id
      );
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$


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
$$


-- ============================================================
-- 3-touch bucket (22 functions)
-- ============================================================

CREATE OR REPLACE FUNCTION public._enqueue_gate_notifications(p_chain_id uuid, p_event text, p_gate_kind text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_chain record; v_doc record; v_version record; v_submitter record;
  v_gate jsonb; v_target record; v_link text; v_title text; v_body text;
  v_notif_type text; v_enqueued int := 0;
  v_action_label text; v_role_singular text; v_action_verb text;
BEGIN
  IF p_event NOT IN ('chain_opened','gate_advanced','chain_approved') THEN
    RAISE EXCEPTION 'Invalid event: %', p_event USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT ac.id, ac.status, ac.gates, ac.document_id, ac.version_id, ac.opened_by
  INTO v_chain FROM public.approval_chains ac WHERE ac.id = p_chain_id;
  IF v_chain.id IS NULL THEN RETURN 0; END IF;

  SELECT gd.id, gd.title, gd.doc_type INTO v_doc
  FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;

  SELECT dv.id, dv.version_label INTO v_version
  FROM public.document_versions dv WHERE dv.id = v_chain.version_id;

  SELECT m.id, m.name, m.email INTO v_submitter
  FROM public.members m WHERE m.id = v_chain.opened_by;

  IF p_event = 'chain_opened' THEN
    SELECT g INTO v_gate FROM jsonb_array_elements(v_chain.gates) g
    ORDER BY (g->>'order')::int ASC LIMIT 1;
    IF v_gate IS NULL THEN RETURN 0; END IF;

    v_link := public._ip_ratify_cta_link(p_chain_id, v_gate->>'kind');
    v_notif_type := 'ip_ratification_gate_pending';

    v_action_label := CASE v_gate->>'kind'
      WHEN 'curator' THEN 'Curadoria'
      WHEN 'leader_awareness' THEN 'Ciencia da lideranca'
      WHEN 'submitter_acceptance' THEN 'Aceite do GP'
      WHEN 'chapter_witness' THEN 'Testemunho de capitulo'
      WHEN 'president_go' THEN 'Assinatura da presidencia PMI-GO'
      WHEN 'president_others' THEN 'Assinatura de presidencia de capitulo'
      WHEN 'volunteers_in_role_active' THEN 'Ratificacao de voluntario em funcao ativa'
      WHEN 'member_ratification' THEN 'Ratificacao de membro'
      ELSE v_gate->>'kind' END;
    v_role_singular := CASE v_gate->>'kind'
      WHEN 'curator' THEN 'curador(a)'
      WHEN 'leader_awareness' THEN 'lider do Nucleo'
      WHEN 'submitter_acceptance' THEN 'Gerente de Projeto'
      WHEN 'chapter_witness' THEN 'ponto focal do seu capitulo'
      WHEN 'president_go' THEN 'presidencia do PMI-GO'
      WHEN 'president_others' THEN 'presidencia do seu capitulo'
      WHEN 'volunteers_in_role_active' THEN 'voluntario(a) em funcao ativa'
      WHEN 'member_ratification' THEN 'membro ativo'
      ELSE v_gate->>'kind' END;
    v_action_verb := CASE v_gate->>'kind'
      WHEN 'curator' THEN 'ler o documento completo e decidir se ele avanca para a fase de aprovacao pelas presidencias de capitulo. Voce pode registrar duvidas ou pontos de ajuste como comentarios antes de aprovar'
      WHEN 'leader_awareness' THEN 'ler o documento e registrar ciencia. Este passo nao bloqueia o workflow, mas formaliza que a lideranca esta ciente do que sera ratificado'
      WHEN 'submitter_acceptance' THEN 'confirmar formalmente que o documento esta pronto para circular as presidencias de capitulo'
      WHEN 'chapter_witness' THEN 'confirmar que o documento foi apresentado e e de conhecimento dos membros do seu capitulo'
      WHEN 'president_go' THEN 'ler e assinar como presidencia do capitulo-sede. Apos sua assinatura, as demais presidencias serao notificadas'
      WHEN 'president_others' THEN 'ler e assinar como presidencia do seu capitulo, apos a presidencia PMI-GO ja ter assinado'
      WHEN 'volunteers_in_role_active' THEN 'ler o documento e ratificar como voluntario(a) em funcao ativa. Sua ratificacao formaliza a adesao pessoal aos termos atualizados enquanto voce mantem funcao ativa no Nucleo'
      WHEN 'member_ratification' THEN 'ler o documento e ratificar como membro ativo. Sua ratificacao formaliza a adesao pessoal aos termos'
      ELSE 'revisar e agir conforme o seu papel neste workflow' END;

    FOR v_target IN
      SELECT m.id AS member_id, m.name FROM public.members m
      WHERE m.is_active = true
        AND public._can_sign_gate(m.id, p_chain_id, v_gate->>'kind')
        AND NOT EXISTS (SELECT 1 FROM public.approval_signoffs s
          WHERE s.approval_chain_id = p_chain_id
            AND s.gate_kind = v_gate->>'kind' AND s.signer_id = m.id)
    LOOP
      v_title := v_doc.title || ' ' || COALESCE(v_version.version_label,'') ||
                 ' — ' || v_action_label || ' solicitada por ' || COALESCE(v_submitter.name, 'Gerente de Projeto');
      v_body := COALESCE(v_submitter.name, 'O Gerente de Projeto') ||
                ' submeteu o documento "' || v_doc.title || '" versao ' ||
                COALESCE(v_version.version_label,'') || ' para ratificacao no Nucleo IA & GP. ' ||
                'Como ' || v_role_singular || ', voce deve ' || v_action_verb || '.';
      PERFORM public.create_notification(
        v_target.member_id, v_notif_type, v_title, v_body, v_link,
        'approval_chain', p_chain_id);
      v_enqueued := v_enqueued + 1;
    END LOOP;
    RETURN v_enqueued;
  END IF;

  IF p_event = 'gate_advanced' AND p_gate_kind IS NOT NULL THEN
    SELECT g INTO v_gate FROM jsonb_array_elements(v_chain.gates) g
    WHERE (g->>'order')::int > (
      SELECT (g2->>'order')::int FROM jsonb_array_elements(v_chain.gates) g2
      WHERE g2->>'kind' = p_gate_kind LIMIT 1)
    ORDER BY (g->>'order')::int ASC LIMIT 1;

    IF v_gate IS NOT NULL THEN
      v_link := public._ip_ratify_cta_link(p_chain_id, v_gate->>'kind');
      v_notif_type := CASE WHEN (v_gate->>'kind') IN ('volunteers_in_role_active','member_ratification')
                          THEN 'ip_ratification_awaiting_members'
                          ELSE 'ip_ratification_gate_pending' END;

      v_action_label := CASE v_gate->>'kind'
        WHEN 'curator' THEN 'Curadoria'
        WHEN 'leader_awareness' THEN 'Ciencia da lideranca'
        WHEN 'submitter_acceptance' THEN 'Aceite do GP'
        WHEN 'chapter_witness' THEN 'Testemunho de capitulo'
        WHEN 'president_go' THEN 'Assinatura da presidencia PMI-GO'
        WHEN 'president_others' THEN 'Assinatura de presidencia de capitulo'
        WHEN 'volunteers_in_role_active' THEN 'Ratificacao de voluntario em funcao ativa'
        WHEN 'member_ratification' THEN 'Ratificacao de membro'
        ELSE v_gate->>'kind' END;
      v_role_singular := CASE v_gate->>'kind'
        WHEN 'curator' THEN 'curador(a)'
        WHEN 'leader_awareness' THEN 'lider do Nucleo'
        WHEN 'submitter_acceptance' THEN 'Gerente de Projeto'
        WHEN 'chapter_witness' THEN 'ponto focal do seu capitulo'
        WHEN 'president_go' THEN 'presidencia do PMI-GO'
        WHEN 'president_others' THEN 'presidencia do seu capitulo'
        WHEN 'volunteers_in_role_active' THEN 'voluntario(a) em funcao ativa'
        WHEN 'member_ratification' THEN 'membro ativo'
        ELSE v_gate->>'kind' END;
      v_action_verb := CASE v_gate->>'kind'
        WHEN 'curator' THEN 'ler o documento e aprovar como curador'
        WHEN 'leader_awareness' THEN 'ler e registrar ciencia'
        WHEN 'submitter_acceptance' THEN 'confirmar que esta pronto para circular presidencias'
        WHEN 'chapter_witness' THEN 'confirmar como ponto focal do seu capitulo'
        WHEN 'president_go' THEN 'assinar como presidencia PMI-GO'
        WHEN 'president_others' THEN 'assinar como presidencia de capitulo'
        WHEN 'volunteers_in_role_active' THEN 'ratificar como voluntario(a) em funcao ativa'
        WHEN 'member_ratification' THEN 'ratificar como membro ativo'
        ELSE 'agir conforme seu papel' END;

      FOR v_target IN
        SELECT m.id AS member_id, m.name FROM public.members m
        WHERE m.is_active = true
          AND public._can_sign_gate(m.id, p_chain_id, v_gate->>'kind')
          AND NOT EXISTS (SELECT 1 FROM public.approval_signoffs s
            WHERE s.approval_chain_id = p_chain_id
              AND s.gate_kind = v_gate->>'kind' AND s.signer_id = m.id)
      LOOP
        v_title := v_doc.title || ' ' || COALESCE(v_version.version_label,'') ||
                   ' — sua ' || lower(v_action_label) || ' agora e necessaria';
        v_body := 'O gate anterior foi satisfeito. Voce esta agora elegivel para ' ||
                  v_action_verb || ' no documento "' || v_doc.title || '" versao ' ||
                  COALESCE(v_version.version_label,'') ||
                  ', submetido por ' || COALESCE(v_submitter.name, 'Gerente de Projeto') ||
                  ' para ratificacao no Nucleo IA & GP. Como ' || v_role_singular || ', ' || v_action_verb || '.';
        PERFORM public.create_notification(
          v_target.member_id, v_notif_type, v_title, v_body, v_link,
          'approval_chain', p_chain_id);
        v_enqueued := v_enqueued + 1;
      END LOOP;
    END IF;

    IF v_submitter.id IS NOT NULL THEN
      v_link := '/admin/governance/documents/' || p_chain_id::text;
      v_title := v_doc.title || ' ' || COALESCE(v_version.version_label,'') ||
                 ' — gate "' || p_gate_kind || '" satisfeito';
      v_body := 'O gate "' || p_gate_kind || '" da cadeia de ratificacao do documento "' ||
                v_doc.title || '" versao ' || COALESCE(v_version.version_label,'') ||
                ' foi satisfeito. O workflow avancou automaticamente. Acompanhe o progresso dos proximos gates na plataforma.';
      PERFORM public.create_notification(
        v_submitter.id, 'ip_ratification_gate_advanced', v_title, v_body, v_link,
        'approval_chain', p_chain_id);
      v_enqueued := v_enqueued + 1;
    END IF;
    RETURN v_enqueued;
  END IF;

  IF p_event = 'chain_approved' AND v_submitter.id IS NOT NULL THEN
    v_link := '/admin/governance/documents/' || p_chain_id::text;
    v_title := v_doc.title || ' ' || COALESCE(v_version.version_label,'') ||
               ' — cadeia de ratificacao concluida';
    v_body := 'Todos os gates da cadeia de ratificacao do documento "' || v_doc.title ||
              '" versao ' || COALESCE(v_version.version_label,'') ||
              ' foram satisfeitos. O documento pode ser ativado como vigente no Nucleo IA & GP.';
    PERFORM public.create_notification(
      v_submitter.id, 'ip_ratification_chain_approved', v_title, v_body, v_link,
      'approval_chain', p_chain_id);
    RETURN 1;
  END IF;

  RETURN 0;
END;
$$


CREATE OR REPLACE FUNCTION public.admin_bulk_mark_attendance(p_event_id uuid, p_member_ids uuid[], p_present boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_count int := 0;
  v_mid uuid;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  -- V4: delegate to _can_manage_event (covers org admin + tribe-scoped leader)
  IF NOT public._can_manage_event(p_event_id) THEN
    RETURN json_build_object('success', false, 'error', 'permission_denied');
  END IF;

  IF p_present THEN
    FOREACH v_mid IN ARRAY p_member_ids LOOP
      INSERT INTO public.attendance (event_id, member_id, checked_in_at, marked_by)
      VALUES (p_event_id, v_mid, now(), v_caller_id)
      ON CONFLICT (event_id, member_id)
      DO UPDATE SET checked_in_at = now(), marked_by = v_caller_id;
      v_count := v_count + 1;
    END LOOP;
  ELSE
    FOREACH v_mid IN ARRAY p_member_ids LOOP
      DELETE FROM public.attendance WHERE event_id = p_event_id AND member_id = v_mid;
      v_count := v_count + 1;
    END LOOP;
  END IF;

  RETURN json_build_object('success', true, 'marked', v_count);
END;
$$


CREATE OR REPLACE FUNCTION public.admin_preview_campaign(p_template_id uuid, p_preview_member_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
DECLARE
  v_caller_member_id uuid;
  v_tmpl record;
  v_member record;
  v_html text;
  v_text text;
  v_subject text;
  v_lang text := 'pt';
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  -- V4 gate (replaces V3 mix of role + designation check)
  IF NOT public.can_by_member(v_caller_member_id, 'manage_comms') THEN
    RAISE EXCEPTION 'Forbidden: insufficient permissions';
  END IF;

  -- Load template
  SELECT * INTO v_tmpl FROM public.campaign_templates WHERE id = p_template_id;
  IF v_tmpl IS NULL THEN
    RAISE EXCEPTION 'Template not found';
  END IF;

  -- Load preview member (or first active member)
  IF p_preview_member_id IS NOT NULL THEN
    SELECT m.id, m.name, m.email, m.tribe_id, m.is_active, t.name AS tribe_name
    INTO v_member
    FROM public.members m
    LEFT JOIN public.tribes t ON t.id = m.tribe_id
    WHERE m.id = p_preview_member_id;
  ELSE
    SELECT m.id, m.name, m.email, m.tribe_id, m.is_active, t.name AS tribe_name
    INTO v_member
    FROM public.members m
    LEFT JOIN public.tribes t ON t.id = m.tribe_id
    WHERE m.is_active = true
    LIMIT 1;
  END IF;

  -- Log PII access (preview reads member.name + member.email)
  IF v_member.id IS NOT NULL THEN
    PERFORM public.log_pii_access(
      v_member.id,
      ARRAY['name','email']::text[],
      'admin_preview_campaign',
      'template ' || p_template_id::text
    );
  END IF;

  -- Render subject
  v_subject := COALESCE(v_tmpl.subject->>v_lang, v_tmpl.subject->>'pt', '');
  v_html := COALESCE(v_tmpl.body_html->>v_lang, v_tmpl.body_html->>'pt', '');
  v_text := COALESCE(v_tmpl.body_text->>v_lang, v_tmpl.body_text->>'pt', '');

  -- Replace variables
  v_subject := replace(v_subject, '{member.name}', COALESCE(v_member.name, 'Membro'));
  v_html := replace(v_html, '{member.name}', COALESCE(v_member.name, 'Membro'));
  v_html := replace(v_html, '{member.tribe}', COALESCE(v_member.tribe_name, ''));
  v_html := replace(v_html, '{member.chapter}', '');
  v_html := replace(v_html, '{platform.url}', 'https://ai-pm-research-hub.pages.dev');
  v_html := replace(v_html, '{unsubscribe_url}', 'https://ai-pm-research-hub.pages.dev/unsubscribe?token=preview');
  v_text := replace(v_text, '{member.name}', COALESCE(v_member.name, 'Membro'));
  v_text := replace(v_text, '{member.tribe}', COALESCE(v_member.tribe_name, ''));
  v_text := replace(v_text, '{member.chapter}', '');
  v_text := replace(v_text, '{platform.url}', 'https://ai-pm-research-hub.pages.dev');
  v_text := replace(v_text, '{unsubscribe_url}', 'https://ai-pm-research-hub.pages.dev/unsubscribe?token=preview');

  RETURN jsonb_build_object(
    'subject', v_subject,
    'html', v_html,
    'text', v_text,
    'member_name', v_member.name,
    'language', v_lang
  );
END;
$$


CREATE OR REPLACE FUNCTION public.admin_update_board_columns(p_board_id uuid, p_columns jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
DECLARE
  v_caller_id uuid;
  v_board record;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'authentication_required');
  END IF;

  SELECT * INTO v_board FROM public.project_boards WHERE id = p_board_id;
  IF v_board IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'board_not_found');
  END IF;

  -- V4 gate: org-wide manage_board_admin OR initiative-scoped
  IF NOT public.can_by_member(v_caller_id, 'manage_board_admin', 'initiative', v_board.initiative_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'permission_denied');
  END IF;

  IF jsonb_array_length(p_columns) < 2 THEN
    RETURN jsonb_build_object('success', false, 'error', 'minimum_2_columns');
  END IF;
  IF jsonb_array_length(p_columns) > 8 THEN
    RETURN jsonb_build_object('success', false, 'error', 'maximum_8_columns');
  END IF;

  UPDATE public.project_boards
  SET columns = p_columns, updated_at = now()
  WHERE id = p_board_id;

  RETURN jsonb_build_object('success', true);
END;
$$


CREATE OR REPLACE FUNCTION public.campaign_send_one_off(p_template_slug text, p_to_email text, p_variables jsonb DEFAULT '{}'::jsonb, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_template_id uuid;
  v_send_id uuid;
  v_system_sender_id uuid;
  v_recipient_lang text;
  v_service_role_key text;
  v_dispatch_request_id bigint;
BEGIN
  SELECT id INTO v_template_id FROM public.campaign_templates WHERE slug = p_template_slug;
  IF v_template_id IS NULL THEN
    RAISE EXCEPTION 'Template not found: %', p_template_slug USING ERRCODE = 'no_data_found';
  END IF;

  SELECT m.id INTO v_system_sender_id
  FROM public.members m
  WHERE public.can_by_member(m.id, 'manage_platform') = true
    AND m.is_active = true
  ORDER BY
    CASE m.operational_role
      WHEN 'manager' THEN 1
      WHEN 'gp_lead' THEN 2
      WHEN 'deputy_manager' THEN 3
      WHEN 'co_gp' THEN 4
      ELSE 99
    END,
    m.created_at
  LIMIT 1;

  IF v_system_sender_id IS NULL THEN
    RAISE EXCEPTION 'No GP-tier active member found to attribute system one-off send';
  END IF;

  v_recipient_lang := COALESCE(p_metadata->>'language', p_variables->>'lang', 'pt');

  -- Direct INSERT — variables stored in audience_filter for EF rendering
  INSERT INTO public.campaign_sends (
    id, template_id, sent_by, audience_filter, status, recipient_count, scheduled_at
  ) VALUES (
    gen_random_uuid(),
    v_template_id,
    v_system_sender_id,
    jsonb_build_object(
      'type', 'transactional',
      'one_off', true,
      'source', COALESCE(p_metadata->>'source', 'system'),
      'variables', p_variables
    ),
    'pending_delivery',
    1,
    NULL
  )
  RETURNING id INTO v_send_id;

  INSERT INTO public.campaign_recipients (
    send_id, external_email, external_name, language
  ) VALUES (
    v_send_id,
    p_to_email,
    p_metadata->>'recipient_name',
    v_recipient_lang
  );

  -- Async dispatch: invoke send-campaign EF (handles Resend delivery)
  -- If dispatch fails, the row stays pending_delivery and can be retried.
  BEGIN
    SELECT decrypted_secret INTO v_service_role_key
    FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

    IF v_service_role_key IS NOT NULL THEN
      SELECT net.http_post(
        url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/send-campaign',
        body := jsonb_build_object('send_id', v_send_id),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_service_role_key
        )
      ) INTO v_dispatch_request_id;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'send-campaign EF dispatch failed: % (send_id=%)', SQLERRM, v_send_id;
  END;

  RETURN jsonb_build_object(
    'send_id', v_send_id,
    'system_sender_id', v_system_sender_id,
    'template_slug', p_template_slug,
    'to_email', p_to_email,
    'status', 'pending_delivery',
    'mode', 'one_off_transactional',
    'dispatch_request_id', v_dispatch_request_id
  );
END;
$$


CREATE OR REPLACE FUNCTION public.exec_all_tribes_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_cycle_start date;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  -- ADR-0042: V4 catalog (manage_platform writes; view_chapter_dashboards reads)
  IF NOT (public.can_by_member(v_caller_id, 'manage_platform')
          OR public.can_by_member(v_caller_id, 'view_chapter_dashboards')) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform or view_chapter_dashboards permission';
  END IF;

  v_cycle_start := COALESCE(
    (SELECT MIN(date) FROM public.events
     WHERE title ILIKE '%kick%off%' AND date >= '2026-01-01'),
    '2026-03-05'::date
  );

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'tribe_id', t.id,
      'name', t.name,
      'quadrant', t.quadrant,
      'member_count', (SELECT COUNT(*) FROM public.members WHERE tribe_id = t.id AND is_active = true),
      'attendance_rate', COALESCE(
        (SELECT ROUND(
          COUNT(*) FILTER (WHERE a.present = true)::numeric /
          NULLIF(COUNT(*), 0), 2
        ) FROM public.attendance a
        JOIN public.events e ON e.id = a.event_id
        JOIN public.initiatives i2 ON i2.id = e.initiative_id
        WHERE i2.legacy_tribe_id = t.id AND e.date >= v_cycle_start),
        0
      ),
      'articles_count', COALESCE(
        (SELECT COUNT(*) FROM public.board_items bi
         JOIN public.project_boards pb ON pb.id = bi.board_id
         JOIN public.initiatives i3 ON i3.id = pb.initiative_id
         WHERE i3.legacy_tribe_id = t.id AND bi.curation_status IN ('submitted', 'approved', 'published')),
        0
      ),
      'xp_total', COALESCE(
        (SELECT SUM(gp.points) FROM public.gamification_points gp
         WHERE gp.member_id IN (SELECT id FROM public.members WHERE tribe_id = t.id AND is_active = true)),
        0
      ),
      'leader_name', (SELECT name FROM public.members WHERE id = t.leader_member_id)
    ) ORDER BY t.id
  ), '[]'::jsonb) INTO v_result
  FROM public.tribes t
  WHERE t.is_active = true AND t.workstream_type = 'research';

  RETURN v_result;
END;
$$


CREATE OR REPLACE FUNCTION public.export_audit_log_csv(p_category text DEFAULT 'all'::text, p_start_date text DEFAULT NULL::text, p_end_date text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_csv text;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN 'Unauthorized'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_pii') THEN
    RETURN 'Unauthorized: requires view_pii permission';
  END IF;

  SELECT string_agg(
    category||','||to_char(event_date,'YYYY-MM-DD HH24:MI')||','||
    COALESCE(replace(actor_name,',',';'),'')||','||
    COALESCE(replace(action,',',';'),'')||','||
    COALESCE(replace(subject,',',';'),'')||','||
    COALESCE(replace(summary,',',';'),'')||','||
    COALESCE(replace(detail,',',';'),''),
    E'\n'
  ) INTO v_csv
  FROM (
    SELECT
      'members' AS category,
      al.created_at AS event_date,
      actor.name AS actor_name,
      CASE al.action
        WHEN 'member.status_transition' THEN 'status_change'
        WHEN 'member.role_change' THEN 'role_change'
        ELSE al.action
      END AS action,
      target.name AS subject,
      CASE al.action
        WHEN 'member.status_transition' THEN
          COALESCE(al.changes->>'previous_status','') || ' → ' || COALESCE(al.changes->>'new_status','')
        WHEN 'member.role_change' THEN
          COALESCE(al.changes->>'old_value','') || ' → ' || COALESCE(al.changes->>'new_value','')
        ELSE al.changes::text
      END AS summary,
      COALESCE(al.metadata->>'reason_detail', al.metadata->>'reason') AS detail
    FROM public.admin_audit_log al
    LEFT JOIN public.members actor  ON actor.id  = al.actor_id
    LEFT JOIN public.members target ON target.id = al.target_id
    WHERE (p_category = 'all' OR p_category = 'members')
      AND al.action IN ('member.status_transition','member.role_change')
      AND (p_start_date IS NULL OR al.created_at >= p_start_date::timestamptz)
      AND (p_end_date   IS NULL OR al.created_at <= (p_end_date::date + 1)::timestamptz)
    UNION ALL
    SELECT
      'settings', al.created_at, actor.name, 'setting_changed',
      COALESCE(al.metadata->>'setting_key', '(unknown)'),
      COALESCE(al.changes->>'previous_value','?') || ' → ' || COALESCE(al.changes->>'new_value','?'),
      al.metadata->>'reason'
    FROM public.admin_audit_log al
    LEFT JOIN public.members actor ON actor.id = al.actor_id
    WHERE (p_category='all' OR p_category='settings')
      AND al.action = 'platform.setting_changed'
      AND (p_start_date IS NULL OR al.created_at >= p_start_date::timestamptz)
      AND (p_end_date   IS NULL OR al.created_at <= (p_end_date::date + 1)::timestamptz)
    UNION ALL
    SELECT
      'partnerships', pi.created_at, actor.name, pi.interaction_type, pe.name,
      pi.summary, pi.outcome
    FROM public.partner_interactions pi
    JOIN public.partner_entities pe ON pe.id = pi.partner_id
    LEFT JOIN public.members actor ON actor.id = pi.actor_member_id
    WHERE (p_category='all' OR p_category='partnerships')
      AND (p_start_date IS NULL OR pi.created_at >= p_start_date::timestamptz)
      AND (p_end_date   IS NULL OR pi.created_at <= (p_end_date::date + 1)::timestamptz)
    ORDER BY event_date DESC
  ) entries;

  RETURN 'Categoria,Data,Actor,Ação,Assunto,Resumo,Detalhe' || E'\n' || COALESCE(v_csv,'');
END;
$$


CREATE OR REPLACE FUNCTION public.get_application_pmi_profile(p_application_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller record;
  v_app record;
  v_in_committee boolean;
  v_referrer_name text;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found: %', p_application_id;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.selection_committee
    WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id
  ) INTO v_in_committee;

  IF NOT v_in_committee AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: requires committee membership or manage_platform';
  END IF;

  PERFORM public._log_application_pii_access(
    p_application_id,
    v_caller.id,
    ARRAY['pmi_id','profile_about_me','profile_company','profile_linkedin_url','pmi_memberships','service_history','referrer_member_id'],
    'get_application_pmi_profile'
  );

  IF v_app.referrer_member_id IS NOT NULL THEN
    SELECT name INTO v_referrer_name FROM public.members WHERE id = v_app.referrer_member_id;
  END IF;

  RETURN jsonb_build_object(
    'identity', jsonb_build_object(
      'pmi_id', v_app.pmi_id,
      'is_pmi_member', (v_app.pmi_id IS NOT NULL AND v_app.pmi_id <> ''),
      'member_status', CASE
        WHEN v_app.pmi_id IS NULL OR v_app.pmi_id = '' THEN 'unknown'
        WHEN v_app.service_latest_end_date IS NULL THEN 'unknown'
        WHEN v_app.service_latest_end_date >= CURRENT_DATE THEN 'active'
        ELSE 'past'
      END,
      'member_since', v_app.service_first_start_date,
      'member_until', v_app.service_latest_end_date,
      'service_history_count', COALESCE(v_app.service_history_count, 0),
      'phase_b_fetched_at', v_app.pmi_data_fetched_at,
      'community_profile_private', v_app.community_profile_private
    ),
    'chapters', jsonb_build_object(
      'memberships', COALESCE(v_app.pmi_memberships, '[]'::jsonb),
      'service_history_chapters', v_app.service_history_chapters,
      'form_chapter', v_app.chapter,
      'chapter_affiliation', v_app.chapter_affiliation
    ),
    'certifications', jsonb_build_object(
      'verified', COALESCE(to_jsonb(v_app.profile_certifications), '[]'::jsonb),
      'form_declared', v_app.certifications
    ),
    'profile', jsonb_build_object(
      'industry', v_app.profile_industry,
      'company', v_app.profile_company,
      'designation', v_app.profile_designation,
      'about_me', v_app.profile_about_me,
      'linkedin_url', v_app.profile_linkedin_url,
      'specialties', v_app.profile_specialties,
      'volunteer_interest', v_app.profile_volunteer_interest,
      'location', v_app.profile_location,
      'city', v_app.profile_city,
      'state', v_app.profile_state,
      'country', v_app.profile_country,
      'is_open_to_volunteer', v_app.is_open_to_volunteer
    ),
    'service_history', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'chapter_name', sh.chapter_name,
        'role_name', sh.role_name,
        'start_date', sh.start_date,
        'end_date', sh.end_date,
        'source', sh.source
      ) ORDER BY sh.start_date DESC NULLS LAST)
      FROM public.selection_application_service_history sh
      WHERE sh.application_id = p_application_id
    ), '[]'::jsonb),
    'previous_cycles', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'application_id', pa.id,
        'cycle_code', pc.cycle_code,
        'role_applied', pa.role_applied,
        'status', pa.status,
        'final_score', pa.final_score,
        'application_date', pa.application_date,
        'rank_chapter', pa.rank_chapter,
        'rank_overall', pa.rank_overall
      ) ORDER BY pa.application_date DESC NULLS LAST)
      FROM public.selection_applications pa
      JOIN public.selection_cycles pc ON pc.id = pa.cycle_id
      WHERE lower(pa.email) = lower(v_app.email)
        AND pa.cycle_id <> v_app.cycle_id
        AND pa.id <> p_application_id
    ), '[]'::jsonb),
    -- p152 W4 OPP-152.7-lite: sibling applications (same email + SAME cycle, different role/application)
    'sibling_applications', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'application_id', sa.id,
        'role_applied', sa.role_applied,
        'status', sa.status,
        'objective_score_avg', sa.objective_score_avg,
        'final_score', sa.final_score,
        'rank_chapter', sa.rank_chapter,
        'rank_overall', sa.rank_overall,
        'interview_count', (SELECT count(*)::int FROM public.selection_interviews si WHERE si.application_id = sa.id),
        'application_date', sa.application_date
      ) ORDER BY sa.application_date DESC NULLS LAST)
      FROM public.selection_applications sa
      WHERE lower(sa.email) = lower(v_app.email)
        AND sa.cycle_id = v_app.cycle_id
        AND sa.id <> p_application_id
    ), '[]'::jsonb),
    'non_pmi_volunteering', v_app.non_pmi_experience,
    'funnel', jsonb_build_object(
      'referral_source', v_app.referral_source,
      'referrer_member_id', v_app.referrer_member_id,
      'referrer_member_name', v_referrer_name,
      'utm_data', v_app.utm_data,
      'imported_at', v_app.imported_at,
      'vep_application_id', v_app.vep_application_id,
      'vep_opportunity_id', v_app.vep_opportunity_id
    )
  );
END;
$$


CREATE OR REPLACE FUNCTION public.get_cycle_report(p_cycle integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  v_result := jsonb_build_object(
    'cycle', p_cycle,
    'generated_at', now(),
    'members', (SELECT jsonb_build_object(
      'total', count(*),
      'active', count(*) FILTER (WHERE is_active),
      'observers', count(*) FILTER (WHERE member_status = 'observer'),
      'alumni', count(*) FILTER (WHERE member_status = 'alumni'),
      'by_role', (SELECT coalesce(jsonb_object_agg(operational_role, cnt), '{}') FROM (SELECT operational_role, count(*) as cnt FROM public.members WHERE is_active GROUP BY operational_role) r)
    ) FROM public.members),
    'tribes', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id, 'name', t.name,
      'member_count', (SELECT count(*) FROM public.members WHERE tribe_id = t.id AND is_active),
      'board_progress', (SELECT CASE WHEN count(*) = 0 THEN 0 ELSE round(100.0 * count(*) FILTER (WHERE bi.status = 'done') / count(*)) END FROM public.project_boards pb JOIN public.initiatives i ON i.id = pb.initiative_id JOIN public.board_items bi ON bi.board_id = pb.id WHERE i.legacy_tribe_id = t.id AND bi.status != 'archived')
    ) ORDER BY t.id), '[]') FROM public.tribes t WHERE t.is_active),
    'events', (SELECT jsonb_build_object(
      'total', count(*),
      'total_impact_hours', (SELECT * FROM public.get_homepage_stats())->'impact_hours'
    ) FROM public.events WHERE date >= '2026-01-01'),
    'boards', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', pb.id, 'title', pb.board_name,
      'total_items', (SELECT count(*) FROM public.board_items WHERE board_id = pb.id AND status != 'archived'),
      'done_items', (SELECT count(*) FROM public.board_items WHERE board_id = pb.id AND status = 'done'),
      'progress', (SELECT CASE WHEN count(*) = 0 THEN 0 ELSE round(100.0 * count(*) FILTER (WHERE status = 'done') / count(*)) END FROM public.board_items WHERE board_id = pb.id AND status != 'archived')
    )), '[]') FROM public.project_boards pb WHERE pb.is_active),
    'kpis', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'name', k.kpi_label_pt, 'name_en', k.kpi_label_en,
      'target', k.target_value, 'current', k.current_value,
      'pct', CASE WHEN k.target_value > 0 THEN round(100.0 * k.current_value / k.target_value) ELSE 0 END
    )), '[]') FROM public.annual_kpi_targets k WHERE k.year = 2026),
    'platform', jsonb_build_object(
      'releases_count', (SELECT count(*) FROM public.releases),
      'governance_entries', 125,
      'zero_cost', true,
      'stack', 'Astro 5 + React 19 + Tailwind 4 + Supabase + Cloudflare Pages'
    )
  );
  RETURN v_result;
END;
$$


CREATE OR REPLACE FUNCTION public.get_dropout_risk_members(p_threshold integer DEFAULT 3)
 RETURNS TABLE(member_id uuid, member_name text, tribe_id integer, tribe_name text, operational_role text, last_attendance_date date, days_since_last bigint, missed_events integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $$
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
    SELECT m.id, m.name, m.tribe_id, t.name as tname, m.operational_role
    FROM public.members m
    LEFT JOIN public.tribes t ON t.id = m.tribe_id
    WHERE m.is_active AND m.operational_role IN ('researcher','tribe_leader','manager')
  ),
  member_expected_events AS (
    SELECT am.id as mid, e.id as eid, e.date,
      ROW_NUMBER() OVER (PARTITION BY am.id ORDER BY e.date DESC) as rn
    FROM active_members am
    CROSS JOIN LATERAL (
      SELECT e2.id, e2.date FROM public.events e2
      LEFT JOIN public.initiatives ini ON ini.id = e2.initiative_id
      WHERE e2.date <= current_date
        AND (
          e2.type IN ('general_meeting','kickoff')
          OR (e2.type = 'tribe_meeting' AND ini.legacy_tribe_id = am.tribe_id)
          OR (e2.type = 'leadership_meeting' AND am.operational_role IN ('manager','tribe_leader'))
        )
      ORDER BY e2.date DESC
      LIMIT p_threshold
    ) e
  ),
  member_misses AS (
    SELECT mee.mid,
      count(*) FILTER (WHERE a.id IS NULL) as missed,
      count(*) as expected
    FROM member_expected_events mee
    LEFT JOIN public.attendance a ON a.event_id = mee.eid AND a.member_id = mee.mid AND a.present
    WHERE mee.rn <= p_threshold
    GROUP BY mee.mid
  ),
  last_att AS (
    SELECT a.member_id as mid, max(e.date) as last_date
    FROM public.attendance a JOIN public.events e ON e.id = a.event_id
    WHERE a.present
    GROUP BY a.member_id
  )
  SELECT am.id, am.name, am.tribe_id, am.tname, am.operational_role,
    la.last_date,
    (current_date - COALESCE(la.last_date, '2025-01-01'))::bigint,
    mm.missed::integer
  FROM active_members am
  JOIN member_misses mm ON mm.mid = am.id
  LEFT JOIN last_att la ON la.mid = am.id
  WHERE mm.missed >= p_threshold
  ORDER BY la.last_date ASC NULLS FIRST;
END;
$$


CREATE OR REPLACE FUNCTION public.get_gamification_leaderboard(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_cycle_code text DEFAULT NULL::text, p_scope_kind text DEFAULT 'global'::text, p_chapter_code text DEFAULT NULL::text, p_initiative_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(member_id uuid, name text, chapter text, photo_url text, operational_role text, designations text[], total_points integer, attendance_points integer, learning_points integer, cert_points integer, badge_points integer, artifact_points integer, course_points integer, showcase_points integer, bonus_points integer, producao_points integer, curadoria_points integer, champions_points integer, cycle_points integer, cycle_attendance_points integer, cycle_course_points integer, cycle_artifact_points integer, cycle_showcase_points integer, cycle_bonus_points integer, cycle_learning_points integer, cycle_cert_points integer, cycle_badge_points integer, cycle_producao_points integer, cycle_curadoria_points integer, cycle_champions_points integer, total_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid; v_cycle_start date; v_cycle_end date; v_total_count int;
  v_effective_limit int; v_effective_offset int; v_scope text;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege'; END IF;
  v_effective_limit := GREATEST(1, LEAST(COALESCE(p_limit, 50), 200));
  v_effective_offset := GREATEST(0, COALESCE(p_offset, 0));
  v_scope := COALESCE(NULLIF(trim(p_scope_kind), ''), 'global');
  IF v_scope NOT IN ('global', 'chapter', 'tribe') THEN
    RAISE EXCEPTION 'invalid_scope_kind: % (allowed: global|chapter|tribe)', v_scope USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_scope = 'chapter' AND (p_chapter_code IS NULL OR trim(p_chapter_code) = '') THEN
    RAISE EXCEPTION 'chapter_code_required' USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_scope = 'tribe' AND p_initiative_id IS NULL THEN
    RAISE EXCEPTION 'initiative_id_required' USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF p_cycle_code IS NOT NULL THEN
    SELECT c.cycle_start, c.cycle_end INTO v_cycle_start, v_cycle_end FROM public.cycles c WHERE c.cycle_code = p_cycle_code;
    IF v_cycle_start IS NULL THEN RAISE EXCEPTION 'cycle_not_found: %', p_cycle_code USING ERRCODE = 'no_data_found'; END IF;
  ELSE
    SELECT c.cycle_start, c.cycle_end INTO v_cycle_start, v_cycle_end FROM public.cycles c WHERE c.is_current = true LIMIT 1;
  END IF;

  SELECT COUNT(*) INTO v_total_count FROM public.members m
  WHERE m.gamification_opt_out = false
    AND (m.current_cycle_active = true
         OR EXISTS (SELECT 1 FROM public.gamification_points gp_check
                    WHERE gp_check.member_id = m.id
                      AND gp_check.created_at >= v_cycle_start
                      AND (v_cycle_end IS NULL OR gp_check.created_at < (v_cycle_end + INTERVAL '1 day'))))
    AND (v_scope = 'global'
         OR (v_scope = 'chapter' AND m.chapter = p_chapter_code)
         OR (v_scope = 'tribe' AND EXISTS (
             SELECT 1 FROM public.persons p JOIN public.auth_engagements ae ON ae.person_id = p.id
             WHERE p.legacy_member_id = m.id AND ae.is_authoritative = true AND ae.initiative_id = p_initiative_id)));

  RETURN QUERY
  SELECT m.id, m.name, m.chapter, m.photo_url, m.operational_role, m.designations,
    COALESCE(sum(gp.points), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'presenca'), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'trilha'), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'certificacoes' AND gr.slug LIKE 'cert_%'), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.slug = 'badge'), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.slug = 'artifact_published'), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'trilha'), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.slug LIKE 'showcase%'), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar IS NULL OR gr.pillar NOT IN ('presenca','trilha','certificacoes','producao','curadoria','champions')), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'producao' AND gr.slug <> 'artifact_published' AND gr.slug NOT LIKE 'showcase%'), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'curadoria'), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'champions'), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gp.created_at >= v_cycle_start AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'presenca' AND gp.created_at >= v_cycle_start AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'trilha' AND gp.created_at >= v_cycle_start AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.slug = 'artifact_published' AND gp.created_at >= v_cycle_start AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.slug LIKE 'showcase%' AND gp.created_at >= v_cycle_start AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE (gr.pillar IS NULL OR gr.pillar NOT IN ('presenca','trilha','certificacoes','producao','curadoria','champions')) AND gp.created_at >= v_cycle_start AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'trilha' AND gp.created_at >= v_cycle_start AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'certificacoes' AND gr.slug LIKE 'cert_%' AND gp.created_at >= v_cycle_start AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.slug = 'badge' AND gp.created_at >= v_cycle_start AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'producao' AND gr.slug <> 'artifact_published' AND gr.slug NOT LIKE 'showcase%' AND gp.created_at >= v_cycle_start AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'curadoria' AND gp.created_at >= v_cycle_start AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'champions' AND gp.created_at >= v_cycle_start AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer,
    v_total_count
  FROM public.members m
    LEFT JOIN public.gamification_points gp ON gp.member_id = m.id
    LEFT JOIN public.gamification_rules gr ON gr.organization_id = gp.organization_id AND gr.slug = gp.category
  WHERE m.gamification_opt_out = false
    AND (m.current_cycle_active = true
         OR EXISTS (SELECT 1 FROM public.gamification_points gp_check
                    WHERE gp_check.member_id = m.id
                      AND gp_check.created_at >= v_cycle_start
                      AND (v_cycle_end IS NULL OR gp_check.created_at < (v_cycle_end + INTERVAL '1 day'))))
    AND (v_scope = 'global'
         OR (v_scope = 'chapter' AND m.chapter = p_chapter_code)
         OR (v_scope = 'tribe' AND EXISTS (
             SELECT 1 FROM public.persons p JOIN public.auth_engagements ae ON ae.person_id = p.id
             WHERE p.legacy_member_id = m.id AND ae.is_authoritative = true AND ae.initiative_id = p_initiative_id)))
  GROUP BY m.id, m.name, m.chapter, m.photo_url, m.operational_role, m.designations
  ORDER BY total_points DESC, m.name ASC
  LIMIT v_effective_limit OFFSET v_effective_offset;
END;
$$


CREATE OR REPLACE FUNCTION public.get_invariant_alerts()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id   uuid;
  v_alerts      jsonb := '[]'::jsonb;
  v_violation   record;
  v_first_seen  timestamptz;
  v_age_hours   numeric;
  v_existing    int;
  v_current_invariant_names text[];
  v_open_baseline record;
BEGIN
  SELECT id INTO v_caller_id FROM public.members
   WHERE auth_id = (SELECT auth.uid())
     AND (is_superadmin = true OR operational_role IN ('manager','deputy_manager'))
   LIMIT 1;

  IF v_caller_id IS NULL AND (SELECT auth.role()) <> 'service_role' THEN
    RAISE EXCEPTION 'get_invariant_alerts: admin only';
  END IF;

  SELECT COALESCE(array_agg(invariant_name), ARRAY[]::text[])
    INTO v_current_invariant_names
    FROM public.check_schema_invariants()
   WHERE violation_count > 0;

  FOR v_violation IN
    SELECT invariant_name, description, severity, violation_count, sample_ids
      FROM public.check_schema_invariants()
     WHERE violation_count > 0
     ORDER BY (CASE severity WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END),
              invariant_name
  LOOP
    SELECT min(al.created_at) INTO v_first_seen
      FROM public.admin_audit_log al
     WHERE al.action = 'security_incident.invariant_drift.detected'
       AND al.changes->>'invariant_name' = v_violation.invariant_name
       AND NOT EXISTS (
         SELECT 1 FROM public.admin_audit_log al2
          WHERE al2.action = 'security_incident.invariant_drift.cleared'
            AND al2.changes->>'invariant_name' = v_violation.invariant_name
            AND al2.created_at > al.created_at
       );

    IF v_first_seen IS NULL THEN
      SELECT count(*) INTO v_existing FROM public.admin_audit_log
       WHERE action = 'security_incident.invariant_drift.detected'
         AND changes->>'invariant_name' = v_violation.invariant_name
         AND created_at > now() - interval '1 hour';

      IF v_existing = 0 THEN
        INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, changes, metadata)
        VALUES (
          v_caller_id,
          'security_incident.invariant_drift.detected',
          'invariant',
          NULL,
          jsonb_build_object(
            'invariant_name', v_violation.invariant_name,
            'description',    v_violation.description,
            'severity',       v_violation.severity,
            'violation_count', v_violation.violation_count,
            'sample_ids',     to_jsonb(v_violation.sample_ids),
            'summary',        format('Drift detected: %s (%s violations)', v_violation.invariant_name, v_violation.violation_count)
          ),
          jsonb_build_object(
            'severity',     CASE v_violation.severity WHEN 'critical' THEN 'p0' WHEN 'high' THEN 'p1' WHEN 'medium' THEN 'p2' ELSE 'p3' END,
            'status',       'open',
            'incident_id',  gen_random_uuid(),
            'auto_detected', true,
            'via',          'get_invariant_alerts'
          )
        );
        v_first_seen := now();
      END IF;
    END IF;

    v_age_hours := EXTRACT(EPOCH FROM (now() - v_first_seen)) / 3600.0;

    v_alerts := v_alerts || jsonb_build_object(
      'invariant_name',  v_violation.invariant_name,
      'description',     v_violation.description,
      'severity',        v_violation.severity,
      'violation_count', v_violation.violation_count,
      'sample_ids',      to_jsonb(v_violation.sample_ids),
      'first_seen_at',   v_first_seen,
      'age_hours',       round(v_age_hours, 2),
      'persistent',      (v_age_hours >= 24)
    );
  END LOOP;

  FOR v_open_baseline IN
    SELECT DISTINCT
      al.changes->>'invariant_name' AS invariant_name,
      al.changes->>'severity'       AS severity,
      al.metadata->>'incident_id'   AS incident_id,
      MIN(al.created_at) OVER (PARTITION BY al.changes->>'invariant_name') AS first_seen_at
    FROM public.admin_audit_log al
    WHERE al.action = 'security_incident.invariant_drift.detected'
      AND NOT EXISTS (
        SELECT 1 FROM public.admin_audit_log al2
         WHERE al2.action = 'security_incident.invariant_drift.cleared'
           AND al2.changes->>'invariant_name' = al.changes->>'invariant_name'
           AND al2.created_at > al.created_at
      )
      AND NOT (al.changes->>'invariant_name' = ANY(v_current_invariant_names))
  LOOP
    INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      v_caller_id,
      'security_incident.invariant_drift.cleared',
      'invariant',
      NULL,
      jsonb_build_object(
        'invariant_name', v_open_baseline.invariant_name,
        'severity',       v_open_baseline.severity,
        'summary',        format('Drift cleared: %s now has 0 violations', v_open_baseline.invariant_name),
        'first_seen_at',  v_open_baseline.first_seen_at,
        'duration_hours', round(EXTRACT(EPOCH FROM (now() - v_open_baseline.first_seen_at)) / 3600.0, 2)
      ),
      jsonb_build_object(
        'status',        'cleared',
        'auto_cleared',  true,
        'via',           'get_invariant_alerts',
        'incident_id',   v_open_baseline.incident_id
      )
    );
  END LOOP;

  RETURN jsonb_build_object(
    'alerts',          v_alerts,
    'alert_count',     jsonb_array_length(v_alerts),
    'has_persistent',  EXISTS (SELECT 1 FROM jsonb_array_elements(v_alerts) e WHERE (e->>'persistent')::boolean),
    'checked_at',      now()
  );
END;
$$


CREATE OR REPLACE FUNCTION public.get_kpi_dashboard(p_cycle_start date DEFAULT '2026-01-01'::date, p_cycle_end date DEFAULT '2026-06-30'::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  result jsonb;
  days_elapsed numeric;
  days_total numeric;
  linear_pct numeric;
  v_target RECORD;
BEGIN
  days_elapsed := GREATEST(current_date - p_cycle_start, 0);
  days_total := p_cycle_end - p_cycle_start;
  linear_pct := CASE WHEN days_total > 0 THEN round(days_elapsed / days_total * 100, 1) ELSE 0 END;

  SELECT jsonb_build_object(
    'cycle_pct', linear_pct,
    'kpis', jsonb_build_array(
      jsonb_build_object(
        'name', 'Horas de Impacto',
        'current', COALESCE((
          SELECT round(sum(COALESCE(e.duration_actual, e.duration_minutes, 60)::numeric
            * (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present)) / 60)
          FROM events e WHERE e.date BETWEEN p_cycle_start AND p_cycle_end), 0),
        'target', 1800, 'unit', 'h', 'icon', 'clock'),
      jsonb_build_object(
        'name', 'Certificação CPMAI',
        'current', (SELECT count(*) FROM members WHERE is_active AND cpmai_certified = true),
        'target', COALESCE((SELECT target_value::int FROM annual_kpi_targets WHERE kpi_key = 'cpmai_certified' AND year = 2026), 5),
        'unit', 'membros', 'icon', 'award'),
      jsonb_build_object(
        'name', 'Pilotos de IA',
        'current', COALESCE((SELECT (value)::int FROM site_config WHERE key = 'kpi_pilot_count_override'), 0),
        'target', COALESCE((SELECT target_value::int FROM annual_kpi_targets WHERE kpi_key = 'pilots_completed' AND year = 2026), 3),
        'unit', '', 'icon', 'rocket'),
      jsonb_build_object(
        'name', 'Artigos Publicados',
        'current', (SELECT count(*) FROM board_items bi JOIN project_boards pb ON pb.id = bi.board_id
          WHERE pb.board_name ILIKE '%publica%' AND bi.status IN ('done','published')),
        'target', COALESCE((SELECT target_value::int FROM annual_kpi_targets WHERE kpi_key = 'publications_submitted' AND year = 2026), 10),
        'unit', '', 'icon', 'file-text'),
      jsonb_build_object(
        'name', 'Webinars Realizados',
        'current', (SELECT count(*) FROM events WHERE type = 'webinar' AND date BETWEEN p_cycle_start AND p_cycle_end),
        'target', COALESCE((SELECT target_value::int FROM annual_kpi_targets WHERE kpi_key = 'webinars_realized' AND year = 2026), 6),
        'unit', '', 'icon', 'video'),
      jsonb_build_object(
        'name', 'Capítulos Integrados',
        'current', (SELECT count(DISTINCT chapter) FROM members WHERE is_active AND chapter IS NOT NULL),
        'target', COALESCE((SELECT target_value::int FROM annual_kpi_targets WHERE kpi_key = 'chapters_participating' AND year = 2026), 8),
        'unit', '', 'icon', 'map-pin')
    )
  ) INTO result;
  RETURN result;
END;
$$


CREATE OR REPLACE FUNCTION public.get_ratification_reminder_targets(p_document_id uuid)
 RETURNS TABLE(target_type text, member_id uuid, person_id uuid, name text, email text, expected_gate_kind text, chain_id uuid, version_label text, days_since_chain_opened integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid; v_current_version uuid; v_chain_id uuid;
  v_chain_opened_at timestamptz; v_chain_gates jsonb;
  v_version_label text; v_member_gate_kind text;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Access denied: requires manage_member' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT current_version_id INTO v_current_version
  FROM public.governance_documents WHERE id = p_document_id;
  IF v_current_version IS NULL THEN RETURN; END IF;

  SELECT dv.version_label INTO v_version_label
  FROM public.document_versions dv WHERE dv.id = v_current_version;

  SELECT ac.id, ac.opened_at, ac.gates
    INTO v_chain_id, v_chain_opened_at, v_chain_gates
  FROM public.approval_chains ac
  WHERE ac.document_id = p_document_id
    AND ac.version_id = v_current_version
    AND ac.status IN ('review', 'approved')
  ORDER BY ac.opened_at DESC NULLS LAST LIMIT 1;

  IF v_chain_id IS NULL THEN RETURN; END IF;

  SELECT g->>'kind' INTO v_member_gate_kind
  FROM jsonb_array_elements(v_chain_gates) g
  WHERE g->>'kind' IN ('volunteers_in_role_active','member_ratification')
  LIMIT 1;

  IF v_member_gate_kind IS NOT NULL THEN
    RETURN QUERY
    SELECT 'member_pending_ratification'::text,
      m.id, m.person_id, m.name, m.email,
      v_member_gate_kind::text, v_chain_id, v_version_label,
      GREATEST(0, EXTRACT(day FROM (now() - v_chain_opened_at))::int)
    FROM public.members m
    WHERE public._can_sign_gate(m.id, v_chain_id, v_member_gate_kind)
      AND NOT EXISTS (SELECT 1 FROM public.member_document_signatures mds
        WHERE mds.member_id = m.id AND mds.signed_version_id = v_current_version);
  END IF;

  RETURN QUERY
  SELECT 'external_signer_pending'::text,
    m.id, m.person_id, m.name, m.email,
    COALESCE(ae.role, 'external_signer')::text,
    v_chain_id, v_version_label,
    GREATEST(0, EXTRACT(day FROM (now() - v_chain_opened_at))::int)
  FROM public.members m
  JOIN public.auth_engagements ae ON ae.person_id = m.person_id
  WHERE m.operational_role = 'external_signer'
    AND ae.kind = 'external_signer' AND ae.status = 'active'
    AND ae.is_authoritative = true
    AND NOT EXISTS (SELECT 1 FROM public.approval_signoffs s
      WHERE s.approval_chain_id = v_chain_id AND s.signer_id = m.id)
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_chain_gates) g
      WHERE g->>'kind' = COALESCE(ae.role, 'external_signer'));
END;
$$


CREATE OR REPLACE FUNCTION public.get_weekly_member_digest(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $$
DECLARE
  v_caller_id uuid;
  v_is_self boolean;
  v_member_tribe_id integer;
  v_window_start timestamptz := date_trunc('day', now()) - interval '7 days';
  v_extended_window timestamptz := date_trunc('day', now()) - interval '14 days';
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  v_is_self := (v_caller_id = p_member_id);

  IF NOT v_is_self AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: can only read own digest or requires manage_member permission';
  END IF;

  SELECT tribe_id INTO v_member_tribe_id FROM public.members WHERE id = p_member_id;

  SELECT jsonb_build_object(
    'member_id', p_member_id,
    'generated_at', now(),
    'window_start', v_window_start,
    'sections', jsonb_build_object(
      'cards', jsonb_build_object(
        'this_week_pending', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', bi.id, 'title', bi.title, 'status', bi.status,
            'due_date', bi.due_date, 'board_name', pb.board_name,
            'initiative_title', i.title,
            'days_overdue', GREATEST(0, CURRENT_DATE - bi.due_date)
          ) ORDER BY bi.due_date ASC)
          FROM public.board_items bi
          LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
          LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
          WHERE bi.assignee_id = p_member_id
            AND bi.status NOT IN ('done', 'archived')
            AND bi.due_date BETWEEN CURRENT_DATE - INTERVAL '7 days' AND CURRENT_DATE
        ), '[]'::jsonb),
        'next_week_due', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', bi.id, 'title', bi.title, 'status', bi.status,
            'due_date', bi.due_date, 'board_name', pb.board_name,
            'initiative_title', i.title
          ) ORDER BY bi.due_date ASC)
          FROM public.board_items bi
          LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
          LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
          WHERE bi.assignee_id = p_member_id
            AND bi.status NOT IN ('done', 'archived')
            AND bi.due_date > CURRENT_DATE
            AND bi.due_date <= CURRENT_DATE + INTERVAL '7 days'
        ), '[]'::jsonb),
        'overdue_7plus', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', bi.id, 'title', bi.title, 'status', bi.status,
            'due_date', bi.due_date, 'board_name', pb.board_name,
            'initiative_title', i.title,
            'days_overdue', CURRENT_DATE - bi.due_date
          ) ORDER BY bi.due_date ASC)
          FROM public.board_items bi
          LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
          LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
          WHERE bi.assignee_id = p_member_id
            AND bi.status NOT IN ('done', 'archived')
            AND bi.due_date < CURRENT_DATE - INTERVAL '7 days'
        ), '[]'::jsonb),
        -- NEW p95 #99 1B: assignment_new notifications shown in cards section
        'new_assignments', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', n.id, 'title', n.title, 'body', n.body,
            'created_at', n.created_at, 'link', n.link
          ) ORDER BY n.created_at DESC)
          FROM public.notifications n
          WHERE n.recipient_id = p_member_id
            AND n.delivery_mode = 'digest_weekly'
            AND n.digest_delivered_at IS NULL
            AND n.type = 'assignment_new'
            AND n.created_at >= v_extended_window
        ), '[]'::jsonb)
      ),

      'engagements_new', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', n.id, 'type', n.type, 'title', n.title,
          'created_at', n.created_at,
          'source_type', n.source_type, 'source_id', n.source_id,
          'link', n.link
        ) ORDER BY n.created_at DESC)
        FROM public.notifications n
        WHERE n.recipient_id = p_member_id
          AND n.delivery_mode = 'digest_weekly'
          AND n.digest_delivered_at IS NULL
          AND n.type IN ('engagement_welcome', 'engagement_added', 'volunteer_agreement_signed')
          AND n.created_at >= v_window_start
      ), '[]'::jsonb),

      'events_upcoming', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', e.id, 'title', e.title, 'date', e.date,
          'type', e.type, 'initiative_id', e.initiative_id,
          'initiative_title', i.title
        ) ORDER BY e.date ASC)
        FROM public.events e
        LEFT JOIN public.initiatives i ON i.id = e.initiative_id
        WHERE e.date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '7 days'
          AND (
            i.legacy_tribe_id = v_member_tribe_id
            OR e.type IN ('plenaria', 'webinar', 'workshop_geral')
          )
      ), '[]'::jsonb),

      -- NEW p95 #99 1A: attendance_reminder pending notifications visible in dedicated section
      'attendance_reminders_pending', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', n.id, 'title', n.title, 'body', n.body,
          'created_at', n.created_at, 'link', n.link
        ) ORDER BY n.created_at DESC)
        FROM public.notifications n
        WHERE n.recipient_id = p_member_id
          AND n.delivery_mode = 'digest_weekly'
          AND n.digest_delivered_at IS NULL
          AND n.type = 'attendance_reminder'
          AND n.created_at >= v_extended_window
      ), '[]'::jsonb),

      'publications_new', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', ps.id, 'title', ps.title,
          'submission_date', ps.submission_date,
          'primary_author_id', ps.primary_author_id
        ) ORDER BY ps.submission_date DESC)
        FROM public.publication_submissions ps
        WHERE ps.status = 'published'::public.submission_status
          AND ps.submission_date >= v_window_start::date
      ), '[]'::jsonb),

      'broadcasts', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', n.id, 'title', n.title, 'body', n.body,
          'created_at', n.created_at, 'link', n.link
        ) ORDER BY n.created_at DESC)
        FROM public.notifications n
        WHERE n.recipient_id = p_member_id
          AND n.delivery_mode = 'digest_weekly'
          AND n.digest_delivered_at IS NULL
          AND n.type = 'tribe_broadcast'
          AND n.created_at >= v_window_start
      ), '[]'::jsonb),

      'governance_pending', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', n.id, 'type', n.type, 'title', n.title,
          'created_at', n.created_at, 'link', n.link
        ) ORDER BY n.created_at DESC)
        FROM public.notifications n
        WHERE n.recipient_id = p_member_id
          AND n.delivery_mode = 'digest_weekly'
          AND n.digest_delivered_at IS NULL
          AND n.type IN ('governance_vote_reminder', 'ip_ratification_gate_pending', 'change_request_pending')
          AND n.created_at >= v_window_start
      ), '[]'::jsonb),

      'achievements', jsonb_build_object(
        'certificates_issued', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', c.id, 'title', c.title, 'type', c.type,
            'issued_at', c.issued_at
          ) ORDER BY c.issued_at DESC)
          FROM public.certificates c
          WHERE c.member_id = p_member_id
            AND c.issued_at >= v_window_start
        ), '[]'::jsonb),
        'xp_delta', COALESCE((
          SELECT sum(gp.points)::int
          FROM public.gamification_points gp
          WHERE gp.member_id = p_member_id
            AND gp.created_at >= v_window_start
        ), 0)
      )
    ),
    -- p95 #99 1A+1B: include attendance_reminder + assignment_new in consumed set (extended window)
    'consumed_notification_ids', COALESCE((
      SELECT jsonb_agg(n.id)
      FROM public.notifications n
      WHERE n.recipient_id = p_member_id
        AND n.delivery_mode = 'digest_weekly'
        AND n.digest_delivered_at IS NULL
        AND (
          n.created_at >= v_window_start
          OR (n.type IN ('attendance_reminder', 'assignment_new') AND n.created_at >= v_extended_window)
        )
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$


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
$$


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
END; $$


CREATE OR REPLACE FUNCTION public.log_webinar_created()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_actor_id uuid;
  v_legacy_tribe_id int;
BEGIN
  SELECT id INTO v_actor_id FROM members WHERE auth_id = auth.uid();

  -- ADR-0015 Phase 3b: webinars.tribe_id droppado; derivar via initiative
  SELECT legacy_tribe_id INTO v_legacy_tribe_id
  FROM public.initiatives WHERE id = NEW.initiative_id;

  INSERT INTO webinar_lifecycle_events (webinar_id, action, actor_id, new_status, metadata)
  VALUES (NEW.id, 'created', v_actor_id, NEW.status,
    jsonb_build_object('chapter_code', NEW.chapter_code, 'legacy_tribe_id', v_legacy_tribe_id));

  RETURN NEW;
END;
$$


CREATE OR REPLACE FUNCTION public.manage_initiative_engagement(p_initiative_id uuid, p_person_id uuid, p_kind text, p_role text DEFAULT 'participant'::text, p_action text DEFAULT 'add'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_caller_person_id uuid; v_initiative record; v_engagement record;
  v_org_id uuid := '2b4f58ab-7c45-4170-8718-b77ee69ff906';
  v_is_admin boolean; v_is_owner_of_initiative boolean; v_kind_allows_owner boolean;
BEGIN
  SELECT p.id INTO v_caller_person_id FROM persons p WHERE p.auth_id = auth.uid();
  IF v_caller_person_id IS NULL THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  v_is_admin := can(v_caller_person_id, 'manage_member', 'initiative', p_initiative_id);
  IF NOT v_is_admin THEN
    v_is_owner_of_initiative := EXISTS (SELECT 1 FROM engagements e WHERE e.person_id = v_caller_person_id AND e.initiative_id = p_initiative_id AND e.status = 'active' AND (e.kind LIKE '%_owner' OR e.kind LIKE '%_coordinator' OR e.role IN ('owner','coordinator','lead')));
    v_kind_allows_owner := EXISTS (SELECT 1 FROM engagement_kinds ek WHERE ek.slug = p_kind AND ('owner' = ANY(ek.created_by_role) OR 'coordinator' = ANY(ek.created_by_role)));
    IF NOT (v_is_owner_of_initiative AND v_kind_allows_owner) THEN
      RETURN jsonb_build_object('error', 'Unauthorized: requires manage_member permission OR owner/coordinator of this initiative with kind that allows owner creation', 'hint', CASE WHEN NOT v_is_owner_of_initiative THEN 'Caller is not active owner/coordinator of initiative' ELSE 'Engagement kind does not allow owner as creator' END);
    END IF;
  END IF;
  SELECT i.id, i.kind, i.status INTO v_initiative FROM initiatives i WHERE i.id = p_initiative_id;
  IF v_initiative IS NULL THEN RETURN jsonb_build_object('error', 'Initiative not found'); END IF;
  IF v_initiative.status NOT IN ('active', 'draft') THEN RETURN jsonb_build_object('error', 'Initiative is not active'); END IF;
  IF NOT EXISTS (SELECT 1 FROM engagement_kinds ek WHERE ek.slug = p_kind AND v_initiative.kind = ANY(ek.initiative_kinds_allowed)) THEN
    RETURN jsonb_build_object('error', format('Engagement kind "%s" not allowed for initiative kind "%s"', p_kind, v_initiative.kind));
  END IF;
  IF p_action = 'add' THEN
    IF NOT EXISTS (SELECT 1 FROM persons WHERE id = p_person_id) THEN RETURN jsonb_build_object('error', 'Person not found'); END IF;
    IF EXISTS (SELECT 1 FROM engagements e WHERE e.person_id = p_person_id AND e.initiative_id = p_initiative_id AND e.status = 'active') THEN
      RETURN jsonb_build_object('error', 'Person already has active engagement in this initiative');
    END IF;
    INSERT INTO engagements (person_id, initiative_id, kind, role, status, legal_basis, granted_by, metadata, organization_id)
    VALUES (p_person_id, p_initiative_id, p_kind, p_role, 'active', 'consent', v_caller_person_id,
      jsonb_build_object('source', 'manage_initiative_engagement', 'added_by', v_caller_person_id::text, 'invoked_as', CASE WHEN v_is_admin THEN 'admin' ELSE 'initiative_owner' END), v_org_id)
    RETURNING * INTO v_engagement;
    RETURN jsonb_build_object('ok', true, 'action', 'added', 'engagement_id', v_engagement.id, 'authorized_as', CASE WHEN v_is_admin THEN 'admin' ELSE 'initiative_owner' END);
  ELSIF p_action = 'remove' THEN
    UPDATE engagements SET status = 'revoked', revoked_at = now(), revoked_by = v_caller_person_id, revoke_reason = 'Removed via manage_initiative_engagement', updated_at = now()
    WHERE person_id = p_person_id AND initiative_id = p_initiative_id AND status = 'active' RETURNING * INTO v_engagement;
    IF v_engagement IS NULL THEN RETURN jsonb_build_object('error', 'No active engagement found for this person'); END IF;
    RETURN jsonb_build_object('ok', true, 'action', 'removed', 'engagement_id', v_engagement.id);
  ELSIF p_action = 'update_role' THEN
    UPDATE engagements SET role = p_role, updated_at = now()
    WHERE person_id = p_person_id AND initiative_id = p_initiative_id AND status = 'active' RETURNING * INTO v_engagement;
    IF v_engagement IS NULL THEN RETURN jsonb_build_object('error', 'No active engagement found for this person'); END IF;
    RETURN jsonb_build_object('ok', true, 'action', 'role_updated', 'engagement_id', v_engagement.id, 'new_role', p_role);
  ELSE RETURN jsonb_build_object('error', format('Unknown action: %s', p_action));
  END IF;
END; $$


CREATE OR REPLACE FUNCTION public.trg_document_version_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF OLD.locked_at IS NOT NULL THEN
    IF NEW.content_html IS DISTINCT FROM OLD.content_html
       OR NEW.content_markdown IS DISTINCT FROM OLD.content_markdown
       OR NEW.version_number IS DISTINCT FROM OLD.version_number
       OR NEW.version_label IS DISTINCT FROM OLD.version_label
       OR NEW.document_id IS DISTINCT FROM OLD.document_id
       OR NEW.locked_at IS DISTINCT FROM OLD.locked_at
    THEN
      RAISE EXCEPTION 'document_versions row locked at % is immutable (id=%, document=%)', OLD.locked_at, OLD.id, OLD.document_id
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  NEW.updated_at = now();
  RETURN NEW;
END;
$$


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
END; $$


CREATE OR REPLACE FUNCTION public.v4_notify_expiring_engagements()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_count_d60 int := 0;
  v_count_d30 int := 0;
  v_count_d7 int := 0;
  v_engagement record;
  v_gp_member_id uuid;
  v_lorena_member_id uuid;
BEGIN
  SELECT m.id INTO v_gp_member_id
  FROM public.members m
  WHERE m.is_active=true AND m.operational_role='manager'
  LIMIT 1;

  SELECT m.id INTO v_lorena_member_id
  FROM public.members m
  WHERE m.is_active=true
    AND 'voluntariado_director' = ANY(m.designations)
  LIMIT 1;

  FOR v_engagement IN
    SELECT
      e.id AS engagement_id, e.person_id, p.legacy_member_id, p.name AS person_name,
      e.kind, e.role, e.end_date, e.metadata,
      ek.display_name AS kind_name,
      i.title AS initiative_title,
      (e.end_date - CURRENT_DATE) AS days_until_expiry
    FROM public.engagements e
    JOIN public.persons p ON p.id = e.person_id
    JOIN public.engagement_kinds ek ON ek.slug = e.kind
    LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.status = 'active'
      AND e.kind = 'volunteer'
      AND e.end_date IS NOT NULL
      AND e.end_date BETWEEN CURRENT_DATE AND (CURRENT_DATE + interval '60 days')
  LOOP
    -- D-60 GP-only aggregate (digest_weekly, default OK)
    IF v_engagement.days_until_expiry BETWEEN 53 AND 60
       AND v_gp_member_id IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM public.notifications n
         WHERE n.recipient_id = v_gp_member_id
           AND n.type = 'engagement_renewal_d60_gp_aggregate'
           AND n.source_id = v_engagement.engagement_id
           AND n.created_at > (now() - interval '7 days')
       ) THEN
      INSERT INTO public.notifications (recipient_id, type, title, body, source_type, source_id, delivery_mode)
      VALUES (
        v_gp_member_id, 'engagement_renewal_d60_gp_aggregate',
        'Voluntário vencerá em 60d: ' || v_engagement.person_name,
        v_engagement.person_name || ' (' || v_engagement.role || COALESCE(' · ' || v_engagement.initiative_title, '') ||
        ') tem vínculo expirando em ' || v_engagement.end_date || '. Nudge ao voluntário só dispara em D-30.',
        'engagement', v_engagement.engagement_id,
        public._delivery_mode_for('engagement_renewal_d60_gp_aggregate')
      );
      v_count_d60 := v_count_d60 + 1;
    END IF;

    -- D-30 (digest_weekly, both volunteer + GP)
    IF v_engagement.days_until_expiry BETWEEN 23 AND 30 THEN
      IF v_engagement.legacy_member_id IS NOT NULL
         AND NOT EXISTS (
           SELECT 1 FROM public.notifications n
           WHERE n.recipient_id = v_engagement.legacy_member_id
             AND n.type = 'engagement_renewal_d30'
             AND n.source_id = v_engagement.engagement_id
             AND n.created_at > (now() - interval '7 days')
         ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, source_type, source_id, delivery_mode)
        VALUES (
          v_engagement.legacy_member_id, 'engagement_renewal_d30',
          'Sua vaga vence em 30 dias',
          'Sua vaga como ' || v_engagement.kind_name ||
          COALESCE(' na ' || v_engagement.initiative_title, '') ||
          ' expira em ' || v_engagement.end_date || '. Para renovar, cadastre-se na vaga atual no PMI VEP.',
          'engagement', v_engagement.engagement_id,
          public._delivery_mode_for('engagement_renewal_d30')
        );
        v_count_d30 := v_count_d30 + 1;
      END IF;
      IF v_gp_member_id IS NOT NULL
         AND NOT EXISTS (
           SELECT 1 FROM public.notifications n
           WHERE n.recipient_id = v_gp_member_id
             AND n.type = 'engagement_renewal_d30'
             AND n.source_id = v_engagement.engagement_id
             AND n.created_at > (now() - interval '7 days')
         ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, source_type, source_id, delivery_mode)
        VALUES (
          v_gp_member_id, 'engagement_renewal_d30',
          'Voluntário ' || v_engagement.person_name || ' vence em 30d',
          v_engagement.person_name || ' precisa renovar VEP. Se renovação detected, ball-in-court transfere para você.',
          'engagement', v_engagement.engagement_id,
          public._delivery_mode_for('engagement_renewal_d30')
        );
        v_count_d30 := v_count_d30 + 1;
      END IF;
    END IF;

    -- D-7 URGENT (transactional_immediate explícito — não default)
    IF v_engagement.days_until_expiry BETWEEN 1 AND 7 THEN
      IF v_engagement.legacy_member_id IS NOT NULL
         AND NOT EXISTS (
           SELECT 1 FROM public.notifications n
           WHERE n.recipient_id = v_engagement.legacy_member_id
             AND n.type = 'engagement_renewal_d7_urgent'
             AND n.source_id = v_engagement.engagement_id
             AND n.created_at > (now() - interval '7 days')
         ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, source_type, source_id, delivery_mode)
        VALUES (
          v_engagement.legacy_member_id, 'engagement_renewal_d7_urgent',
          'URGENTE: vaga vence em 7 dias',
          'Sua vaga como ' || v_engagement.kind_name ||
          COALESCE(' na ' || v_engagement.initiative_title, '') ||
          ' expira em ' || v_engagement.end_date || '. URGENTE: cadastre renovação no PMI VEP imediatamente.',
          'engagement', v_engagement.engagement_id,
          public._delivery_mode_for('engagement_renewal_d7_urgent')
        );
        v_count_d7 := v_count_d7 + 1;
      END IF;
      IF v_gp_member_id IS NOT NULL
         AND NOT EXISTS (
           SELECT 1 FROM public.notifications n
           WHERE n.recipient_id = v_gp_member_id
             AND n.type = 'engagement_renewal_d7_urgent'
             AND n.source_id = v_engagement.engagement_id
             AND n.created_at > (now() - interval '7 days')
         ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, source_type, source_id, delivery_mode)
        VALUES (
          v_gp_member_id, 'engagement_renewal_d7_urgent',
          'D-7: ' || v_engagement.person_name || ' vence em 7d',
          v_engagement.person_name || ' (' || v_engagement.role || ') vence ' || v_engagement.end_date || '. Verificar status renovação VEP.',
          'engagement', v_engagement.engagement_id,
          public._delivery_mode_for('engagement_renewal_d7_urgent')
        );
        v_count_d7 := v_count_d7 + 1;
      END IF;
      IF v_lorena_member_id IS NOT NULL
         AND v_lorena_member_id <> v_gp_member_id
         AND NOT EXISTS (
           SELECT 1 FROM public.notifications n
           WHERE n.recipient_id = v_lorena_member_id
             AND n.type = 'engagement_renewal_d7_urgent'
             AND n.source_id = v_engagement.engagement_id
             AND n.created_at > (now() - interval '7 days')
         ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, source_type, source_id, delivery_mode)
        VALUES (
          v_lorena_member_id, 'engagement_renewal_d7_urgent',
          'PMI-GO Voluntariado D-7: ' || v_engagement.person_name,
          v_engagement.person_name || ' (' || v_engagement.role || ') vence ' || v_engagement.end_date || '. cc Diretoria de Voluntariado PMI-GO para awareness.',
          'engagement', v_engagement.engagement_id,
          public._delivery_mode_for('engagement_renewal_d7_urgent')
        );
        v_count_d7 := v_count_d7 + 1;
      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'notifications_d60', v_count_d60,
    'notifications_d30', v_count_d30,
    'notifications_d7', v_count_d7,
    'total_sent', v_count_d60 + v_count_d30 + v_count_d7,
    'run_at', now()
  );
END;
$$

