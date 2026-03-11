-- ============================================================================
-- Global publications board + operational board scope hardening
-- Date: 2026-03-14
-- ============================================================================

begin;

alter table public.project_boards
  add column if not exists board_scope text not null default 'tribe';

alter table public.project_boards
  drop constraint if exists project_boards_board_scope_chk;

alter table public.project_boards
  add constraint project_boards_board_scope_chk
  check (board_scope in ('tribe', 'operational', 'global'));

create index if not exists idx_project_boards_scope
  on public.project_boards (board_scope, is_active)
  where is_active is true;

alter table public.project_boards
  drop constraint if exists project_boards_linked_sources_require_tribe_chk;

alter table public.project_boards
  add constraint project_boards_linked_sources_require_tribe_chk
  check (
    source not in ('trello', 'notion')
    or tribe_id is not null
    or board_scope = 'global'
  );

update public.tribes
set
  name = 'Hub de Comunicação',
  workstream_type = 'operational',
  updated_at = now()
where id = 8
  and (
    name is distinct from 'Hub de Comunicação'
    or coalesce(workstream_type, '') <> 'operational'
  );

update public.project_boards pb
set
  board_scope = 'operational',
  domain_key = coalesce(nullif(pb.domain_key, ''), 'communication'),
  tribe_id = coalesce(pb.tribe_id, 8),
  updated_at = now()
where (
  lower(coalesce(pb.board_name, '')) like '%comunic%'
  or lower(coalesce(pb.board_name, '')) like '%midia%'
  or lower(coalesce(pb.board_name, '')) like '%social%'
  or coalesce(pb.domain_key, '') = 'communication'
  or exists (
    select 1
    from public.board_items bi
    where bi.board_id = pb.id
      and bi.source_board in ('comunicacao_ciclo3', 'midias_sociais', 'social_media', 'comms_c3')
  )
);

do $$
declare
  v_target_board_id uuid;
  v_promoted_board_id uuid;
begin
  select pb.id
    into v_target_board_id
  from public.project_boards pb
  where pb.is_active is true
    and (
      coalesce(pb.domain_key, '') = 'communication'
      or lower(coalesce(pb.board_name, '')) like '%hub de comunicação%'
      or lower(coalesce(pb.board_name, '')) like '%hub de comunicacao%'
      or lower(coalesce(pb.board_name, '')) like '%comunicacao%'
    )
  order by
    case when coalesce(pb.domain_key, '') = 'communication' then 0 else 1 end,
    pb.updated_at desc nulls last,
    pb.created_at asc
  limit 1;

  if v_target_board_id is null then
    insert into public.project_boards (
      board_name,
      tribe_id,
      source,
      board_scope,
      domain_key,
      columns,
      is_active
    ) values (
      'Hub de Comunicação',
      8,
      'manual',
      'operational',
      'communication',
      '["backlog","todo","in_progress","review","done"]'::jsonb,
      true
    )
    returning id into v_target_board_id;
  else
    update public.project_boards
    set
      board_name = 'Hub de Comunicação',
      tribe_id = 8,
      board_scope = 'operational',
      domain_key = 'communication',
      is_active = true,
      updated_at = now()
    where id = v_target_board_id;
  end if;

  with merge_sources as (
    select pb.id
    from public.project_boards pb
    where pb.id <> v_target_board_id
      and pb.is_active is true
      and (
        coalesce(pb.domain_key, '') = 'communication'
        or lower(coalesce(pb.board_name, '')) like '%comunic%'
        or lower(coalesce(pb.board_name, '')) like '%midia%'
        or lower(coalesce(pb.board_name, '')) like '%social%'
      )
  )
  update public.board_items bi
  set board_id = v_target_board_id,
      updated_at = now()
  where bi.board_id in (select id from merge_sources);

  update public.project_boards pb
  set
    is_active = false,
    updated_at = now()
  where pb.id <> v_target_board_id
    and pb.is_active is true
    and (
      coalesce(pb.domain_key, '') = 'communication'
      or lower(coalesce(pb.board_name, '')) like '%comunic%'
      or lower(coalesce(pb.board_name, '')) like '%midia%'
      or lower(coalesce(pb.board_name, '')) like '%social%'
    );

  select pb.id
    into v_promoted_board_id
  from public.project_boards pb
  where pb.is_active is true
    and (
      coalesce(pb.domain_key, '') = 'publications_submissions'
      or lower(coalesce(pb.board_name, '')) like '%projectmanagement.com%'
      or lower(coalesce(pb.board_name, '')) like '%publica%'
      or lower(coalesce(pb.board_name, '')) like '%submiss%'
      or lower(coalesce(pb.board_name, '')) like '%artigo%'
    )
  order by
    case when coalesce(pb.domain_key, '') = 'publications_submissions' then 0 else 1 end,
    pb.updated_at desc nulls last,
    pb.created_at asc
  limit 1;

  if v_promoted_board_id is null then
    insert into public.project_boards (
      board_name,
      tribe_id,
      source,
      board_scope,
      domain_key,
      columns,
      is_active
    ) values (
      'Publicações & Submissões PMI',
      null,
      'manual',
      'global',
      'publications_submissions',
      '["backlog","todo","in_progress","review","done"]'::jsonb,
      true
    )
    returning id into v_promoted_board_id;
  else
    update public.project_boards
    set
      board_name = 'Publicações & Submissões PMI',
      tribe_id = null,
      board_scope = 'global',
      domain_key = 'publications_submissions',
      is_active = true,
      updated_at = now()
    where id = v_promoted_board_id;
  end if;
