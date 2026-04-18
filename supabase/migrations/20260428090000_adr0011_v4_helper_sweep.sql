-- ADR-0011 V4 helper sweep — 4 functions flagged pós Phase 3e guardian audit
-- Swaps legacy operational_role list checks for can_by_member() where semantics match.
--
-- Functions:
--   1. can_read_internal_analytics — substitui role list por can_by_member('manage_member'),
--      mantém designations (co_gp/sponsor/chapter_liaison/curator são valid V4 concepts)
--   2. curate_item — auth gate agora via can_by_member('manage_member') (admin-level)
--   3. create_recurring_weekly_events — auth via can_by_member('manage_event'),
--      tribe_leader scope refinement preservado como scope check (não auth gate primário)
--   4. exec_impact_hours_v2 — no body change (já usa can_read_internal_analytics que agora é V4-compliant)

CREATE OR REPLACE FUNCTION public.can_read_internal_analytics()
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_caller record;
begin
  select * into v_caller from public.get_my_member_record();

  if v_caller is null then
    return false;
  end if;

  return v_caller.is_superadmin is true
    or public.can_by_member(v_caller.id, 'manage_member')
    or coalesce(v_caller.designations && ARRAY['co_gp', 'sponsor', 'chapter_liaison', 'curator'], false);
end;
$function$;

