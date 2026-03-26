-- Migration repair: captures 6 RPCs + 1 RLS policy applied via SQL Editor on 26 Mar 2026
-- This file exists solely so that `supabase migration repair` can track these changes.
-- All statements below are already live in production DB.

-- =============================================================================
-- 1. POLICY: site_config_public_read
-- =============================================================================
-- Allows authenticated users to read specific public config keys
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'site_config_public_read') THEN
    CREATE POLICY site_config_public_read ON site_config
      FOR SELECT TO authenticated
      USING (key IN ('whatsapp_gp', 'general_meeting_link', 'group_term',
        'attendance_risk_threshold', 'attendance_weight_geral', 'attendance_weight_tribo'));
  END IF;
END $$;

-- =============================================================================
-- 2. RPC: list_tribe_deliverables (relaxed auth — any authenticated user can read)
-- =============================================================================
DROP FUNCTION IF EXISTS list_tribe_deliverables(integer, text);
CREATE FUNCTION public.list_tribe_deliverables(p_tribe_id integer, p_cycle_code text DEFAULT NULL)
 RETURNS SETOF tribe_deliverables
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  rec record;
begin
  select * into rec from public.get_my_member_record();
  if rec is null then
    raise exception 'Not authenticated';
  end if;

  -- Any authenticated active member can READ deliverables (exploration mode)
  return query
    select * from public.tribe_deliverables
    where tribe_id = p_tribe_id
      and (p_cycle_code is null or cycle_code = p_cycle_code)
    order by due_date asc nulls last, created_at desc;
end;
$function$;

-- =============================================================================
-- 3. RPC: update_certificate
-- =============================================================================
DROP FUNCTION IF EXISTS update_certificate(uuid, jsonb);
CREATE FUNCTION public.update_certificate(p_cert_id uuid, p_updates jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND OR (
    v_caller.is_superadmin IS NOT TRUE
    AND v_caller.operational_role NOT IN ('manager', 'deputy_manager')
    AND NOT ('curator' = ANY(v_caller.designations))
  ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  UPDATE certificates SET
    title = COALESCE(p_updates->>'title', title),
    description = COALESCE(p_updates->>'description', description),
    type = COALESCE(p_updates->>'type', type),
    period_start = COALESCE(p_updates->>'period_start', period_start),
    period_end = COALESCE(p_updates->>'period_end', period_end),
    function_role = COALESCE(p_updates->>'function_role', function_role),
    language = COALESCE(p_updates->>'language', language),
    cycle = COALESCE((p_updates->>'cycle')::int, cycle),
    updated_at = now()
  WHERE id = p_cert_id AND status != 'revoked';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Certificate not found or revoked');
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$function$;

-- =============================================================================
-- 4. RPC: detect_and_notify_detractors
-- =============================================================================
DROP FUNCTION IF EXISTS detect_and_notify_detractors();
CREATE FUNCTION public.detect_and_notify_detractors()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_count int := 0;
  v_member record;
  v_leader record;
BEGIN
  PERFORM 1 FROM members WHERE auth_id = auth.uid() AND (is_superadmin = true OR operational_role = 'manager');
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  FOR v_member IN
    SELECT m.id, m.name, m.tribe_id
    FROM members m
    WHERE m.is_active = true
    AND m.current_cycle_active = true
    AND m.operational_role NOT IN ('sponsor', 'chapter_liaison')
    AND NOT EXISTS (
      SELECT 1 FROM attendance a
      JOIN events e ON a.event_id = e.id
      WHERE a.member_id = m.id AND a.present = true
      AND e.date >= (now() - interval '21 days')::date
    )
    AND EXISTS (
      SELECT 1 FROM events e
      WHERE e.date >= (now() - interval '21 days')::date
      AND (e.type IN ('geral', 'tribo') OR e.tribe_id = m.tribe_id)
    )
  LOOP
    FOR v_leader IN
      SELECT m2.id FROM members m2
      WHERE m2.is_active = true AND (
        m2.is_superadmin = true
        OR m2.operational_role IN ('manager', 'deputy_manager')
        OR (m2.operational_role = 'tribe_leader' AND m2.tribe_id = v_member.tribe_id)
      )
    LOOP
      IF NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.recipient_id = v_leader.id
        AND n.type = 'attendance_detractor'
        AND n.source_id = v_member.id
        AND n.created_at > now() - interval '7 days'
      ) THEN
        PERFORM create_notification(
          v_leader.id,
          'attendance_detractor',
          'Detractor Alert: ' || v_member.name,
          v_member.name || ' missed 3+ consecutive eligible meetings',
          '/admin/members',
          'member',
          v_member.id
        );
      END IF;
    END LOOP;
    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('detractors_found', v_count);
END;
$function$;

-- =============================================================================
-- 5. RPC: send_attendance_reminders
-- =============================================================================
DROP FUNCTION IF EXISTS send_attendance_reminders();
CREATE FUNCTION public.send_attendance_reminders()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_event record;
  v_count int := 0;
BEGIN
  PERFORM 1 FROM members WHERE auth_id = auth.uid() AND (is_superadmin = true OR operational_role = 'manager');
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  FOR v_event IN
    SELECT e.id, e.title, e.date, e.tribe_id, e.type
    FROM events e
    WHERE e.date = current_date
    AND NOT EXISTS (
      SELECT 1 FROM notifications n
      WHERE n.type = 'attendance_reminder'
      AND n.source_id = e.id
    )
  LOOP
    INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id)
    SELECT m.id, 'attendance_reminder',
      v_event.title || ' starts soon!',
      'Don''t forget to check in!',
      '/attendance',
      'event',
      v_event.id
    FROM members m
    WHERE m.is_active = true
    AND m.current_cycle_active = true
    AND (v_event.type IN ('geral', 'tribo') OR m.tribe_id = v_event.tribe_id)
    AND NOT EXISTS (
      SELECT 1 FROM notifications n2
      WHERE n2.recipient_id = m.id AND n2.type = 'attendance_reminder' AND n2.source_id = v_event.id
    )
    AND NOT EXISTS (
      SELECT 1 FROM notification_preferences np
      WHERE np.member_id = m.id AND 'attendance_reminder' = ANY(np.muted_types)
    );

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('events_reminded', v_count);
END;
$function$;

