-- Track Q-B Phase B (2-touch drift diff) — drift-correction batch 4 completion part A (13 fns)
--
-- Captures live `pg_get_functiondef` for 13 of the remaining 25 drifted 2-touch fns.
-- Continuation of batch 4 (which captured 10/35). After this + part B (12 fns),
-- 2-touch drift coverage = 35/35 = 100%, completing Phase B.
--
-- Captured (part A — 13 fns):
--   admin_inactivate_member, admin_link_communication_boards, admin_list_members,
--   admin_send_campaign, admin_update_member_audited, get_audit_log,
--   get_cycle_evolution, get_diversity_dashboard, get_initiative_events_timeline,
--   get_initiative_stats, get_kpi_dashboard, get_member_detail,
--   get_ratification_reminder_targets.
--
-- Bodies preserved verbatim. CREATE OR REPLACE idempotent. $$-quoted.

CREATE OR REPLACE FUNCTION public.admin_inactivate_member(p_member_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_actor_id uuid;
BEGIN
  SELECT id INTO v_actor_id FROM public.members WHERE auth_id = auth.uid();

  UPDATE public.members
     SET is_active = false,
         inactivation_reason = p_reason
   WHERE id = p_member_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    v_actor_id, 'member.inactivated', 'member', p_member_id,
    jsonb_build_object('is_active', false, 'reason', p_reason)
  );

  RETURN json_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_link_communication_boards(p_tribe_id integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
declare
  v_caller record;
  v_target_tribe_id integer;
  v_target_initiative_id uuid;
  v_updated integer := 0;
  v_result jsonb;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      v_caller.is_superadmin is true
      or public.can_by_member(v_caller.id, 'manage_member')
      or coalesce('co_gp' = any(v_caller.designations), false)
    ) then
    raise exception 'Project management access required';
  end if;

  if p_tribe_id is null then
    select (public.admin_ensure_communication_tribe() ->> 'tribe_id')::integer into v_target_tribe_id;
  else
    v_target_tribe_id := p_tribe_id;
  end if;

  -- Resolve initiative_id for the target tribe
  SELECT id INTO v_target_initiative_id FROM public.initiatives WHERE legacy_tribe_id = v_target_tribe_id LIMIT 1;

  update public.project_boards pb
  set initiative_id = v_target_initiative_id,
      domain_key = 'communication',
      updated_at = now()
  where (
    lower(coalesce(pb.board_name, '')) like '%comunic%'
    or lower(coalesce(pb.board_name, '')) like '%midias%'
    or exists (
      select 1
      from public.board_items bi
      where bi.board_id = pb.id
        and bi.source_board in ('comunicacao_ciclo3', 'midias_sociais', 'social_media', 'comms_c3')
    )
  )
    and (pb.initiative_id is distinct from v_target_initiative_id or coalesce(pb.domain_key, '') <> 'communication');

  get diagnostics v_updated = row_count;

  v_result := jsonb_build_object(
    'success', true,
    'tribe_id', v_target_tribe_id,
    'initiative_id', v_target_initiative_id,
    'boards_linked', v_updated
  );

  return v_result;