CREATE OR REPLACE FUNCTION public.curate_item(p_table text, p_id uuid, p_action text, p_tags text[] DEFAULT NULL::text[], p_tribe_id integer DEFAULT NULL::integer, p_audience_level text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_caller record;
  v_rows integer := 0;
  v_enqueue_publication boolean := false;
  v_initiative_id uuid := NULL;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      v_caller.is_superadmin
      or public.can_by_member(v_caller.id, 'manage_member')
    ) then
    raise exception 'Admin access required';
  end if;

  if p_action not in ('approve', 'reject', 'update_tags') then
    raise exception 'Invalid action: %', p_action;
  end if;

  if p_tribe_id is not null then
    SELECT id INTO v_initiative_id FROM public.initiatives WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  end if;

  if p_table = 'knowledge_assets' then
    if p_action = 'approve' then
      update public.knowledge_assets
      set
        is_active = true,
        published_at = coalesce(published_at, now()),
        tags = coalesce(p_tags, tags),
        metadata = case
          when p_tribe_id is null then metadata
          else jsonb_set(coalesce(metadata, '{}'::jsonb), '{target_tribe_id}', to_jsonb(p_tribe_id), true)
        end
      where id = p_id;
    elsif p_action = 'reject' then
      update public.knowledge_assets
      set
        is_active = false,
        published_at = null
      where id = p_id;
    else
      update public.knowledge_assets
      set tags = coalesce(p_tags, tags)
      where id = p_id;
    end if;
    get diagnostics v_rows = row_count;
  elsif p_table = 'artifacts' then
    if p_action = 'approve' then
      update public.artifacts
      set
        curation_status = 'approved',
        tags = coalesce(p_tags, tags),
        tribe_id = coalesce(p_tribe_id, tribe_id)
      where id = p_id;
      v_enqueue_publication := coalesce(nullif(trim(coalesce(p_audience_level, '')), ''), '') = 'pmi_submission';
    elsif p_action = 'reject' then
      update public.artifacts
      set curation_status = 'rejected'
      where id = p_id;
    else
      update public.artifacts
      set
        tags = coalesce(p_tags, tags),
        tribe_id = coalesce(p_tribe_id, tribe_id)
      where id = p_id;
    end if;
    get diagnostics v_rows = row_count;
  elsif p_table = 'hub_resources' then
    if p_action = 'approve' then
      update public.hub_resources
      set
        curation_status = 'approved',
        tags = coalesce(p_tags, tags),
        initiative_id = coalesce(v_initiative_id, initiative_id)
      where id = p_id;
    elsif p_action = 'reject' then
      update public.hub_resources
      set curation_status = 'rejected'
      where id = p_id;
    else
      update public.hub_resources
      set
        tags = coalesce(p_tags, tags),
        initiative_id = coalesce(v_initiative_id, initiative_id)
      where id = p_id;
    end if;
    get diagnostics v_rows = row_count;
  elsif p_table = 'events' then
    if p_action = 'approve' then
      update public.events
      set
        curation_status = 'approved',
        initiative_id = coalesce(v_initiative_id, initiative_id),
        audience_level = coalesce(nullif(trim(coalesce(p_audience_level, '')), ''), audience_level)
      where id = p_id;
    elsif p_action = 'reject' then
      update public.events
      set curation_status = 'rejected'
      where id = p_id;
    else
      update public.events
      set
        initiative_id = coalesce(v_initiative_id, initiative_id),
        audience_level = coalesce(nullif(trim(coalesce(p_audience_level, '')), ''), audience_level)
      where id = p_id;
    end if;
    get diagnostics v_rows = row_count;
  else
    raise exception 'Invalid table: %', p_table;
  end if;

  if v_rows = 0 then
    raise exception 'Item not found: % in %', p_id, p_table;
  end if;

  if p_table = 'artifacts' and p_action = 'approve' and v_enqueue_publication then
    perform public.enqueue_artifact_publication_card(p_id, v_caller.id);
  end if;

  return jsonb_build_object(
    'success', true,
    'table', p_table,
    'id', p_id,
    'action', p_action,
    'tribe_id', p_tribe_id,
    'audience_level', p_audience_level,
    'publication_enqueued', (p_table = 'artifacts' and p_action = 'approve' and v_enqueue_publication),
    'by', v_caller.name
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_recurring_weekly_events(p_type text, p_title_template text, p_start_date date, p_duration_minutes integer DEFAULT 60, p_n_weeks integer DEFAULT 10, p_meeting_link text DEFAULT NULL::text, p_tribe_id integer DEFAULT NULL::integer, p_is_recorded boolean DEFAULT false, p_audience_level text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller   RECORD;
  v_group_id UUID := gen_random_uuid();
  v_week     INTEGER;
  v_date     DATE;
  v_title    TEXT;
  v_ids      UUID[] := '{}';
  v_new_id   UUID;
  v_initiative_id UUID;
BEGIN
  SELECT m.* INTO v_caller
  FROM public.members m
  WHERE m.auth_id = auth.uid()
  LIMIT 1;

  IF v_caller IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  -- V4 gate: requires manage_event permission
  IF NOT (v_caller.is_superadmin OR public.can_by_member(v_caller.id, 'manage_event')) THEN
    RETURN json_build_object('success', false, 'error', 'Insufficient permissions: requires manage_event');
  END IF;

  -- Scope refinement: tribe_leader can only create tribe events for own tribe
  IF v_caller.operational_role = 'tribe_leader' AND NOT v_caller.is_superadmin THEN
    IF p_type NOT IN ('tribo', 'tribe_meeting') THEN
      RETURN json_build_object('success', false, 'error', 'Leaders can only create tribe meetings');
    END IF;
    IF p_tribe_id IS DISTINCT FROM v_caller.tribe_id THEN
      RETURN json_build_object('success', false, 'error', 'Can only create events for your own tribe');
    END IF;
  END IF;

  IF p_type = 'tribe_meeting' THEN
    p_type := 'tribo';
  END IF;

  IF p_tribe_id IS NOT NULL THEN
    SELECT id INTO v_initiative_id FROM public.initiatives
    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  END IF;

  FOR v_week IN 1..p_n_weeks LOOP
    v_date  := p_start_date + ((v_week - 1) * 7);
    v_title := REPLACE(
                 REPLACE(p_title_template, '{n}', v_week::TEXT),
                 '{date}', TO_CHAR(v_date, 'DD/MM')
               );

    INSERT INTO public.events
      (type, title, date, duration_minutes, initiative_id, meeting_link,
       is_recorded, recurrence_group, created_by, audience_level)
    VALUES
      (p_type, v_title, v_date, p_duration_minutes,
       v_initiative_id, p_meeting_link, p_is_recorded, v_group_id, auth.uid(),
       p_audience_level)
    RETURNING id INTO v_new_id;

    v_ids := array_append(v_ids, v_new_id);
  END LOOP;

  RETURN json_build_object(
    'success',          true,
    'recurrence_group', v_group_id,
    'events_created',   p_n_weeks,
    'event_ids',        v_ids
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
