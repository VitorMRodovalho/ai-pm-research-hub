-- W80: taxonomy drift alerts for board governance.
create table if not exists public.board_taxonomy_alerts (
  id bigint generated always as identity primary key,
  alert_code text not null,
  severity text not null default 'warning' check (severity in ('info', 'warning', 'critical')),
  board_id uuid null references public.project_boards(id) on delete set null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  resolved_at timestamptz null
);

create index if not exists board_taxonomy_alerts_open_idx
  on public.board_taxonomy_alerts(alert_code, resolved_at, created_at desc);

create or replace function public.admin_detect_board_taxonomy_drift()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_member public.members%rowtype;
  v_new_alerts integer := 0;
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

  if not (coalesce(v_member.is_superadmin, false) or v_member.operational_role in ('manager', 'deputy_manager')) then
    raise exception 'Admin project management access required';
  end if;

  insert into public.board_taxonomy_alerts(alert_code, severity, board_id, payload)
  select
    'GLOBAL_WITH_TRIBE',
    'critical',
    pb.id,
    jsonb_build_object('board_scope', pb.board_scope, 'tribe_id', pb.tribe_id, 'domain_key', pb.domain_key)
  from public.project_boards pb
  where pb.board_scope = 'global'
    and pb.tribe_id is not null
    and not exists (
      select 1 from public.board_taxonomy_alerts a
      where a.alert_code = 'GLOBAL_WITH_TRIBE'
        and a.board_id = pb.id
        and a.resolved_at is null
    );
  GET DIAGNOSTICS v_new_alerts = ROW_COUNT;

  insert into public.board_taxonomy_alerts(alert_code, severity, board_id, payload)
  select
    'SCOPE_DOMAIN_MISMATCH',
    'warning',
    pb.id,
    jsonb_build_object('board_scope', pb.board_scope, 'domain_key', pb.domain_key)
  from public.project_boards pb
  where pb.board_scope = 'tribe'
    and coalesce(pb.domain_key, '') not in ('', 'research_delivery', 'tribe_general')
    and not exists (
      select 1 from public.board_taxonomy_alerts a
      where a.alert_code = 'SCOPE_DOMAIN_MISMATCH'
        and a.board_id = pb.id
        and a.resolved_at is null
    );

  return jsonb_build_object(
    'success', true,
    'new_alerts_inserted', v_new_alerts,
    'open_alerts', (
      select count(*) from public.board_taxonomy_alerts where resolved_at is null
    )
  );
end;
$$;

grant execute on function public.admin_detect_board_taxonomy_drift() to authenticated;
