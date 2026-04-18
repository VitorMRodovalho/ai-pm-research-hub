-- ADR-0015 Phase 3c — DROP COLUMN tribe_id em broadcast_log + hub_resources
--
-- Pre-req (already done in this session):
--   - 3 Edge Functions refactored to write initiative_id only:
--     send-tribe-broadcast, send-global-onboarding, send-allocation-notify
--     (deploy scheduled right after this migration applies)
--   - Frontend: KnowledgeIsland.tsx, library.astro, tribe/[id].astro refactored
--   - Script: scripts/bulk_knowledge_ingestion/2_execute_upload.ts refactored
--
-- Changes:
--   1. broadcast_history: derive tribe_id from i.legacy_tribe_id via JOIN initiatives
--   2. list_curation_board: hub_resources branch derives tribe_id via JOIN initiatives
--   3. curate_item: hub_resources branch updates initiative_id derived from p_tribe_id
--   4. search_hub_resources: derive tribe_id from i.legacy_tribe_id via JOIN initiatives
--   5. Drop policy broadcast_log_read_tribe_leader → recreate as broadcast_log_read_initiative
--   6. DROP COLUMN broadcast_log.tribe_id + hub_resources.tribe_id
--   7. Reload schema
--
-- Row state pre-migration (verified):
--   broadcast_log: 25 rows, 0 tribe_only, 0 orphans
--   hub_resources: 330 rows, 0 tribe_only, 173 neither (global), 157 both
--
-- Rollback: revert to prior migration bodies + re-add columns + FKs + backfill
-- initiative.legacy_tribe_id → tribe_id via UPDATE.

