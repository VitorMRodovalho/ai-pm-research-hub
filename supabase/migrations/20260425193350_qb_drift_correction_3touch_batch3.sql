-- Track Q-B Phase B (3-touch drift diff) — drift-correction batch 3 (17 fns + 3 overloads)
--
-- Captures live `pg_get_functiondef` body as-of 2026-04-25 for 17 of the 53
-- three-migration-touched (3-touch) functions where the live body diverged
-- from the latest migration capture, plus 3 overloads of `create_notification`
-- (overloaded by signature; included verbatim to keep all 3 captured).
--
-- Drift rate: 17/53 single-sig + create_notification overload uncertainty =
-- approximately 32%. Lower than batch 2's 26.5%? Actually higher — confirms
-- 3-touch bucket retained significant divergence opportunity. The hash-diff
-- methodology is name-only and doesn't differentiate overloads, so
-- create_notification's 3 overloads are all captured here regardless.
--
-- Bodies preserved verbatim from `pg_get_functiondef`. CREATE OR REPLACE
-- is idempotent on existing live state. Dollar-quote tag `$$` (verified
-- safe — no `$$` literals in any body).

CREATE OR REPLACE FUNCTION public.admin_change_tribe_leader(p_tribe_id integer, p_new_leader_id uuid, p_reason text DEFAULT 'Leadership transition'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller record;
  v_tribe record;
  v_old_leader record;
  v_new_leader record;
  v_cycle record;
BEGIN
  SELECT * INTO v_caller FROM public.get_my_member_record();
  IF v_caller IS NULL OR v_caller.is_superadmin IS NOT TRUE THEN
    RAISE EXCEPTION 'Superadmin access required';
  END IF;

  SELECT * INTO v_tribe FROM public.tribes WHERE id = p_tribe_id;
  IF v_tribe IS NULL THEN RAISE EXCEPTION 'Tribe not found: %', p_tribe_id; END IF;

  SELECT * INTO v_new_leader FROM public.members WHERE id = p_new_leader_id;
  IF v_new_leader IS NULL THEN RAISE EXCEPTION 'New leader member not found: %', p_new_leader_id; END IF;

  SELECT * INTO v_cycle FROM public.cycles WHERE is_current = true LIMIT 1;

  IF v_tribe.leader_member_id IS NOT NULL THEN
    SELECT * INTO v_old_leader FROM public.members WHERE id = v_tribe.leader_member_id;

    IF v_old_leader IS NOT NULL THEN
      INSERT INTO public.member_cycle_history (
        member_id, cycle_code, cycle_label, cycle_start, cycle_end,
        operational_role, designations, tribe_id, tribe_name,
        chapter, is_active, member_name_snapshot, notes
      ) VALUES (
        v_old_leader.id,
        COALESCE(v_cycle.cycle_code, 'cycle_3'), COALESCE(v_cycle.cycle_label, 'Ciclo 3'),
        COALESCE(v_cycle.cycle_start, now()::text), now()::text,
        v_old_leader.operational_role, v_old_leader.designations,
        v_old_leader.tribe_id, v_tribe.name,
        v_old_leader.chapter, true, v_old_leader.name,
        'LEADER_REMOVED: Replaced by ' || v_new_leader.name || '. Reason: ' || p_reason || '. By: ' || v_caller.name
      );

      UPDATE public.members SET operational_role = 'researcher'
      WHERE id = v_old_leader.id AND operational_role = 'tribe_leader';

      INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
      VALUES (v_caller.id, 'role.demoted', 'member', v_old_leader.id,
        jsonb_build_object('old_role', 'tribe_leader', 'new_role', 'researcher',
          'tribe_id', p_tribe_id, 'tribe_name', v_tribe.name, 'reason', p_reason));
    END IF;
  END IF;

  UPDATE public.members SET operational_role = 'tribe_leader', tribe_id = p_tribe_id
  WHERE id = p_new_leader_id;

  UPDATE public.tribes SET leader_member_id = p_new_leader_id WHERE id = p_tribe_id;

  INSERT INTO public.member_cycle_history (
    member_id, cycle_code, cycle_label, cycle_start, cycle_end,
    operational_role, designations, tribe_id, tribe_name,
    chapter, is_active, member_name_snapshot, notes
  ) VALUES (
    p_new_leader_id,
    COALESCE(v_cycle.cycle_code, 'cycle_3'), COALESCE(v_cycle.cycle_label, 'Ciclo 3'),
    COALESCE(v_cycle.cycle_start, now()::text), NULL,
    'tribe_leader', v_new_leader.designations, p_tribe_id, v_tribe.name,
    v_new_leader.chapter, true, v_new_leader.name,
    'LEADER_ASSIGNED: Promoted to leader of ' || v_tribe.name || '. Reason: ' || p_reason || '. By: ' || v_caller.name
  );

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller.id, 'role.promoted', 'member', p_new_leader_id,
    jsonb_build_object('old_role', v_new_leader.operational_role, 'new_role', 'tribe_leader',
      'tribe_id', p_tribe_id, 'tribe_name', v_tribe.name, 'reason', p_reason));

  RETURN jsonb_build_object(
    'success', true, 'tribe', v_tribe.name,
    'old_leader', COALESCE(v_old_leader.name, 'N/A'),
    'new_leader', v_new_leader.name, 'reason', p_reason
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_deactivate_member(p_member_id uuid, p_reason text DEFAULT 'Administrative deactivation'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller record;
  v_member record;
  v_tribe_name text;
  v_cycle record;
BEGIN
  SELECT * INTO v_caller FROM public.get_my_member_record();
  IF v_caller IS NULL OR v_caller.is_superadmin IS NOT TRUE THEN
    RAISE EXCEPTION 'Superadmin access required';
  END IF;

  SELECT * INTO v_member FROM public.members WHERE id = p_member_id;
  IF v_member IS NULL THEN
    RAISE EXCEPTION 'Member not found: %', p_member_id;
  END IF;

  SELECT name INTO v_tribe_name FROM public.tribes WHERE id = v_member.tribe_id;
  SELECT * INTO v_cycle FROM public.cycles WHERE is_current = true LIMIT 1;

  INSERT INTO public.member_cycle_history (
    member_id, cycle_code, cycle_label, cycle_start, cycle_end,
    operational_role, designations, tribe_id, tribe_name,
    chapter, is_active, member_name_snapshot, notes
  ) VALUES (
    p_member_id,
    COALESCE(v_cycle.cycle_code, 'cycle_3'),
    COALESCE(v_cycle.cycle_label, 'Ciclo 3'),
    COALESCE(v_cycle.cycle_start, now()::text),
    now()::text,
    v_member.operational_role,
    v_member.designations,
    v_member.tribe_id,
    COALESCE(v_tribe_name, 'N/A'),
    v_member.chapter,
    false,
    v_member.name,
    'DEACTIVATED: ' || p_reason || '. By: ' || v_caller.name
  );

  UPDATE public.members
  SET current_cycle_active = false,
      inactivated_at = now()
  WHERE id = p_member_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    v_caller.id, 'member.deactivated', 'member', p_member_id,
    jsonb_build_object('current_cycle_active', false, 'reason', p_reason)
  );

  RETURN jsonb_build_object(
    'success', true, 'member_name', v_member.name,
    'tribe', COALESCE(v_tribe_name, 'N/A'), 'reason', p_reason,
    'draft_email_subject', 'Comunicado: Afastamento de ' || v_member.name,
    'draft_email_body', 'Prezados,\n\nInformamos que o(a) pesquisador(a) ' || v_member.name || ' foi desligado(a) do Nucleo IA & GP.\nMotivo: ' || p_reason || '\n\nAtenciosamente,\nGerencia do Projeto'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_offboard_member(p_member_id uuid, p_new_status text, p_reason_category text, p_reason_detail text DEFAULT NULL::text, p_reassign_to uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller             record;
  v_member             record;
  v_audit_id           uuid;
  v_new_role           text;
  v_items_reassigned   integer := 0;
  v_engagements_closed integer := 0;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
    RETURN jsonb_build_object('error','Unauthorized: requires manage_member permission');
  END IF;

  IF p_new_status NOT IN ('observer','alumni','inactive') THEN
    RETURN jsonb_build_object('error','Invalid status: ' || p_new_status);
  END IF;

  SELECT * INTO v_member FROM public.members WHERE id = p_member_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Member not found'); END IF;

  IF v_member.member_status = p_new_status THEN
    RETURN jsonb_build_object('error','Member is already ' || p_new_status);
  END IF;

  v_new_role := CASE p_new_status
    WHEN 'alumni'   THEN 'alumni'
    WHEN 'observer' THEN 'observer'
    WHEN 'inactive' THEN 'none'
  END;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller.id,
    'member.status_transition',
    'member',
    p_member_id,
    jsonb_strip_nulls(jsonb_build_object(
      'previous_status', COALESCE(v_member.member_status,'active'),
      'new_status', p_new_status,
      'previous_tribe_id', v_member.tribe_id
    )),
    jsonb_strip_nulls(jsonb_build_object(
      'reason_category', p_reason_category,
      'reason_detail', p_reason_detail,
      'items_reassigned_to', p_reassign_to
    ))
  )
  RETURNING id INTO v_audit_id;

  IF v_member.operational_role IS DISTINCT FROM v_new_role THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      v_caller.id,
      'member.role_change',
      'member',
      p_member_id,
      jsonb_build_object(
        'field', 'operational_role',
        'old_value', to_jsonb(v_member.operational_role),
        'new_value', to_jsonb(v_new_role),
        'effective_date', CURRENT_DATE
      ),
      jsonb_strip_nulls(jsonb_build_object(
        'change_type', 'role_changed',
        'reason', p_reason_detail,
        'authorized_by', v_caller.id
      ))
    );
  END IF;

  UPDATE public.members SET
    member_status        = p_new_status,
    operational_role     = v_new_role,
    is_active            = false,
    designations         = '{}'::text[],
    offboarded_at        = now(),
    offboarded_by        = v_caller.id,
    status_changed_at    = now(),
    status_change_reason = COALESCE(p_reason_detail, p_reason_category),
    updated_at           = now()
  WHERE id = p_member_id;

  IF v_member.person_id IS NOT NULL THEN
    UPDATE public.engagements SET
      status = 'offboarded', end_date = CURRENT_DATE,
      revoked_at = now(), revoked_by = v_caller.person_id,
      revoke_reason = COALESCE(p_reason_detail, p_reason_category),
      updated_at = now()
    WHERE person_id = v_member.person_id AND status = 'active';
    GET DIAGNOSTICS v_engagements_closed = ROW_COUNT;
  END IF;

  IF p_reassign_to IS NOT NULL THEN
    UPDATE public.board_items SET assignee_id = p_reassign_to
    WHERE assignee_id = p_member_id AND status != 'archived';
    GET DIAGNOSTICS v_items_reassigned = ROW_COUNT;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'audit_id', v_audit_id,
    'transition_id', v_audit_id,
    'member_name', v_member.name,
    'previous_status', COALESCE(v_member.member_status,'active'),
    'new_status', p_new_status,
    'new_role', v_new_role,
    'items_reassigned', v_items_reassigned,
    'engagements_closed', v_engagements_closed,
    'designations_cleared', COALESCE(array_length(v_member.designations,1),0)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_member_present(p_event_id uuid, p_member_id uuid, p_present boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid; v_caller_role text; v_is_admin boolean; v_caller_tribe int;
BEGIN
  SELECT id, operational_role, is_superadmin, tribe_id
  INTO v_caller_id, v_caller_role, v_is_admin, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  -- Self: always allowed
  IF v_caller_id = p_member_id THEN NULL;
  -- Admin/GP: always allowed
  ELSIF v_is_admin = true OR v_caller_role IN ('manager', 'deputy_manager') THEN NULL;
  -- Tribe leader: can mark own tribe members on ANY event (tribe or global)
  ELSIF v_caller_role = 'tribe_leader' THEN
    IF NOT EXISTS (
      SELECT 1 FROM members m WHERE m.id = p_member_id AND m.tribe_id = v_caller_tribe
    ) THEN
      RAISE EXCEPTION 'Tribe leaders can only mark attendance for their own tribe members';
    END IF;
  ELSE
    RAISE EXCEPTION 'Unauthorized: can only mark own presence or requires admin/leader role';
  END IF;

  IF p_present THEN
    INSERT INTO public.attendance (event_id, member_id) VALUES (p_event_id, p_member_id) ON CONFLICT (event_id, member_id) DO NOTHING;
  ELSE
    DELETE FROM public.attendance WHERE event_id = p_event_id AND member_id = p_member_id;
  END IF;
  RETURN json_build_object('success', true);
END;
$$;

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
$$;

CREATE OR REPLACE FUNCTION public.process_email_webhook(p_resend_id text, p_event_type text, p_update_fields jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_send_id uuid;
  v_delivered_at timestamptz;
  v_user_agent text;
  v_is_bot boolean := false;
  v_known_bot_patterns text[] := ARRAY[
    'GoogleImageProxy', 'YahooMailProxy', 'Outlook-iOS',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'python-requests', 'Go-http-client', 'curl',
    'Barracuda', 'ZScaler', 'Mimecast', 'Proofpoint',
    'MessageLabs', 'Symantec', 'FireEye', 'Trend Micro'
  ];
  v_pattern text;
BEGIN
  CASE p_event_type
    WHEN 'email.delivered' THEN
      UPDATE campaign_recipients SET
        delivered = true,
        delivered_at = COALESCE(delivered_at, now())
      WHERE resend_id = p_resend_id;

    WHEN 'email.opened' THEN
      v_user_agent := p_update_fields->>'user_agent';

      SELECT delivered_at INTO v_delivered_at
      FROM campaign_recipients WHERE resend_id = p_resend_id;

      -- Bot detection: timing (<30s after delivery)
      IF v_delivered_at IS NOT NULL
         AND (now() - v_delivered_at) < interval '30 seconds' THEN
        v_is_bot := true;
      END IF;

      -- Bot detection: known bot user-agent patterns
      IF v_user_agent IS NOT NULL THEN
        FOREACH v_pattern IN ARRAY v_known_bot_patterns LOOP
          IF v_user_agent ILIKE '%' || v_pattern || '%' THEN
            v_is_bot := true;
            EXIT;
          END IF;
        END LOOP;
      END IF;

      UPDATE campaign_recipients SET
        opened = true,
        opened_at = COALESCE(opened_at, now()),
        first_opened_at = COALESCE(first_opened_at, now()),
        open_count = open_count + 1,
        last_user_agent = COALESCE(v_user_agent, last_user_agent),
        bot_suspected = bot_suspected OR v_is_bot
      WHERE resend_id = p_resend_id;

    WHEN 'email.clicked' THEN
      -- Click = strong human signal — clear bot flag
      UPDATE campaign_recipients SET
        clicked_at = COALESCE(clicked_at, now()),
        click_count = click_count + 1,
        bot_suspected = false
      WHERE resend_id = p_resend_id;

    WHEN 'email.bounced' THEN
      UPDATE campaign_recipients SET
        bounced_at = COALESCE(bounced_at, now()),
        bounce_type = COALESCE(p_update_fields->>'bounce_type', 'unknown')
      WHERE resend_id = p_resend_id;

    WHEN 'email.complained' THEN
      UPDATE campaign_recipients SET
        complained_at = COALESCE(complained_at, now()),
        unsubscribed = true
      WHERE resend_id = p_resend_id;
  END CASE;

  UPDATE email_webhook_events SET processed = true
  WHERE resend_id = p_resend_id AND event_type = p_event_type
  AND processed = false;

  SELECT send_id INTO v_send_id FROM campaign_recipients WHERE resend_id = p_resend_id;
  IF v_send_id IS NOT NULL THEN
    UPDATE campaign_sends SET
      delivered_count = (SELECT count(*) FROM campaign_recipients WHERE send_id = v_send_id AND delivered = true),
      failed_count = (SELECT count(*) FROM campaign_recipients WHERE send_id = v_send_id AND bounced_at IS NOT NULL)
    WHERE id = v_send_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.exec_funnel_summary(p_cycle_code text DEFAULT NULL::text, p_tribe_id integer DEFAULT NULL::integer, p_chapter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT public.can_read_internal_analytics() THEN
    RAISE EXCEPTION 'Internal analytics access required';
  END IF;

  WITH scoped AS (
    SELECT * FROM public.analytics_member_scope(p_cycle_code, p_tribe_id, p_chapter)
  ),
  core_total AS (
    SELECT count(*)::integer AS total_core_courses FROM public.courses WHERE category = 'core'
  ),
  member_core_progress AS (
    SELECT s.member_id,
      count(DISTINCT cp.course_id) FILTER (WHERE cp.status = 'completed')::integer AS completed_core_courses
    FROM scoped s
    LEFT JOIN public.course_progress cp ON cp.member_id = s.member_id
    LEFT JOIN public.courses c ON c.id = cp.course_id AND c.category = 'core'
    GROUP BY s.member_id
  ),
  published_publications AS (
    -- ADR-0012 archival: ex-artifacts table → publication_submissions
    SELECT DISTINCT s.member_id
    FROM scoped s
    JOIN public.publication_submissions ps ON ps.primary_author_id = s.member_id
    WHERE ps.status = 'published'::submission_status
      AND coalesce(ps.acceptance_date, ps.submission_date, ps.created_at::date, now()::date) >= s.cycle_start::date
      AND (s.cycle_end IS NULL OR coalesce(ps.acceptance_date, ps.submission_date, ps.created_at::date, now()::date) < (s.cycle_end + interval '1 day')::date)
  ),
  stage_rollup AS (
    SELECT
      count(DISTINCT s.member_id)::integer AS total_members,
      count(DISTINCT s.member_id) FILTER (
        WHERE coalesce(mcp.completed_core_courses, 0) >= coalesce((SELECT total_core_courses FROM core_total), 0)
      )::integer AS members_with_full_core_trail,
      count(DISTINCT s.member_id) FILTER (WHERE s.tribe_id IS NOT NULL)::integer AS members_allocated_to_tribe,
      count(DISTINCT pp.member_id)::integer AS members_with_published_artifact
    FROM scoped s
    LEFT JOIN member_core_progress mcp ON mcp.member_id = s.member_id
    LEFT JOIN published_publications pp ON pp.member_id = s.member_id
  )
  SELECT jsonb_build_object(
    'cycle_code', (SELECT max(cycle_code) FROM scoped),
    'cycle_label', (SELECT max(cycle_label) FROM scoped),
    'filters', jsonb_build_object('cycle_code', p_cycle_code, 'tribe_id', p_tribe_id, 'chapter', p_chapter),
    'stages', jsonb_build_object(
      'total_members', coalesce((SELECT total_members FROM stage_rollup), 0),
      'members_with_full_core_trail', coalesce((SELECT members_with_full_core_trail FROM stage_rollup), 0),
      'members_allocated_to_tribe', coalesce((SELECT members_allocated_to_tribe FROM stage_rollup), 0),
      'members_with_published_artifact', coalesce((SELECT members_with_published_artifact FROM stage_rollup), 0)
    ),
    'breakdown_by_tribe', coalesce((
      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.tribe_id) FROM (
        SELECT s.tribe_id,
          count(DISTINCT s.member_id)::integer AS total_members,
          count(DISTINCT s.member_id) FILTER (
            WHERE coalesce(mcp.completed_core_courses, 0) >= coalesce((SELECT total_core_courses FROM core_total), 0)
          )::integer AS members_with_full_core_trail,
          count(DISTINCT s.member_id) FILTER (WHERE s.tribe_id IS NOT NULL)::integer AS members_allocated_to_tribe,
          count(DISTINCT pp.member_id)::integer AS members_with_published_artifact
        FROM scoped s
        LEFT JOIN member_core_progress mcp ON mcp.member_id = s.member_id
        LEFT JOIN published_publications pp ON pp.member_id = s.member_id
        WHERE s.tribe_id IS NOT NULL GROUP BY s.tribe_id
      ) t
    ), '[]'::jsonb),
    'breakdown_by_chapter', coalesce((
      SELECT jsonb_agg(to_jsonb(c) ORDER BY c.chapter) FROM (
        SELECT s.chapter,
          count(DISTINCT s.member_id)::integer AS total_members,
          count(DISTINCT s.member_id) FILTER (
            WHERE coalesce(mcp.completed_core_courses, 0) >= coalesce((SELECT total_core_courses FROM core_total), 0)
          )::integer AS members_with_full_core_trail,
          count(DISTINCT s.member_id) FILTER (WHERE s.tribe_id IS NOT NULL)::integer AS members_allocated_to_tribe,
          count(DISTINCT pp.member_id)::integer AS members_with_published_artifact
        FROM scoped s
        LEFT JOIN member_core_progress mcp ON mcp.member_id = s.member_id
        LEFT JOIN published_publications pp ON pp.member_id = s.member_id
        WHERE s.chapter IS NOT NULL AND trim(s.chapter) <> '' GROUP BY s.chapter
      ) c
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN coalesce(v_result, jsonb_build_object(
    'cycle_code', p_cycle_code,
    'filters', jsonb_build_object('cycle_code', p_cycle_code, 'tribe_id', p_tribe_id, 'chapter', p_chapter),
    'stages', jsonb_build_object('total_members', 0, 'members_with_full_core_trail', 0, 'members_allocated_to_tribe', 0, 'members_with_published_artifact', 0),
    'breakdown_by_tribe', '[]'::jsonb, 'breakdown_by_chapter', '[]'::jsonb
  ));
END;
$$;

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
$$;

CREATE OR REPLACE FUNCTION public.export_my_data()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_member_id uuid;
  v_member_email text;
  v_person_id uuid;
  v_result jsonb;
BEGIN
  SELECT id, email INTO v_member_id, v_member_email
  FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT id INTO v_person_id FROM public.persons WHERE legacy_member_id = v_member_id;

  SELECT jsonb_build_object(
    'profile', (SELECT row_to_json(m)::jsonb FROM public.members m WHERE m.id = v_member_id),
    'person', CASE WHEN v_person_id IS NOT NULL THEN
      (SELECT row_to_json(p)::jsonb FROM public.persons p WHERE p.id = v_person_id)
    ELSE NULL END,
    'engagements', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', e.id, 'kind', e.kind, 'role', e.role, 'status', e.status,
        'initiative_name', i.name, 'start_date', e.start_date, 'end_date', e.end_date,
        'legal_basis', e.legal_basis, 'has_agreement', (e.agreement_certificate_id IS NOT NULL),
        'granted_at', e.granted_at, 'revoked_at', e.revoked_at, 'revoke_reason', e.revoke_reason
      ) ORDER BY e.start_date DESC)
      FROM public.engagements e LEFT JOIN public.initiatives i ON i.id = e.initiative_id
      WHERE e.person_id = v_person_id
    ), '[]'::jsonb),
    'attendance', COALESCE((SELECT jsonb_agg(row_to_json(a)::jsonb) FROM public.attendance a WHERE a.member_id = v_member_id), '[]'::jsonb),
    'gamification', COALESCE((SELECT jsonb_agg(row_to_json(g)::jsonb) FROM public.gamification_points g WHERE g.member_id = v_member_id), '[]'::jsonb),
    'notifications', COALESCE((SELECT jsonb_agg(row_to_json(n)::jsonb) FROM public.notifications n WHERE n.recipient_id = v_member_id), '[]'::jsonb),
    'board_assignments', COALESCE((SELECT jsonb_agg(row_to_json(ba)::jsonb) FROM public.board_item_assignments ba WHERE ba.member_id = v_member_id), '[]'::jsonb),
    'cycle_history', COALESCE((SELECT jsonb_agg(row_to_json(mch)::jsonb) FROM public.member_cycle_history mch WHERE mch.member_id = v_member_id), '[]'::jsonb),
    'certificates', COALESCE((SELECT jsonb_agg(row_to_json(c)::jsonb) FROM public.certificates c WHERE c.member_id = v_member_id), '[]'::jsonb),
    'selection_applications', COALESCE((SELECT jsonb_agg(row_to_json(sa)::jsonb) FROM public.selection_applications sa WHERE sa.email = v_member_email), '[]'::jsonb),
    'onboarding', COALESCE((SELECT jsonb_agg(row_to_json(op)::jsonb) FROM public.onboarding_progress op WHERE op.member_id = v_member_id), '[]'::jsonb),
    'exported_at', now()
  ) INTO v_result;
  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_board_members(p_board_id uuid)
 RETURNS TABLE(id uuid, name text, photo_url text, operational_role text, board_role text, designations text[])
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_board record;
  v_board_legacy_tribe_id int;
BEGIN
  SELECT pb.* INTO v_board FROM project_boards pb WHERE pb.id = p_board_id;
  IF NOT FOUND THEN RETURN; END IF;

  SELECT i.legacy_tribe_id INTO v_board_legacy_tribe_id
  FROM public.initiatives i WHERE i.id = v_board.initiative_id;

  RETURN QUERY
  SELECT DISTINCT ON (q.id) q.id, q.name, q.photo_url, q.operational_role, q.board_role, q.designations
  FROM (
    SELECT m.id, m.name, m.photo_url, m.operational_role, 'tribe_member'::text as board_role, m.designations, 1 as priority
    FROM members m
    WHERE v_board_legacy_tribe_id IS NOT NULL
      AND m.tribe_id = v_board_legacy_tribe_id
      AND m.is_active = true
      AND m.member_status = 'active'
    UNION ALL
    SELECT bm.member_id, m.name, m.photo_url, m.operational_role, bm.board_role, m.designations, 2
    FROM board_members bm
    JOIN members m ON m.id = bm.member_id
    WHERE bm.board_id = p_board_id
      AND m.is_active = true
    UNION ALL
    SELECT m.id, m.name, m.photo_url, m.operational_role, 'curator'::text, m.designations, 3
    FROM members m
    WHERE 'curator' = ANY(m.designations)
      AND m.is_active = true
    UNION ALL
    SELECT m.id, m.name, m.photo_url, m.operational_role, 'gp'::text, m.designations, 4
    FROM members m
    WHERE m.is_active = true
      AND (m.is_superadmin = true OR m.operational_role IN ('manager', 'deputy_manager'))
  ) q
  ORDER BY q.id, q.priority;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_card_timeline(p_item_id uuid)
 RETURNS TABLE(id bigint, action text, previous_status text, new_status text, reason text, actor_name text, created_at timestamp with time zone, review_score jsonb, review_round integer, sla_deadline timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  RETURN QUERY
  SELECT
    e.id,
    e.action,
    e.previous_status,
    e.new_status,
    e.reason,
    m.name AS actor_name,
    e.created_at,
    e.review_score,
    e.review_round,
    e.sla_deadline
  FROM board_lifecycle_events e
  LEFT JOIN members m ON m.id = e.actor_member_id
  WHERE e.item_id = p_item_id
  ORDER BY e.created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_evaluation_form(p_application_id uuid, p_evaluation_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller record; v_app record; v_cycle record; v_committee record; v_draft record; v_criteria jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Unauthorized: member not found'; END IF;
  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN RAISE EXCEPTION 'Application not found: %', p_application_id; END IF;
  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;
  SELECT * INTO v_committee FROM public.selection_committee WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;
  IF v_committee IS NULL AND v_caller.is_superadmin IS NOT TRUE THEN RAISE EXCEPTION 'Unauthorized: not a committee member'; END IF;

  v_criteria := CASE p_evaluation_type
    WHEN 'objective' THEN v_cycle.objective_criteria
    WHEN 'interview' THEN v_cycle.interview_criteria
    WHEN 'leader_extra' THEN v_cycle.leader_extra_criteria
    ELSE '[]'::jsonb END;

  SELECT * INTO v_draft FROM public.selection_evaluations
  WHERE application_id = p_application_id AND evaluator_id = v_caller.id AND evaluation_type = p_evaluation_type;

  RETURN jsonb_build_object(
    'application', jsonb_build_object(
      'id', v_app.id, 'applicant_name', v_app.applicant_name, 'email', v_app.email,
      'chapter', v_app.chapter, 'role_applied', v_app.role_applied,
      'certifications', v_app.certifications, 'linkedin_url', v_app.linkedin_url,
      'resume_url', v_app.resume_url, 'motivation_letter', v_app.motivation_letter,
      'reason_for_applying', v_app.reason_for_applying,
      'chapter_affiliation', v_app.chapter_affiliation,
      'non_pmi_experience', v_app.non_pmi_experience, 'areas_of_interest', v_app.areas_of_interest,
      'availability_declared', v_app.availability_declared, 'proposed_theme', v_app.proposed_theme,
      'leadership_experience', v_app.leadership_experience, 'academic_background', v_app.academic_background,
      'membership_status', v_app.membership_status, 'status', v_app.status
    ),
    'criteria', v_criteria, 'evaluation_type', p_evaluation_type,
    'committee_role', COALESCE(v_committee.role, 'superadmin'),
    'draft', CASE WHEN v_draft IS NOT NULL THEN jsonb_build_object(
      'id', v_draft.id, 'scores', v_draft.scores, 'notes', v_draft.notes,
      'criterion_notes', COALESCE(v_draft.criterion_notes, '{}'::jsonb),
      'weighted_subtotal', v_draft.weighted_subtotal, 'submitted_at', v_draft.submitted_at
    ) ELSE NULL END,
    'is_locked', CASE WHEN v_draft.submitted_at IS NOT NULL THEN true ELSE false END
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_initiative_attendance_grid(p_initiative_id uuid, p_event_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_caller record;
  v_tribe_id int;
  v_cycle_start date;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  v_tribe_id := public.resolve_tribe_id(p_initiative_id);

  IF v_tribe_id IS NOT NULL THEN
    RETURN public.get_tribe_attendance_grid(v_tribe_id, p_event_type);
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := '2026-03-01'; END IF;

  WITH
  grid_events AS (
    SELECT e.id, e.date, e.title, e.type,
           COALESCE(e.duration_actual, e.duration_minutes, 60) AS duration_minutes,
           EXTRACT(WEEK FROM e.date)::int AS week_number
    FROM events e
    WHERE e.initiative_id = p_initiative_id
      AND e.date >= v_cycle_start
      AND (p_event_type IS NULL OR e.type = p_event_type)
    ORDER BY e.date
  ),
  grid_members AS (
    SELECT DISTINCT m.id, m.name, m.chapter, m.operational_role, m.designations, m.member_status
    FROM engagements eng
    JOIN members m ON m.person_id = eng.person_id
    WHERE eng.initiative_id = p_initiative_id AND eng.status = 'active'
    UNION
    SELECT DISTINCT m.id, m.name, m.chapter, m.operational_role, m.designations, m.member_status
    FROM members m
    JOIN attendance a ON a.member_id = m.id
    JOIN grid_events ge ON ge.id = a.event_id
  ),
  cell_status AS (
    SELECT
      gm.id AS member_id, ge.id AS event_id,
      CASE
        WHEN ge.date > CURRENT_DATE THEN
          CASE WHEN gm.member_status != 'active' THEN 'na' ELSE 'scheduled' END
        WHEN a.id IS NOT NULL AND a.excused = true THEN 'excused'
        WHEN a.id IS NOT NULL AND a.present = true THEN 'present'
        WHEN a.id IS NOT NULL THEN 'absent'
        ELSE 'absent'
      END AS status
    FROM grid_members gm
    CROSS JOIN grid_events ge
    LEFT JOIN attendance a ON a.member_id = gm.id AND a.event_id = ge.id
  ),
  member_stats AS (
    SELECT
      cs.member_id,
      COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent', 'excused')) AS eligible_count,
      COUNT(*) FILTER (WHERE cs.status = 'present') AS present_count,
      ROUND(
        COUNT(*) FILTER (WHERE cs.status = 'present')::numeric
        / NULLIF(COUNT(*) FILTER (WHERE cs.status IN ('present', 'absent')), 0), 2
      ) AS rate,
      ROUND(
        SUM(CASE WHEN cs.status = 'present' THEN ge.duration_minutes ELSE 0 END)::numeric / 60, 1
      ) AS hours
    FROM cell_status cs
    JOIN grid_events ge ON ge.id = cs.event_id
    GROUP BY cs.member_id
  )
  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total_members', (SELECT COUNT(DISTINCT id) FROM grid_members WHERE member_status = 'active'),
      'overall_rate', COALESCE((SELECT ROUND(AVG(ms.rate), 2) FROM member_stats ms JOIN grid_members gm ON gm.id = ms.member_id WHERE gm.member_status = 'active'), 0),
      'total_events', (SELECT COUNT(*) FROM grid_events),
      'past_events', (SELECT COUNT(*) FROM grid_events WHERE date <= CURRENT_DATE),
      'total_hours', COALESCE((SELECT ROUND(SUM(ms.hours), 1) FROM member_stats ms), 0)
    ),
    'events', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', ge.id, 'date', ge.date, 'title', ge.title, 'type', ge.type,
      'duration_minutes', ge.duration_minutes, 'week_number', ge.week_number,
      'is_tribe_event', false,
      'is_future', (ge.date > CURRENT_DATE)
    ) ORDER BY ge.date), '[]'::jsonb) FROM grid_events ge),
    'members', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', gm.id, 'name', gm.name, 'chapter', gm.chapter,
        'member_status', gm.member_status,
        'rate', COALESCE(ms.rate, 0),
        'hours', COALESCE(ms.hours, 0),
        'eligible_count', COALESCE(ms.eligible_count, 0),
        'present_count', COALESCE(ms.present_count, 0),
        'detractor_status', 'regular',
        'consecutive_absences', 0,
        'attendance', (
          SELECT COALESCE(jsonb_object_agg(cs.event_id::text, cs.status), '{}'::jsonb)
          FROM cell_status cs WHERE cs.member_id = gm.id
        )
      ) ORDER BY COALESCE(ms.rate, 0) ASC), '[]'::jsonb)
      FROM grid_members gm
      LEFT JOIN member_stats ms ON ms.member_id = gm.id
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_pending_countersign()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_member_id uuid; v_member_chapter text; v_is_manager boolean; v_is_chapter_board boolean; result jsonb;
BEGIN
  SELECT m.id, m.chapter,
    (m.operational_role IN ('manager') OR m.is_superadmin = true),
    ('chapter_board' = ANY(m.designations))
  INTO v_member_id, v_member_chapter, v_is_manager, v_is_chapter_board
  FROM members m WHERE m.auth_id = auth.uid();
  IF NOT COALESCE(v_is_manager, false) AND NOT COALESCE(v_is_chapter_board, false) THEN
    RETURN '[]'::jsonb;
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', c.id, 'type', c.type, 'title', c.title, 'member_name', m.name, 'member_email', m.email,
    'member_role', m.operational_role, 'member_chapter', m.chapter, 'tribe_name', t.name, 'cycle', c.cycle,
    'verification_code', c.verification_code, 'issued_at', c.issued_at,
    'signature_hash', c.signature_hash
  ) ORDER BY c.issued_at DESC), '[]'::jsonb) INTO result
  FROM certificates c
  JOIN members m ON m.id = c.member_id
  LEFT JOIN tribes t ON t.id = m.tribe_id
  WHERE c.counter_signed_by IS NULL
    AND COALESCE(c.status, 'issued') = 'issued'
    AND c.type != 'volunteer_agreement'
    AND (COALESCE(v_is_manager, false) OR m.chapter = v_member_chapter);
  RETURN result;
