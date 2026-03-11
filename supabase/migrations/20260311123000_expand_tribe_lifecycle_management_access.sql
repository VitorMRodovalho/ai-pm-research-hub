-- ═══════════════════════════════════════════════════════════════════════════
-- Expand tribe lifecycle operations to project management
-- Date: 2026-03-11
--
-- Keeps SECURITY DEFINER lifecycle RPCs, but widens the caller guard from
-- superadmin-only to the project management layer:
--   - superadmin
--   - manager
--   - deputy_manager
--   - members with `co_gp` designation
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create or replace function public.admin_move_member_tribe(
  p_member_id uuid,
  p_new_tribe_id integer,
  p_reason text default 'Administrative transfer'
)
returns jsonb
language plpgsql security definer as $$
declare
  v_caller record;
  v_member record;
  v_old_tribe_name text;
  v_new_tribe_name text;
  v_cycle record;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
    ) then
    raise exception 'Project management access required';
  end if;

  select * into v_member from public.members where id = p_member_id;
  if v_member is null then
    raise exception 'Member not found: %', p_member_id;
  end if;

  select name into v_old_tribe_name from public.tribes where id = v_member.tribe_id;
  select name into v_new_tribe_name from public.tribes where id = p_new_tribe_id;

  if v_new_tribe_name is null then
    raise exception 'Target tribe not found: %', p_new_tribe_id;
  end if;

  select * into v_cycle from public.cycles where is_current = true limit 1;

  insert into public.member_cycle_history (
    member_id, cycle_code, cycle_label, cycle_start, cycle_end,
    operational_role, designations, tribe_id, tribe_name,
    chapter, is_active, member_name_snapshot, notes
  ) values (
    p_member_id,
    coalesce(v_cycle.cycle_code, 'cycle_3'),
    coalesce(v_cycle.cycle_label, 'Ciclo 3'),
    coalesce(v_cycle.cycle_start, now()::text),
    now()::text,
    v_member.operational_role,
    v_member.designations,
    v_member.tribe_id,
    coalesce(v_old_tribe_name, 'Sem tribo'),
    v_member.chapter,
    true,
    v_member.name,
    'TRANSFER: ' || coalesce(v_old_tribe_name, 'N/A') || ' -> ' || v_new_tribe_name || '. Reason: ' || p_reason || '. By: ' || v_caller.name
  );

  update public.members
  set tribe_id = p_new_tribe_id
  where id = p_member_id;

  return jsonb_build_object(
    'success', true,
    'member_name', v_member.name,
    'from_tribe', coalesce(v_old_tribe_name, 'N/A'),
    'to_tribe', v_new_tribe_name,
    'reason', p_reason
  );
end;
$$;

grant execute on function public.admin_move_member_tribe(uuid, integer, text) to authenticated;

create or replace function public.admin_deactivate_member(
  p_member_id uuid,
  p_reason text default 'Administrative deactivation'
)
returns jsonb
language plpgsql security definer as $$
declare
  v_caller record;
  v_member record;
  v_tribe_name text;
  v_cycle record;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
    ) then
    raise exception 'Project management access required';
  end if;

  select * into v_member from public.members where id = p_member_id;
  if v_member is null then
    raise exception 'Member not found: %', p_member_id;
  end if;

  select name into v_tribe_name from public.tribes where id = v_member.tribe_id;
  select * into v_cycle from public.cycles where is_current = true limit 1;

  insert into public.member_cycle_history (
    member_id, cycle_code, cycle_label, cycle_start, cycle_end,
    operational_role, designations, tribe_id, tribe_name,
    chapter, is_active, member_name_snapshot, notes
  ) values (
    p_member_id,
    coalesce(v_cycle.cycle_code, 'cycle_3'),
    coalesce(v_cycle.cycle_label, 'Ciclo 3'),
    coalesce(v_cycle.cycle_start, now()::text),
    now()::text,
    v_member.operational_role,
    v_member.designations,
    v_member.tribe_id,
    coalesce(v_tribe_name, 'N/A'),
    v_member.chapter,
    false,
    v_member.name,
    'DEACTIVATED: ' || p_reason || '. By: ' || v_caller.name
  );

  update public.members
  set current_cycle_active = false,
      inactivated_at = now()
  where id = p_member_id;

  return jsonb_build_object(
    'success', true,
    'member_name', v_member.name,
    'tribe', coalesce(v_tribe_name, 'N/A'),
    'reason', p_reason,
    'draft_email_subject', 'Comunicado: Afastamento de ' || v_member.name,
    'draft_email_body', 'Prezados,\n\nInformamos que o(a) pesquisador(a) ' || v_member.name || ' foi desligado(a) do Nucleo IA & GP.\nMotivo: ' || p_reason || '\n\nAtenciosamente,\nGerencia do Projeto'
  );
end;
$$;

grant execute on function public.admin_deactivate_member(uuid, text) to authenticated;