-- ── 1. broadcast_history — derive tribe_id via JOIN initiatives ──
CREATE OR REPLACE FUNCTION public.broadcast_history(p_tribe_id integer DEFAULT NULL::integer, p_limit integer DEFAULT 50)
 RETURNS TABLE(id uuid, tribe_id integer, tribe_name text, subject text, recipient_count integer, sent_at timestamp with time zone, sent_by_name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT
    bl.id,
    i.legacy_tribe_id AS tribe_id,
    i.title AS tribe_name,
    bl.subject,
    bl.recipient_count,
    bl.sent_at,
    m.name AS sent_by_name
  FROM public.broadcast_log bl
  LEFT JOIN public.initiatives i ON i.id = bl.initiative_id
  LEFT JOIN public.members m ON m.id = bl.sender_id
  WHERE (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
  ORDER BY bl.sent_at DESC
  LIMIT p_limit;
$function$;

-- ── 2. list_curation_board — hub_resources branch derives tribe_id via JOIN ──
CREATE OR REPLACE FUNCTION public.list_curation_board(p_status text DEFAULT NULL::text)
 RETURNS SETOF json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY
  SELECT row_to_json(r) FROM (
    SELECT
      a.id, a.title, a.type, a.url, a.description,
      COALESCE(a.status, 'draft') AS status,
      a.tribe_id,
      t.name AS tribe_name,
      m.name AS author_name,
      a.tags, a.submitted_at, a.reviewed_at, a.review_notes,
      'artifacts'::TEXT AS _table,
      COALESCE(a.source, 'manual') AS source,
      public.suggest_tags(a.title, a.type, a.cycle::TEXT) AS suggested_tags
    FROM artifacts a
    LEFT JOIN tribes t ON t.id = a.tribe_id
    LEFT JOIN members m ON m.id = a.member_id
    WHERE (p_status IS NULL OR a.status = p_status)
    ORDER BY a.submitted_at DESC NULLS LAST
  ) r

  UNION ALL

  SELECT row_to_json(r) FROM (
    SELECT
      hr.id, hr.title, hr.asset_type AS type, hr.url, hr.description,
      CASE WHEN hr.is_active THEN 'approved' ELSE 'pending' END AS status,
      i.legacy_tribe_id AS tribe_id,
      i.title AS tribe_name,
      m.name AS author_name,
      hr.tags, hr.created_at AS submitted_at,
      NULL::TIMESTAMPTZ AS reviewed_at,
      NULL::TEXT AS review_notes,
      'hub_resources'::TEXT AS _table,
      COALESCE(hr.source, 'manual') AS source,
      public.suggest_tags(hr.title, hr.asset_type, hr.cycle_code) AS suggested_tags
    FROM hub_resources hr
    LEFT JOIN initiatives i ON i.id = hr.initiative_id
    LEFT JOIN members m ON m.id = hr.author_id
    WHERE (p_status IS NULL
           OR (p_status = 'approved' AND hr.is_active = true)
           OR (p_status = 'pending' AND hr.is_active = false))
    ORDER BY hr.created_at DESC NULLS LAST
  ) r;
END;
$function$;

-- ── 3. curate_item — hub_resources branch updates initiative_id derived from p_tribe_id ──
CREATE OR REPLACE FUNCTION public.curate_item(p_table text, p_id uuid, p_action text, p_tags text[] DEFAULT NULL::text[], p_tribe_id integer DEFAULT NULL::integer, p_audience_level text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_caller record;
  v_rows integer := 0;
  v_enqueue_publication boolean := false;
  v_initiative_id uuid := NULL;
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

  -- Derive initiative_id once for branches that need it (hub_resources, events)
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
  elsif p_table = 'artifacts' then
    if p_action = 'approve' then
      update public.artifacts
      set
        curation_status = 'approved',
        tags = coalesce(p_tags, tags),
        tribe_id = coalesce(p_tribe_id, tribe_id)
      where id = p_id;
      v_enqueue_publication := coalesce(nullif(trim(coalesce(p_audience_level, '')), ''), '') = 'pmi_submission';
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
    -- Events table still has tribe_id (Phase 3e pending) — ADR-0015 contract requires dual-write
    if p_action = 'approve' then
      update public.events
      set
        curation_status = 'approved',
        tribe_id = coalesce(p_tribe_id, tribe_id),
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
        tribe_id = coalesce(p_tribe_id, tribe_id),
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

  if p_table = 'artifacts' and p_action = 'approve' and v_enqueue_publication then
    perform public.enqueue_artifact_publication_card(p_id, v_caller.id);
  end if;

  return jsonb_build_object(
    'success', true,
    'table', p_table,
    'id', p_id,
    'action', p_action,
    'tribe_id', p_tribe_id,
    'audience_level', p_audience_level,
    'publication_enqueued', (p_table = 'artifacts' and p_action = 'approve' and v_enqueue_publication),
    'by', v_caller.name
  );
end;
$function$;

-- ── 4. search_hub_resources — derive tribe_id via JOIN initiatives ──
CREATE OR REPLACE FUNCTION public.search_hub_resources(p_query text, p_asset_type text DEFAULT NULL::text, p_limit integer DEFAULT 15)
 RETURNS TABLE(id uuid, title text, description text, url text, asset_type text, source text, tags text[], tribe_id integer, created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND m.is_active = true
  ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    r.id,
    r.title,
    r.description,
    r.url,
    r.asset_type,
    r.source,
    r.tags,
    i.legacy_tribe_id AS tribe_id,
    r.created_at
  FROM hub_resources r
  LEFT JOIN initiatives i ON i.id = r.initiative_id
  WHERE r.is_active = true
    AND (
      r.title ILIKE '%' || p_query || '%'
      OR r.description ILIKE '%' || p_query || '%'
      OR EXISTS (
        SELECT 1 FROM unnest(r.tags) t WHERE t ILIKE '%' || p_query || '%'
      )
    )
    AND (p_asset_type IS NULL OR r.asset_type = p_asset_type)
  ORDER BY
    CASE WHEN r.title ILIKE '%' || p_query || '%' THEN 0 ELSE 1 END,
    r.created_at DESC
  LIMIT p_limit;
END;
$function$;

-- ── 5. Refactor RLS policy broadcast_log_read_tribe_leader → broadcast_log_read_initiative ──
DROP POLICY IF EXISTS broadcast_log_read_tribe_leader ON public.broadcast_log;

CREATE POLICY broadcast_log_read_initiative ON public.broadcast_log
  FOR SELECT TO authenticated
  USING (
    public.rls_is_superadmin()
    OR public.rls_can_for_initiative('write'::text, initiative_id)
  );

-- ── 6. DROP COLUMN ──
ALTER TABLE public.broadcast_log DROP COLUMN tribe_id;
ALTER TABLE public.hub_resources DROP COLUMN tribe_id;

-- ── 7. Reload schema cache ──
NOTIFY pgrst, 'reload schema';