END;
$$;

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
$$;

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
$$;

CREATE OR REPLACE FUNCTION public.update_event_instance(p_event_id uuid, p_new_date date DEFAULT NULL::date, p_new_time_start time without time zone DEFAULT NULL::time without time zone, p_new_duration_minutes integer DEFAULT NULL::integer, p_meeting_link text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_agenda_text text DEFAULT NULL::text)
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
  v_event_exists boolean;
  v_updated text[] := '{}';
BEGIN
  SELECT id, operational_role, tribe_id INTO v_caller_id, v_caller_role, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT true, i.legacy_tribe_id
    INTO v_event_exists, v_event_tribe
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.id = p_event_id;
  IF v_event_exists IS NOT TRUE THEN RAISE EXCEPTION 'Event not found'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event permission';
  END IF;
  IF v_caller_role = 'tribe_leader' AND v_caller_tribe IS DISTINCT FROM v_event_tribe THEN
    RAISE EXCEPTION 'Unauthorized: tribe_leader can only manage events of own tribe';
  END IF;

  IF p_new_date IS NOT NULL THEN
    IF v_event_tribe IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.events e2
      JOIN public.initiatives i2 ON i2.id = e2.initiative_id
      WHERE i2.legacy_tribe_id = v_event_tribe
        AND e2.date = p_new_date
        AND e2.id <> p_event_id
    ) THEN
      RAISE EXCEPTION 'Ja existe um evento desta tribo na data %', p_new_date;
    END IF;
    UPDATE public.events SET date = p_new_date, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'date');
  END IF;
  IF p_new_time_start IS NOT NULL THEN
    UPDATE public.events SET time_start = p_new_time_start, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'time_start');
  END IF;
  IF p_new_duration_minutes IS NOT NULL THEN
    UPDATE public.events SET duration_minutes = p_new_duration_minutes, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'duration_minutes');
  END IF;
  IF p_meeting_link IS NOT NULL THEN
    UPDATE public.events SET meeting_link = p_meeting_link, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'meeting_link');
  END IF;
  IF p_notes IS NOT NULL THEN
    UPDATE public.events SET notes = p_notes, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'notes');
  END IF;
  IF p_agenda_text IS NOT NULL THEN
    UPDATE public.events SET agenda_text = p_agenda_text, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'agenda_text');
  END IF;

  RETURN json_build_object('success', true, 'event_id', p_event_id, 'updated_fields', to_json(v_updated));
