-- p178 Phase B drift capture — 1-touch bucket H-P (25 fns).
--
-- Recurring drift-recovery under Q-C/Phase-C charter
-- (docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md §Phase C). Each fn below is currently
-- in the 1-touch bucket of `RPC_BODY_DRIFT_ALLOWLIST_P175.txt` — captured by
-- exactly one prior migration whose body has since drifted from live.
--
-- Bodies pulled via pg_get_functiondef() — live IS canonical at the time of
-- capture. After apply, these fns are clean per Phase C body-hash drift contract
-- and can be removed from the allowlist. BODY_DRIFT_BASELINE_SIZE 88→63.
--
-- Rollback: not needed — capturing live state. To revert a single fn, restore
-- its prior CREATE OR REPLACE FUNCTION body from the migration in `latest_file`.

CREATE OR REPLACE FUNCTION public.invite_alumni_to_re_engage(p_pipeline_id uuid, p_message text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_pipeline record;
  v_member record;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
    RETURN jsonb_build_object('error','Unauthorized: requires manage_member permission');
  END IF;

  SELECT * INTO v_pipeline FROM public.re_engagement_pipeline WHERE id = p_pipeline_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Pipeline entry not found'); END IF;

  IF v_pipeline.state <> 'staged' THEN
    RETURN jsonb_build_object('error','Cannot invite from state: ' || v_pipeline.state::text);
  END IF;

  SELECT * INTO v_member FROM public.members WHERE id = v_pipeline.member_id;
  IF v_member.anonymized_at IS NOT NULL THEN
    RETURN jsonb_build_object('error','Member was anonymized — cannot invite');
  END IF;

  UPDATE public.re_engagement_pipeline SET
    state = 'invited',
    invited_at = now(),
    invited_by = v_caller.id,
    invitation_message = p_message
  WHERE id = p_pipeline_id;

  -- Notify the alumni
  PERFORM public.create_notification(
    v_member.id,
    're_engagement_invitation',
    'Convite para retornar ao Núcleo IA',
    COALESCE(p_message, 'Você foi convidado(a) para retornar ao Núcleo IA no ciclo ' || v_pipeline.cycle_code || '.'),
    '/me/re-engagement/' || p_pipeline_id::text,
    're_engagement_pipeline',
    p_pipeline_id
  );

  -- Audit log
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller.id, 're_engagement.invited', 're_engagement_pipeline', p_pipeline_id,
    jsonb_build_object('member_id', v_pipeline.member_id, 'cycle_code', v_pipeline.cycle_code),
    jsonb_strip_nulls(jsonb_build_object('message_excerpt', LEFT(p_message, 200)))
  );

  RETURN jsonb_build_object('success', true, 'pipeline_id', p_pipeline_id, 'invited_at', now());
END $function$;