end $$;

alter table public.project_boards
  drop constraint if exists project_boards_linked_sources_require_tribe_chk;

alter table public.project_boards
  add constraint project_boards_linked_sources_require_tribe_chk
  check (
    source not in ('trello', 'notion')
    or tribe_id is not null
    or board_scope = 'global'
  );

create or replace function public.enforce_board_item_source_tribe_integrity()
returns trigger
language plpgsql
as $$
declare
  v_expected_tribe integer;
  v_board_tribe integer;
  v_board_scope text;
begin
  if new.source_board is null or trim(new.source_board) = '' then
    return new;
  end if;

  new.source_board := lower(trim(new.source_board));

  select pb.tribe_id, pb.board_scope
    into v_board_tribe, v_board_scope
  from public.project_boards pb
  where pb.id = new.board_id;

  if coalesce(v_board_scope, 'tribe') = 'global' then
    return new;
  end if;

  if v_board_tribe is null then
    raise exception 'Board % must have tribe_id before linking source_board %', new.board_id, new.source_board;
  end if;

  select m.tribe_id
    into v_expected_tribe
  from public.board_source_tribe_map m
  where m.source_board = new.source_board
    and m.is_active is true
  limit 1;

  if v_expected_tribe is not null and v_expected_tribe is distinct from v_board_tribe then
    raise exception 'Source board % expects tribe %, but board % is linked to tribe %',
      new.source_board, v_expected_tribe, new.board_id, v_board_tribe;
  end if;

  return new;
end;
$$;

create or replace function public.list_project_boards(
  p_tribe_id integer default null
)
returns setof json
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select row_to_json(r) from (
    select
      pb.id,
      pb.board_name,
      pb.tribe_id,
      t.name as tribe_name,
      pb.source,
      pb.columns,
      pb.is_active,
      pb.board_scope,
      pb.domain_key,
      pb.cycle_scope,
      pb.created_at,
      (select count(*) from public.board_items bi where bi.board_id = pb.id) as item_count
    from public.project_boards pb
    left join public.tribes t on t.id = pb.tribe_id
    where pb.is_active is true
      and (p_tribe_id is null or pb.tribe_id = p_tribe_id)
    order by
      case pb.board_scope when 'global' then 0 when 'operational' then 1 else 2 end,
      pb.created_at desc
  ) r;
end;
$$;

