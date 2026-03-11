-- Sprint UX taxonomy: stable tribe/subproject classification without frontend hardcode.

alter table if exists public.tribes
  add column if not exists workstream_type text not null default 'research';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'tribes_workstream_type_chk'
  ) then
    alter table public.tribes
      add constraint tribes_workstream_type_chk
      check (workstream_type in ('research', 'operational', 'legacy'));
  end if;
end;
$$;

-- Canonical operational mapping for comms/webinars-style ongoing fronts.
update public.tribes
set workstream_type = 'operational'
where id = 8;

update public.tribes
set workstream_type = 'operational'
where lower(coalesce(name, '')) similar to '%(comunica|comms|colabora)%';

-- Normalize remaining active tribes as research by default.
update public.tribes
set workstream_type = 'research'
where workstream_type not in ('operational', 'legacy');