CREATE OR REPLACE FUNCTION public.is_eu_resident(p_person_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_country text;
BEGIN
  SELECT country INTO v_country FROM public.persons WHERE id = p_person_id;
  IF v_country IS NULL THEN RETURN false; END IF;

  RETURN lower(trim(v_country)) = ANY (ARRAY[
    'austria', 'belgium', 'bulgaria', 'croatia', 'cyprus', 'czech republic',
    'czechia', 'denmark', 'estonia', 'finland', 'france', 'germany',
    'greece', 'hungary', 'ireland', 'italy', 'latvia', 'lithuania',
    'luxembourg', 'malta', 'netherlands', 'poland', 'portugal', 'romania',
    'slovakia', 'slovenia', 'spain', 'sweden',
    'iceland', 'liechtenstein', 'norway',
    'áustria', 'bélgica', 'belgica', 'bulgária', 'croácia', 'croacia',
    'chipre', 'república tcheca', 'republica tcheca', 'tchéquia', 'tchequia',
    'dinamarca', 'estônia', 'finlândia', 'finlandia', 'frança', 'franca',
    'alemanha', 'grécia', 'grecia', 'hungria', 'irlanda', 'itália', 'italia',
    'letônia', 'letonia', 'lituânia', 'lituania', 'luxemburgo',
    'países baixos', 'paises baixos', 'holanda', 'polônia', 'polonia',
    'romênia', 'romenia', 'eslováquia', 'eslovaquia', 'eslovênia',
    'eslovenia', 'espanha', 'suécia', 'suecia', 'islândia', 'islandia',
    'noruega',
    'at', 'be', 'bg', 'hr', 'cy', 'cz', 'dk', 'ee', 'fi', 'fr', 'de',
    'gr', 'hu', 'ie', 'it', 'lv', 'lt', 'lu', 'mt', 'nl', 'pl', 'pt',
    'ro', 'sk', 'si', 'es', 'se',
    'is', 'li', 'no'
  ]);
END;
$function$;

CREATE OR REPLACE FUNCTION public.join_initiative(p_initiative_id uuid, p_motivation text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_person_id uuid; v_member_id uuid; v_initiative record; v_kind_row record;
  v_default_engagement_kind text; v_engagement_id uuid; v_current_count integer;
BEGIN
  SELECT m.id, m.person_id INTO v_member_id, v_person_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_person_id IS NULL THEN RAISE EXCEPTION 'Not authenticated or no person record' USING ERRCODE = 'P0002'; END IF;
  SELECT * INTO v_initiative FROM public.initiatives WHERE id = p_initiative_id;
  IF v_initiative IS NULL THEN RAISE EXCEPTION 'Initiative not found: %', p_initiative_id USING ERRCODE = 'P0002'; END IF;
  SELECT * INTO v_kind_row FROM public.initiative_kinds WHERE slug = v_initiative.kind;
  IF (v_initiative.metadata->>'max_enrollment') IS NOT NULL THEN
    SELECT count(*) INTO v_current_count FROM public.engagements WHERE initiative_id = p_initiative_id AND status IN ('active', 'onboarding');
    IF v_current_count >= (v_initiative.metadata->>'max_enrollment')::integer THEN
      RAISE EXCEPTION 'Initiative is at capacity' USING ERRCODE = 'P0005';
    END IF;
  END IF;
  IF EXISTS (SELECT 1 FROM public.engagements WHERE person_id = v_person_id AND initiative_id = p_initiative_id AND status IN ('active', 'onboarding')) THEN
    RAISE EXCEPTION 'Already enrolled in this initiative' USING ERRCODE = 'P0009';
  END IF;
  IF array_length(v_kind_row.allowed_engagement_kinds, 1) = 1 THEN
    v_default_engagement_kind := v_kind_row.allowed_engagement_kinds[1];
  ELSE
    SELECT ek INTO v_default_engagement_kind FROM unnest(v_kind_row.allowed_engagement_kinds) ek WHERE ek != ALL(v_kind_row.required_engagement_kinds) LIMIT 1;
    IF v_default_engagement_kind IS NULL THEN v_default_engagement_kind := v_kind_row.allowed_engagement_kinds[1]; END IF;
  END IF;
  INSERT INTO public.engagements (person_id, initiative_id, kind, role, status, metadata, organization_id)
  VALUES (v_person_id, p_initiative_id, v_default_engagement_kind, 'participant', 'active', jsonb_build_object('motivation', p_motivation) || p_metadata, public.auth_org())
  RETURNING id INTO v_engagement_id;
  RETURN v_engagement_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.link_board_to_drive(p_board_id uuid, p_drive_folder_id text, p_drive_folder_url text, p_drive_folder_name text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_is_authorized boolean;
  v_existing record;
  v_new_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- Authority: manage_member (admin/GP) OR board_admin
  v_is_authorized := public.can_by_member(v_caller_id, 'manage_member')
    OR EXISTS (
      SELECT 1 FROM public.board_members bm
      WHERE bm.board_id = p_board_id AND bm.member_id = v_caller_id AND bm.board_role = 'admin'
    );

  IF NOT v_is_authorized THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_member or board admin');
  END IF;

  IF coalesce(trim(p_drive_folder_id), '') = '' OR coalesce(trim(p_drive_folder_url), '') = '' THEN
    RETURN jsonb_build_object('error', 'drive_folder_id and drive_folder_url required');
  END IF;

  -- Reuse if already linked (and active) — return existing instead of dup error
  SELECT id INTO v_existing.id FROM public.board_drive_links
  WHERE board_id = p_board_id AND drive_folder_id = p_drive_folder_id AND unlinked_at IS NULL;
  IF v_existing.id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'existing', true,
      'link_id', v_existing.id
    );
  END IF;

  INSERT INTO public.board_drive_links (
    board_id, drive_folder_id, drive_folder_url, drive_folder_name, linked_by
  ) VALUES (
    p_board_id, p_drive_folder_id, p_drive_folder_url, p_drive_folder_name, v_caller_id
  )
  RETURNING id INTO v_new_id;

  RETURN jsonb_build_object(
    'success', true,
    'link_id', v_new_id,
    'board_id', p_board_id,
    'drive_folder_id', p_drive_folder_id
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.link_initiative_to_drive(p_initiative_id uuid, p_drive_folder_id text, p_drive_folder_url text, p_drive_folder_name text DEFAULT NULL::text, p_link_purpose text DEFAULT 'workspace'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_is_authorized boolean;
  v_existing record;
  v_new_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF p_link_purpose NOT IN ('workspace', 'minutes', 'archive', 'shared_resources') THEN
    RETURN jsonb_build_object('error', 'Invalid link_purpose. Use: workspace | minutes | archive | shared_resources');
  END IF;

  -- Authority: manage_member (admin) OR can(write, initiative, p_initiative_id) (leader scope)
  v_is_authorized := public.can_by_member(v_caller_id, 'manage_member')
    OR public.can(v_caller_id, 'write', 'initiative', p_initiative_id);

  IF NOT v_is_authorized THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_member or write on initiative');
  END IF;

  IF coalesce(trim(p_drive_folder_id), '') = '' OR coalesce(trim(p_drive_folder_url), '') = '' THEN
    RETURN jsonb_build_object('error', 'drive_folder_id and drive_folder_url required');
  END IF;

  SELECT id INTO v_existing.id FROM public.initiative_drive_links
  WHERE initiative_id = p_initiative_id AND drive_folder_id = p_drive_folder_id
    AND link_purpose = p_link_purpose AND unlinked_at IS NULL;
  IF v_existing.id IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'existing', true, 'link_id', v_existing.id);
  END IF;

  INSERT INTO public.initiative_drive_links (
    initiative_id, drive_folder_id, drive_folder_url, drive_folder_name, link_purpose, linked_by
  ) VALUES (
    p_initiative_id, p_drive_folder_id, p_drive_folder_url, p_drive_folder_name, p_link_purpose, v_caller_id
  )
  RETURNING id INTO v_new_id;

  RETURN jsonb_build_object(
    'success', true,
    'link_id', v_new_id,
    'initiative_id', p_initiative_id,
    'drive_folder_id', p_drive_folder_id,
    'link_purpose', p_link_purpose
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.link_interview_event(p_event_id uuid, p_application_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_event record;
  v_app record;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  IF NOT (
    public.can_by_member(v_caller.id, 'manage_member'::text)
    OR public.can_by_member(v_caller.id, 'manage_platform'::text)
  ) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member or manage_platform';
  END IF;

  SELECT * INTO v_event FROM public.events WHERE id = p_event_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Event not found: %', p_event_id;
  END IF;

  IF v_event.type <> 'entrevista' THEN
    RAISE EXCEPTION 'Event is not entrevista type (got %)', v_event.type;
  END IF;

  IF v_event.selection_application_id IS NOT NULL THEN
    RAISE EXCEPTION 'Event already linked to application: %', v_event.selection_application_id;
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Application not found: %', p_application_id;
  END IF;

  UPDATE public.events
     SET selection_application_id = p_application_id,
         updated_at = now()
   WHERE id = p_event_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller.id,
    'link_interview_event',
    'event',
    p_event_id,
    jsonb_build_object(
      'before', jsonb_build_object('selection_application_id', NULL),
      'after',  jsonb_build_object('selection_application_id', p_application_id)
    ),
    jsonb_build_object(
      'applicant_name', v_app.applicant_name,
      'event_title', v_event.title,
      'event_date', v_event.date,
      'method', 'manual_admin_link'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'event_id', p_event_id,
    'application_id', p_application_id,
    'applicant_name', v_app.applicant_name,
    'linked_by', v_caller.id,
    'linked_at', now()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.link_partner_to_card(p_partner_entity_id uuid, p_board_item_id uuid, p_link_role text DEFAULT 'general'::text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record;
  v_partner_exists boolean;
  v_card_exists boolean;
  v_link_id uuid;
  v_was_update boolean := false;
BEGIN
  SELECT m.id, m.name INTO v_member
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_member.id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_member.id, 'manage_partner') THEN
    RAISE EXCEPTION 'Access denied: manage_partner required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT EXISTS(SELECT 1 FROM public.partner_entities WHERE id = p_partner_entity_id) INTO v_partner_exists;
  IF NOT v_partner_exists THEN
    RAISE EXCEPTION 'partner_entity not found (id=%)', p_partner_entity_id USING ERRCODE = 'no_data_found';
  END IF;

  SELECT EXISTS(SELECT 1 FROM public.board_items WHERE id = p_board_item_id) INTO v_card_exists;
  IF NOT v_card_exists THEN
    RAISE EXCEPTION 'board_item not found (id=%)', p_board_item_id USING ERRCODE = 'no_data_found';
  END IF;

  IF p_link_role NOT IN ('general','pipeline','deliverable','follow_up','contract','onboarding') THEN
    RAISE EXCEPTION 'invalid link_role: %. Must be: general|pipeline|deliverable|follow_up|contract|onboarding', p_link_role
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  INSERT INTO public.partner_cards (partner_entity_id, board_item_id, link_role, notes, created_by)
  VALUES (p_partner_entity_id, p_board_item_id, p_link_role, p_notes, v_member.id)
  ON CONFLICT (partner_entity_id, board_item_id) DO UPDATE
    SET link_role = EXCLUDED.link_role,
        notes = COALESCE(EXCLUDED.notes, public.partner_cards.notes),
        updated_at = now()
  RETURNING id, (xmax <> 0) INTO v_link_id, v_was_update;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    v_member.id,
    CASE WHEN v_was_update THEN 'partner_card.updated' ELSE 'partner_card.linked' END,
    'partner_card', v_link_id,
    jsonb_build_object('partner_entity_id', p_partner_entity_id, 'board_item_id', p_board_item_id, 'link_role', p_link_role)
  );

  RETURN jsonb_build_object(
    'success', true,
    'link_id', v_link_id,
    'was_update', v_was_update,
    'partner_entity_id', p_partner_entity_id,
    'board_item_id', p_board_item_id,
    'link_role', p_link_role
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_card_comments(p_board_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- Anyone authenticated who can SELECT board_items can read comments
  IF NOT EXISTS (SELECT 1 FROM public.board_items WHERE id = p_board_item_id) THEN
    RETURN jsonb_build_object('error', 'Card not found');
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', c.id,
    'author_id', c.author_id,
    'author_name', m.name,
    'author_photo_url', m.photo_url,
    'body', c.body,
    'parent_comment_id', c.parent_comment_id,
    'mentioned_member_ids', c.mentioned_member_ids,
    'edited_at', c.edited_at,
    'created_at', c.created_at
  ) ORDER BY c.created_at ASC), '[]'::jsonb)
  INTO v_result
  FROM public.board_item_comments c
  LEFT JOIN public.members m ON m.id = c.author_id
  WHERE c.board_item_id = p_board_item_id
    AND c.deleted_at IS NULL;

  RETURN jsonb_build_object('card_id', p_board_item_id, 'comments', v_result);
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_initiative_events(p_tribe_id integer DEFAULT NULL::integer, p_initiative_id uuid DEFAULT NULL::uuid, p_types text[] DEFAULT NULL::text[], p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_has_minutes boolean DEFAULT NULL::boolean, p_has_recording boolean DEFAULT NULL::boolean, p_has_attendance boolean DEFAULT NULL::boolean, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_caller_tribe int;
  v_is_admin boolean;
  v_is_stakeholder boolean;
  v_clamped_limit int;
  v_resolved_from date;
  v_resolved_to date;
  v_total int;
  v_result jsonb;
  v_target_tribe int;
BEGIN
  SELECT id, operational_role, tribe_id INTO v_caller_id, v_caller_role, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  v_is_admin := public.can_by_member(v_caller_id, 'manage_member');
  v_is_stakeholder := public.can_by_member(v_caller_id, 'manage_partner');

  -- Resolve target tribe (may be NULL = no filter)
  IF p_initiative_id IS NOT NULL THEN
    SELECT legacy_tribe_id INTO v_target_tribe
    FROM public.initiatives WHERE id = p_initiative_id;
  ELSE
    v_target_tribe := p_tribe_id;
  END IF;

  -- Authorization tiering (spec)
  IF v_is_admin THEN
    NULL;  -- admin sees all
  ELSIF v_is_stakeholder AND v_target_tribe IS NULL THEN
    NULL;  -- sponsor/liaison sees general events only (filter applied below)
  ELSIF v_caller_role = 'tribe_leader' AND (v_target_tribe IS NULL OR v_target_tribe = v_caller_tribe) THEN
    NULL;  -- TL of target tribe
  ELSIF v_caller_role IN ('researcher', 'chapter_board') AND v_target_tribe = v_caller_tribe THEN
    NULL;  -- researcher in target tribe
  ELSE
    RETURN jsonb_build_object('error', 'Unauthorized: insufficient access to requested events');
  END IF;

  -- Clamp + defaults
  v_clamped_limit := greatest(1, least(200, coalesce(p_limit, 50)));
  v_resolved_from := coalesce(p_date_from, current_date - interval '90 days');
  v_resolved_to := coalesce(p_date_to, current_date);

  WITH base AS (
    SELECT
      e.id, e.date, e.time_start, e.type, e.title,
      e.duration_minutes, e.duration_actual, e.meeting_link,
      e.minutes_text IS NOT NULL AND length(trim(e.minutes_text)) > 0 AS has_minutes,
      e.minutes_posted_at,
      e.youtube_url, e.recording_url, e.is_recorded, e.recording_type,
      e.nature, e.created_at,
      i.legacy_tribe_id AS tribe_id,
      i.id AS initiative_id,
      i.title AS initiative_title,
      (SELECT count(*) FROM public.attendance a WHERE a.event_id = e.id) AS attendance_count,
      (SELECT count(*) FROM public.attendance a WHERE a.event_id = e.id AND a.present = true) AS attendance_present_count,
      (SELECT count(*) FROM public.event_showcases s WHERE s.event_id = e.id) AS showcase_count,
      (SELECT count(*) FROM public.meeting_action_items m WHERE m.event_id = e.id AND m.status NOT IN ('done', 'cancelled')) AS action_items_open
    FROM public.events e
    LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.date >= v_resolved_from
      AND e.date <= v_resolved_to
      AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
      AND (p_initiative_id IS NULL OR i.id = p_initiative_id)
      AND (p_types IS NULL OR e.type = ANY(p_types))
      -- Stakeholder restriction: sees only general events when no target tribe
      AND (NOT (v_is_stakeholder AND NOT v_is_admin) OR e.type IN ('geral', 'kickoff', 'lideranca'))
  ),
  filtered AS (
    SELECT * FROM base
    WHERE
      (p_has_minutes IS NULL OR base.has_minutes = p_has_minutes)
      AND (p_has_recording IS NULL OR (base.youtube_url IS NOT NULL OR base.recording_url IS NOT NULL) = p_has_recording)
      AND (p_has_attendance IS NULL OR (base.attendance_count > 0) = p_has_attendance)
  )
  SELECT
    count(*)::int,
    coalesce(jsonb_agg(jsonb_build_object(
      'id', f.id,
      'date', f.date,
      'time_start', f.time_start,
      'type', f.type,
      'title', f.title,
      'duration_minutes', f.duration_minutes,
      'duration_actual', f.duration_actual,
      'meeting_link', f.meeting_link,
      'minutes_text_present', f.has_minutes,
      'minutes_posted_at', f.minutes_posted_at,
      'youtube_url', f.youtube_url,
      'recording_url', f.recording_url,
      'is_recorded', f.is_recorded,
      'recording_type', f.recording_type,
      'tribe_id', f.tribe_id,
      'initiative_id', f.initiative_id,
      'initiative_title', f.initiative_title,
      'attendance_count', f.attendance_count,
      'attendance_present_count', f.attendance_present_count,
      'showcase_count', f.showcase_count,
      'action_items_open', f.action_items_open,
      'nature', f.nature
    ) ORDER BY f.date DESC, f.time_start DESC NULLS LAST), '[]'::jsonb)
  INTO v_total, v_result
  FROM (
    SELECT * FROM filtered
    ORDER BY date DESC, time_start DESC NULLS LAST
    OFFSET p_offset
    LIMIT v_clamped_limit
  ) f;

  RETURN jsonb_build_object(
    'total_count', v_total,
    'limit', v_clamped_limit,
    'offset', p_offset,
    'date_from', v_resolved_from,
    'date_to', v_resolved_to,
    'events', v_result
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_invitations_for_my_initiatives(p_initiative_id uuid DEFAULT NULL::uuid, p_status_filter text DEFAULT 'pending'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_caller_person_id uuid;
  v_is_admin boolean;
  v_results jsonb;
  v_invitee_ids uuid[];
BEGIN
  SELECT m.id, m.person_id INTO v_caller_member_id, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_is_admin := public.can_by_member(v_caller_member_id, 'manage_member');

  -- Build query: invitations where caller is owner/coordinator OR admin
  -- + filter by initiative_id and/or status
  WITH owned_initiatives AS (
    SELECT DISTINCT e.initiative_id
    FROM public.engagements e
    WHERE e.person_id = v_caller_person_id
      AND e.status = 'active'
      AND (e.kind LIKE '%_owner' OR e.kind LIKE '%_coordinator' OR e.role IN ('owner','coordinator','lead'))
  ),
  filtered AS (
    SELECT ii.*, i.title AS initiative_title, m.name AS invitee_name
    FROM public.initiative_invitations ii
    JOIN public.initiatives i ON i.id = ii.initiative_id
    JOIN public.members m ON m.id = ii.invitee_member_id
    WHERE (
      v_is_admin
      OR ii.initiative_id IN (SELECT initiative_id FROM owned_initiatives)
    )
    AND (p_initiative_id IS NULL OR ii.initiative_id = p_initiative_id)
    AND (p_status_filter = 'all' OR ii.status = p_status_filter)
  )
  SELECT
    jsonb_agg(jsonb_build_object(
      'invitation_id', f.id,
      'initiative_id', f.initiative_id,
      'initiative_title', f.initiative_title,
      'invitee_member_id', f.invitee_member_id,
      'invitee_name', f.invitee_name,
      'inviter_member_id', f.inviter_member_id,
      'is_self_request', (f.invitee_member_id = f.inviter_member_id),
      'kind_scope', f.kind_scope,
      'message', f.message,
      'status', f.status,
      'expires_at', f.expires_at,
      'created_at', f.created_at,
      'reviewed_at', f.reviewed_at,
      'reviewed_note', f.reviewed_note
    ) ORDER BY f.created_at DESC),
    array_agg(DISTINCT f.invitee_member_id)
  INTO v_results, v_invitee_ids
  FROM filtered f;

  -- Log PII access (#85 Onda C) — owner viewing invitee names is PII access
  IF v_invitee_ids IS NOT NULL AND array_length(v_invitee_ids, 1) > 0 THEN
    PERFORM public.log_pii_access(
      v_caller_member_id,
      ARRAY['name']::text[],
      'list_invitations_for_my_initiatives',
      format('Owner viewing %s invitation(s) for initiative_id=%s, status=%s',
        array_length(v_invitee_ids, 1), p_initiative_id, p_status_filter)
    );
  END IF;

  RETURN COALESCE(v_results, '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_meeting_action_items(p_event_id uuid DEFAULT NULL::uuid, p_status text DEFAULT NULL::text, p_assignee_id uuid DEFAULT NULL::uuid, p_kind text DEFAULT NULL::text, p_unresolved_only boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  -- Authenticated only — any member can see action items.
  -- Privacy is enforced by event visibility (events RLS) when frontend
  -- joins; raw access here is read-only metadata about meetings.
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', mai.id,
    'event_id', mai.event_id,
    'event_title', e.title,
    'event_date', e.date,
    'description', mai.description,
    'assignee_id', mai.assignee_id,
    'assignee_name', mai.assignee_name,
    'due_date', mai.due_date,
    'kind', mai.kind,
    'status', mai.status,
    'board_item_id', mai.board_item_id,
    'board_item_title', bi.title,
    'checklist_item_id', mai.checklist_item_id,
    'carried_to_event_id', mai.carried_to_event_id,
    'resolved_at', mai.resolved_at,
    'resolved_by', mai.resolved_by,
    'resolved_by_name', rm.name,
    'resolution_note', mai.resolution_note,
    'created_by', mai.created_by,
    'created_at', mai.created_at
  ) ORDER BY
    CASE WHEN mai.resolved_at IS NULL THEN 0 ELSE 1 END,  -- unresolved first
    mai.due_date NULLS LAST, mai.created_at DESC), '[]'::jsonb) INTO v_result
  FROM public.meeting_action_items mai
  LEFT JOIN public.events e ON e.id = mai.event_id
  LEFT JOIN public.board_items bi ON bi.id = mai.board_item_id
  LEFT JOIN public.members rm ON rm.id = mai.resolved_by
  WHERE (p_event_id IS NULL OR mai.event_id = p_event_id)
    AND (p_status IS NULL OR mai.status = p_status)
    AND (p_assignee_id IS NULL OR mai.assignee_id = p_assignee_id)
    AND (p_kind IS NULL OR mai.kind = p_kind)
    AND (NOT p_unresolved_only OR mai.resolved_at IS NULL)
  LIMIT 200;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_my_ai_validations(p_application_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller_id uuid; v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  SELECT jsonb_agg(jsonb_build_object('id', v.id, 'ai_purpose', v.ai_purpose, 'ai_model', v.ai_model, 'ai_score', v.ai_score, 'ai_verdict', v.ai_verdict, 'validation_action', v.validation_action, 'override_score', v.override_score, 'comment', v.comment, 'validated_at', v.validated_at))
  INTO v_result FROM public.ai_score_validations v WHERE v.application_id = p_application_id AND v.validator_id = v_caller_id;
  RETURN jsonb_build_object('application_id', p_application_id, 'validations', COALESCE(v_result, '[]'::jsonb));
END; $function$;

CREATE OR REPLACE FUNCTION public.list_orphan_interview_events()
 RETURNS TABLE(event_id uuid, title text, event_date date, time_start time without time zone, duration_minutes integer, calendar_event_id text, source text, status text, suggested_applications jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  IF NOT (
    public.can_by_member(v_caller.id, 'manage_member'::text)
    OR public.can_by_member(v_caller.id, 'manage_platform'::text)
  ) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member or manage_platform';
  END IF;

  RETURN QUERY
  SELECT
    e.id AS event_id,
    e.title,
    e.date AS event_date,
    e.time_start,
    e.duration_minutes,
    e.calendar_event_id,
    e.source,
    e.status,
    (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'application_id', sa.id,
        'applicant_name', sa.applicant_name,
        'email', sa.email,
        'chapter', sa.chapter,
        'status', sa.status,
        'cycle_code', sc.cycle_code,
        'similarity_score', similarity(LOWER(sa.applicant_name), LOWER(COALESCE(substring(e.title FROM '\(([^)]+)\)'), '')))
      ) ORDER BY similarity(LOWER(sa.applicant_name), LOWER(COALESCE(substring(e.title FROM '\(([^)]+)\)'), ''))) DESC), '[]'::jsonb)
      FROM public.selection_applications sa
      JOIN public.selection_cycles sc ON sc.id = sa.cycle_id
      WHERE e.title ~ '\([^)]+\)'
        AND similarity(LOWER(sa.applicant_name), LOWER(substring(e.title FROM '\(([^)]+)\)'))) > 0.3
      LIMIT 3
    ) AS suggested_applications
  FROM public.events e
  WHERE e.type = 'entrevista'
    AND e.selection_application_id IS NULL
  ORDER BY e.date DESC NULLS LAST, e.time_start DESC NULLS LAST;
END;
$function$;

CREATE OR REPLACE FUNCTION public.lock_document_version(p_version_id uuid, p_gates jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record;
  v_version record;
  v_chain_id uuid;
  v_existing_chain uuid;
  v_notif_count int;
BEGIN
  SELECT m.id, m.name INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_member.id, 'manage_member') THEN
    RAISE EXCEPTION 'Access denied: manage_member required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT dv.id, dv.document_id, dv.version_number, dv.version_label, dv.locked_at
  INTO v_version
  FROM public.document_versions dv WHERE dv.id = p_version_id;

  IF v_version.id IS NULL THEN
    RAISE EXCEPTION 'document_version not found (id=%)', p_version_id USING ERRCODE = 'no_data_found';
  END IF;
  IF v_version.locked_at IS NOT NULL THEN
    RAISE EXCEPTION 'document_version already locked at % — create a new version instead', v_version.locked_at
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_gates IS NULL OR jsonb_typeof(p_gates) <> 'array' OR jsonb_array_length(p_gates) = 0 THEN
    RAISE EXCEPTION 'gates must be a non-empty jsonb array' USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_gates) g
    WHERE NOT (g ? 'kind' AND g ? 'order' AND g ? 'threshold')
  ) THEN
    RAISE EXCEPTION 'each gate must have kind, order, threshold keys' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT ac.id INTO v_existing_chain
  FROM public.approval_chains ac
  WHERE ac.version_id = p_version_id LIMIT 1;
  IF v_existing_chain IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'chain_already_exists',
      'chain_id', v_existing_chain,
      'version_id', p_version_id
    );
  END IF;

  UPDATE public.document_versions
    SET locked_at = now(),
        locked_by = v_member.id,
        published_at = now(),
        published_by = v_member.id,
        updated_at = now()
    WHERE id = p_version_id;

  INSERT INTO public.approval_chains (
    document_id, version_id, status, gates, opened_at, opened_by
  ) VALUES (
    v_version.document_id, p_version_id, 'review', p_gates, now(), v_member.id
  ) RETURNING id INTO v_chain_id;

  UPDATE public.governance_documents
    SET current_version_id = p_version_id,
        updated_at = now()
    WHERE id = v_version.document_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    v_member.id, 'document_version.locked', 'document_version', p_version_id,
    jsonb_build_object(
      'document_id', v_version.document_id,
      'version_number', v_version.version_number,
      'version_label', v_version.version_label,
      'chain_id', v_chain_id,
      'gates', p_gates
    )
  );

  v_notif_count := public._enqueue_gate_notifications(v_chain_id, 'chain_opened', NULL);

  RETURN jsonb_build_object(
    'success', true,
    'version_id', p_version_id,
    'chain_id', v_chain_id,
    'notifications_enqueued', v_notif_count,
    'locked_at', now()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.mark_all_notifications_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_member_id uuid; v_count int;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  UPDATE notifications SET is_read = true, read_at = now()
  WHERE recipient_id = v_member_id AND is_read = false;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('success', true, 'marked', v_count);
END; $function$;

CREATE OR REPLACE FUNCTION public.mark_notification_read(p_notification_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_member_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  UPDATE notifications SET is_read = true, read_at = now()
  WHERE id = p_notification_id AND recipient_id = v_member_id AND is_read = false;
  RETURN jsonb_build_object('success', true);
END; $function$;

CREATE OR REPLACE FUNCTION public.meeting_close(p_event_id uuid, p_summary text DEFAULT NULL::text, p_suggested_champion_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_org uuid;
  v_event record;
  v_already_closed boolean;
  v_action_count int;
  v_decision_count int;
  v_unresolved_count int;
  v_markdown_action_count int;
  v_structured_drift int;
  v_links_total int;
  v_showcase_count int;
  v_validated_suggestions uuid[];
  v_invalid_suggestions uuid[];
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id, organization_id INTO v_caller_id, v_caller_org
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Requires manage_event permission';
  END IF;

  SELECT id, title, date, minutes_text, minutes_posted_at
  INTO v_event FROM public.events WHERE id = p_event_id;
  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('error', 'event_not_found');
  END IF;

  v_already_closed := v_event.minutes_posted_at IS NOT NULL;

  IF p_suggested_champion_ids IS NOT NULL AND cardinality(p_suggested_champion_ids) > 0 THEN
    IF cardinality(p_suggested_champion_ids) > 10 THEN
      RETURN jsonb_build_object('error', 'too_many_suggestions', 'detail', 'max 10 suggested member ids per meeting_close');
    END IF;

    SELECT array_agg(DISTINCT s ORDER BY s) INTO v_validated_suggestions
    FROM unnest(p_suggested_champion_ids) AS s
    WHERE EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.id = s AND m.organization_id = v_caller_org
    );

    SELECT array_agg(DISTINCT s) INTO v_invalid_suggestions
    FROM unnest(p_suggested_champion_ids) AS s
    WHERE NOT EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.id = s AND m.organization_id = v_caller_org
    );

    IF v_invalid_suggestions IS NOT NULL AND cardinality(v_invalid_suggestions) > 0 THEN
      RETURN jsonb_build_object(
        'error', 'invalid_suggestions',
        'detail', 'unknown or out-of-org member ids: ' || array_to_string(v_invalid_suggestions, ', ')
      );
    END IF;
  END IF;

  SELECT
    COUNT(*) FILTER (WHERE kind = 'action'),
    COUNT(*) FILTER (WHERE kind = 'decision'),
    COUNT(*) FILTER (WHERE kind IN ('action','followup') AND resolved_at IS NULL)
  INTO v_action_count, v_decision_count, v_unresolved_count
  FROM public.meeting_action_items WHERE event_id = p_event_id;

  v_markdown_action_count := COALESCE(
    (SELECT array_length(regexp_split_to_array(v_event.minutes_text, E'(^|\\n)\\s*-\\s*\\[\\s*\\]'), 1) - 1),
    0
  );
  v_markdown_action_count := GREATEST(0, v_markdown_action_count);
  v_structured_drift := GREATEST(0, v_markdown_action_count - v_action_count);

  SELECT COUNT(*) INTO v_links_total
  FROM public.board_item_event_links WHERE event_id = p_event_id;

  SELECT COUNT(*) INTO v_showcase_count
  FROM public.event_showcases WHERE event_id = p_event_id;

  IF NOT v_already_closed THEN
    UPDATE public.events
    SET minutes_posted_at = now(),
        minutes_posted_by = v_caller_id,
        notes = CASE
          WHEN p_summary IS NOT NULL AND length(trim(p_summary)) > 0
            THEN COALESCE(notes, '') ||
                 CASE WHEN COALESCE(notes, '') <> '' THEN E'\n\n' ELSE '' END ||
                 '## Meeting close summary (' || to_char(now(), 'YYYY-MM-DD HH24:MI') || ')' ||
                 E'\n' || trim(p_summary)
          ELSE notes
        END,
        suggested_champion_ids = COALESCE(v_validated_suggestions, suggested_champion_ids),
        updated_at = now()
    WHERE id = p_event_id;
  ELSE
    IF v_validated_suggestions IS NOT NULL THEN
      UPDATE public.events
      SET suggested_champion_ids = v_validated_suggestions,
          updated_at = now()
      WHERE id = p_event_id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'event_id', p_event_id,
    'event_title', v_event.title,
    'already_closed', v_already_closed,
    'closed_at', CASE WHEN v_already_closed THEN v_event.minutes_posted_at ELSE now() END,
    'action_count', v_action_count,
    'decision_count', v_decision_count,
    'unresolved_actions', v_unresolved_count,
    'markdown_action_count', v_markdown_action_count,
    'structured_drift', v_structured_drift,
    'links_total', v_links_total,
    'showcase_count', v_showcase_count,
    'drift_signal', v_structured_drift > 0,
    'summary_appended', p_summary IS NOT NULL AND length(trim(p_summary)) > 0 AND NOT v_already_closed,
    'suggestions_count', COALESCE(cardinality(v_validated_suggestions), 0),
    'suggestions_stored', v_validated_suggestions
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.mirror_sibling_interview(p_application_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id        uuid;
  v_app              record;
  v_sibling_id       uuid;
  v_source_interview record;
  v_source_eval      record;
  v_new_interview_id uuid;
  v_new_eval_id      uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN json_build_object('error', 'Unauthorized'); END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN json_build_object('error', 'Unauthorized');
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF NOT FOUND THEN RETURN json_build_object('error', 'Application not found'); END IF;

  IF v_app.promotion_path IS DISTINCT FROM 'dual_track' OR v_app.linked_application_id IS NULL THEN
    RETURN json_build_object('error', 'Application is not part of a dual_track pair');
  END IF;

  v_sibling_id := v_app.linked_application_id;

  IF EXISTS (SELECT 1 FROM public.selection_interviews WHERE application_id = p_application_id) THEN
    RETURN json_build_object('error', 'Target application already has an interview row — refusing to overwrite');
  END IF;

  SELECT * INTO v_source_interview
  FROM public.selection_interviews
  WHERE application_id = v_sibling_id
    AND status = 'completed'
  ORDER BY conducted_at DESC NULLS LAST, scheduled_at DESC NULLS LAST
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Sibling application has no completed interview to mirror');
  END IF;

  SELECT * INTO v_source_eval
  FROM public.selection_evaluations
  WHERE application_id = v_sibling_id
    AND evaluation_type = 'interview'
    AND submitted_at IS NOT NULL
  ORDER BY submitted_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Sibling application has no submitted interview evaluation to mirror');
  END IF;

  -- Mirror interview row (skip calendar_event_id — UNIQUE constraint guarantees no reuse)
  INSERT INTO public.selection_interviews (
    application_id, interviewer_ids, scheduled_at, conducted_at, status,
    theme_of_interest, calendar_event_id, notes, duration_minutes, created_at
  ) VALUES (
    p_application_id,
    v_source_interview.interviewer_ids,
    v_source_interview.scheduled_at,
    v_source_interview.conducted_at,
    v_source_interview.status,
    v_source_interview.theme_of_interest,
    NULL,
    COALESCE(v_source_interview.notes, '') || E'\n\n[Espelhado da entrevista de líder/pesquisador sibling ' || v_source_interview.id::text || ' — 4 criterios role-agnostic.]',
    v_source_interview.duration_minutes,
    now()
  )
  RETURNING id INTO v_new_interview_id;

  -- Mirror evaluation row
  INSERT INTO public.selection_evaluations (
    application_id, evaluator_id, evaluation_type, scores, weighted_subtotal,
    notes, submitted_at, created_at
  ) VALUES (
    p_application_id,
    v_source_eval.evaluator_id,
    'interview',
    v_source_eval.scores,
    v_source_eval.weighted_subtotal,
    COALESCE(v_source_eval.notes, '') || E'\n[Espelhado da avaliação interview sibling — 4 criterios role-agnostic. Theme question role-specific NOT espelhada.]',
    v_source_eval.submitted_at,
    now()
  )
  RETURNING id INTO v_new_eval_id;

  -- Update target app interview_score
  UPDATE public.selection_applications
  SET    interview_score = v_source_eval.weighted_subtotal,
         updated_at      = now()
  WHERE  id = p_application_id
    AND  interview_score IS NULL;

  -- Audit
  INSERT INTO public.data_anomaly_log (anomaly_type, severity, description, context)
  VALUES (
    'selection_dual_track_interview_mirror',
    'info',
    v_app.applicant_name || ' — interview mirrored from sibling app',
    jsonb_build_object(
      'target_app_id',        p_application_id,
      'sibling_app_id',       v_sibling_id,
      'source_interview_id',  v_source_interview.id,
      'source_evaluation_id', v_source_eval.id,
      'new_interview_id',     v_new_interview_id,
      'new_evaluation_id',    v_new_eval_id,
      'weighted_subtotal',    v_source_eval.weighted_subtotal,
      'caller_id',            v_caller_id
    )
  );

  RETURN json_build_object(
    'success',           true,
    'target_app_id',     p_application_id,
    'sibling_app_id',    v_sibling_id,
    'new_interview_id',  v_new_interview_id,
    'new_evaluation_id', v_new_eval_id,
    'mirrored_score',    v_source_eval.weighted_subtotal
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.parse_vep_chapters(p_membership text)
 RETURNS text[]
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_chapters text[] := '{}';
  v_match text;
BEGIN
  IF p_membership IS NULL OR p_membership = '' THEN RETURN v_chapters; END IF;

  -- Extract all "X, Brazil Chapter" or "X Chapter" patterns
  FOR v_match IN
    SELECT m[1] FROM regexp_matches(p_membership, '([^,]+(?:,\s*Brazil)?\s+Chapter)', 'gi') AS m
  LOOP
    v_match := trim(v_match);
    v_chapters := v_chapters || CASE
      WHEN v_match ILIKE '%goiás%' OR v_match ILIKE '%goias%' THEN 'PMI-GO'
      WHEN v_match ILIKE '%ceará%' OR v_match ILIKE '%ceara%' THEN 'PMI-CE'
      WHEN v_match ILIKE '%minas gerais%' THEN 'PMI-MG'
      WHEN v_match ILIKE '%distrito federal%' THEN 'PMI-DF'
      WHEN v_match ILIKE '%rio grande do sul%' THEN 'PMI-RS'
      WHEN v_match ILIKE '%são paulo%' OR v_match ILIKE '%sao paulo%' THEN 'PMI-SP'
      WHEN v_match ILIKE '%rio de janeiro%' THEN 'PMI-RJ'
      WHEN v_match ILIKE '%pernambuco%' THEN 'PMI-PE'
      WHEN v_match ILIKE '%espírito santo%' OR v_match ILIKE '%espirito santo%' THEN 'PMI-ES'
      WHEN v_match ILIKE '%bahia%' THEN 'PMI-BA'
      WHEN v_match ILIKE '%paraná%' OR v_match ILIKE '%parana%' THEN 'PMI-PR'
      WHEN v_match ILIKE '%honduras%' THEN 'PMI-HN'
      ELSE 'PMI-' || regexp_replace(split_part(v_match, ',', 1), '[^A-Za-z ]', '', 'g')
    END;
  END LOOP;

  RETURN v_chapters;
END;
$function$;

CREATE OR REPLACE FUNCTION public.process_interview_reminders_1h()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_intv record;
  v_app record;
  v_first_name text;
  v_time_str text;
  v_sent int := 0;
  v_processed jsonb := '[]'::jsonb;
  v_errors jsonb := '[]'::jsonb;
BEGIN
  FOR v_intv IN
    SELECT si.id, si.scheduled_at, si.application_id
    FROM public.selection_interviews si
    WHERE si.status = 'scheduled'
      AND si.reminder_sent_at_1h IS NULL
      AND si.scheduled_at BETWEEN now() + interval '30 minutes' AND now() + interval '90 minutes'
    ORDER BY si.scheduled_at
  LOOP
    SELECT id, applicant_name, first_name, email INTO v_app
    FROM public.selection_applications WHERE id = v_intv.application_id;
    IF v_app.id IS NULL OR v_app.email IS NULL THEN CONTINUE; END IF;

    v_first_name := COALESCE(
      NULLIF(trim(v_app.first_name), ''),
      NULLIF(split_part(v_app.applicant_name, ' ', 1), ''),
      'candidato(a)'
    );
    v_time_str := to_char(v_intv.scheduled_at AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI');

    BEGIN
      PERFORM public.campaign_send_one_off(
        p_template_slug := 'interview_reminder_1h',
        p_to_email := v_app.email,
        p_variables := jsonb_build_object(
          'first_name', v_first_name,
          'time_str', v_time_str
        ),
        p_metadata := jsonb_build_object(
          'source', 'process_interview_reminders_1h',
          'application_id', v_app.id,
          'interview_id', v_intv.id,
          'scheduled_at', v_intv.scheduled_at
        )
      );

      UPDATE public.selection_interviews
      SET reminder_sent_at_1h = now()
      WHERE id = v_intv.id;

      v_sent := v_sent + 1;
      v_processed := v_processed || jsonb_build_object(
        'interview_id', v_intv.id,
        'applicant_name', v_app.applicant_name,
        'scheduled_at', v_intv.scheduled_at,
        'time_str', v_time_str
      );

      -- Resend rate limit 5rps — small sleep between dispatches
      PERFORM pg_sleep(0.3);
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors || jsonb_build_object(
        'interview_id', v_intv.id,
        'error', SQLERRM
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'reminders_sent', v_sent,
    'processed', v_processed,
    'errors', v_errors,
    'run_at', now()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.process_pending_reschedule_nudges()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_app record;
  v_cycle record;
  v_first_name text;
  v_booking_url text;
  v_nudges_sent int := 0;
  v_errors jsonb := '[]'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
  v_processed jsonb := '[]'::jsonb;
BEGIN
  -- Cron-context auth bypass (no JWT). Aligns with ADR-0028 amendment p89 pattern.
  -- This RPC is only invoked by pg_cron (no human callers) so explicit role gate
  -- would never pass; we trust the scheduler context.
  IF auth.role() IS NOT NULL AND auth.role() NOT IN ('service_role') AND auth.uid() IS NOT NULL THEN
    -- A real user is calling — they must have manage_member
    IF NOT public.can_by_member(
      (SELECT id FROM public.members WHERE auth_id = auth.uid()),
      'manage_member'
    ) THEN
      RAISE EXCEPTION 'Unauthorized: cron RPC requires manage_member or service_role';
    END IF;
  END IF;

  FOR v_app IN
    SELECT a.id, a.applicant_name, a.email, a.cycle_id,
           a.interview_reschedule_reason,
           a.interview_reschedule_requested_at,
           a.interview_reschedule_last_nudged_at
    FROM public.selection_applications a
    WHERE a.interview_status = 'needs_reschedule'
      AND a.interview_reschedule_requested_at IS NOT NULL
      AND a.interview_reschedule_requested_at < now() - interval '3 days'
      AND (
        a.interview_reschedule_last_nudged_at IS NULL
        OR a.interview_reschedule_last_nudged_at < now() - interval '3 days'
      )
      AND a.status IN ('interview_pending', 'interview_scheduled')
  LOOP
    v_first_name := split_part(v_app.applicant_name, ' ', 1);

    SELECT interview_booking_url INTO v_cycle
    FROM public.selection_cycles
    WHERE id = v_app.cycle_id;

    v_booking_url := COALESCE(
      v_cycle.interview_booking_url,
      'https://calendar.app.google/gh9WjefjcmisVLoh7'  -- PM 2026-05-05 fallback
    );

    BEGIN
      PERFORM public.campaign_send_one_off(
        p_template_slug := 'interview_reschedule_nudge',
        p_to_email := v_app.email,
        p_variables := jsonb_build_object(
          'first_name', v_first_name,
          'reason', COALESCE(v_app.interview_reschedule_reason, '—'),
          'booking_url', v_booking_url
        ),
        p_metadata := jsonb_build_object(
          'source', 'process_pending_reschedule_nudges',
          'application_id', v_app.id,
          'reschedule_requested_at', v_app.interview_reschedule_requested_at,
          'last_nudged_at_before', v_app.interview_reschedule_last_nudged_at,
          'days_pending', EXTRACT(EPOCH FROM (now() - v_app.interview_reschedule_requested_at)) / 86400.0
        )
      );

      UPDATE public.selection_applications
      SET interview_reschedule_last_nudged_at = now()
      WHERE id = v_app.id;

      v_nudges_sent := v_nudges_sent + 1;
      v_processed := v_processed || jsonb_build_object(
        'application_id', v_app.id,
        'applicant_name', v_app.applicant_name,
        'days_since_request', EXTRACT(EPOCH FROM (now() - v_app.interview_reschedule_requested_at)) / 86400.0
      );

    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors || jsonb_build_object(
        'application_id', v_app.id,
        'error', SQLERRM
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'nudges_sent', v_nudges_sent,
    'processed', v_processed,
    'errors', v_errors,
    'run_at', now()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.process_vep_acceptance_transition()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id     uuid;
  v_marked        boolean := false;
  v_term_pending  boolean;
BEGIN
  SELECT id INTO v_member_id
  FROM public.members
  WHERE lower(email) = lower(NEW.email)
  LIMIT 1;

  IF v_member_id IS NULL THEN
    RETURN NEW;
  END IF;

  UPDATE public.onboarding_progress
  SET    status       = 'completed',
         completed_at = now(),
         updated_at   = now()
  WHERE  member_id = v_member_id
    AND  step_key  = 'vep_acceptance'
    AND  status    = 'pending';

  IF FOUND THEN
    v_marked := true;
  ELSE
    INSERT INTO public.onboarding_progress
      (application_id, member_id, step_key, status, completed_at, metadata)
    SELECT NEW.id, v_member_id, 'vep_acceptance', 'completed', now(), '{}'::jsonb
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.onboarding_progress
      WHERE member_id = v_member_id AND step_key = 'vep_acceptance'
    );

    IF FOUND THEN v_marked := true; END IF;
  END IF;

  IF v_marked THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.onboarding_progress
      WHERE member_id = v_member_id
        AND step_key  = 'volunteer_term'
        AND status    = 'pending'
    ) INTO v_term_pending;

    IF v_term_pending THEN
      PERFORM public.create_notification(
        v_member_id,
        'selection_termo_due',
        'Termo de Voluntário disponível para assinatura',
        'Sua aceitação no VEP foi confirmada. Acesse seu onboarding para assinar o Termo de Voluntário e seguir para a próxima etapa.',
        '/onboarding',
        'selection_application',
        NEW.id
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.promote_lead_to_application(p_lead_id uuid, p_cycle_id uuid, p_pmi_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_lead record;
  v_cycle record;
  v_app_id uuid;
  v_first text;
  v_last text;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
    RETURN jsonb_build_object('error','Unauthorized: requires manage_member permission');
  END IF;

  SELECT * INTO v_lead FROM public.visitor_leads WHERE id = p_lead_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Lead not found'); END IF;

  IF v_lead.status = 'promoted' THEN
    RETURN jsonb_build_object('error','Lead already promoted', 'application_id', v_lead.promoted_to_application_id);
  END IF;

  IF v_lead.status = 'dismissed' THEN
    RETURN jsonb_build_object('error','Lead was dismissed; cannot promote');
  END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = p_cycle_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Cycle not found'); END IF;
  IF v_cycle.status <> 'open' THEN
    RETURN jsonb_build_object('error','Cycle is not open: ' || v_cycle.status);
  END IF;

  -- Best-effort split applicant_name into first/last
  v_first := SPLIT_PART(v_lead.name, ' ', 1);
  v_last := NULLIF(TRIM(SUBSTRING(v_lead.name FROM POSITION(' ' IN v_lead.name) + 1)), '');

  INSERT INTO public.selection_applications (
    cycle_id, applicant_name, first_name, last_name, email, phone, pmi_id, chapter,
    referral_source, referrer_member_id, utm_data, status, created_at, application_date
  ) VALUES (
    p_cycle_id,
    v_lead.name,
    v_first,
    v_last,
    v_lead.email,
    v_lead.phone,
    p_pmi_id,
    v_lead.chapter_interest,
    COALESCE(v_lead.source, 'lead_promote'),
    v_lead.referrer_member_id,
    v_lead.utm_data,
    'submitted',
    now(),
    CURRENT_DATE
  )
  RETURNING id INTO v_app_id;

  UPDATE public.visitor_leads SET
    status = 'promoted',
    promoted_at = now(),
    promoted_by = v_caller.id,
    promoted_to_application_id = v_app_id
  WHERE id = p_lead_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller.id, 'visitor_lead.promoted', 'visitor_lead', p_lead_id,
    jsonb_build_object('application_id', v_app_id, 'cycle_id', p_cycle_id),
    jsonb_strip_nulls(jsonb_build_object('lead_email', v_lead.email, 'pmi_id', p_pmi_id))
  );

  RETURN jsonb_build_object('success', true, 'lead_id', p_lead_id, 'application_id', v_app_id);
END $function$;

CREATE OR REPLACE FUNCTION public.propose_manual_version(p_version_label text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_proposer_id uuid;
  v_count int;
  v_existing_pending uuid;
  v_proposal_id uuid;
  v_admin_id uuid;
  v_proposer_name text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id, name INTO v_proposer_id, v_proposer_name FROM public.members WHERE auth_id = auth.uid();
  IF v_proposer_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  -- ADR-0044: V4 catalog gate (manage_platform)
  IF NOT public.can_by_member(v_proposer_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Requires manage_platform permission';
  END IF;

  IF p_version_label IS NULL OR length(trim(p_version_label)) = 0 THEN
    RETURN jsonb_build_object('error', 'version_label_required');
  END IF;

  -- Validate approved CRs exist (preserves V3 invariant)
  SELECT count(*) INTO v_count FROM public.change_requests WHERE status = 'approved';
  IF v_count = 0 THEN RETURN jsonb_build_object('error', 'no_approved_crs'); END IF;

  -- Block if a pending proposal already exists (avoid concurrent proposals)
  SELECT id INTO v_existing_pending
  FROM public.pending_manual_version_approvals
  WHERE status = 'pending' AND expires_at > now()
  LIMIT 1;
  IF v_existing_pending IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'pending_proposal_exists', 'existing_proposal_id', v_existing_pending);
  END IF;

  -- Block if version label already used
  IF EXISTS (
    SELECT 1 FROM public.governance_documents
    WHERE doc_type = 'manual' AND version = p_version_label
  ) THEN
    RETURN jsonb_build_object('error', 'version_label_in_use', 'version_label', p_version_label);
  END IF;

  INSERT INTO public.pending_manual_version_approvals (version_label, notes, proposed_by)
  VALUES (p_version_label, p_notes, v_proposer_id)
  RETURNING id INTO v_proposal_id;

  -- Audit log
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_proposer_id, 'manual_version_proposed', 'pending_manual_version_approval', v_proposal_id,
    jsonb_build_object('version_label', p_version_label, 'notes', p_notes, 'crs_count', v_count));

  -- Notify all OTHER manage_platform holders (governance: 2nd signoff required)
  FOR v_admin_id IN
    SELECT DISTINCT m.id
    FROM public.members m
    JOIN public.persons p ON p.legacy_member_id = m.id
    JOIN public.auth_engagements ae ON ae.person_id = p.id
    JOIN public.engagement_kind_permissions ekp
      ON ekp.kind = ae.kind AND ekp.role = ae.role AND ekp.action = 'manage_platform'
    WHERE m.is_active = true
      AND ae.is_authoritative = true
      AND m.id <> v_proposer_id  -- exclude proposer (they can't sign off themselves)
  LOOP
    PERFORM public.create_notification(
      v_admin_id,
      'governance_manual_proposed',
      'pending_manual_version_approval',
      v_proposal_id,
      'Manual ' || p_version_label || ' proposto por ' || v_proposer_name || ' — assinatura pendente',
      v_proposer_id,
      'Aguardando 2ª assinatura para confirmar (24h). ' || v_count::text || ' CRs aprovados serão incorporados.'
    );
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'proposal_id', v_proposal_id,
    'version_label', p_version_label,
    'crs_count', v_count,
    'expires_at', (now() + interval '24 hours')
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.purge_expired_logs(p_dry_run boolean DEFAULT true, p_limit integer DEFAULT 10000)
 RETURNS TABLE(table_name text, purge_mode text, rows_affected bigint, oldest_row_kept timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  -- Retention constants (days). Change here to adjust policy.
  v_mcp_retention_days          constant integer := 90;
  v_email_webhook_retention_days constant integer := 180;
  v_broadcast_retention_days    constant integer := 730;
  v_data_anomaly_resolved_days  constant integer := 180;
  v_comms_ingestion_retention_days constant integer := 90;
  v_knowledge_ingestion_retention_days constant integer := 90;
  v_pii_access_anonymize_days   constant integer := 1825;
  v_pii_access_drop_days        constant integer := 2190;
  v_admin_audit_archive_days    constant integer := 1825;
  v_admin_audit_drop_days       constant integer := 2555;
  v_count bigint;
  v_oldest timestamptz;
BEGIN
  -- Auth: GRANT-based only. Function EXECUTE is granted to service_role
  -- exclusively (see GRANT at migration tail). Callers without the grant
  -- receive Postgres-level 'permission denied for function' error directly.
  -- This is an infrastructure RPC (log retention) — ADR-0011 can_by_member
  -- pattern applies to domain RPCs with user-level authority derivation.

  -- mcp_usage_log (90d drop)
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count FROM public.mcp_usage_log
      WHERE created_at < now() - (v_mcp_retention_days || ' days')::interval;
    ELSE
      WITH del AS (
        DELETE FROM public.mcp_usage_log WHERE id IN (
          SELECT id FROM public.mcp_usage_log
          WHERE created_at < now() - (v_mcp_retention_days || ' days')::interval
          LIMIT p_limit
        ) RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    SELECT min(created_at) INTO v_oldest FROM public.mcp_usage_log;
    RETURN QUERY SELECT 'mcp_usage_log'::text, 'drop'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'mcp_usage_log purge failed: %', SQLERRM;
    RETURN QUERY SELECT 'mcp_usage_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- comms_metrics_ingestion_log (90d drop)
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count FROM public.comms_metrics_ingestion_log
      WHERE created_at < now() - (v_comms_ingestion_retention_days || ' days')::interval;
    ELSE
      WITH del AS (
        DELETE FROM public.comms_metrics_ingestion_log WHERE id IN (
          SELECT id FROM public.comms_metrics_ingestion_log
          WHERE created_at < now() - (v_comms_ingestion_retention_days || ' days')::interval
          LIMIT p_limit
        ) RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    SELECT min(created_at) INTO v_oldest FROM public.comms_metrics_ingestion_log;
    RETURN QUERY SELECT 'comms_metrics_ingestion_log'::text, 'drop'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'comms_metrics_ingestion_log purge failed: %', SQLERRM;
    RETURN QUERY SELECT 'comms_metrics_ingestion_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- knowledge_insights_ingestion_log (90d drop)
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count FROM public.knowledge_insights_ingestion_log
      WHERE created_at < now() - (v_knowledge_ingestion_retention_days || ' days')::interval;
    ELSE
      WITH del AS (
        DELETE FROM public.knowledge_insights_ingestion_log WHERE id IN (
          SELECT id FROM public.knowledge_insights_ingestion_log
          WHERE created_at < now() - (v_knowledge_ingestion_retention_days || ' days')::interval
          LIMIT p_limit
        ) RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    SELECT min(created_at) INTO v_oldest FROM public.knowledge_insights_ingestion_log;
    RETURN QUERY SELECT 'knowledge_insights_ingestion_log'::text, 'drop'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'knowledge_insights_ingestion_log purge failed: %', SQLERRM;
    RETURN QUERY SELECT 'knowledge_insights_ingestion_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- data_anomaly_log (180d after resolved)
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count FROM public.data_anomaly_log
      WHERE fixed_at IS NOT NULL
        AND fixed_at < now() - (v_data_anomaly_resolved_days || ' days')::interval;
    ELSE
      WITH del AS (
        DELETE FROM public.data_anomaly_log WHERE id IN (
          SELECT id FROM public.data_anomaly_log
          WHERE fixed_at IS NOT NULL
            AND fixed_at < now() - (v_data_anomaly_resolved_days || ' days')::interval
          LIMIT p_limit
        ) RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    SELECT min(detected_at) INTO v_oldest FROM public.data_anomaly_log;
    RETURN QUERY SELECT 'data_anomaly_log'::text, 'drop_resolved'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'data_anomaly_log purge failed: %', SQLERRM;
    RETURN QUERY SELECT 'data_anomaly_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- email_webhook_events (180d drop)
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count FROM public.email_webhook_events
      WHERE created_at < now() - (v_email_webhook_retention_days || ' days')::interval;
    ELSE
      WITH del AS (
        DELETE FROM public.email_webhook_events WHERE id IN (
          SELECT id FROM public.email_webhook_events
          WHERE created_at < now() - (v_email_webhook_retention_days || ' days')::interval
          LIMIT p_limit
        ) RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    SELECT min(created_at) INTO v_oldest FROM public.email_webhook_events;
    RETURN QUERY SELECT 'email_webhook_events'::text, 'drop'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'email_webhook_events purge failed: %', SQLERRM;
    RETURN QUERY SELECT 'email_webhook_events'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- broadcast_log (2y drop)
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count FROM public.broadcast_log
      WHERE sent_at < now() - (v_broadcast_retention_days || ' days')::interval;
    ELSE
      WITH del AS (
        DELETE FROM public.broadcast_log WHERE id IN (
          SELECT id FROM public.broadcast_log
          WHERE sent_at < now() - (v_broadcast_retention_days || ' days')::interval
          LIMIT p_limit
        ) RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    SELECT min(sent_at) INTO v_oldest FROM public.broadcast_log;
    RETURN QUERY SELECT 'broadcast_log'::text, 'drop'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'broadcast_log purge failed: %', SQLERRM;
    RETURN QUERY SELECT 'broadcast_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- pii_access_log: 5y anonymize
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count FROM public.pii_access_log
      WHERE accessed_at < now() - (v_pii_access_anonymize_days || ' days')::interval
        AND accessed_at >= now() - (v_pii_access_drop_days || ' days')::interval
        AND accessor_id IS NOT NULL;
    ELSE
      WITH upd AS (
        UPDATE public.pii_access_log
        SET accessor_id = NULL,
            reason = CASE WHEN reason IS NOT NULL THEN 'anonymized' ELSE reason END
        WHERE id IN (
          SELECT id FROM public.pii_access_log
          WHERE accessed_at < now() - (v_pii_access_anonymize_days || ' days')::interval
            AND accessed_at >= now() - (v_pii_access_drop_days || ' days')::interval
            AND accessor_id IS NOT NULL
          LIMIT p_limit
        ) RETURNING 1
      ) SELECT count(*) INTO v_count FROM upd;
    END IF;
    SELECT min(accessed_at) INTO v_oldest FROM public.pii_access_log;
    RETURN QUERY SELECT 'pii_access_log'::text, 'anonymize'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'pii_access_log anonymize failed: %', SQLERRM;
    RETURN QUERY SELECT 'pii_access_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- pii_access_log: 6y drop
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count FROM public.pii_access_log
      WHERE accessed_at < now() - (v_pii_access_drop_days || ' days')::interval;
    ELSE
      WITH del AS (
        DELETE FROM public.pii_access_log WHERE id IN (
          SELECT id FROM public.pii_access_log
          WHERE accessed_at < now() - (v_pii_access_drop_days || ' days')::interval
          LIMIT p_limit
        ) RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    RETURN QUERY SELECT 'pii_access_log'::text, 'drop'::text, v_count, NULL::timestamptz;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'pii_access_log drop failed: %', SQLERRM;
    RETURN QUERY SELECT 'pii_access_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- admin_audit_log: 5y archive
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count FROM public.admin_audit_log
      WHERE created_at < now() - (v_admin_audit_archive_days || ' days')::interval;
    ELSE
      WITH moved AS (
        INSERT INTO z_archive.admin_audit_log
          (id, actor_id, action, target_type, target_id, changes, metadata, created_at)
        SELECT id, actor_id, action, target_type, target_id, changes, metadata, created_at
        FROM public.admin_audit_log
        WHERE id IN (
          SELECT id FROM public.admin_audit_log
          WHERE created_at < now() - (v_admin_audit_archive_days || ' days')::interval
          LIMIT p_limit
        )
        ON CONFLICT (id) DO NOTHING
        RETURNING id
      ), del AS (
        DELETE FROM public.admin_audit_log WHERE id IN (SELECT id FROM moved)
        RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    SELECT min(created_at) INTO v_oldest FROM public.admin_audit_log;
    RETURN QUERY SELECT 'admin_audit_log'::text, 'archive'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'admin_audit_log archive failed: %', SQLERRM;
    RETURN QUERY SELECT 'admin_audit_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- z_archive.admin_audit_log: 7y drop
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count FROM z_archive.admin_audit_log
      WHERE created_at < now() - (v_admin_audit_drop_days || ' days')::interval;
    ELSE
      WITH del AS (
        DELETE FROM z_archive.admin_audit_log WHERE id IN (
          SELECT id FROM z_archive.admin_audit_log
          WHERE created_at < now() - (v_admin_audit_drop_days || ' days')::interval
          LIMIT p_limit
        ) RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    SELECT min(created_at) INTO v_oldest FROM z_archive.admin_audit_log;
    RETURN QUERY SELECT 'z_archive.admin_audit_log'::text, 'drop'::text, v_count, v_oldest;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'z_archive.admin_audit_log drop failed: %', SQLERRM;
    RETURN QUERY SELECT 'z_archive.admin_audit_log'::text, 'error'::text, 0::bigint, NULL::timestamptz;
  END;

  -- Meta-log
  IF NOT p_dry_run THEN
    BEGIN
      INSERT INTO public.admin_audit_log (
        actor_id, action, target_type, target_id, changes, metadata
      ) VALUES (
        NULL, 'platform.log_retention_run', 'system', NULL, NULL,
        jsonb_build_object('executed_at', now(), 'p_limit', p_limit, 'source', 'purge_expired_logs')
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'meta-log insert failed: %', SQLERRM;
    END;
  END IF;
END;
$function$;
