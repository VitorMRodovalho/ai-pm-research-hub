-- ============================================================================
-- Tribe alignment patch: comms allocation + legacy remap + notion tribe 8 lane
-- Date: 2026-03-14
-- ============================================================================

begin;

do $$
declare
  v_comm_tribe_id integer;
  v_mayanna_id uuid;
  v_leticia_id uuid;
  v_andressa_id uuid;
  v_actor_id uuid;
  v_notion_board_id uuid;
begin
  -- Pick a management actor for audit columns when available.
  select id
    into v_actor_id
  from public.members
  where is_superadmin is true
     or operational_role in ('manager', 'deputy_manager')
  order by updated_at desc nulls last
  limit 1;

  -- 1) Resolve communication tribe inside current 1..8 model.
  select id
    into v_comm_tribe_id
  from public.tribes
  where lower(trim(name)) in (
    'tribo comunicacao',
    'tribo comunicação',
    'time de comunicacao',
    'time de comunicação',
    'comunicacao',
    'comunicação'
  )
  order by updated_at desc nulls last
  limit 1;

  if v_comm_tribe_id is null then
    -- Fallback agreed in operations: tribe 8 is the communication/notion lane.
    select id into v_comm_tribe_id
    from public.tribes
    where id = 8
    limit 1;
  end if;

  if v_comm_tribe_id is null then
    raise exception 'Communication tribe not found and fallback tribe 8 missing';
  end if;

  update public.tribes
  set is_active = true,
      name = case
        when v_comm_tribe_id = 8 and lower(name) not like '%comunic%'
          then trim(name || ' & Comunicação')
        else name
      end,
      notes = case
        when v_comm_tribe_id = 8
          then coalesce(notes, 'Tribo com frente de comunicação e integração de conhecimento')
        else notes
      end,
      updated_at = now(),
      updated_by = coalesce(v_actor_id, updated_by)
  where id = v_comm_tribe_id;

  -- 2) Allocate comms leader/member users into communication tribe.
  select id into v_mayanna_id
  from public.members
  where lower(name) like '%mayanna%duarte%'
  order by updated_at desc nulls last
  limit 1;

  select id into v_leticia_id
  from public.members
  where lower(name) like '%leticia%clemente%'
  order by updated_at desc nulls last
  limit 1;

  select id into v_andressa_id
  from public.members
  where lower(name) like '%andressa%martins%'
  order by updated_at desc nulls last
  limit 1;

  if v_mayanna_id is not null then
    update public.members
    set tribe_id = v_comm_tribe_id,
        designations = case
          when coalesce(designations, '{}') @> array['comms_leader']::text[] then coalesce(designations, '{}')
          else array_append(coalesce(designations, '{}'::text[]), 'comms_leader')
        end,
        updated_at = now()
    where id = v_mayanna_id;
  end if;

  if v_leticia_id is not null then
    update public.members
    set tribe_id = v_comm_tribe_id,
        designations = case
          when coalesce(designations, '{}') @> array['comms_member']::text[] then coalesce(designations, '{}')
          else array_append(coalesce(designations, '{}'::text[]), 'comms_member')
        end,
        updated_at = now()
    where id = v_leticia_id;
  end if;

  if v_andressa_id is not null then
    update public.members
    set tribe_id = v_comm_tribe_id,
        designations = case
          when coalesce(designations, '{}') @> array['comms_member']::text[] then coalesce(designations, '{}')
          else array_append(coalesce(designations, '{}'::text[]), 'comms_member')
        end,
        updated_at = now()
    where id = v_andressa_id;
  end if;

  -- Promote Mayanna as current communication tribe leader when available.
  if v_mayanna_id is not null then
    update public.tribes
    set leader_member_id = v_mayanna_id,
        updated_at = now(),
        updated_by = coalesce(v_actor_id, updated_by)
    where id = v_comm_tribe_id;
  end if;

  -- 3) Explicit continuity overrides requested by leadership:
  -- legacy tribe 3 -> current tribe 6
  -- legacy tribe 6 -> current tribe 2
  insert into public.tribe_continuity_overrides (
    continuity_key,
    legacy_cycle_code,
    legacy_tribe_id,
    current_cycle_code,
    current_tribe_id,
    leader_name,
    continuity_type,
    is_active,
    notes,
    metadata,
    updated_by
  )
  values
    (
      'fabricio-stream-renumbering',
      'cycle_2',
      3,
      'cycle_3',
      6,
      'Fabricio',
      'same_stream_new_id',
      true,
      'Leadership override: legacy tribe 3 continues as current tribe 6.',
      jsonb_build_object('patched_by', '20260314123000_tribe_alignment_comms_legacy_notion_fix.sql'),
      v_actor_id
    ),
    (
      'debora-stream-renumbering',
      'cycle_2',
      6,
      'cycle_3',
      2,
      'Debora',
      'same_stream_new_id',
      true,
      'Leadership override: legacy tribe 6 continues as current tribe 2.',
      jsonb_build_object('patched_by', '20260314123000_tribe_alignment_comms_legacy_notion_fix.sql'),
      v_actor_id
    )
  on conflict (continuity_key)
  do update set
    legacy_cycle_code = excluded.legacy_cycle_code,
    legacy_tribe_id = excluded.legacy_tribe_id,
    current_cycle_code = excluded.current_cycle_code,
    current_tribe_id = excluded.current_tribe_id,
    leader_name = excluded.leader_name,
    continuity_type = excluded.continuity_type,
    is_active = excluded.is_active,
    notes = excluded.notes,
    metadata = excluded.metadata,
    updated_by = excluded.updated_by;

  -- Keep lineage table aligned for legacy mapping visibility.
  insert into public.tribe_lineage (
    legacy_tribe_id,
    current_tribe_id,
    relation_type,
    cycle_scope,
    notes,
    metadata,
    is_active,
    created_by,
    updated_by
  )
  values
    (
      3,
      6,
      'renumbered_to',
      'cycle_1,cycle_2->cycle_3',
      'Legacy tribe 3 remapped to tribe 6 by leadership decision.',
      jsonb_build_object('patched_by', '20260314123000_tribe_alignment_comms_legacy_notion_fix.sql'),
      true,
      v_actor_id,
      v_actor_id
    ),
    (
      6,
      2,
      'renumbered_to',
      'cycle_1,cycle_2->cycle_3',
      'Legacy tribe 6 remapped to tribe 2 by leadership decision.',
      jsonb_build_object('patched_by', '20260314123000_tribe_alignment_comms_legacy_notion_fix.sql'),
      true,
      v_actor_id,
      v_actor_id
    )
  on conflict (legacy_tribe_id, current_tribe_id, relation_type, coalesce(cycle_scope, ''))
  do update set
    notes = excluded.notes,
    metadata = excluded.metadata,
    is_active = true,
    updated_by = excluded.updated_by;

  -- 4) Legacy Trello remap: old tribe 3 board stream now belongs to tribe 6.
  update public.project_boards pb
  set tribe_id = 6,
      is_active = true,
      updated_at = now()
  where exists (
    select 1
    from public.board_items bi
    where bi.board_id = pb.id
      and bi.source_board = 'tribo3_priorizacao'
  )
    and pb.tribe_id is distinct from 6;

  -- Keep manual board continuity for Italo/Fabricio stream visible in tribe 6.
  update public.project_boards
  set tribe_id = 6,
      is_active = true,
      updated_at = now()
  where source = 'manual'
    and coalesce(tribe_id, 0) <> 6
    and (
      lower(coalesce(board_name, '')) like '%italo%'
      or lower(coalesce(board_name, '')) like '%fabricio%'
      or lower(coalesce(board_name, '')) like '%roi%'
      or lower(coalesce(board_name, '')) like '%portfolio%'
    );

  -- 5) Communication boards should be attached to the communication tribe.
  update public.project_boards pb
  set tribe_id = v_comm_tribe_id,
      domain_key = 'communication',
      is_active = true,
      updated_at = now()
  where exists (
    select 1
    from public.board_items bi
    where bi.board_id = pb.id
      and bi.source_board in ('comunicacao_ciclo3', 'midias_sociais', 'social_media', 'comms_c3')
  );

  -- 6) Notion lane for tribe 8: ensure target board exists and link unmapped hints.
  select id
    into v_notion_board_id
  from public.project_boards
  where tribe_id = 8
    and source = 'notion'
    and lower(coalesce(board_name, '')) like '%notion%'
  order by created_at desc
  limit 1;

  if v_notion_board_id is null then
    insert into public.project_boards (
      board_name,
      tribe_id,
      source,
      domain_key,
      is_active,
      created_by,
      created_at,
      updated_at
    )
    values (
      'Notion Backlog - Tribo 8',
      8,
      'notion',
      'knowledge',
      true,
      v_actor_id,
      now(),
      now()
    )
    returning id into v_notion_board_id;
  else
    update public.project_boards
    set is_active = true,
        updated_at = now()
    where id = v_notion_board_id;
  end if;

  update public.notion_import_staging
  set mapped_board_id = v_notion_board_id,
      mapped_at = coalesce(mapped_at, now()),
      updated_at = now()
  where mapped_board_id is null
    and (
      lower(coalesce(tribe_hint, '')) in ('8', 'tribo 8', 'tribe 8')
      or lower(coalesce(title, '')) like '%tribo 8%'
      or lower(coalesce(title, '')) like '%tribe 8%'
      or lower(coalesce(description, '')) like '%tribo 8%'
      or lower(coalesce(description, '')) like '%tribe 8%'
      or lower(coalesce(tribe_hint, '')) like '%inclus%'
      or lower(coalesce(tribe_hint, '')) like '%colabora%'
      or lower(coalesce(tribe_hint, '')) like '%notion%'
    );
end
$$;

commit;