END;
$$;

CREATE OR REPLACE FUNCTION public.create_notification(p_recipient_id uuid, p_type text, p_source_type text DEFAULT NULL::text, p_source_id uuid DEFAULT NULL::uuid, p_source_title text DEFAULT NULL::text, p_actor_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE v_notif_id uuid; v_prefs record;
BEGIN
  IF p_recipient_id = p_actor_id THEN RETURN NULL; END IF;
  SELECT * INTO v_prefs FROM notification_preferences WHERE member_id = p_recipient_id;
  IF FOUND THEN
    IF v_prefs.in_app = false THEN RETURN NULL; END IF;
    IF p_type = ANY(v_prefs.muted_types) THEN RETURN NULL; END IF;
  END IF;
  INSERT INTO notifications (recipient_id, type, source_type, source_id, title, actor_id, delivery_mode)
  VALUES (p_recipient_id, p_type, p_source_type, p_source_id, p_source_title, p_actor_id,
          public._delivery_mode_for(p_type))
  RETURNING id INTO v_notif_id;
  RETURN v_notif_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_notification(p_recipient_id uuid, p_type text, p_source_type text, p_source_id uuid, p_source_title text, p_actor_id uuid, p_body text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE v_notif_id uuid; v_prefs record;
BEGIN
  IF p_recipient_id = p_actor_id THEN RETURN NULL; END IF;
  SELECT * INTO v_prefs FROM notification_preferences WHERE member_id = p_recipient_id;
  IF FOUND THEN
    IF v_prefs.in_app = false THEN RETURN NULL; END IF;
    IF p_type = ANY(v_prefs.muted_types) THEN RETURN NULL; END IF;
  END IF;
  INSERT INTO notifications (recipient_id, type, source_type, source_id, title, body, actor_id, delivery_mode)
  VALUES (p_recipient_id, p_type, p_source_type, p_source_id, p_source_title, p_body, p_actor_id,
          public._delivery_mode_for(p_type))
  RETURNING id INTO v_notif_id;
  RETURN v_notif_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_notification(p_recipient_id uuid, p_type text, p_title text, p_body text DEFAULT NULL::text, p_link text DEFAULT NULL::text, p_source_type text DEFAULT NULL::text, p_source_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_prefs notification_preferences%ROWTYPE;
BEGIN
  SELECT * INTO v_prefs FROM notification_preferences WHERE member_id = p_recipient_id;
  IF FOUND THEN
    IF NOT v_prefs.in_app THEN RETURN; END IF;
    IF p_type = ANY(v_prefs.muted_types) THEN RETURN; END IF;
  END IF;

  INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
  VALUES (p_recipient_id, p_type, p_title, p_body, p_link, p_source_type, p_source_id,
          public._delivery_mode_for(p_type));
END;
$$;
