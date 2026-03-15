CREATE OR REPLACE FUNCTION public.comms_metrics_latest()
 RETURNS TABLE(metric_date date, audience bigint, reach bigint, engagement numeric, leads bigint, rows_count integer, updated_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with latest as (
    select max(metric_date) as d
    from public.comms_metrics_daily
  ), base as (
    select *
    from public.comms_metrics_daily c
    where c.metric_date = (select d from latest)
  )
  select
    (select d from latest) as metric_date,
    coalesce(sum(base.audience), 0)::bigint as audience,
    coalesce(sum(base.reach), 0)::bigint as reach,
    coalesce(avg(base.engagement_rate), 0)::numeric(8,4) as engagement,
    coalesce(sum(base.leads), 0)::bigint as leads,
    count(*)::int as rows_count,
    max(base.updated_at) as updated_at
  from base;
$function$

CREATE OR REPLACE FUNCTION public.finalize_decisions(p_cycle_id uuid, p_decisions jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_cycle record;
  v_committee record;
  v_decision jsonb;
  v_app record;
  v_member_id uuid;
  v_existing_member record;
  v_approved_count int := 0;
  v_rejected_count int := 0;
  v_waitlisted_count int := 0;
  v_converted_count int := 0;
  v_created_members int := 0;
  v_step jsonb;
  v_sla_days int;
  v_onboarding_steps jsonb;
BEGIN
  -- 1. Auth: committee lead or superadmin
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = p_cycle_id;
  IF v_cycle IS NULL THEN
    RAISE EXCEPTION 'Cycle not found';
  END IF;

  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = p_cycle_id AND member_id = v_caller.id AND role = 'lead';

  IF v_committee IS NULL AND v_caller.is_superadmin IS NOT TRUE THEN
    RAISE EXCEPTION 'Unauthorized: must be committee lead or superadmin';
  END IF;

  v_onboarding_steps := v_cycle.onboarding_steps;

  -- 2. Process each decision
  FOR v_decision IN SELECT * FROM jsonb_array_elements(p_decisions)
  LOOP
    SELECT * INTO v_app
    FROM public.selection_applications
    WHERE id = (v_decision ->> 'application_id')::uuid
      AND cycle_id = p_cycle_id;

    IF v_app IS NULL THEN
      CONTINUE;
    END IF;

    -- 2a. Handle conversion (researcher → leader)
    IF (v_decision ->> 'convert_to') IS NOT NULL AND v_decision ->> 'convert_to' != '' THEN
      UPDATE public.selection_applications
      SET status = 'converted',
          converted_from = v_app.role_applied,
          converted_to = v_decision ->> 'convert_to',
          conversion_reason = COALESCE(v_decision ->> 'feedback', 'Score above 90th percentile threshold'),
          feedback = v_decision ->> 'feedback',
          updated_at = now()
      WHERE id = v_app.id;

      v_converted_count := v_converted_count + 1;

      -- Notify candidate about conversion offer
      PERFORM public.create_notification(
        m.id,
        'selection_conversion_offer',
        'Proposta de conversão de papel',
        'Parabéns! Com base no seu desempenho, gostaríamos de convidá-lo(a) para o papel de ' || (v_decision ->> 'convert_to') || '.',
        '/workspace',
        'selection_application',
        v_app.id
      )
      FROM public.members m WHERE m.email = v_app.email;

      CONTINUE;
    END IF;

    -- 2b. Update application with decision
    UPDATE public.selection_applications
    SET status = v_decision ->> 'decision',
        feedback = v_decision ->> 'feedback',
        updated_at = now()
    WHERE id = v_app.id;

    -- 2c. Handle approved candidates
    IF v_decision ->> 'decision' = 'approved' THEN
      v_approved_count := v_approved_count + 1;

      -- Check if member already exists
      SELECT * INTO v_existing_member
      FROM public.members WHERE email = v_app.email;

      IF v_existing_member IS NULL THEN
        -- Auto-create member record
        INSERT INTO public.members (
          name, email, chapter, pmi_id, phone, linkedin_url,
          operational_role, is_active, current_cycle_active,
          cycles, country, state, created_at
        ) VALUES (
          v_app.applicant_name,
          v_app.email,
          v_app.chapter,
          v_app.pmi_id,
          v_app.phone,
          v_app.linkedin_url,
          COALESCE(v_app.role_applied, 'researcher'),
          true,
          true,
          ARRAY[v_cycle.cycle_code],
          v_app.country,
          v_app.state,
          now()
        )
        RETURNING id INTO v_member_id;

        v_created_members := v_created_members + 1;
      ELSE
        v_member_id := v_existing_member.id;

        -- Reactivate if inactive
        UPDATE public.members
        SET is_active = true,
            current_cycle_active = true,
            operational_role = COALESCE(
              CASE WHEN v_app.role_applied = 'leader' THEN 'tribe_leader' ELSE operational_role END,
              v_app.role_applied
            ),
            cycles = CASE
              WHEN cycles IS NULL THEN ARRAY[v_cycle.cycle_code]
              WHEN NOT (v_cycle.cycle_code = ANY(cycles)) THEN cycles || v_cycle.cycle_code
              ELSE cycles
            END,
            updated_at = now()
        WHERE id = v_member_id;
      END IF;

      -- Create onboarding steps
      FOR v_step IN SELECT * FROM jsonb_array_elements(v_onboarding_steps)
      LOOP
        v_sla_days := COALESCE((v_step ->> 'sla_days')::int, 7);

        INSERT INTO public.onboarding_progress (
          application_id, member_id, step_key, status, sla_deadline
        ) VALUES (
          v_app.id,
          v_member_id,
          v_step ->> 'key',
          'pending',
          now() + (v_sla_days || ' days')::interval
        )
        ON CONFLICT (application_id, step_key) DO NOTHING;
      END LOOP;

      -- Notify approved member
      PERFORM public.create_notification(
        v_member_id,
        'selection_approved',
        'Parabéns! Você foi aprovado(a)!',
        'Você foi aprovado(a) na seleção do ' || v_cycle.title || '. Complete seu onboarding para começar.',
        '/workspace',
        'selection_application',
        v_app.id
      );

    ELSIF v_decision ->> 'decision' = 'rejected' THEN
      v_rejected_count := v_rejected_count + 1;

    ELSIF v_decision ->> 'decision' = 'waitlist' THEN
      v_waitlisted_count := v_waitlisted_count + 1;
    END IF;
  END LOOP;

  -- 3. Take diversity snapshot
  INSERT INTO public.selection_diversity_snapshots (cycle_id, snapshot_type, metrics)
  SELECT p_cycle_id, 'approved', jsonb_build_object(
    'total', COUNT(*),
    'by_chapter', COALESCE((
      SELECT jsonb_object_agg(chapter, cnt)
      FROM (SELECT chapter, COUNT(*) AS cnt FROM public.selection_applications
            WHERE cycle_id = p_cycle_id AND status = 'approved' GROUP BY chapter) sub
    ), '{}'::jsonb),
    'by_role', COALESCE((
      SELECT jsonb_object_agg(role_applied, cnt)
      FROM (SELECT role_applied, COUNT(*) AS cnt FROM public.selection_applications
            WHERE cycle_id = p_cycle_id AND status = 'approved' GROUP BY role_applied) sub
    ), '{}'::jsonb),
    'by_gender', COALESCE((
      SELECT jsonb_object_agg(COALESCE(gender, 'undeclared'), cnt)
      FROM (SELECT gender, COUNT(*) AS cnt FROM public.selection_applications
            WHERE cycle_id = p_cycle_id AND status = 'approved' GROUP BY gender) sub
    ), '{}'::jsonb)
  )
  FROM public.selection_applications
  WHERE cycle_id = p_cycle_id AND status = 'approved';

  RETURN jsonb_build_object(
    'success', true,
    'approved', v_approved_count,
    'rejected', v_rejected_count,
    'waitlisted', v_waitlisted_count,
    'converted', v_converted_count,
    'members_created', v_created_members,
    'decisions_processed', jsonb_array_length(p_decisions)
  );
END;
$function$

CREATE OR REPLACE FUNCTION public.kpi_summary()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT jsonb_build_object(
    'chapters', (SELECT COUNT(DISTINCT chapter) FROM members WHERE current_cycle_active = true AND chapter IS NOT NULL),
    'active_members', (SELECT COUNT(*) FROM members WHERE current_cycle_active = true),
    'tribes', (SELECT COUNT(*) FROM tribes),
    'published_artifacts', (SELECT COUNT(*) FROM artifacts WHERE status = 'published'),
    'total_events', (SELECT COUNT(*) FROM events),
    'impact_hours', COALESCE((SELECT total_impact_hours FROM impact_hours_total LIMIT 1), 0),
    'impact_target', COALESCE((SELECT annual_target_hours FROM impact_hours_total LIMIT 1), 1800),
    'impact_pct', COALESCE((SELECT percent_of_target FROM impact_hours_total LIMIT 1), 0),
    'cert_pct', ROUND(COALESCE(
      (SELECT COUNT(*)::numeric * 100 / NULLIF(COUNT(*) FILTER (WHERE current_cycle_active), 0)
       FROM members WHERE cpmai_certified = true AND current_cycle_active = true), 0
    ))
  );
$function$

CREATE OR REPLACE FUNCTION public.move_board_item_to_board(p_item_id bigint, p_target_board_id bigint, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_actor uuid;
  v_member public.members%rowtype;
  v_source record;
  v_target record;
begin
  v_actor := auth.uid();
  if v_actor is null then
    raise exception 'Auth required';
  end if;

  select * into v_member
  from public.members m
  where m.auth_user_id = v_actor
    and m.is_active = true
  limit 1;

  if v_member.id is null then
    raise exception 'Member not found';
  end if;

  select bi.id,
         bi.board_id,
         sb.board_scope as source_scope,
         coalesce(sb.domain_key, '') as source_domain,
         sb.tribe_id as source_tribe_id,
         sb.is_active as source_active
    into v_source
  from public.board_items bi
  join public.project_boards sb on sb.id = bi.board_id
  where bi.id = p_item_id;

  if v_source.id is null then
    raise exception 'Board item not found';
  end if;

  select tb.id,
         tb.board_scope as target_scope,
         coalesce(tb.domain_key, '') as target_domain,
         tb.tribe_id as target_tribe_id,
         tb.is_active as target_active
    into v_target
  from public.project_boards tb
  where tb.id = p_target_board_id;

  if v_target.id is null then
    raise exception 'Target board not found';
  end if;

  if v_target.target_active is not true then
    raise exception 'Target board must be active';
  end if;

  if v_source.source_scope is distinct from v_target.target_scope then
    raise exception 'Cross-board move denied: board_scope mismatch';
  end if;

  if coalesce(v_source.source_domain, '') is distinct from coalesce(v_target.target_domain, '') then
    raise exception 'Cross-board move denied: domain_key mismatch';
  end if;

  if v_source.source_scope = 'tribe' and v_source.source_tribe_id is distinct from v_target.target_tribe_id then
    raise exception 'Cross-board move denied: tribe board must keep tribe_id';
  end if;

  if not (
    coalesce(v_member.is_superadmin, false)
    or v_member.operational_role in ('manager', 'deputy_manager', 'tribe_leader', 'communicator')
    or exists (
      select 1
      from unnest(coalesce(v_member.designations, array[]::text[])) d
      where d in ('co_gp', 'curator', 'comms_leader', 'comms_member')
    )
  ) then
    raise exception 'Project management access required';
  end if;

  update public.board_items
     set board_id = p_target_board_id,
         updated_at = now()
   where id = p_item_id;

  return jsonb_build_object(
    'success', true,
    'item_id', p_item_id,
    'from_board_id', v_source.board_id,
    'to_board_id', p_target_board_id,
    'reason', coalesce(p_reason, '')
  );
end;
$function$

-- ============================================================
-- exec_funnel_v2 — Deprecated 2026-03-14 (F-02 audit fix)
-- Replaced by exec_funnel_summary(text, integer, text)
-- ============================================================
CREATE OR REPLACE FUNCTION public.exec_funnel_v2(
  p_cycle_code text default null,
  p_tribe_id integer default null,
  p_chapter text default null
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
declare
  v_result jsonb;
begin
  if not public.can_read_internal_analytics() then
    raise exception 'Internal analytics access required';
  end if;

  with scoped as (
    select * from public.analytics_member_scope(p_cycle_code, p_tribe_id, p_chapter)
  ),
  core_total as (
    select count(*)::integer as total_core_courses
    from public.courses
    where category = 'core'
  ),
  member_core_progress as (
    select
      s.member_id,
      count(distinct cp.course_id) filter (where cp.status = 'completed')::integer as completed_core_courses
    from scoped s
    left join public.course_progress cp on cp.member_id = s.member_id
    left join public.courses c on c.id = cp.course_id and c.category = 'core'
    group by s.member_id
  ),
  published_artifacts as (
    select distinct s.member_id
    from scoped s
    join public.artifacts a on a.member_id = s.member_id
    where a.status = 'published'
      and coalesce(a.published_at, a.created_at, now()) >= s.cycle_start
      and (
        s.cycle_end is null
        or coalesce(a.published_at, a.created_at, now()) < s.cycle_end + interval '1 day'
      )
  ),
  stage_rollup as (
    select
      count(distinct s.member_id)::integer as total_members,
      count(distinct s.member_id) filter (
        where coalesce(mcp.completed_core_courses, 0) >= coalesce((select total_core_courses from core_total), 0)
      )::integer as members_with_full_core_trail,
      count(distinct s.member_id) filter (where s.tribe_id is not null)::integer as members_allocated_to_tribe,
      count(distinct pa.member_id)::integer as members_with_published_artifact
    from scoped s
    left join member_core_progress mcp on mcp.member_id = s.member_id
    left join published_artifacts pa on pa.member_id = s.member_id
  )
  select jsonb_build_object(
    'cycle_code', (select max(cycle_code) from scoped),
    'cycle_label', (select max(cycle_label) from scoped),
    'filters', jsonb_build_object(
      'cycle_code', p_cycle_code,
      'tribe_id', p_tribe_id,
      'chapter', p_chapter
    ),
    'stages', jsonb_build_object(
      'total_members', coalesce((select total_members from stage_rollup), 0),
      'members_with_full_core_trail', coalesce((select members_with_full_core_trail from stage_rollup), 0),
      'members_allocated_to_tribe', coalesce((select members_allocated_to_tribe from stage_rollup), 0),
      'members_with_published_artifact', coalesce((select members_with_published_artifact from stage_rollup), 0)
    ),
    'breakdown_by_tribe', coalesce((
      select jsonb_agg(to_jsonb(t) order by t.tribe_id)
      from (
        select
          s.tribe_id,
          count(distinct s.member_id)::integer as total_members,
          count(distinct s.member_id) filter (
            where coalesce(mcp.completed_core_courses, 0) >= coalesce((select total_core_courses from core_total), 0)
          )::integer as members_with_full_core_trail,
          count(distinct s.member_id) filter (where s.tribe_id is not null)::integer as members_allocated_to_tribe,
          count(distinct pa.member_id)::integer as members_with_published_artifact
        from scoped s
        left join member_core_progress mcp on mcp.member_id = s.member_id
        left join published_artifacts pa on pa.member_id = s.member_id
        where s.tribe_id is not null
        group by s.tribe_id
      ) t
    ), '[]'::jsonb),
    'breakdown_by_chapter', coalesce((
      select jsonb_agg(to_jsonb(c) order by c.chapter)
      from (
        select
          s.chapter,
          count(distinct s.member_id)::integer as total_members,
          count(distinct s.member_id) filter (
            where coalesce(mcp.completed_core_courses, 0) >= coalesce((select total_core_courses from core_total), 0)
          )::integer as members_with_full_core_trail,
          count(distinct s.member_id) filter (where s.tribe_id is not null)::integer as members_allocated_to_tribe,
          count(distinct pa.member_id)::integer as members_with_published_artifact
        from scoped s
        left join member_core_progress mcp on mcp.member_id = s.member_id
        left join published_artifacts pa on pa.member_id = s.member_id
        where s.chapter is not null and trim(s.chapter) <> ''
        group by s.chapter
      ) c
    ), '[]'::jsonb)
  ) into v_result;

  return coalesce(v_result, jsonb_build_object(
    'cycle_code', p_cycle_code,
    'filters', jsonb_build_object('cycle_code', p_cycle_code, 'tribe_id', p_tribe_id, 'chapter', p_chapter),
    'stages', jsonb_build_object(
      'total_members', 0,
      'members_with_full_core_trail', 0,
      'members_allocated_to_tribe', 0,
      'members_with_published_artifact', 0
    ),
    'breakdown_by_tribe', '[]'::jsonb,
    'breakdown_by_chapter', '[]'::jsonb
  ));
end;
$$;

