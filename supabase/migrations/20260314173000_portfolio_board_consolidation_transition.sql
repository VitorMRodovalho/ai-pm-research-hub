-- ============================================================================
-- Transitional portfolio consolidation
-- Goal: one active board per research tribe + one comms operational board +
-- one global publications board for legacy visibility.
-- Date: 2026-03-14
-- ============================================================================

begin;

do $$
declare
  v_global_board_id uuid;
  v_comms_board_id uuid;
  v_tribe_board_id uuid;
  v_tribe record;
begin
  -- Canonical global publications board
  select pb.id
    into v_global_board_id
  from public.project_boards pb
  where pb.is_active is true
    and coalesce(pb.domain_key, '') = 'publications_submissions'
  order by pb.updated_at desc nulls last, pb.created_at asc
  limit 1;

  if v_global_board_id is null then
    insert into public.project_boards (
      board_name, tribe_id, source, board_scope, domain_key, columns, is_active
    ) values (
      'Publicações & Submissões PMI',
      null,
      'manual',
      'global',
      'publications_submissions',
      '["backlog","todo","in_progress","review","done"]'::jsonb,
      true
    )
    returning id into v_global_board_id;
  end if;

  -- Canonical operational comms board
  update public.tribes
  set name = 'Hub de Comunicação',
      workstream_type = 'operational',
      updated_at = now()
  where id = 8;

  select pb.id
    into v_comms_board_id
  from public.project_boards pb
  where pb.is_active is true
    and (
      coalesce(pb.domain_key, '') = 'communication'
      or lower(coalesce(pb.board_name, '')) like '%hub de comunica%'
      or (pb.tribe_id = 8 and pb.board_scope = 'operational')
    )
  order by
    case when coalesce(pb.domain_key, '') = 'communication' then 0 else 1 end,
    pb.updated_at desc nulls last,
    pb.created_at asc
  limit 1;

  if v_comms_board_id is null then
    insert into public.project_boards (
      board_name, tribe_id, source, board_scope, domain_key, columns, is_active
    ) values (
      'Hub de Comunicação',
      8,
      'manual',
      'operational',
      'communication',
      '["backlog","todo","in_progress","review","done"]'::jsonb,
      true
    )
    returning id into v_comms_board_id;
  else
    update public.project_boards
    set board_name = 'Hub de Comunicação',
        tribe_id = 8,
        board_scope = 'operational',
        domain_key = 'communication',
        is_active = true,
        updated_at = now()
    where id = v_comms_board_id;
  end if;

  -- Move legacy article boards to global publications board
  update public.board_items bi
  set board_id = v_global_board_id,
      updated_at = now()
  where bi.board_id in (
    select pb.id
    from public.project_boards pb
    where pb.id <> v_global_board_id
      and pb.is_active is true
      and (
        lower(coalesce(pb.board_name, '')) = 'articles'
        or lower(coalesce(pb.board_name, '')) like '%artigos%'
        or lower(coalesce(pb.board_name, '')) like '%projectmanagement%'
      )
  );

  update public.project_boards pb
  set board_scope = 'global',
      domain_key = 'publications_submissions',
      tribe_id = null,
      is_active = false,
      updated_at = now()
  where pb.id <> v_global_board_id
    and pb.is_active is true
    and (
      lower(coalesce(pb.board_name, '')) = 'articles'
      or lower(coalesce(pb.board_name, '')) like '%artigos%'
      or lower(coalesce(pb.board_name, '')) like '%projectmanagement%'
    );

  -- Merge remaining tribe-8 operational/legacy cards into canonical comms board
  update public.board_items bi
  set board_id = v_comms_board_id,
      updated_at = now()
  where bi.board_id in (
    select pb.id
    from public.project_boards pb
    where pb.is_active is true
      and pb.id <> v_comms_board_id
      and pb.tribe_id = 8
      and pb.board_scope <> 'global'
  );

  update public.project_boards pb
  set is_active = false,
      updated_at = now()
  where pb.is_active is true
    and pb.id <> v_comms_board_id
    and pb.tribe_id = 8
    and pb.board_scope <> 'global';

  -- One active tribe board per active research tribe
  for v_tribe in
    select t.id, t.name
    from public.tribes t
    where t.is_active is true
      and coalesce(t.workstream_type, 'research') = 'research'
    order by t.id
  loop
    select pb.id
      into v_tribe_board_id
    from public.project_boards pb
    where pb.is_active is true
      and pb.tribe_id = v_tribe.id
      and coalesce(pb.board_scope, 'tribe') = 'tribe'
    order by
      case when coalesce(pb.domain_key, '') in ('research_delivery', 'research') then 0 else 1 end,
      pb.created_at asc
    limit 1;

    if v_tribe_board_id is null then
      insert into public.project_boards (
        board_name, tribe_id, source, board_scope, domain_key, columns, is_active
      ) values (
        format('T%s: %s - Quadro Geral', v_tribe.id, v_tribe.name),
        v_tribe.id,
        'manual',
        'tribe',
        'research_delivery',
        '["backlog","todo","in_progress","review","done"]'::jsonb,
        true
      )
      returning id into v_tribe_board_id;
    else
      update public.project_boards
      set board_name = format('T%s: %s - Quadro Geral', v_tribe.id, v_tribe.name),
          board_scope = 'tribe',
          domain_key = coalesce(nullif(domain_key, ''), 'research_delivery'),
          is_active = true,
          updated_at = now()
      where id = v_tribe_board_id;
    end if;

    -- Merge sibling active tribe boards into canonical board
    update public.board_items bi
    set board_id = v_tribe_board_id,
        updated_at = now()
    where bi.board_id in (
      select pb.id
      from public.project_boards pb
      where pb.is_active is true
        and pb.tribe_id = v_tribe.id
        and coalesce(pb.board_scope, 'tribe') = 'tribe'
        and pb.id <> v_tribe_board_id
    );

    update public.project_boards pb
    set is_active = false,
        updated_at = now()
    where pb.is_active is true
      and pb.tribe_id = v_tribe.id
      and coalesce(pb.board_scope, 'tribe') = 'tribe'
      and pb.id <> v_tribe_board_id;
  end loop;
end $$;

commit;
