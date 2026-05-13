-- p155 Op 3 hotfix: move emoji icons from hardcoded JS to initiative_kinds.icon_emoji column.
-- Aligns with ADR-0009 ("Novos tipos de iniciativa = config no admin, não código"):
-- each kind's emoji should be admin-configurable, not buried in a JS map.
-- Page /admin/initiatives.astro now reads icon_emoji from list_initiatives kind_config.

ALTER TABLE public.initiative_kinds
  ADD COLUMN IF NOT EXISTS icon_emoji text;

COMMENT ON COLUMN public.initiative_kinds.icon_emoji IS
  'Emoji renderizado em listings de iniciativas. Editável via /admin/initiative-kinds. Complementa icon (lucide name) usado em outras superfícies. p155 Op 3 hotfix.';

UPDATE public.initiative_kinds SET icon_emoji = CASE slug
  WHEN 'research_tribe' THEN '🔬'
  WHEN 'study_group'    THEN '📖'
  WHEN 'committee'      THEN '👥'
  WHEN 'workgroup'      THEN '💼'
  WHEN 'congress'       THEN '🎤'
  WHEN 'book_club'      THEN '📚'
  WHEN 'workshop'       THEN '🛠️'
  ELSE '📌'
END
WHERE icon_emoji IS NULL;

CREATE OR REPLACE FUNCTION public.list_initiatives(p_kind text DEFAULT NULL::text, p_status text DEFAULT NULL::text)
RETURNS SETOF jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY
  SELECT jsonb_build_object(
    'id', i.id,
    'kind', i.kind,
    'title', i.title,
    'description', i.description,
    'status', i.status,
    'metadata', i.metadata,
    'parent_initiative_id', i.parent_initiative_id,
    'legacy_tribe_id', i.legacy_tribe_id,
    'created_at', i.created_at,
    'member_count', (SELECT count(*) FROM engagements e WHERE e.initiative_id = i.id AND e.status = 'active'),
    'kind_display_name', ik.display_name,
    'kind_config', jsonb_build_object(
      'display_name', ik.display_name,
      'icon', ik.icon,
      'icon_emoji', ik.icon_emoji,
      'has_board', ik.has_board,
      'has_meeting_notes', ik.has_meeting_notes,
      'has_deliverables', ik.has_deliverables,
      'has_attendance', ik.has_attendance,
      'has_certificate', ik.has_certificate
    )
  )
  FROM public.initiatives i
  JOIN public.initiative_kinds ik ON ik.slug = i.kind
  WHERE i.organization_id = public.auth_org()
    AND (p_kind IS NULL OR i.kind = p_kind)
    AND (p_status IS NULL OR i.status = p_status)
  ORDER BY i.created_at DESC;
END;
$function$;
