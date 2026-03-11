-- W67: publication submission workflow enrichment.
create table if not exists public.publication_submission_events (
  id bigint generated always as identity primary key,
  board_item_id uuid not null references public.board_items(id) on delete cascade,
  channel text not null default 'projectmanagement_com',
  submitted_at timestamptz null,
  outcome text not null default 'pending' check (outcome in ('pending', 'submitted', 'approved', 'rejected', 'withdrawn')),
  notes text null,
  updated_by uuid not null references public.members(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists publication_submission_events_item_idx
  on public.publication_submission_events(board_item_id, created_at desc);

create or replace function public.upsert_publication_submission_event(
  p_board_item_id uuid,
  p_channel text default 'projectmanagement_com',
  p_submitted_at timestamptz default null,
  p_outcome text default 'pending',
  p_notes text default null
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
    board_item_id, channel, submitted_at, outcome, notes, updated_by
  ) values (
    p_board_item_id, coalesce(nullif(trim(p_channel), ''), 'projectmanagement_com'), p_submitted_at, p_outcome, nullif(trim(p_notes), ''), v_member.id
  )
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.upsert_publication_submission_event(uuid, text, timestamptz, text, text) to authenticated;
