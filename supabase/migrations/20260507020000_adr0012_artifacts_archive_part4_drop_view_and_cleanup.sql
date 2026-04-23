-- ADR-0012 artifacts archival — Part 4: DROP VIEW + cleanup orphans.
-- Completes Part 3 (20260507010000 which DROPped TABLE public.artifacts CASCADE
-- and left a compat VIEW + orphan function + dead curate_item branch).
--
-- Frontend refactor Task #9 concluído (23/Abr 2026 p38):
-- - /artifacts virou redirect 301 → /publications (src/pages/artifacts.astro + en/ + es/)
-- - profile.astro:367, gamification.astro:1000, tribe/[id].astro:1651 migrados
--   para publication_submissions (primary_author_id)
-- - /publications nav gate abriu (minTier leader → visitor, sem allowedDesignations)
-- - onboarding.astro step 8 + workspace.astro card atualizados
--
-- Objetos removidos nesta Part 4:
-- 1. VIEW public.artifacts (compat backstop criada em Part 3; 29 legacy rows
--    continuam preservadas em publication_submissions com marker
--    '[Legacy artifact migrated%' em reviewer_feedback, conforme Part 1)
-- 2. FUNCTION reject_artifacts_insert() — orphan. Trigger foi auto-dropped no
--    DROP TABLE CASCADE da Part 3; função sobrou sem caller
-- 3. FUNCTION enqueue_artifact_publication_card(uuid, uuid) — deprecated per
--    Part 2 COMMENT ("Will be DROP CASCADE removed with artifacts table in
--    migration 20260504090000+"). Lê FROM public.artifacts + chamada de
--    curate_item artifacts branch (dead code)
-- 4. curate_item: excisar branch p_table='artifacts' (fazia UPDATE public.artifacts
--    que falharia em VIEW). Part 2 COMMENT prometeu "curate_item artifacts branch
--    also excised" mas não executou. Agora sim.
--
-- Rollback: VIEW + FUNCTION definitions preservadas em Part 3 migration header +
-- commit 6c58204 (Part 1 artifacts_archive migration tem definição canônica de
-- enqueue_artifact_publication_card + curate_item artifacts branch pre-Part 4).

BEGIN;

-- =============================================================================
-- 1. DROP VIEW public.artifacts
-- =============================================================================
DROP VIEW IF EXISTS public.artifacts;

-- =============================================================================
-- 2. DROP orphan trigger function (trigger já auto-dropped em Part 3)
-- =============================================================================
DROP FUNCTION IF EXISTS public.reject_artifacts_insert();

-- =============================================================================
-- 3. DROP deprecated RPC enqueue_artifact_publication_card
-- =============================================================================
DROP FUNCTION IF EXISTS public.enqueue_artifact_publication_card(uuid, uuid);

-- =============================================================================
-- 4. REPLACE curate_item sem branch 'artifacts' (UPDATE em VIEW quebraria)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.curate_item(
  p_table text,
  p_id uuid,
  p_action text,
  p_tags text[] DEFAULT NULL::text[],
  p_tribe_id integer DEFAULT NULL::integer,
  p_audience_level text DEFAULT NULL::text
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_caller record;
  v_rows integer := 0;
  v_initiative_id uuid := NULL;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      v_caller.is_superadmin
      or public.can_by_member(v_caller.id, 'manage_member')
    ) then
    raise exception 'Admin access required';
  end if;

  if p_action not in ('approve', 'reject', 'update_tags') then
    raise exception 'Invalid action: %', p_action;
  end if;

  if p_tribe_id is not null then
    SELECT id INTO v_initiative_id FROM public.initiatives WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
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
  elsif p_table = 'hub_resources' then
    if p_action = 'approve' then
      update public.hub_resources
      set
        curation_status = 'approved',
        tags = coalesce(p_tags, tags),
        initiative_id = coalesce(v_initiative_id, initiative_id)
      where id = p_id;
    elsif p_action = 'reject' then
      update public.hub_resources
      set curation_status = 'rejected'
      where id = p_id;
    else
      update public.hub_resources
      set
        tags = coalesce(p_tags, tags),
        initiative_id = coalesce(v_initiative_id, initiative_id)
      where id = p_id;
    end if;
    get diagnostics v_rows = row_count;
  elsif p_table = 'events' then
    if p_action = 'approve' then
      update public.events
      set
        curation_status = 'approved',
        initiative_id = coalesce(v_initiative_id, initiative_id),
        audience_level = coalesce(nullif(trim(coalesce(p_audience_level, '')), ''), audience_level)
      where id = p_id;
    elsif p_action = 'reject' then
      update public.events
      set curation_status = 'rejected'
      where id = p_id;
    else
      update public.events
      set
        initiative_id = coalesce(v_initiative_id, initiative_id),
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
$function$;

-- Defensivo: CREATE OR REPLACE preserva grants, mas garantir explicitamente
-- para runs limpos em novos ambientes.
GRANT EXECUTE ON FUNCTION public.curate_item(text, uuid, text, text[], integer, text) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