create or replace function public.admin_change_tribe_leader(
  p_tribe_id integer,
  p_new_leader_id uuid,
  p_reason text default 'Leadership transition'
)
returns jsonb
language plpgsql security definer as $$
declare
  v_caller record;
  v_tribe record;
  v_old_leader record;
  v_new_leader record;
  v_cycle record;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
    ) then
    raise exception 'Project management access required';
  end if;

  select * into v_tribe from public.tribes where id = p_tribe_id;
  if v_tribe is null then
    raise exception 'Tribe not found: %', p_tribe_id;
  end if;

  select * into v_new_leader from public.members where id = p_new_leader_id;
  if v_new_leader is null then
    raise exception 'New leader member not found: %', p_new_leader_id;
  end if;

  select * into v_cycle from public.cycles where is_current = true limit 1;

  if v_tribe.leader_member_id is not null then
    select * into v_old_leader from public.members where id = v_tribe.leader_member_id;

    if v_old_leader is not null then
      insert into public.member_cycle_history (
        member_id, cycle_code, cycle_label, cycle_start, cycle_end,
        operational_role, designations, tribe_id, tribe_name,
        chapter, is_active, member_name_snapshot, notes
      ) values (
        v_old_leader.id,
        coalesce(v_cycle.cycle_code, 'cycle_3'),
        coalesce(v_cycle.cycle_label, 'Ciclo 3'),
        coalesce(v_cycle.cycle_start, now()::text),
        now()::text,
        v_old_leader.operational_role,
        v_old_leader.designations,
        v_old_leader.tribe_id,
        v_tribe.name,
        v_old_leader.chapter,
        true,
        v_old_leader.name,
        'LEADER_REMOVED: Replaced by ' || v_new_leader.name || '. Reason: ' || p_reason || '. By: ' || v_caller.name
      );

      update public.members
      set operational_role = 'researcher'
      where id = v_old_leader.id
        and operational_role = 'tribe_leader';
    end if;
  end if;

  update public.members
  set operational_role = 'tribe_leader',
      tribe_id = p_tribe_id
  where id = p_new_leader_id;

  update public.tribes
  set leader_member_id = p_new_leader_id
  where id = p_tribe_id;

  insert into public.member_cycle_history (
    member_id, cycle_code, cycle_label, cycle_start, cycle_end,
    operational_role, designations, tribe_id, tribe_name,
    chapter, is_active, member_name_snapshot, notes
  ) values (
    p_new_leader_id,
    coalesce(v_cycle.cycle_code, 'cycle_3'),
    coalesce(v_cycle.cycle_label, 'Ciclo 3'),
    coalesce(v_cycle.cycle_start, now()::text),
    null,
    'tribe_leader',
    v_new_leader.designations,
    p_tribe_id,
    v_tribe.name,
    v_new_leader.chapter,
    true,
    v_new_leader.name,
    'LEADER_ASSIGNED: Promoted to leader of ' || v_tribe.name || '. Reason: ' || p_reason || '. By: ' || v_caller.name
  );

  return jsonb_build_object(
    'success', true,
    'tribe', v_tribe.name,
    'old_leader', coalesce(v_old_leader.name, 'N/A'),
    'new_leader', v_new_leader.name,
    'reason', p_reason
  );
end;
$$;

grant execute on function public.admin_change_tribe_leader(integer, uuid, text) to authenticated;

create or replace function public.admin_deactivate_tribe(
  p_tribe_id integer,
  p_reason text default 'Tribe deactivated'
)
returns jsonb
language plpgsql security definer as $$
declare
  v_caller record;
  v_tribe record;
  v_member record;
  v_cycle record;
  v_count integer := 0;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
    ) then
    raise exception 'Project management access required';
  end if;

  select * into v_tribe from public.tribes where id = p_tribe_id;
  if v_tribe is null then
    raise exception 'Tribe not found: %', p_tribe_id;
  end if;

  select * into v_cycle from public.cycles where is_current = true limit 1;

  for v_member in
    select * from public.members
    where tribe_id = p_tribe_id and current_cycle_active = true
  loop
    insert into public.member_cycle_history (
      member_id, cycle_code, cycle_label, cycle_start, cycle_end,
      operational_role, designations, tribe_id, tribe_name,
      chapter, is_active, member_name_snapshot, notes
    ) values (
      v_member.id,
      coalesce(v_cycle.cycle_code, 'cycle_3'),
      coalesce(v_cycle.cycle_label, 'Ciclo 3'),
      coalesce(v_cycle.cycle_start, now()::text),
      now()::text,
      v_member.operational_role,
      v_member.designations,
      v_member.tribe_id,
      v_tribe.name,
      v_member.chapter,
      false,
      v_member.name,
      'TRIBE_DEACTIVATED: ' || v_tribe.name || ' closed. Reason: ' || p_reason || '. By: ' || v_caller.name
    );

    update public.members
    set current_cycle_active = false,
        inactivated_at = now()
    where id = v_member.id;

    v_count := v_count + 1;
  end loop;

  return jsonb_build_object(
    'success', true,
    'tribe', v_tribe.name,
    'members_affected', v_count,
    'reason', p_reason,
    'draft_email_subject', 'Comunicado: Encerramento da Tribo ' || v_tribe.name,
    'draft_email_body', 'Prezados membros da Tribo ' || v_tribe.name || ',\n\nInformamos que a tribo foi encerrada.\nMotivo: ' || p_reason || '\n\nOs membros afetados serao realocados. Qualquer duvida, entrem em contato com a gerencia do projeto.\n\nAtenciosamente,\nGerencia do Projeto'
  );
end;
$$;

grant execute on function public.admin_deactivate_tribe(integer, text) to authenticated;

commit;
