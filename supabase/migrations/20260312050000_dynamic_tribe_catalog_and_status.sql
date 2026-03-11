-- ═══════════════════════════════════════════════════════════════════════════
-- Dynamic tribe catalog and explicit active status
-- Date: 2026-03-12
-- ═══════════════════════════════════════════════════════════════════════════

begin;

alter table public.tribes
  add column if not exists is_active boolean not null default true;

update public.tribes
set is_active = true
where is_active is null;

create or replace function public.admin_list_tribes(
  p_include_inactive boolean default false
)
returns table (
  id integer,
  name text,
  quadrant integer,
  quadrant_name text,
  is_active boolean,
  leader_member_id uuid,
  leader_name text,
  active_members bigint,
  total_members bigint
)
language plpgsql
security definer
as $$
declare
  v_caller record;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager', 'tribe_leader')
      or coalesce('co_gp' = any(v_caller.designations), false)
    ) then
    raise exception 'Management access required';
  end if;

  return query
  select
    t.id,
    t.name,
    t.quadrant,
    t.quadrant_name,
    t.is_active,
    t.leader_member_id,
    lm.name as leader_name,
    count(m.id) filter (where m.current_cycle_active is true) as active_members,
    count(m.id) as total_members
  from public.tribes t
  left join public.members lm on lm.id = t.leader_member_id
  left join public.members m on m.tribe_id = t.id
  where p_include_inactive or t.is_active is true
  group by t.id, t.name, t.quadrant, t.quadrant_name, t.is_active, t.leader_member_id, lm.name
  order by t.id;
end;
$$;

grant execute on function public.admin_list_tribes(boolean) to authenticated;

create or replace function public.admin_upsert_tribe(
  p_id integer default null,
  p_name text default null,
  p_quadrant integer default null,
  p_quadrant_name text default null,
  p_notes text default null,
  p_is_active boolean default true,
  p_leader_member_id uuid default null,
  p_meeting_link text default null,
  p_whatsapp_url text default null,
  p_drive_url text default null,
  p_miro_url text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_id integer;
  v_exists boolean;
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

  if coalesce(trim(p_name), '') = '' then
    raise exception 'Tribe name is required';
  end if;

  if p_quadrant is null or p_quadrant < 1 or p_quadrant > 4 then
    raise exception 'Quadrant must be between 1 and 4';
  end if;

  if coalesce(trim(p_quadrant_name), '') = '' then
    raise exception 'Quadrant label is required';
  end if;

  if p_id is null then
    select coalesce(max(id), 0) + 1 into v_id from public.tribes;
    insert into public.tribes (
      id, name, quadrant, quadrant_name, notes, is_active, leader_member_id,
      meeting_link, whatsapp_url, drive_url, miro_url, updated_at, updated_by
    ) values (
      v_id, trim(p_name), p_quadrant, trim(p_quadrant_name), nullif(trim(coalesce(p_notes, '')), ''),
      coalesce(p_is_active, true), p_leader_member_id,
      nullif(trim(coalesce(p_meeting_link, '')), ''),
      nullif(trim(coalesce(p_whatsapp_url, '')), ''),
      nullif(trim(coalesce(p_drive_url, '')), ''),
      nullif(trim(coalesce(p_miro_url, '')), ''),
      now(), v_caller.id
    );
  else
    v_id := p_id;
    select exists(select 1 from public.tribes where id = v_id) into v_exists;
    if not v_exists then
      insert into public.tribes (
        id, name, quadrant, quadrant_name, notes, is_active, leader_member_id,
        meeting_link, whatsapp_url, drive_url, miro_url, updated_at, updated_by
      ) values (
        v_id, trim(p_name), p_quadrant, trim(p_quadrant_name), nullif(trim(coalesce(p_notes, '')), ''),
        coalesce(p_is_active, true), p_leader_member_id,
        nullif(trim(coalesce(p_meeting_link, '')), ''),
        nullif(trim(coalesce(p_whatsapp_url, '')), ''),
        nullif(trim(coalesce(p_drive_url, '')), ''),
        nullif(trim(coalesce(p_miro_url, '')), ''),
        now(), v_caller.id
      );
    else
      update public.tribes
      set name = trim(p_name),
          quadrant = p_quadrant,
          quadrant_name = trim(p_quadrant_name),
          notes = nullif(trim(coalesce(p_notes, '')), ''),
          is_active = coalesce(p_is_active, true),
          leader_member_id = p_leader_member_id,
          meeting_link = nullif(trim(coalesce(p_meeting_link, '')), ''),
          whatsapp_url = nullif(trim(coalesce(p_whatsapp_url, '')), ''),
          drive_url = nullif(trim(coalesce(p_drive_url, '')), ''),
          miro_url = nullif(trim(coalesce(p_miro_url, '')), ''),
          updated_at = now(),
          updated_by = v_caller.id
      where id = v_id;
    end if;
  end if;

  return jsonb_build_object(
    'success', true,
    'tribe_id', v_id,
    'name', trim(p_name),
    'is_active', coalesce(p_is_active, true)
  );
end;
$$;

grant execute on function public.admin_upsert_tribe(integer, text, integer, text, text, boolean, uuid, text, text, text, text) to authenticated;

create or replace function public.admin_set_tribe_active(
  p_tribe_id integer,
  p_is_active boolean,
  p_reason text default 'Tribe status updated'
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_tribe record;
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

  update public.tribes
  set is_active = p_is_active,
      updated_at = now(),
      updated_by = v_caller.id
  where id = p_tribe_id;

  return jsonb_build_object(
    'success', true,
    'tribe_id', p_tribe_id,
    'name', v_tribe.name,
    'is_active', p_is_active,
    'reason', p_reason
  );
end;
$$;

grant execute on function public.admin_set_tribe_active(integer, boolean, text) to authenticated;

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

  update public.tribes
  set is_active = false,
      updated_at = now(),
      updated_by = v_caller.id
  where id = p_tribe_id;

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
