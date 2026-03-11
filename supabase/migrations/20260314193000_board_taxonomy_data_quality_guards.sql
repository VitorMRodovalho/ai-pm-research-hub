-- W70: data-quality guards for board taxonomy.
create or replace function public.enforce_project_board_taxonomy()
returns trigger
language plpgsql
as $$
begin
  if new.board_scope = 'global' and new.tribe_id is not null then
    raise exception 'Global boards must not have tribe_id';
  end if;

  if new.board_scope = 'tribe' and new.tribe_id is null then
    raise exception 'Tribe boards require tribe_id';
  end if;

  if new.board_scope = 'operational' and new.tribe_id is null then
    raise exception 'Operational boards require tribe_id';
  end if;

  if coalesce(new.domain_key, '') = '' and new.board_scope in ('global', 'operational') then
    raise exception 'domain_key is required for global and operational boards';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_project_board_taxonomy on public.project_boards;
create trigger trg_enforce_project_board_taxonomy
before insert or update on public.project_boards
for each row
execute function public.enforce_project_board_taxonomy();