end;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_members(p_search text DEFAULT NULL::text, p_tier text DEFAULT NULL::text, p_tribe_id integer DEFAULT NULL::integer, p_status text DEFAULT 'active'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM members WHERE auth_id = auth.uid()
    AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager', 'sponsor', 'chapter_liaison'))
  ) THEN RAISE EXCEPTION 'Admin only'; END IF;

  RETURN (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', m.id,
      'full_name', m.name,
      'email', m.email,
      'photo_url', m.photo_url,
      'operational_role', m.operational_role,
      'designations', m.designations,
      'is_superadmin', m.is_superadmin,
      'is_active', m.is_active,
      'member_status', m.member_status,
      'tribe_id', m.tribe_id,
      'tribe_name', tc.name,
      'chapter', m.chapter,
      'auth_id', m.auth_id,
      'last_seen_at', m.last_seen_at,
      'total_sessions', COALESCE(m.total_sessions, 0),
      'credly_username', m.credly_url,
      'offboarded_at', m.offboarded_at,
      'status_change_reason', m.status_change_reason
    ) ORDER BY m.name), '[]'::jsonb)
    FROM members m
    LEFT JOIN tribes tc ON tc.id = m.tribe_id
    WHERE
      (p_status = 'all'
        OR (p_status = 'active' AND m.member_status = 'active')
        OR (p_status = 'inactive' AND m.member_status = 'inactive')
        OR (p_status = 'observer' AND m.member_status = 'observer')
        OR (p_status = 'alumni' AND m.member_status = 'alumni'))
      AND (p_tier IS NULL OR m.operational_role = p_tier)
      AND (p_tribe_id IS NULL OR m.tribe_id = p_tribe_id)
      AND (p_search IS NULL OR m.name ILIKE '%' || p_search || '%' OR m.email ILIKE '%' || p_search || '%')
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_send_campaign(p_template_id uuid, p_audience_filter jsonb DEFAULT '{}'::jsonb, p_scheduled_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_external_contacts jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_send_id uuid;
  v_count int := 0;
  v_ext_count int := 0;
  v_sends_last_hour int;
  v_sends_last_day int;
  v_member record;
  v_tmpl record;
  v_roles text[];
  v_desigs text[];
  v_chapters text[];
  v_all boolean;
  v_include_inactive boolean;
  v_ext record;
BEGIN
  SELECT id INTO v_caller_id FROM public.members
  WHERE auth_id = auth.uid() AND (is_superadmin OR operational_role IN ('manager','deputy_manager'));
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Forbidden: only GP/DM can send campaigns'; END IF;

  SELECT COUNT(*) INTO v_sends_last_hour FROM public.campaign_sends
  WHERE sent_by = v_caller_id AND created_at > now() - interval '1 hour' AND status NOT IN ('draft','failed');
  IF v_sends_last_hour >= 1 THEN RAISE EXCEPTION 'Rate limit: max 1 campaign per hour'; END IF;

  SELECT COUNT(*) INTO v_sends_last_day FROM public.campaign_sends
  WHERE sent_by = v_caller_id AND created_at > now() - interval '1 day' AND status NOT IN ('draft','failed');
  IF v_sends_last_day >= 3 THEN RAISE EXCEPTION 'Rate limit: max 3 campaigns per day'; END IF;

  SELECT * INTO v_tmpl FROM public.campaign_templates WHERE id = p_template_id;
  IF v_tmpl IS NULL THEN RAISE EXCEPTION 'Template not found'; END IF;

  v_roles := ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_audience_filter->'roles', '[]'::jsonb)));
  v_desigs := ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_audience_filter->'designations', '[]'::jsonb)));
  v_chapters := ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_audience_filter->'chapters', '[]'::jsonb)));
  v_all := COALESCE((p_audience_filter->>'all')::boolean, false);
  v_include_inactive := COALESCE((p_audience_filter->>'include_inactive')::boolean, false);

  INSERT INTO public.campaign_sends (id, template_id, sent_by, audience_filter, status, scheduled_at)
  VALUES (gen_random_uuid(), p_template_id, v_caller_id, p_audience_filter,
          CASE WHEN p_scheduled_at IS NOT NULL THEN 'scheduled' ELSE 'pending_delivery' END, p_scheduled_at)
  RETURNING id INTO v_send_id;

  FOR v_member IN
    SELECT m.id, 'pt' AS lang
    FROM public.members m
    WHERE m.email IS NOT NULL
      AND (
        (m.is_active = true AND m.current_cycle_active = true)
        OR (v_include_inactive AND (m.is_active = false OR m.current_cycle_active = false))
      )
      AND (
        v_all OR v_include_inactive
        OR (array_length(v_roles, 1) > 0 AND m.operational_role = ANY(v_roles))
        OR (array_length(v_desigs, 1) > 0 AND m.designations && v_desigs)
        OR (array_length(v_chapters, 1) > 0 AND m.chapter = ANY(v_chapters))
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.campaign_recipients cr2
        JOIN public.campaign_sends cs2 ON cs2.id = cr2.send_id
        WHERE cr2.member_id = m.id AND cr2.unsubscribed = true
      )
  LOOP
    INSERT INTO public.campaign_recipients (send_id, member_id, language)
    VALUES (v_send_id, v_member.id, v_member.lang);
    v_count := v_count + 1;
  END LOOP;

  FOR v_ext IN SELECT * FROM jsonb_array_elements(p_external_contacts)
  LOOP
    INSERT INTO public.campaign_recipients (send_id, external_email, external_name, language)
    VALUES (v_send_id, v_ext.value->>'email', v_ext.value->>'name', COALESCE(v_ext.value->>'language', 'en'));
    v_ext_count := v_ext_count + 1;
  END LOOP;

  UPDATE public.campaign_sends SET recipient_count = v_count + v_ext_count WHERE id = v_send_id;

  RETURN jsonb_build_object(
    'send_id', v_send_id, 'member_recipients', v_count, 'external_recipients', v_ext_count,
    'total_recipients', v_count + v_ext_count,
    'status', CASE WHEN p_scheduled_at IS NOT NULL THEN 'scheduled' ELSE 'pending_delivery' END
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_update_member_audited(p_member_id uuid, p_changes jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_actor_id uuid; v_old_record jsonb; v_field text; v_old_val text; v_new_val text;
BEGIN
  SELECT id INTO v_actor_id FROM public.members WHERE auth_id = auth.uid();
  IF v_actor_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.can_by_member(v_actor_id, 'manage_member') THEN RAISE EXCEPTION 'Unauthorized: requires manage_member permission'; END IF;
  SELECT jsonb_build_object('operational_role', m.operational_role, 'designations', m.designations, 'tribe_id', m.tribe_id, 'chapter', m.chapter, 'is_active', m.is_active, 'is_superadmin', m.is_superadmin) INTO v_old_record FROM public.members m WHERE m.id = p_member_id;
  UPDATE public.members SET operational_role = COALESCE((p_changes->>'operational_role'), operational_role), designations = CASE WHEN p_changes ? 'designations' THEN ARRAY(SELECT jsonb_array_elements_text(p_changes->'designations')) ELSE designations END, tribe_id = CASE WHEN p_changes ? 'tribe_id' THEN (p_changes->>'tribe_id')::integer ELSE tribe_id END, chapter = COALESCE((p_changes->>'chapter'), chapter), is_active = CASE WHEN p_changes ? 'is_active' THEN (p_changes->>'is_active')::boolean ELSE is_active END, is_superadmin = CASE WHEN p_changes ? 'is_superadmin' THEN (p_changes->>'is_superadmin')::boolean ELSE is_superadmin END WHERE id = p_member_id;
  FOR v_field IN SELECT jsonb_object_keys(p_changes) LOOP
    v_old_val := v_old_record->>v_field;
    v_new_val := p_changes->>v_field;
    IF v_old_val IS DISTINCT FROM v_new_val THEN
      INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
      VALUES (v_actor_id, 'member.' || v_field || '_changed', 'member', p_member_id, jsonb_build_object('field', v_field, 'old', v_old_val, 'new', v_new_val));
    END IF;
  END LOOP;
  RETURN jsonb_build_object('success', true);
END; $$;

CREATE OR REPLACE FUNCTION public.get_audit_log(p_actor_id uuid DEFAULT NULL::uuid, p_target_id uuid DEFAULT NULL::uuid, p_action text DEFAULT NULL::text, p_date_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_date_to timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller record;
  v_entries jsonb;
  v_total bigint;
  v_actors jsonb;
  v_search text;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  IF NOT (v_caller.is_superadmin IS TRUE
       OR public.can_by_member(v_caller.id, 'manage_platform')) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  v_search := CASE WHEN p_action IS NOT NULL AND trim(p_action) != ''
                   THEN '%' || trim(p_action) || '%' ELSE NULL END;

  WITH unified AS (
    SELECT al.id::text AS id, 'members'::text AS category, al.created_at AS event_date,
      al.actor_id AS actor_id, actor.name AS actor_name,
      CASE al.action WHEN 'member.status_transition' THEN 'status_change'
        WHEN 'member.role_change' THEN 'role_change'
        ELSE replace(al.action, 'member.', '') END AS action,
      target.name AS target_name, al.target_id AS target_id,
      CASE al.action
        WHEN 'member.status_transition' THEN
          COALESCE(al.changes->>'previous_status','') || ' → ' || COALESCE(al.changes->>'new_status','')
        WHEN 'member.role_change' THEN
          COALESCE(al.changes->>'field','') || ': ' ||
          COALESCE(al.changes->>'old_value','') || ' → ' || COALESCE(al.changes->>'new_value','')
        ELSE al.changes::text END AS summary,
      COALESCE(al.metadata->>'reason_detail', al.metadata->>'reason') AS detail
    FROM public.admin_audit_log al
    LEFT JOIN public.members actor  ON actor.id  = al.actor_id
    LEFT JOIN public.members target ON target.id = al.target_id
    WHERE al.target_type = 'member'
      AND al.action IN ('member.status_transition','member.role_change')
    UNION ALL
    SELECT ble.id::text, 'boards', ble.created_at,
      ble.actor_member_id, actor.name, ble.action,
      COALESCE(bi.title, 'Card'), ble.item_id,
      COALESCE(ble.previous_status, '') ||
        CASE WHEN ble.new_status IS NOT NULL AND ble.previous_status IS NOT NULL THEN ' → ' || ble.new_status
             WHEN ble.new_status IS NOT NULL THEN ble.new_status ELSE '' END,
      ble.reason
    FROM public.board_lifecycle_events ble
    LEFT JOIN public.board_items bi ON bi.id = ble.item_id
    LEFT JOIN public.members actor ON actor.id = ble.actor_member_id
    UNION ALL
    SELECT al.id::text, 'settings', al.created_at,
      al.actor_id, actor.name, 'setting_changed',
      COALESCE(al.metadata->>'setting_key', '(unknown)'), NULL::uuid,
      COALESCE(al.changes->>'previous_value', '?') || ' → ' ||
      COALESCE(al.changes->>'new_value', '?'),
      al.metadata->>'reason'
    FROM public.admin_audit_log al
    LEFT JOIN public.members actor ON actor.id = al.actor_id
    WHERE al.action = 'platform.setting_changed'
    UNION ALL
    SELECT pi.id::text, 'partnerships', pi.created_at,
      pi.actor_member_id, actor.name, pi.interaction_type,
      pe.name, NULL::uuid, pi.summary, pi.outcome
    FROM public.partner_interactions pi
    JOIN public.partner_entities pe ON pe.id = pi.partner_id
    LEFT JOIN public.members actor ON actor.id = pi.actor_member_id
  )
  SELECT jsonb_agg(jsonb_build_object(
      'id', u.id, 'category', u.category, 'created_at', u.event_date,
      'actor_id', u.actor_id, 'actor_name', COALESCE(u.actor_name, 'Sistema'),
      'action', u.action, 'target_name', u.target_name, 'target_id', u.target_id,
      'changes', NULL, 'summary', u.summary, 'detail', u.detail
    ) ORDER BY u.event_date DESC)
  INTO v_entries FROM unified u
  WHERE (p_actor_id IS NULL OR u.actor_id = p_actor_id)
    AND (p_target_id IS NULL OR u.target_id = p_target_id)
    AND (p_date_from IS NULL OR u.event_date >= p_date_from)
    AND (p_date_to IS NULL OR u.event_date <= p_date_to)
    AND (v_search IS NULL OR u.action ILIKE v_search OR u.category ILIKE v_search
      OR u.target_name ILIKE v_search OR u.summary ILIKE v_search
      OR COALESCE(u.detail,'') ILIKE v_search OR COALESCE(u.actor_name,'') ILIKE v_search)
  LIMIT p_limit OFFSET p_offset;

  WITH unified2 AS (
    SELECT al.actor_id AS actor_id, al.created_at AS event_date,
           CASE al.action WHEN 'member.status_transition' THEN 'status_change'
                          WHEN 'member.role_change' THEN 'role_change'
                          ELSE replace(al.action,'member.','') END AS action,
           'members'::text AS category, target.name AS target_name,
           CASE al.action
             WHEN 'member.status_transition' THEN
               COALESCE(al.changes->>'previous_status','')||' → '||COALESCE(al.changes->>'new_status','')
             WHEN 'member.role_change' THEN
               COALESCE(al.changes->>'old_value','')||' → '||COALESCE(al.changes->>'new_value','')
             ELSE al.changes::text END AS summary,
           COALESCE(al.metadata->>'reason_detail', al.metadata->>'reason') AS detail,
           actor.name AS actor_name, al.target_id
    FROM public.admin_audit_log al
    LEFT JOIN public.members target ON target.id = al.target_id
    LEFT JOIN public.members actor ON actor.id = al.actor_id
    WHERE al.target_type = 'member'
      AND al.action IN ('member.status_transition','member.role_change')
    UNION ALL
    SELECT ble.actor_member_id, ble.created_at, ble.action, 'boards',
           COALESCE(bi.title,'Card'),
           COALESCE(ble.previous_status,'')||COALESCE(' → '||ble.new_status,''),
           ble.reason, actor.name, ble.item_id
    FROM public.board_lifecycle_events ble
    LEFT JOIN public.board_items bi ON bi.id = ble.item_id
    LEFT JOIN public.members actor ON actor.id = ble.actor_member_id
    UNION ALL
    SELECT al.actor_id, al.created_at, 'setting_changed', 'settings',
           COALESCE(al.metadata->>'setting_key','(unknown)'),
           COALESCE(al.changes->>'previous_value','?')||' → '||COALESCE(al.changes->>'new_value','?'),
           al.metadata->>'reason', actor.name, NULL::uuid
    FROM public.admin_audit_log al
    LEFT JOIN public.members actor ON actor.id = al.actor_id
    WHERE al.action = 'platform.setting_changed'
    UNION ALL
    SELECT pi.actor_member_id, pi.created_at, pi.interaction_type, 'partnerships',
           pe.name, pi.summary, pi.outcome, actor.name, NULL::uuid
    FROM public.partner_interactions pi
    JOIN public.partner_entities pe ON pe.id = pi.partner_id
    LEFT JOIN public.members actor ON actor.id = pi.actor_member_id
  )
  SELECT count(*) INTO v_total FROM unified2 u
  WHERE (p_actor_id IS NULL OR u.actor_id = p_actor_id)
    AND (p_target_id IS NULL OR u.target_id = p_target_id)
    AND (p_date_from IS NULL OR u.event_date >= p_date_from)
    AND (p_date_to IS NULL OR u.event_date <= p_date_to)
    AND (v_search IS NULL OR u.action ILIKE v_search OR u.category ILIKE v_search
      OR u.target_name ILIKE v_search OR u.summary ILIKE v_search
      OR COALESCE(u.detail,'') ILIKE v_search OR COALESCE(u.actor_name,'') ILIKE v_search);

  SELECT jsonb_agg(DISTINCT jsonb_build_object('id', a.id, 'name', a.name))
  INTO v_actors FROM (
    SELECT DISTINCT al.actor_id AS id FROM public.admin_audit_log al WHERE al.actor_id IS NOT NULL
    UNION SELECT DISTINCT ble.actor_member_id FROM public.board_lifecycle_events ble WHERE ble.actor_member_id IS NOT NULL
    UNION SELECT DISTINCT pi.actor_member_id FROM public.partner_interactions pi WHERE pi.actor_member_id IS NOT NULL
  ) ids JOIN public.members a ON a.id = ids.id;

  RETURN jsonb_build_object(
    'entries', COALESCE(v_entries, '[]'::jsonb),
    'total', COALESCE(v_total, 0),
    'actors', COALESCE(v_actors, '[]'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION public.get_cycle_evolution()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE result jsonb; v_c2_members int; v_c3_members int;
BEGIN
  SELECT count(DISTINCT member_id) INTO v_c2_members FROM member_cycle_history WHERE cycle_code = 'cycle_2';
  SELECT count(DISTINCT member_id) INTO v_c3_members FROM member_cycle_history WHERE cycle_code = 'cycle_3';

  SELECT jsonb_build_object(
    'cycles', jsonb_build_array(
      jsonb_build_object('cycle_code', 'pilot', 'cycle_label', 'Piloto 2024', 'members', 8,
        'chapters', 1, 'tribes', 0, 'events',
        (SELECT count(*) FROM events WHERE date BETWEEN '2024-06-01' AND '2024-12-31' AND title ILIKE '%Núcleo%'),
        'growth', null),
      jsonb_build_object('cycle_code', 'cycle_1', 'cycle_label', 'Ciclo 1 (2025/1)',
        'members', (SELECT count(DISTINCT member_id) FROM member_cycle_history WHERE cycle_code = 'cycle_1'),
        'chapters', 2, 'tribes', 5,
        'events', (SELECT count(*) FROM events WHERE date BETWEEN '2025-01-01' AND '2025-06-30'),
        'growth', ROUND(((SELECT count(DISTINCT member_id) FROM member_cycle_history WHERE cycle_code = 'cycle_1') - 8.0) / 8 * 100)),
      jsonb_build_object('cycle_code', 'cycle_2', 'cycle_label', 'Ciclo 2 (2025/2)',
        'members', v_c2_members, 'chapters', 2, 'tribes', 5,
        'events', (SELECT count(*) FROM events WHERE date BETWEEN '2025-07-01' AND '2025-12-31'),
        'growth', ROUND(((v_c2_members - (SELECT count(DISTINCT member_id) FROM member_cycle_history WHERE cycle_code = 'cycle_1')::numeric) / GREATEST((SELECT count(DISTINCT member_id) FROM member_cycle_history WHERE cycle_code = 'cycle_1'), 1)) * 100)),
      jsonb_build_object('cycle_code', 'cycle_3', 'cycle_label', 'Ciclo 3 (2026/1)',
        'members', v_c3_members, 'chapters', 5, 'tribes', 7,
        'events', (SELECT count(*) FROM events WHERE date >= '2026-01-01'),
        'growth', CASE WHEN v_c2_members > 0 THEN ROUND(((v_c3_members - v_c2_members)::numeric / v_c2_members) * 100) ELSE 0 END)
    ),
    'highlights', jsonb_build_object(
      'new_chapters', 3, 'chapter_names', 'PMI-DF, PMI-MG, PMI-RS',
      'platform_version', 'v2.0.0', 'governance_digital', true, 'mcp_server', true,
      'total_articles', (SELECT count(*) FROM publication_submissions),
      'total_events_c3', (SELECT count(*) FROM events WHERE date >= '2026-01-01'),
      'total_attendance', (SELECT count(*) FROM attendance WHERE present = true),
      'active_members', (SELECT count(*) FROM members WHERE is_active AND current_cycle_active),
      'blog_posts', (SELECT count(*) FROM blog_posts),
      'change_requests', (SELECT count(*) FROM change_requests WHERE status != 'withdrawn'),
      'board_items', (SELECT count(*) FROM board_items WHERE status != 'archived'),
      'gamification_points', (SELECT count(*) FROM gamification_points),
      'growth_c2_c3', CASE WHEN v_c2_members > 0 THEN ROUND(((v_c3_members - v_c2_members)::numeric / v_c2_members) * 100) ELSE 0 END
    )
  ) INTO result;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_diversity_dashboard(p_cycle_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller record; v_cycle_id uuid;
  v_by_gender jsonb; v_by_chapter jsonb; v_by_sector jsonb;
  v_by_seniority jsonb; v_by_region jsonb;
  v_applicants_total int; v_approved_total int; v_snapshots jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Unauthorized: member not found'; END IF;
  IF v_caller.is_superadmin IS NOT TRUE
    AND v_caller.operational_role NOT IN ('manager', 'deputy_manager')
    AND NOT (v_caller.designations && ARRAY['sponsor', 'chapter_liaison']::text[]) THEN
    RAISE EXCEPTION 'Unauthorized: admin or sponsor required';
  END IF;

  IF p_cycle_id IS NOT NULL THEN v_cycle_id := p_cycle_id;
  ELSE SELECT id INTO v_cycle_id FROM public.selection_cycles ORDER BY created_at DESC LIMIT 1;
  END IF;
  IF v_cycle_id IS NULL THEN RETURN jsonb_build_object('error', 'no_cycle_found'); END IF;

  SELECT COUNT(*) INTO v_applicants_total FROM public.selection_applications WHERE cycle_id = v_cycle_id;
  SELECT COUNT(*) INTO v_approved_total FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status IN ('approved', 'converted');

  SELECT jsonb_agg(jsonb_build_object('gender', gender_label, 'applicants', applicants, 'approved', approved))
  INTO v_by_gender FROM (
    SELECT
      CASE sa.gender WHEN 'M' THEN 'Masculino' WHEN 'F' THEN 'Feminino' ELSE COALESCE(sa.gender, 'Não informado') END as gender_label,
      COUNT(*) AS applicants, COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa WHERE sa.cycle_id = v_cycle_id
    GROUP BY gender_label ORDER BY applicants DESC
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('chapter', COALESCE(chapter, 'Não informado'), 'applicants', applicants, 'approved', approved))
  INTO v_by_chapter FROM (
    SELECT sa.chapter, COUNT(*) AS applicants, COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa WHERE sa.cycle_id = v_cycle_id GROUP BY sa.chapter ORDER BY applicants DESC
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('sector', COALESCE(sector, 'Não informado'), 'applicants', applicants, 'approved', approved))
  INTO v_by_sector FROM (
    SELECT sa.sector, COUNT(*) AS applicants, COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa WHERE sa.cycle_id = v_cycle_id GROUP BY sa.sector ORDER BY applicants DESC
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('band', band, 'applicants', applicants, 'approved', approved))
  INTO v_by_seniority FROM (
    SELECT
      CASE WHEN sa.seniority_years IS NULL THEN 'Não informado'
        WHEN sa.seniority_years < 3 THEN '0-2 anos' WHEN sa.seniority_years < 6 THEN '3-5 anos'
        WHEN sa.seniority_years < 11 THEN '6-10 anos' WHEN sa.seniority_years < 16 THEN '11-15 anos'
        ELSE '16+ anos' END AS band,
      COUNT(*) AS applicants, COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa WHERE sa.cycle_id = v_cycle_id GROUP BY band ORDER BY band
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('region', COALESCE(region, 'Não informado'), 'applicants', applicants, 'approved', approved))
  INTO v_by_region FROM (
    SELECT
      CASE
        WHEN sa.country IS NULL OR sa.country = '' THEN COALESCE(sa.state, 'Não informado')
        WHEN sa.country IN ('Brazil', 'BR', 'Brasil') THEN COALESCE(sa.state, 'Brasil')
        WHEN sa.state IS NOT NULL AND sa.state != '' THEN sa.state || ' (' || sa.country || ')'
        ELSE sa.country
      END AS region,
      COUNT(*) AS applicants, COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa WHERE sa.cycle_id = v_cycle_id GROUP BY region ORDER BY applicants DESC
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('snapshot_type', sds.snapshot_type, 'metrics', sds.metrics, 'created_at', sds.created_at) ORDER BY sds.created_at DESC) INTO v_snapshots
  FROM public.selection_diversity_snapshots sds WHERE sds.cycle_id = v_cycle_id;

  RETURN jsonb_build_object(
    'cycle_id', v_cycle_id,
    'applicants_total', v_applicants_total, 'approved_total', v_approved_total,
    'by_gender', COALESCE(v_by_gender, '[]'::jsonb),
    'by_chapter', COALESCE(v_by_chapter, '[]'::jsonb),
    'by_sector', COALESCE(v_by_sector, '[]'::jsonb),
    'by_seniority', COALESCE(v_by_seniority, '[]'::jsonb),
    'by_region', COALESCE(v_by_region, '[]'::jsonb),
    'snapshots', COALESCE(v_snapshots, '[]'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION public.get_initiative_events_timeline(p_initiative_id uuid, p_upcoming_limit integer DEFAULT 5, p_past_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_caller record; v_upcoming jsonb; v_past jsonb;
  v_today date := (NOW() AT TIME ZONE 'America/Sao_Paulo')::date;
  v_eligible int;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  SELECT count(*) INTO v_eligible FROM engagements
  WHERE initiative_id = p_initiative_id AND status = 'active';

  SELECT COALESCE(jsonb_agg(row_data ORDER BY row_data->>'date'), '[]'::jsonb)
  INTO v_upcoming FROM (
    SELECT jsonb_build_object('id', e.id, 'title', e.title, 'date', e.date, 'time_start', e.time_start,
      'type', e.type, 'duration_minutes', COALESCE(e.duration_minutes, 60),
      'meeting_link', e.meeting_link, 'agenda_text', e.agenda_text) as row_data
    FROM events e
    WHERE e.initiative_id = p_initiative_id AND e.date >= v_today
    ORDER BY e.date ASC LIMIT p_upcoming_limit
  ) sub;

  SELECT COALESCE(jsonb_agg(row_data ORDER BY (row_data->>'date') DESC), '[]'::jsonb)
  INTO v_past FROM (
    SELECT jsonb_build_object('id', e.id, 'title', e.title, 'date', e.date, 'time_start', e.time_start,
      'type', e.type, 'duration_minutes', COALESCE(e.duration_actual, e.duration_minutes, 60),
      'recording_url', e.recording_url, 'youtube_url', e.youtube_url,
      'has_recording', (e.youtube_url IS NOT NULL OR e.recording_url IS NOT NULL),
      'minutes_text', e.minutes_text,
      'has_minutes', (e.minutes_text IS NOT NULL AND e.minutes_text != ''),
      'agenda_text', e.agenda_text,
      'attendee_count', (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present = true),
      'eligible_count', v_eligible) as row_data
    FROM events e
    WHERE e.initiative_id = p_initiative_id AND e.date < v_today
    ORDER BY e.date DESC LIMIT p_past_limit
  ) sub;

  RETURN jsonb_build_object('upcoming', v_upcoming, 'past', v_past);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_initiative_stats(p_initiative_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_tribe_id int;
BEGIN
  v_tribe_id := public.resolve_tribe_id(p_initiative_id);
  IF v_tribe_id IS NOT NULL THEN
    RETURN public.get_tribe_stats(v_tribe_id);
  END IF;

  RETURN (
    WITH cycle AS (SELECT cycle_start FROM cycles WHERE is_current LIMIT 1),
    init_members AS (
      SELECT DISTINCT m.id, m.name FROM engagements eng
      JOIN members m ON m.person_id = eng.person_id
      WHERE eng.initiative_id = p_initiative_id AND eng.status = 'active'
    ),
    init_events AS (
      SELECT e.id, COALESCE(e.duration_actual, e.duration_minutes, 60) AS duration_minutes
      FROM events e, cycle c
      WHERE e.initiative_id = p_initiative_id AND e.date >= c.cycle_start AND e.date <= current_date
    ),
    att AS (
      SELECT a.event_id, a.member_id FROM attendance a
      JOIN init_events ie ON ie.id = a.event_id
      WHERE a.present = true AND a.excused IS NOT TRUE
    ),
    init_boards AS (
      SELECT bi.id, bi.status FROM board_items bi
      JOIN project_boards pb ON pb.id = bi.board_id
      WHERE pb.initiative_id = p_initiative_id
    )
    SELECT json_build_object(
      'member_count', (SELECT count(*) FROM init_members),
      'events_held', (SELECT count(*) FROM init_events),
      'attendance_rate', (SELECT round(
        count(a.*)::numeric / NULLIF((SELECT count(*) FROM init_members) * (SELECT count(*) FROM init_events), 0) * 100, 0
      ) FROM att a),
      'impact_hours', (SELECT coalesce(round(sum(ie.duration_minutes * sub.c)::numeric / 60, 1), 0)
        FROM init_events ie JOIN (SELECT event_id, count(*) c FROM att GROUP BY event_id) sub ON sub.event_id = ie.id),
      'cards_backlog', (SELECT count(*) FROM init_boards WHERE status = 'backlog'),
      'cards_in_progress', (SELECT count(*) FROM init_boards WHERE status = 'in_progress'),
      'cards_review', (SELECT count(*) FROM init_boards WHERE status = 'review'),
      'cards_done', (SELECT count(*) FROM init_boards WHERE status = 'done'),
      'top_contributors', (SELECT coalesce(json_agg(row_to_json(r) ORDER BY r.att_count DESC), '[]')
        FROM (
          SELECT im.name, count(a2.event_id) as att_count,
            round(count(a2.event_id)::numeric / NULLIF((SELECT count(*) FROM init_events), 0) * 100, 0) as rate
          FROM init_members im
          LEFT JOIN att a2 ON a2.member_id = im.id
          GROUP BY im.name
        ) r
      )
    )
  );
END;
$$;

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
      jsonb_build_object('name', 'Horas de Impacto',
        'current', COALESCE((
          SELECT round(sum(COALESCE(e.duration_actual, e.duration_minutes, 60)::numeric
            * (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present)) / 60)
          FROM events e WHERE e.date BETWEEN p_cycle_start AND p_cycle_end), 0),
        'target', 1800, 'unit', 'h', 'icon', 'clock'),
      jsonb_build_object('name', 'Certificação CPMAI',
        'current', (SELECT count(*) FROM members WHERE is_active AND cpmai_certified = true),
        'target', COALESCE((SELECT target_value::int FROM annual_kpi_targets WHERE kpi_key = 'cpmai_certified' AND year = 2026), 5),
        'unit', 'membros', 'icon', 'award'),
      jsonb_build_object('name', 'Pilotos de IA',
        'current', COALESCE((SELECT (value)::int FROM site_config WHERE key = 'kpi_pilot_count_override'), 0),
        'target', COALESCE((SELECT target_value::int FROM annual_kpi_targets WHERE kpi_key = 'pilots_completed' AND year = 2026), 3),
        'unit', '', 'icon', 'rocket'),
      jsonb_build_object('name', 'Artigos Publicados',
        'current', (SELECT count(*) FROM board_items bi JOIN project_boards pb ON pb.id = bi.board_id
          WHERE pb.board_name ILIKE '%publica%' AND bi.status IN ('done','published')),
        'target', COALESCE((SELECT target_value::int FROM annual_kpi_targets WHERE kpi_key = 'publications_submitted' AND year = 2026), 10),
        'unit', '', 'icon', 'file-text'),
      jsonb_build_object('name', 'Webinars Realizados',
        'current', (SELECT count(*) FROM events WHERE type = 'webinar' AND date BETWEEN p_cycle_start AND p_cycle_end),
        'target', COALESCE((SELECT target_value::int FROM annual_kpi_targets WHERE kpi_key = 'webinars_realized' AND year = 2026), 6),
        'unit', '', 'icon', 'video'),
      jsonb_build_object('name', 'Capítulos Integrados',
        'current', (SELECT count(DISTINCT chapter) FROM members WHERE is_active AND chapter IS NOT NULL),
        'target', COALESCE((SELECT target_value::int FROM annual_kpi_targets WHERE kpi_key = 'chapters_participating' AND year = 2026), 8),
        'unit', '', 'icon', 'map-pin')
    )
  ) INTO result;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_member_detail(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_result jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM members WHERE auth_id = auth.uid() AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager', 'sponsor', 'chapter_liaison'))) THEN RAISE EXCEPTION 'Admin only'; END IF;
  SELECT jsonb_build_object(
    'member', (SELECT jsonb_build_object('id', m.id, 'full_name', m.name, 'email', m.email, 'photo_url', m.photo_url, 'operational_role', m.operational_role, 'designations', m.designations, 'is_superadmin', m.is_superadmin, 'is_active', m.is_active, 'tribe_id', m.tribe_id, 'tribe_name', t.name, 'chapter', m.chapter, 'auth_id', m.auth_id, 'credly_username', m.credly_url, 'last_seen_at', m.last_seen_at, 'total_sessions', COALESCE(m.total_sessions, 0), 'credly_badges', COALESCE(m.credly_badges, '[]'::jsonb)) FROM members m LEFT JOIN tribes t ON t.id = m.tribe_id WHERE m.id = p_member_id),
    'cycles', (SELECT COALESCE(jsonb_agg(jsonb_build_object('cycle', mch.cycle, 'tribe_id', mch.tribe_id, 'tribe_name', t.name, 'operational_role', mch.operational_role, 'designations', mch.designations, 'status', mch.status) ORDER BY mch.cycle DESC), '[]'::jsonb) FROM member_cycle_history mch LEFT JOIN tribes t ON t.id = mch.tribe_id WHERE mch.member_id = p_member_id),
    'gamification', (SELECT jsonb_build_object('total_xp', COALESCE(gl.total_points, 0), 'rank', (SELECT rk FROM (SELECT member_id, ROW_NUMBER() OVER (ORDER BY total_points DESC) AS rk FROM gamification_leaderboard) ranked WHERE ranked.member_id = p_member_id), 'categories', (SELECT COALESCE(jsonb_agg(jsonb_build_object('category', gp.category, 'xp', gp.points, 'description', gp.reason)), '[]'::jsonb) FROM gamification_points gp WHERE gp.member_id = p_member_id)) FROM gamification_leaderboard gl WHERE gl.member_id = p_member_id),
    'attendance', (SELECT jsonb_build_object(
      'total_events', count(DISTINCT e.id),
      'attended', count(a.id),
      'rate', ROUND(count(a.id)::numeric / NULLIF(count(DISTINCT e.id), 0) * 100, 1),
      'recent', (SELECT COALESCE(jsonb_agg(jsonb_build_object('event_name', ev.title, 'event_date', ev.date, 'present', att.id IS NOT NULL) ORDER BY ev.date DESC), '[]'::jsonb)
        FROM (SELECT * FROM events WHERE date >= CURRENT_DATE - INTERVAL '6 months' AND date <= CURRENT_DATE ORDER BY date DESC LIMIT 20) ev
        LEFT JOIN attendance att ON att.event_id = ev.id AND att.member_id = p_member_id)
    ) FROM events e
      LEFT JOIN attendance a ON a.event_id = e.id AND a.member_id = p_member_id
      WHERE e.date >= CURRENT_DATE - INTERVAL '12 months' AND e.date <= CURRENT_DATE),
    'publications', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', ps.id, 'title', ps.title, 'status', ps.status, 'submitted_at', ps.submission_date, 'target_type', ps.target_type) ORDER BY ps.submission_date DESC), '[]'::jsonb) FROM publication_submissions ps JOIN publication_submission_authors psa ON psa.submission_id = ps.id WHERE psa.member_id = p_member_id),
    'audit_log', (SELECT COALESCE(jsonb_agg(jsonb_build_object('action', al.action, 'changes', al.changes, 'actor_name', actor.name, 'created_at', al.created_at) ORDER BY al.created_at DESC), '[]'::jsonb) FROM admin_audit_log al LEFT JOIN members actor ON actor.id = al.actor_id WHERE al.target_id = p_member_id AND al.target_type = 'member' LIMIT 20)
  ) INTO v_result;
  RETURN v_result;
END;
$$;

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
$$;