-- =============================================================================
-- 6. RPC: bulk_issue_certificates
-- =============================================================================
DROP FUNCTION IF EXISTS bulk_issue_certificates(text, text, text, text, text, integer, uuid[]);
CREATE FUNCTION public.bulk_issue_certificates(
  p_type text,
  p_title text,
  p_period_start text,
  p_period_end text,
  p_language text DEFAULT 'pt-BR',
  p_cycle integer DEFAULT NULL,
  p_member_ids uuid[] DEFAULT '{}'
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_member record;
  v_count int := 0;
  v_code text;
  v_function_role text;
  v_cert_id uuid;
  v_results jsonb := '[]'::jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND OR (
    v_caller.is_superadmin IS NOT TRUE
    AND v_caller.operational_role NOT IN ('manager', 'deputy_manager')
  ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: only GP/Deputy can bulk issue');
  END IF;

  IF p_type NOT IN ('participation', 'completion') THEN
    RETURN jsonb_build_object('error', 'Bulk issuance only for participation/completion types');
  END IF;

  IF array_length(p_member_ids, 1) IS NULL OR array_length(p_member_ids, 1) = 0 THEN
    RETURN jsonb_build_object('error', 'No members selected');
  END IF;

  FOR v_member IN
    SELECT m.id, m.name, m.operational_role, m.tribe_id, t.name as tribe_name
    FROM members m
    LEFT JOIN tribes t ON m.tribe_id = t.id
    WHERE m.id = ANY(p_member_ids)
    AND m.is_active = true
  LOOP
    v_code := 'CERT-' || to_char(now(), 'YYYY') || '-' || upper(substr(md5(random()::text), 1, 6));

    v_function_role := CASE v_member.operational_role
      WHEN 'tribe_leader' THEN 'Líder de Tribo — ' || COALESCE(v_member.tribe_name, '')
      WHEN 'researcher' THEN 'Pesquisador(a) — ' || COALESCE(v_member.tribe_name, '')
      WHEN 'manager' THEN 'Gestor do Projeto'
      WHEN 'deputy_manager' THEN 'Vice-Gestor do Projeto'
      ELSE COALESCE(v_member.operational_role, 'Voluntário(a)') ||
           CASE WHEN v_member.tribe_name IS NOT NULL THEN ' — ' || v_member.tribe_name ELSE '' END
    END;

    INSERT INTO certificates (
      member_id, type, title, description, period_start, period_end,
      function_role, language, cycle, verification_code, status,
      issued_by, issued_at
    ) VALUES (
      v_member.id, p_type, p_title, NULL, p_period_start, p_period_end,
      v_function_role, p_language, COALESCE(p_cycle, 3), v_code, 'issued',
      v_caller.id, now()
    ) RETURNING id INTO v_cert_id;

    PERFORM create_notification(
      v_member.id, 'certificate_issued',
      'Certificado emitido: ' || p_title,
      'Você recebeu: ' || p_title,
      '/gamification',
      'certificate',
      v_cert_id
    );

    v_count := v_count + 1;
    v_results := v_results || jsonb_build_object(
      'member_id', v_member.id, 'name', v_member.name, 'code', v_code
    );
  END LOOP;

  RETURN jsonb_build_object('issued', v_count, 'certificates', v_results);
END;
$function$;

-- =============================================================================
-- 7. RPC: get_chapter_dashboard (attendance formula fix)
-- =============================================================================
DROP FUNCTION IF EXISTS get_chapter_dashboard(text);
CREATE FUNCTION public.get_chapter_dashboard(p_chapter text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller record; v_chapter text; v_result jsonb; v_hub_members int; v_hub_avg_xp numeric; v_hub_certs int;
  v_ch_members int;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;

  IF v_caller.is_superadmin OR v_caller.operational_role IN ('manager', 'deputy_manager') THEN
    v_chapter := COALESCE(p_chapter, v_caller.chapter);
  ELSIF v_caller.operational_role IN ('sponsor', 'chapter_liaison') OR 'sponsor' = ANY(v_caller.designations) OR 'chapter_liaison' = ANY(v_caller.designations) THEN
    v_chapter := v_caller.chapter;
  ELSE RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  IF v_chapter IS NULL THEN RETURN jsonb_build_object('error', 'No chapter specified'); END IF;

  SELECT count(*) INTO v_hub_members FROM members WHERE is_active AND current_cycle_active;
  SELECT count(*) INTO v_ch_members FROM members WHERE chapter = v_chapter AND is_active;
  SELECT COALESCE(avg(t.xp), 0) INTO v_hub_avg_xp FROM (SELECT sum(points) AS xp FROM gamification_points GROUP BY member_id) t;
  SELECT count(*) INTO v_hub_certs FROM gamification_points WHERE category IN ('cert_pmi_senior','cert_cpmai','cert_pmi_mid','cert_pmi_practitioner','cert_pmi_entry');

  SELECT jsonb_build_object(
    'chapter', v_chapter, 'cycle', 3,
    'people', (SELECT jsonb_build_object(
      'active', count(*) FILTER (WHERE member_status = 'active'),
      'observers', count(*) FILTER (WHERE member_status = 'observer'),
      'alumni', count(*) FILTER (WHERE member_status = 'alumni'),
      'hub_total', v_hub_members,
      'by_role', (SELECT jsonb_object_agg(role, cnt) FROM (SELECT operational_role AS role, count(*) AS cnt FROM members WHERE chapter = v_chapter AND member_status = 'active' GROUP BY operational_role) r)
    ) FROM members WHERE chapter = v_chapter),
    'output', jsonb_build_object(
      'board_cards_completed', (SELECT count(*) FROM board_items bi JOIN board_item_assignments bia ON bia.item_id = bi.id JOIN members m ON m.id = bia.member_id WHERE m.chapter = v_chapter AND bi.status = 'done'),
      'publications_submitted', (SELECT count(*) FROM publication_submissions ps JOIN members m ON m.id = ps.primary_author_id WHERE m.chapter = v_chapter)
    ),
    'attendance', jsonb_build_object(
      'rate_pct', (
        SELECT ROUND(COUNT(DISTINCT a.member_id)::numeric / NULLIF(v_ch_members, 0) * 100, 1)
        FROM attendance a JOIN members m ON a.member_id = m.id JOIN events e ON a.event_id = e.id
        WHERE m.chapter = v_chapter AND m.is_active AND a.present AND e.date >= now() - interval '90 days'
      ),
      'avg_events_per_member', (
        SELECT ROUND(COUNT(a.id)::numeric / NULLIF(v_ch_members, 0), 1)
        FROM attendance a JOIN members m ON a.member_id = m.id JOIN events e ON a.event_id = e.id
        WHERE m.chapter = v_chapter AND m.is_active AND a.present AND e.date >= now() - interval '90 days'
      ),
      'total_events_attended', (
        SELECT COUNT(a.id)
        FROM attendance a JOIN members m ON a.member_id = m.id JOIN events e ON a.event_id = e.id
        WHERE m.chapter = v_chapter AND m.is_active AND a.present AND e.date >= now() - interval '90 days'
      ),
      'hub_participation_pct', (
        SELECT ROUND(COUNT(DISTINCT a.member_id)::numeric / NULLIF(v_hub_members, 0) * 100, 1)
        FROM attendance a JOIN members m ON a.member_id = m.id JOIN events e ON a.event_id = e.id
        WHERE m.is_active AND a.present AND e.date >= now() - interval '90 days'
      )
    ),
    'hours', (SELECT jsonb_build_object(
      'total_hours', COALESCE(round(sum(CASE WHEN a.present THEN COALESCE(e.duration_minutes, 60) / 60.0 ELSE 0 END)::numeric, 1), 0),
      'pdu_equivalent', LEAST(COALESCE(round(sum(CASE WHEN a.present THEN COALESCE(e.duration_minutes, 60) / 60.0 ELSE 0 END)::numeric, 1), 0), 25)
    ) FROM attendance a JOIN events e ON e.id = a.event_id JOIN members m ON m.id = a.member_id WHERE m.chapter = v_chapter AND m.member_status = 'active'),
    'certifications', (SELECT jsonb_build_object(
      'pmp', count(*) FILTER (WHERE gp.category = 'cert_pmi_senior'),
      'cpmai', count(*) FILTER (WHERE gp.category = 'cert_cpmai'),
      'total_certs', count(*) FILTER (WHERE gp.category IN ('cert_pmi_senior','cert_cpmai','cert_pmi_mid','cert_pmi_practitioner','cert_pmi_entry')),
      'hub_total_certs', v_hub_certs
    ) FROM gamification_points gp JOIN members m ON m.id = gp.member_id WHERE m.chapter = v_chapter AND m.member_status = 'active'),
    'partnerships', (SELECT jsonb_build_object(
      'active', count(*) FILTER (WHERE pe.status = 'active'),
      'negotiation', count(*) FILTER (WHERE pe.status = 'negotiation'),
      'total', count(*)
    ) FROM partner_entities pe WHERE pe.chapter = v_chapter),
    'gamification', (SELECT jsonb_build_object(
      'avg_xp', COALESCE(round(avg(total_xp)), 0),
      'hub_avg_xp', round(v_hub_avg_xp),
      'top_contributors', (SELECT jsonb_agg(row_to_json(tc) ORDER BY tc.total_xp DESC) FROM (
        SELECT m.name, m.photo_url, sum(gp.points) AS total_xp FROM gamification_points gp JOIN members m ON m.id = gp.member_id
        WHERE m.chapter = v_chapter AND m.member_status = 'active' GROUP BY m.id, m.name, m.photo_url ORDER BY total_xp DESC LIMIT 3
      ) tc)
    ) FROM (SELECT sum(gp.points) AS total_xp FROM gamification_points gp JOIN members m ON m.id = gp.member_id WHERE m.chapter = v_chapter AND m.member_status = 'active' GROUP BY gp.member_id) t),
    'members', (SELECT jsonb_agg(row_to_json(ml) ORDER BY ml.total_xp DESC) FROM (
      SELECT m.id, m.name, m.photo_url, m.operational_role, m.designations,
        COALESCE((SELECT sum(points) FROM gamification_points WHERE member_id = m.id), 0) AS total_xp,
        COALESCE((SELECT round(100.0 * count(*) FILTER (WHERE present) / NULLIF(count(*), 0)) FROM attendance WHERE member_id = m.id), 0) AS attendance_pct,
        (SELECT count(*) FROM gamification_points WHERE member_id = m.id AND category = 'trail') AS trail_count
      FROM members m WHERE m.chapter = v_chapter AND m.member_status = 'active'
    ) ml),
    'available_chapters', (SELECT jsonb_agg(DISTINCT m.chapter ORDER BY m.chapter) FROM members m WHERE m.chapter IS NOT NULL AND m.member_status = 'active')
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

-- =============================================================================
-- Schema reload
-- =============================================================================
NOTIFY pgrst, 'reload schema';
