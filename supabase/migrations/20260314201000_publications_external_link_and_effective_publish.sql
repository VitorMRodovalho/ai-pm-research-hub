-- W78 gap closure: external publication link and effective publish date.
alter table public.publication_submission_events
  add column if not exists external_link text null,
  add column if not exists published_at timestamptz null;

create or replace function public.upsert_publication_submission_event(
  p_board_item_id uuid,
  p_channel text default 'projectmanagement_com',
  p_submitted_at timestamptz default null,
  p_outcome text default 'pending',
  p_notes text default null,
  p_external_link text default null,
  p_published_at timestamptz default null
)
returns public.publication_submission_events
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_member public.members%rowtype;
  v_row public.publication_submission_events%rowtype;
begin
  v_actor := auth.uid();
  if v_actor is null then
    raise exception 'Auth required';
  end if;

  select * into v_member
  from public.members
  where auth_user_id = v_actor
    and is_active = true
  limit 1;

  if v_member.id is null then
    raise exception 'Member not found';
  end if;

  if not (
    coalesce(v_member.is_superadmin, false)
    or v_member.operational_role in ('manager', 'deputy_manager', 'communicator')
    or exists (
      select 1
      from unnest(coalesce(v_member.designations, array[]::text[])) d
      where d in ('curator', 'co_gp', 'comms_leader', 'comms_member')
    )
  ) then
    raise exception 'Publication workflow access required';
  end if;

  insert into public.publication_submission_events (
    board_item_id, channel, submitted_at, outcome, notes, external_link, published_at, updated_by
  ) values (
    p_board_item_id,
    coalesce(nullif(trim(p_channel), ''), 'projectmanagement_com'),
    p_submitted_at,
    p_outcome,
    nullif(trim(p_notes), ''),
    nullif(trim(p_external_link), ''),
    p_published_at,
    v_member.id
  )
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.upsert_publication_submission_event(uuid, text, timestamptz, text, text, text, timestamptz) to authenticated;
