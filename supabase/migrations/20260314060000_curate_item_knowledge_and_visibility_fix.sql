-- ═══════════════════════════════════════════════════════════════════════════
-- Fix curate_item for knowledge_assets + visibility targeting
-- Date: 2026-03-14
-- ═══════════════════════════════════════════════════════════════════════════

begin;

drop function if exists public.curate_item(text, uuid, text, text[]);

create or replace function public.curate_item(
  p_table text,
  p_id uuid,
  p_action text,
  p_tags text[] default null,
  p_tribe_id integer default null,
  p_audience_level text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_rows integer := 0;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      v_caller.is_superadmin
      or v_caller.operational_role in ('manager', 'deputy_manager')
    ) then
    raise exception 'Admin access required';
  end if;

  if p_action not in ('approve', 'reject', 'update_tags') then
    raise exception 'Invalid action: %', p_action;
  end if;

  if p_table = 'knowledge_assets' then
    if p_action = 'approve' then
      update public.knowledge_assets
      set
        is_active = true,
        published_at = coalesce(published_at, now()),
        tags = coalesce(p_tags, tags),
        metadata = case
          when p_tribe_id is null then metadata
          else jsonb_set(coalesce(metadata, '{}'::jsonb), '{target_tribe_id}', to_jsonb(p_tribe_id), true)
        end
      where id = p_id;
    elsif p_action = 'reject' then
      update public.knowledge_assets
      set
        is_active = false,
        published_at = null
      where id = p_id;
    else
      update public.knowledge_assets
      set tags = coalesce(p_tags, tags)
      where id = p_id;
    end if;
    get diagnostics v_rows = row_count;
  elsif p_table = 'artifacts' then
    if p_action = 'approve' then
      update public.artifacts
      set
        curation_status = 'approved',
        tags = coalesce(p_tags, tags),
        tribe_id = coalesce(p_tribe_id, tribe_id)
      where id = p_id;
    elsif p_action = 'reject' then
      update public.artifacts
      set curation_status = 'rejected'
      where id = p_id;
    else
      update public.artifacts
      set
        tags = coalesce(p_tags, tags),
        tribe_id = coalesce(p_tribe_id, tribe_id)
      where id = p_id;
    end if;
    get diagnostics v_rows = row_count;
  elsif p_table = 'hub_resources' then
    if p_action = 'approve' then
      update public.hub_resources
      set
        curation_status = 'approved',
        tags = coalesce(p_tags, tags),
        tribe_id = coalesce(p_tribe_id, tribe_id)
      where id = p_id;
    elsif p_action = 'reject' then
      update public.hub_resources
      set curation_status = 'rejected'
      where id = p_id;
    else
      update public.hub_resources
      set
        tags = coalesce(p_tags, tags),
        tribe_id = coalesce(p_tribe_id, tribe_id)
      where id = p_id;
    end if;
    get diagnostics v_rows = row_count;
  elsif p_table = 'events' then
    if p_action = 'approve' then
      update public.events
      set
        curation_status = 'approved',
        tribe_id = coalesce(p_tribe_id, tribe_id),
        audience_level = coalesce(nullif(trim(coalesce(p_audience_level, '')), ''), audience_level)
      where id = p_id;
    elsif p_action = 'reject' then
      update public.events
      set curation_status = 'rejected'
      where id = p_id;
    else
      update public.events
      set
        tribe_id = coalesce(p_tribe_id, tribe_id),
        audience_level = coalesce(nullif(trim(coalesce(p_audience_level, '')), ''), audience_level)
      where id = p_id;
    end if;
    get diagnostics v_rows = row_count;
  else
    raise exception 'Invalid table: %', p_table;
  end if;

  if v_rows = 0 then
    raise exception 'Item not found: % in %', p_id, p_table;
  end if;

  return jsonb_build_object(
    'success', true,
    'table', p_table,
    'id', p_id,
    'action', p_action,
    'tribe_id', p_tribe_id,
    'audience_level', p_audience_level,
    'by', v_caller.name
  );
end;
$$;

grant execute on function public.curate_item(text, uuid, text, text[], integer, text) to authenticated;

commit;