create or replace function public.upsert_board_item(
  p_item_id uuid default null,
  p_board_id uuid default null,
  p_title text default null,
  p_description text default null,
  p_status text default 'backlog',
  p_assignee_id uuid default null,
  p_due_date date default null,
  p_tags text[] default null,
  p_labels jsonb default '[]'::jsonb,
  p_checklist jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member public.members%rowtype;
  v_board public.project_boards%rowtype;
  v_item_id uuid;
  v_board_id uuid;
  v_allowed boolean := false;
  v_designations text[] := '{}';
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into v_member from public.members where auth_id = auth.uid();
  if v_member.id is null then
    raise exception 'Member not found';
  end if;

  v_designations := coalesce(v_member.designations, '{}'::text[]);

  if p_item_id is not null then
    select pb.*
      into v_board
    from public.project_boards pb
    join public.board_items bi on bi.board_id = pb.id
    where bi.id = p_item_id
    limit 1;
    v_board_id := v_board.id;
  else
    select * into v_board from public.project_boards where id = p_board_id limit 1;
    v_board_id := p_board_id;
  end if;

  if v_board.id is null then
    raise exception 'Board not found';
  end if;

  v_allowed := (
    coalesce(v_member.is_superadmin, false)
    or v_member.operational_role in ('manager', 'deputy_manager')
    or coalesce('co_gp' = any(v_designations), false)
    or (v_member.operational_role = 'tribe_leader' and v_member.tribe_id = v_board.tribe_id)
    or (
      coalesce(v_board.domain_key, '') = 'communication'
      and (
        v_member.operational_role = 'communicator'
        or coalesce('comms_team' = any(v_designations), false)
        or coalesce('comms_leader' = any(v_designations), false)
        or coalesce('comms_member' = any(v_designations), false)
      )
    )
    or (
      coalesce(v_board.domain_key, '') = 'publications_submissions'
      and (
        v_member.operational_role in ('tribe_leader', 'communicator')
        or coalesce('curator' = any(v_designations), false)
        or coalesce('co_gp' = any(v_designations), false)
        or coalesce('comms_leader' = any(v_designations), false)
        or coalesce('comms_member' = any(v_designations), false)
      )
    )
  );

  if not v_allowed then
    raise exception 'Project management access required';
  end if;

  if p_item_id is null then
    if coalesce(trim(p_title), '') = '' then
      raise exception 'Title is required';
    end if;

    insert into public.board_items (
      board_id,
      title,
      description,
      status,
      assignee_id,
      due_date,
      tags,
      labels,
      checklist,
      position
    )
    values (
      v_board_id,
      trim(p_title),
      nullif(trim(coalesce(p_description, '')), ''),
      coalesce(nullif(trim(coalesce(p_status, '')), ''), 'backlog'),
      p_assignee_id,
      p_due_date,
      p_tags,
      coalesce(p_labels, '[]'::jsonb),
      coalesce(p_checklist, '[]'::jsonb),
      coalesce((
        select max(position) + 1
        from public.board_items
        where board_id = v_board_id
      ), 1)
    )
    returning id into v_item_id;

    return v_item_id;
  end if;

  update public.board_items
  set
    title = coalesce(nullif(trim(coalesce(p_title, '')), ''), title),
    description = case
      when p_description is null then description
      else nullif(trim(p_description), '')
    end,
    status = coalesce(nullif(trim(coalesce(p_status, '')), ''), status),
    assignee_id = p_assignee_id,
    due_date = p_due_date,
    tags = p_tags,
    labels = coalesce(p_labels, labels),
    checklist = coalesce(p_checklist, checklist),
    updated_at = now()
  where id = p_item_id
  returning id into v_item_id;

  if v_item_id is null then
    raise exception 'Board item not found';
  end if;

  return v_item_id;
end;
$$;

create or replace function public.move_board_item(
  p_item_id uuid,
  p_new_status text,
  p_position integer default 0
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_board_id uuid;
  v_tribe_id integer;
  v_domain_key text;
  v_board_scope text;
  v_caller record;
  v_designations text[] := '{}';
begin
  select bi.board_id, pb.tribe_id, pb.domain_key, pb.board_scope
    into v_board_id, v_tribe_id, v_domain_key, v_board_scope
  from public.board_items bi
  join public.project_boards pb on pb.id = bi.board_id
  where bi.id = p_item_id;

  if not found then
    raise exception 'Board item not found';
  end if;

  select * into v_caller from public.members where auth_id = auth.uid();
  if v_caller is null then
    raise exception 'Member not found';
  end if;
  v_designations := coalesce(v_caller.designations, '{}'::text[]);

  if not (
    v_caller.is_superadmin is true
    or v_caller.operational_role in ('manager', 'deputy_manager')
    or coalesce('co_gp' = any(v_designations), false)
    or (v_caller.operational_role = 'tribe_leader' and v_caller.tribe_id = v_tribe_id)
    or (
      coalesce(v_domain_key, '') = 'communication'
      and (
        v_caller.operational_role = 'communicator'
        or coalesce('comms_team' = any(v_designations), false)
        or coalesce('comms_leader' = any(v_designations), false)
        or coalesce('comms_member' = any(v_designations), false)
      )
    )
    or (
      coalesce(v_domain_key, '') = 'publications_submissions'
      and (
        v_caller.operational_role in ('tribe_leader', 'communicator')
        or coalesce('curator' = any(v_designations), false)
        or coalesce('co_gp' = any(v_designations), false)
        or coalesce('comms_leader' = any(v_designations), false)
        or coalesce('comms_member' = any(v_designations), false)
      )
    )
  ) then
    raise exception 'Insufficient permissions';
  end if;

  update public.board_items
  set status = p_new_status, position = p_position, updated_at = now()
  where id = p_item_id;
end;
$$;

create or replace function public.admin_archive_board_item(
  p_item_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_item record;
  v_prev_status text;
  v_designations text[] := '{}';
begin
  select * into v_caller from public.get_my_member_record();
  select bi.*, pb.tribe_id as board_tribe_id, pb.domain_key
    into v_item
  from public.board_items bi
  join public.project_boards pb on pb.id = bi.board_id
  where bi.id = p_item_id;

  if v_item is null then
    raise exception 'Board item not found: %', p_item_id;
  end if;

  v_designations := coalesce(v_caller.designations, '{}'::text[]);

  if v_caller is null
    or not (
      v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_designations), false)
      or (v_caller.operational_role = 'tribe_leader' and v_caller.tribe_id = v_item.board_tribe_id)
      or (
        coalesce(v_item.domain_key, '') = 'communication'
        and (
          v_caller.operational_role = 'communicator'
          or coalesce('comms_team' = any(v_designations), false)
          or coalesce('comms_leader' = any(v_designations), false)
          or coalesce('comms_member' = any(v_designations), false)
        )
      )
      or (
        coalesce(v_item.domain_key, '') = 'publications_submissions'
        and (
          v_caller.operational_role in ('tribe_leader', 'communicator')
          or coalesce('curator' = any(v_designations), false)
          or coalesce('co_gp' = any(v_designations), false)
          or coalesce('comms_leader' = any(v_designations), false)
          or coalesce('comms_member' = any(v_designations), false)
        )
      )
    ) then
    raise exception 'Insufficient permissions';
  end if;

  v_prev_status := v_item.status;

  update public.board_items
  set status = 'archived',
      updated_at = now()
  where id = p_item_id;

  insert into public.board_lifecycle_events (
    board_id, item_id, action, previous_status, new_status, reason, actor_member_id
  ) values (
    v_item.board_id, p_item_id, 'item_archived', v_prev_status, 'archived',
    nullif(trim(coalesce(p_reason, '')), ''), v_caller.id
  );

  return jsonb_build_object(
    'success', true,
    'item_id', p_item_id,
    'previous_status', v_prev_status,
    'new_status', 'archived'
  );
end;
$$;

create or replace function public.enqueue_artifact_publication_card(
  p_artifact_id uuid,
  p_actor_member_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_board_id uuid;
  v_artifact record;
  v_existing_item_id uuid;
  v_new_item_id uuid;
  v_title text;
  v_description text;
begin
  select id
    into v_board_id
  from public.project_boards
  where is_active is true
    and coalesce(domain_key, '') = 'publications_submissions'
  order by updated_at desc nulls last, created_at asc
  limit 1;

  if v_board_id is null then
    raise exception 'Global publications board not found';
  end if;

  select a.*
    into v_artifact
  from public.artifacts a
  where a.id = p_artifact_id;

  if v_artifact is null then
    raise exception 'Artifact not found: %', p_artifact_id;
  end if;

  select bi.id
    into v_existing_item_id
  from public.board_items bi
  where bi.board_id = v_board_id
    and bi.source_board = 'global_publications_pipeline'
    and bi.source_card_id = p_artifact_id::text
  limit 1;

  v_title := coalesce(nullif(trim(v_artifact.title), ''), 'Artifact sem titulo');
  v_description := trim(
    coalesce(v_artifact.description, '')
    || E'\n\n'
    || 'Origem: Curadoria de Artefatos'
    || E'\n'
    || 'Artifact ID: ' || p_artifact_id::text
    || E'\n'
    || 'Tribo: ' || coalesce(v_artifact.tribe_id::text, 'Global')
  );

  if v_existing_item_id is not null then
    update public.board_items
    set
      title = v_title,
      description = nullif(v_description, ''),
      status = case when status = 'archived' then 'backlog' else status end,
      updated_at = now()
    where id = v_existing_item_id;

    return jsonb_build_object(
      'success', true,
      'enqueued', true,
      'board_id', v_board_id,
      'item_id', v_existing_item_id,
      'deduplicated', true
    );
  end if;

  insert into public.board_items (
    board_id,
    title,
    description,
    status,
    position,
    tags,
    source_board,
    source_card_id
  ) values (
    v_board_id,
    v_title,
    nullif(v_description, ''),
    'backlog',
    coalesce((select max(position) + 1 from public.board_items where board_id = v_board_id), 1),
    array['pmi_submission'],
    'global_publications_pipeline',
    p_artifact_id::text
  )
  returning id into v_new_item_id;

  if p_actor_member_id is not null then
    insert into public.board_lifecycle_events (
      board_id, item_id, action, previous_status, new_status, reason, actor_member_id
    ) values (
      v_board_id,
      v_new_item_id,
      'item_restored',
      null,
      'backlog',
      'Artifact aprovado na curadoria e enfileirado para submissao PMI',
      p_actor_member_id
    );
  end if;

  return jsonb_build_object(
    'success', true,
    'enqueued', true,
    'board_id', v_board_id,
    'item_id', v_new_item_id,
    'deduplicated', false
  );
end;
$$;

grant execute on function public.enqueue_artifact_publication_card(uuid, uuid) to authenticated;

create or replace function public.curate_item(
  p_table text,
  p_id uuid,
  p_action text,
  p_tags text[] default null,
  p_tribe_id integer default null,
  p_audience_level text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_rows integer := 0;
  v_enqueue_publication boolean := false;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      v_caller.is_superadmin
      or v_caller.operational_role in ('manager', 'deputy_manager')
    ) then
    raise exception 'Admin access required';
  end if;

  if p_action not in ('approve', 'reject', 'update_tags') then
    raise exception 'Invalid action: %', p_action;
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
        tribe_id = coalesce(p_tribe_id, tribe_id)
      where id = p_id;
    elsif p_action = 'reject' then
      update public.hub_resources
      set curation_status = 'rejected'
      where id = p_id;
    else
      update public.hub_resources
      set
        tags = coalesce(p_tags, tags),
        tribe_id = coalesce(p_tribe_id, tribe_id)
      where id = p_id;
    end if;
    get diagnostics v_rows = row_count;
  elsif p_table = 'events' then
    if p_action = 'approve' then
      update public.events
      set
        curation_status = 'approved',
        tribe_id = coalesce(p_tribe_id, tribe_id),
        audience_level = coalesce(nullif(trim(coalesce(p_audience_level, '')), ''), audience_level)
      where id = p_id;
    elsif p_action = 'reject' then
      update public.events
      set curation_status = 'rejected'
      where id = p_id;
    else
      update public.events
      set
        tribe_id = coalesce(p_tribe_id, tribe_id),
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
$$;

grant execute on function public.curate_item(text, uuid, text, text[], integer, text) to authenticated;

commit;
