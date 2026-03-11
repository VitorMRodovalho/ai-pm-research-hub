-- ═══════════════════════════════════════════════════════════════════════════
-- Ingestion source controls for apply-mode safety
-- Date: 2026-03-12
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create table if not exists public.ingestion_source_controls (
  source text primary key check (source in ('trello', 'notion', 'miro', 'calendar', 'volunteer_csv', 'whatsapp', 'mixed')),
  allow_apply boolean not null default false,
  require_manual_review boolean not null default true,
  notes text,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.members(id) on delete set null
);

insert into public.ingestion_source_controls (source, allow_apply, require_manual_review, notes)
values
  ('trello', true, false, 'Board imports are allowed after migration-backed controls.'),
  ('miro', true, false, 'Miro links import can run in apply mode.'),
  ('calendar', true, false, 'Calendar ingestion can run in apply mode.'),
  ('volunteer_csv', true, true, 'Contains sensitive profile data; review before apply.'),
  ('notion', false, true, 'Notion mapping requires explicit normalization review.'),
  ('whatsapp', false, true, 'Policy-blocked for automated apply.'),
  ('mixed', false, true, 'Mixed source apply requires explicit per-source policy.')
on conflict (source) do nothing;

alter table public.ingestion_source_controls enable row level security;

drop policy if exists ingestion_source_controls_read_mgmt on public.ingestion_source_controls;
create policy ingestion_source_controls_read_mgmt
on public.ingestion_source_controls
for select to authenticated
using (
  exists (
    select 1 from public.get_my_member_record() r
    where
      r.is_superadmin is true
      or r.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(r.designations), false)
  )
);

drop policy if exists ingestion_source_controls_write_mgmt on public.ingestion_source_controls;
create policy ingestion_source_controls_write_mgmt
on public.ingestion_source_controls
for all to authenticated
using (
  exists (
    select 1 from public.get_my_member_record() r
    where
      r.is_superadmin is true
      or r.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(r.designations), false)
  )
)
with check (
  exists (
    select 1 from public.get_my_member_record() r
    where
      r.is_superadmin is true
      or r.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(r.designations), false)
  )
);

create or replace function public.admin_set_ingestion_source_policy(
  p_source text,
  p_allow_apply boolean,
  p_require_manual_review boolean default true,
  p_notes text default null
)
returns jsonb
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
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
    ) then
    raise exception 'Project management access required';
  end if;

  insert into public.ingestion_source_controls (
    source, allow_apply, require_manual_review, notes, updated_by, updated_at
  )
  values (
    p_source, p_allow_apply, p_require_manual_review, nullif(trim(coalesce(p_notes, '')), ''), v_caller.id, now()
  )
  on conflict (source)
  do update set
    allow_apply = excluded.allow_apply,
    require_manual_review = excluded.require_manual_review,
    notes = excluded.notes,
    updated_by = v_caller.id,
    updated_at = now();

  return jsonb_build_object(
    'success', true,
    'source', p_source,
    'allow_apply', p_allow_apply,
    'require_manual_review', p_require_manual_review
  );
end;
$$;

grant execute on function public.admin_set_ingestion_source_policy(text, boolean, boolean, text) to authenticated;

create or replace function public.admin_get_ingestion_source_policy(
  p_source text
)
returns jsonb
language plpgsql
security definer
stable
as $$
declare
  v_caller record;
  v_row record;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      auth.role() = 'service_role'
      or v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
    ) then
    raise exception 'Project management access required';
  end if;

  select * into v_row
  from public.ingestion_source_controls
  where source = p_source
  limit 1;

  if v_row is null then
    return jsonb_build_object(
      'source', p_source,
      'allow_apply', false,
      'require_manual_review', true,
      'notes', 'No policy found; default deny.'
    );
  end if;

  return to_jsonb(v_row);
end;
$$;

grant execute on function public.admin_get_ingestion_source_policy(text) to authenticated;

commit;
