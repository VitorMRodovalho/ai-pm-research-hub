-- Track Q-A Phase A (p174 re-audit) — orphan recovery batch p174 (23 fns)
--
-- Captures live bodies for 23 functions that exist in pg_proc.public but had
-- ZERO CREATE [OR REPLACE] FUNCTION blocks in any supabase/migrations/*.sql
-- file at p174 audit time.
--
-- The functions accumulated post-p52 (Track Q-A baseline empty 2026-04-25)
-- because the Track Q-C contract test (`tests/contracts/rpc-migration-coverage.test.mjs`)
-- was SKIPPED on CI due to missing SUPABASE_SERVICE_ROLE_KEY env var. The
-- test silently passed via offline-only baseline check. CI gap is addressed
-- separately in p174 (`.github/workflows/ci.yml`).
--
-- Categories (23 total):
--   * 10 trigger functions (`*_set_updated_at`): trivial updated_at row-event triggers
--   * 4 analytics + tier helpers (`analytics_is_leadership_role`, `analytics_role_bucket`,
--     `has_min_tier`, `exec_role_transitions`)
--   * 9 misc readers/writers (`count_tribe_slots`, `get_comms_dashboard_metrics`,
--     `get_communication_template`, `list_admin_links`, `list_taxonomy_tags`,
--     `member_self_update`, `resolve_whatsapp_link`, `search_knowledge`,
--     `suggest_tags`)
--
-- Bodies captured verbatim from `pg_get_functiondef` (delimiter `$function$`
-- converted to `$$` for kpi-portfolio-health.test.mjs regex). CREATE OR REPLACE
-- is idempotent — live state unchanged.
--
-- Per CLAUDE.md `.claude/rules/database.md`: DDL MUST use apply_migration.
-- This recovery migration captures pre-existing state. Future orphans will be
-- caught by the contract test (after CI env fix in same session).

-- analytics_is_leadership_role(p_operational_role text, p_designations text[])  [prosrc_len=262, secdef=false]
CREATE OR REPLACE FUNCTION public.analytics_is_leadership_role(p_operational_role text, p_designations text[])
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $$
  select
    p_operational_role in ('manager', 'deputy_manager', 'tribe_leader')
    or coalesce('ambassador' = any(p_designations), false)
    or coalesce('chapter_liaison' = any(p_designations), false)
    or coalesce('sponsor' = any(p_designations), false);
$$
;

-- analytics_role_bucket(p_operational_role text, p_designations text[])  [prosrc_len=695, secdef=false]
CREATE OR REPLACE FUNCTION public.analytics_role_bucket(p_operational_role text, p_designations text[])
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $$
  select case
    when p_operational_role = 'manager' then 'manager'
    when p_operational_role = 'deputy_manager' then 'deputy_manager'
    when p_operational_role = 'tribe_leader' then 'tribe_leader'
    when coalesce('ambassador' = any(p_designations), false) then 'ambassador'
    when coalesce('chapter_liaison' = any(p_designations), false) then 'chapter_liaison'
    when coalesce('sponsor' = any(p_designations), false) then 'sponsor'
    when p_operational_role in ('researcher', 'facilitator', 'communicator') then p_operational_role
    when p_operational_role is null or trim(p_operational_role) = '' or p_operational_role = 'none' then 'member'
    else p_operational_role
  end;
$$
;

-- board_source_tribe_map_set_updated_at()  [prosrc_len=104, secdef=false]
CREATE OR REPLACE FUNCTION public.board_source_tribe_map_set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $$
begin
  new.updated_at = now();
  new.source_board = lower(trim(new.source_board));
  return new;
end;
$$
;

-- count_tribe_slots()  [prosrc_len=329, secdef=true]
CREATE OR REPLACE FUNCTION public.count_tribe_slots()
 RETURNS json
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT coalesce(
    json_object_agg(tribe_id, cnt),
    '{}'::json
  )
  FROM (
    SELECT tribe_id, count(*)::int as cnt
    FROM public.members
    WHERE member_status = 'active'
      AND tribe_id IS NOT NULL
      AND operational_role NOT IN ('sponsor', 'chapter_liaison', 'guest', 'none')
    GROUP BY tribe_id
  ) sub;
$$
;

-- exec_role_transitions(p_cycle_code text, p_tribe_id integer, p_chapter text)  [prosrc_len=3509, secdef=true]
CREATE OR REPLACE FUNCTION public.exec_role_transitions(p_cycle_code text DEFAULT NULL::text, p_tribe_id integer DEFAULT NULL::integer, p_chapter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
declare
  v_result jsonb;
begin
  if not public.can_read_internal_analytics() then
    raise exception 'Internal analytics access required';
  end if;

  with history_rows as (
    select
      mch.member_id,
      mch.cycle_code,
      coalesce(mch.cycle_label, c.cycle_label, mch.cycle_code) as cycle_label,
      coalesce(c.sort_order, 9999) as sort_order,
      coalesce(mch.chapter, m.chapter) as chapter,
      coalesce(mch.tribe_id, m.tribe_id) as tribe_id,
      public.analytics_role_bucket(mch.operational_role, mch.designations) as role_bucket,
      public.analytics_is_leadership_role(mch.operational_role, mch.designations) as is_leadership
    from public.member_cycle_history mch
    left join public.cycles c on c.cycle_code = mch.cycle_code
    left join public.members m on m.id = mch.member_id
    where mch.member_id is not null
  ),
  ordered_transitions as (
    select
      hr.*,
      lag(hr.cycle_code) over (partition by hr.member_id order by hr.sort_order, hr.cycle_code) as from_cycle_code,
      lag(hr.cycle_label) over (partition by hr.member_id order by hr.sort_order, hr.cycle_code) as from_cycle_label,
      lag(hr.role_bucket) over (partition by hr.member_id order by hr.sort_order, hr.cycle_code) as from_role_bucket,
      lag(hr.is_leadership) over (partition by hr.member_id order by hr.sort_order, hr.cycle_code) as from_is_leadership
    from history_rows hr
  ),
  filtered_transitions as (
    select *
    from ordered_transitions
    where from_cycle_code is not null
      and (p_cycle_code is null or cycle_code = p_cycle_code)
      and (p_tribe_id is null or tribe_id = p_tribe_id)
      and (p_chapter is null or chapter = p_chapter)
  ),
  conversion_cycles as (
    select
      cycle_code,
      max(cycle_label) as cycle_label,
      count(distinct member_id)::integer as promoted_members
    from filtered_transitions
    where coalesce(from_is_leadership, false) is false
      and is_leadership is true
    group by cycle_code
  )
  select jsonb_build_object(
    'cycle_code', p_cycle_code,
    'summary', jsonb_build_object(
      'tracked_transitions', coalesce((select count(*) from filtered_transitions), 0),
      'promoted_members', coalesce((
        select sum(promoted_members)::integer from conversion_cycles
      ), 0),
      'leadership_roles', jsonb_build_array(
        'tribe_leader',
        'ambassador',
        'manager',
        'deputy_manager',
        'chapter_liaison',
        'sponsor'
      )
    ),
    'conversions_by_cycle', coalesce((
      select jsonb_agg(to_jsonb(c) order by c.cycle_code)
      from conversion_cycles c
    ), '[]'::jsonb),
    'transition_matrix', coalesce((
      select jsonb_agg(to_jsonb(m) order by m.transitions desc, m.from_role_bucket, m.to_role_bucket)
      from (
        select
          from_role_bucket,
          role_bucket as to_role_bucket,
          count(*)::integer as transitions
        from filtered_transitions
        group by from_role_bucket, role_bucket
      ) m
    ), '[]'::jsonb)
  ) into v_result;

  return coalesce(v_result, jsonb_build_object(
    'cycle_code', p_cycle_code,
    'summary', jsonb_build_object(
      'tracked_transitions', 0,
      'promoted_members', 0,
      'leadership_roles', jsonb_build_array(
        'tribe_leader',
        'ambassador',
        'manager',
        'deputy_manager',
        'chapter_liaison',
        'sponsor'
      )
    ),
    'conversions_by_cycle', '[]'::jsonb,
    'transition_matrix', '[]'::jsonb
  ));
end;
$$
;

-- get_comms_dashboard_metrics()  [prosrc_len=2984, secdef=true]
CREATE OR REPLACE FUNCTION public.get_comms_dashboard_metrics()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
declare
  v_result jsonb;
  v_backlog int;
  v_overdue int;
  v_total int;
  v_by_status jsonb;
  v_by_format jsonb;
  v_board_ids uuid[];
begin
  -- Boards de comunicação (domain_key = 'communication')
  select array_agg(pb.id)
    into v_board_ids
  from public.project_boards pb
  where coalesce(pb.domain_key, '') = 'communication'
    and pb.is_active is true;

  if v_board_ids is null or array_length(v_board_ids, 1) = 0 then
    return jsonb_build_object(
      'backlog_count', 0,
      'overdue_count', 0,
      'total_publications', 0,
      'by_status', '[]'::jsonb,
      'by_format', '[]'::jsonb
    );
  end if;

  select
    count(*) filter (where bi.status in ('backlog','todo') or bi.status is null)::int,
    count(*) filter (where bi.due_date is not null and bi.due_date::date < current_date and coalesce(bi.status, '') not in ('done','review'))::int,
    count(*)::int
  into v_backlog, v_overdue, v_total
  from public.board_items bi
  where bi.board_id = any(v_board_ids);

  select coalesce(
    jsonb_object_agg(s.status, s.cnt),
    '{}'::jsonb
  )
  into v_by_status
  from (
    select coalesce(bi.status, 'unknown') as status, count(*)::int as cnt
    from public.board_items bi
    where bi.board_id = any(v_board_ids)
    group by coalesce(bi.status, 'unknown')
  ) s;

  -- Distribuição por formato: tags são string[] no board_items
  -- Extraímos tags comuns: vídeo, artigo, linkedin, post, etc.
  with items_tags as (
    select unnest(
      case when bi.tags is null or array_length(bi.tags, 1) is null or array_length(bi.tags, 1) = 0
        then array['outros']::text[] else bi.tags
      end
    ) as tag
    from public.board_items bi
    where bi.board_id = any(v_board_ids)
  ),
  normalized as (
    select
      case
        when lower(tag) in ('video','vídeo') then 'vídeo'
        when lower(tag) in ('artigo','article','artigos') then 'artigo'
        when lower(tag) in ('linkedin','linkedin post') then 'LinkedIn'
        when lower(tag) in ('post','posts') then 'post'
        when lower(tag) in ('newsletter') then 'newsletter'
        when lower(tag) in ('podcast') then 'podcast'
        when lower(tag) in ('infográfico','infographic') then 'infográfico'
        else coalesce(nullif(trim(tag), ''), 'outros')
      end as format
    from items_tags
  )
  select coalesce(
    jsonb_object_agg(n.format, n.cnt),
    '{}'::jsonb
  )
  into v_by_format
  from (
    select format, count(*)::int as cnt
    from normalized
    group by format
  ) n;

  -- Se não há tags, default "outros" = total
  if v_by_format is null or v_by_format = '{}'::jsonb then
    v_by_format := jsonb_build_object('outros', v_total);
  end if;

  v_result := jsonb_build_object(
    'backlog_count', coalesce(v_backlog, 0),
    'overdue_count', coalesce(v_overdue, 0),
    'total_publications', coalesce(v_total, 0),
    'by_status', coalesce(v_by_status, '{}'::jsonb),
    'by_format', coalesce(v_by_format, '{}'::jsonb)
  );

  return v_result;
end;
$$
;

-- get_communication_template(p_slug text, p_vars jsonb)  [prosrc_len=910, secdef=true]
CREATE OR REPLACE FUNCTION public.get_communication_template(p_slug text, p_vars jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
declare
  v_tpl record;
  v_sig text;
  v_subj text;
  v_body text;
  v_key text;
  v_val text;
begin
  select * into v_tpl from public.communication_templates where slug = p_slug and is_active = true;
  if v_tpl is null then
    return jsonb_build_object('error', 'Template not found: ' || p_slug);
  end if;

  v_sig := v_tpl.signature_tpl;
  v_subj := v_tpl.subject_tpl;
  v_body := v_tpl.body_html_tpl;

  for v_key in select unnest(v_tpl.variables)
  loop
    v_val := coalesce(p_vars ->> v_key, '');
    v_sig := replace(v_sig, '{{' || v_key || '}}', v_val);
    v_subj := replace(v_subj, '{{' || v_key || '}}', v_val);
    v_body := replace(v_body, '{{' || v_key || '}}', v_val);
  end loop;

  return jsonb_build_object(
    'slug', v_tpl.slug,
    'label', v_tpl.label,
    'subject', v_subj,
    'body_html', v_body,
    'signature_html', v_sig,
    'variables', to_jsonb(v_tpl.variables)
  );
end;
$$
;

-- has_min_tier(required_rank integer)  [prosrc_len=791, secdef=true]
CREATE OR REPLACE FUNCTION public.has_min_tier(required_rank integer)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
declare
  v_rec record;
  v_rank integer := 0;
begin
  select * into v_rec from public.get_my_member_record();
  if not found then return false; end if;

  -- Tier mapping: visitor=0, member=1, observer=2, leader=3, admin=4, superadmin=5
  if v_rec.is_superadmin = true then
    v_rank := 5;
  elsif v_rec.operational_role in ('manager', 'deputy_manager') then
    v_rank := 4;
  elsif v_rec.operational_role = 'tribe_leader' then
    v_rank := 3;
  elsif v_rec.operational_role in ('researcher', 'facilitator', 'communicator') then
    v_rank := 1;
  elsif v_rec.designations is not null and array_length(v_rec.designations, 1) > 0 then
    -- Has designations like sponsor, co_gp → observer level
    v_rank := 2;
  else
    v_rank := 0;
  end if;

  return v_rank >= required_rank;
end;
$$
;

-- ingestion_batch_files_set_updated_at()  [prosrc_len=52, secdef=false]
CREATE OR REPLACE FUNCTION public.ingestion_batch_files_set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $$
begin
  new.updated_at = now();
  return new;
end;
$$
;

-- ingestion_run_ledger_set_updated_at()  [prosrc_len=52, secdef=false]
CREATE OR REPLACE FUNCTION public.ingestion_run_ledger_set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $$
begin
  new.updated_at = now();
  return new;
end;
$$
;

-- legacy_member_links_set_updated_at()  [prosrc_len=52, secdef=false]
CREATE OR REPLACE FUNCTION public.legacy_member_links_set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $$
begin
  new.updated_at = now();
  return new;
end;
$$
;

-- legacy_tribe_board_links_set_updated_at()  [prosrc_len=52, secdef=false]
CREATE OR REPLACE FUNCTION public.legacy_tribe_board_links_set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $$
begin
  new.updated_at = now();
  return new;
end;
$$
;

-- list_admin_links()  [prosrc_len=105, secdef=true]
CREATE OR REPLACE FUNCTION public.list_admin_links()
 RETURNS SETOF admin_links
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
  select * from public.admin_links
  where is_active = true
  order by sort_order asc, created_at desc;
$$
;

-- list_taxonomy_tags()  [prosrc_len=89, secdef=true]
CREATE OR REPLACE FUNCTION public.list_taxonomy_tags()
 RETURNS SETOF taxonomy_tags
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
  select * from public.taxonomy_tags where is_active = true order by category, tag_key;
$$
;

-- member_self_update(p_pmi_id text, p_phone text, p_linkedin_url text, p_credly_url text, p_share_whatsapp boolean)  [prosrc_len=640, secdef=true]
CREATE OR REPLACE FUNCTION public.member_self_update(p_pmi_id text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_linkedin_url text DEFAULT NULL::text, p_credly_url text DEFAULT NULL::text, p_share_whatsapp boolean DEFAULT NULL::boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
declare
  v_uid uuid := auth.uid();
  v_member record;
begin
  select * into v_member from public.members where auth_id = v_uid;
  if not found then
    return jsonb_build_object('success', false, 'error', 'Member not found');
  end if;

  update public.members set
    pmi_id       = coalesce(p_pmi_id, pmi_id),
    phone        = coalesce(p_phone, phone),
    linkedin_url = coalesce(p_linkedin_url, linkedin_url),
    credly_url   = coalesce(p_credly_url, credly_url),
    share_whatsapp = coalesce(p_share_whatsapp, share_whatsapp),
    updated_at   = now()
  where auth_id = v_uid;

  return jsonb_build_object('success', true);
end;
$$
;

-- notion_import_staging_set_updated_at()  [prosrc_len=52, secdef=false]
CREATE OR REPLACE FUNCTION public.notion_import_staging_set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $$
begin
  new.updated_at = now();
  return new;
end;
$$
;

-- resolve_whatsapp_link(p_member_id uuid)  [prosrc_len=1451, secdef=true]
CREATE OR REPLACE FUNCTION public.resolve_whatsapp_link(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
declare
  v_caller_id uuid := auth.uid();
  v_caller record;
  v_target record;
  v_clean_phone text;
begin
  -- Get caller
  select id, tribe_id, operational_role, is_superadmin
    into v_caller from public.members where auth_id = v_caller_id;
  if not found then
    return jsonb_build_object('success', false, 'error', 'Caller not found');
  end if;

  -- Get target
  select id, phone, tribe_id, share_whatsapp
    into v_target from public.members where id = p_member_id;
  if not found then
    return jsonb_build_object('success', false, 'error', 'Member not found');
  end if;

  -- Check opt-in
  if v_target.share_whatsapp is not true then
    return jsonb_build_object('success', false, 'error', 'Member has not opted in');
  end if;

  -- Check same tribe or admin
  if not (
    v_caller.is_superadmin = true
    or v_caller.operational_role in ('manager', 'deputy_manager')
    or (v_caller.tribe_id is not null and v_caller.tribe_id = v_target.tribe_id)
  ) then
    return jsonb_build_object('success', false, 'error', 'Not authorized');
  end if;

  -- No phone registered
  if v_target.phone is null or v_target.phone = '' then
    return jsonb_build_object('success', false, 'error', 'No phone registered');
  end if;

  -- Clean phone: keep only digits
  v_clean_phone := regexp_replace(v_target.phone, '[^0-9]', '', 'g');

  return jsonb_build_object(
    'success', true,
    'url', 'https://wa.me/' || v_clean_phone
  );
end;
$$
;

-- search_knowledge(search_term text)  [prosrc_len=805, secdef=true]
CREATE OR REPLACE FUNCTION public.search_knowledge(search_term text)
 RETURNS TABLE(chunk_id uuid, content_snippet text, asset_id uuid, artifact_id text, tribe_name text, theme_title text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
declare
  v_term text;
begin
  v_term := coalesce(trim(search_term), '');
  if length(v_term) < 2 then
    return;
  end if;
  v_term := '%' || v_term || '%';

  return query
  select
    kc.id::uuid as chunk_id,
    left(kc.content, 100) as content_snippet,
    kc.asset_id,
    coalesce(ka.metadata->>'artifact_id', ka.source_url, '')::text as artifact_id,
    coalesce(ka.metadata->>'tribe_name', '')::text as tribe_name,
    coalesce(ka.title, '')::text as theme_title
  from public.knowledge_chunks kc
  join public.knowledge_assets ka on ka.id = kc.asset_id
  where ka.is_active = true
    and (kc.content ilike v_term or ka.title ilike v_term or ka.summary ilike v_term)
  order by
    case when ka.title ilike v_term then 0 else 1 end,
    kc.chunk_index,
    kc.created_at desc
  limit 10;
end;
$$
;

-- set_comms_metrics_updated_at()  [prosrc_len=52, secdef=false]
CREATE OR REPLACE FUNCTION public.set_comms_metrics_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $$
begin
  new.updated_at = now();
  return new;
end;
$$
;

-- set_hub_resources_updated_at()  [prosrc_len=52, secdef=false]
CREATE OR REPLACE FUNCTION public.set_hub_resources_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $$
begin
  new.updated_at = now();
  return new;
end;
$$
;

-- suggest_tags(p_title text, p_type text, p_cycle_code text)  [prosrc_len=2322, secdef=false]
CREATE OR REPLACE FUNCTION public.suggest_tags(p_title text, p_type text DEFAULT NULL::text, p_cycle_code text DEFAULT NULL::text)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $$
declare
  v_tags text[] := '{}';
  v_lower text := lower(coalesce(p_title, ''));
  v_type text := lower(coalesce(p_type, ''));
begin
  -- Keyword-based detection
  if v_lower like '%webinar%' or v_lower like '%pmi-%' or v_lower like '%capitulo%' or v_lower like '%chapter%' then
    v_tags := v_tags || 'webinar'::text;
    if v_lower like '%pmi-go%' or v_lower like '%goias%' or v_lower like '%pmi-ce%' or v_lower like '%pmi-df%' or v_lower like '%pmi-mg%' or v_lower like '%pmi-rs%' then
      v_tags := v_tags || 'chapter_partnership'::text;
    end if;
  end if;

  if v_lower like '%artigo%' or v_lower like '%article%' or v_lower like '%paper%' or v_lower like '%publicacao%' then
    v_tags := v_tags || 'article'::text;
  end if;

  if v_lower like '%framework%' or v_lower like '%modelo%' or v_lower like '%template%' then
    v_tags := v_tags || 'framework'::text;
  end if;

  if v_lower like '%curso%' or v_lower like '%course%' or v_lower like '%trilha%' or v_lower like '%trail%' then
    v_tags := v_tags || 'course'::text;
  end if;

  if v_lower like '%mentor%' or v_lower like '%onboarding%' then
    v_tags := v_tags || 'onboarding'::text;
  end if;

  if v_lower like '%prototip%' or v_lower like '%prototype%' or v_lower like '%piloto%' or v_lower like '%pilot%' then
    v_tags := v_tags || 'pilot_project'::text;
  end if;

  if v_lower like '%ata%' or v_lower like '%minuta%' or v_lower like '%minutes%' or v_lower like '%reuniao%' then
    v_tags := v_tags || 'meeting_minutes'::text;
  end if;

  if v_lower like '%relatorio%' or v_lower like '%report%' then
    v_tags := v_tags || 'report'::text;
  end if;

  -- Type-based fallback
  if v_type in ('article', 'paper') and not ('article' = any(v_tags)) then
    v_tags := v_tags || 'article'::text;
  end if;
  if v_type = 'video' and not ('webinar' = any(v_tags)) then
    v_tags := v_tags || 'webinar'::text;
  end if;

  -- Cycle-based default (from Wave5 plan)
  if array_length(v_tags, 1) is null then
    case
      when p_cycle_code in ('pilot') then v_tags := ARRAY['governance'];
      when p_cycle_code in ('cycle_1', 'cycle_2') then v_tags := ARRAY['article'];
      when p_cycle_code in ('cycle_3') then v_tags := ARRAY['chapter_partnership'];
      else v_tags := ARRAY['untagged'];
    end case;
  end if;

  return v_tags;
end;
$$
;

-- tribe_continuity_overrides_set_updated_at()  [prosrc_len=52, secdef=false]
CREATE OR REPLACE FUNCTION public.tribe_continuity_overrides_set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $$
begin
  new.updated_at = now();
  return new;
end;
$$
;

-- tribe_lineage_set_updated_at()  [prosrc_len=52, secdef=false]
CREATE OR REPLACE FUNCTION public.tribe_lineage_set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $$
begin
  new.updated_at = now();
  return new;
end;
$$
;

