-- #1137 (opção a): expose curated "operational arms" (kind='workgroup' initiatives flagged as
-- landing arms) for a public landing band BELOW the research-tribe quadrants. Display-layer
-- decision (PM 2026-07-09): the Hub de Comunicação and future motor arms render FROM initiatives
-- (SSOT) — NOT promoted into the research-tribe taxonomy (the research_tribe bridge is
-- intentionally blocked in create_initiative). Curation is opt-in via metadata.landing_arm=true
-- so internal/transient workgroups (kickoff team, digital transformation, newsletter, etc.)
-- never leak onto the public homepage.
--
-- Returns ONLY public professional data already exposed via public_members (name, photo,
-- LinkedIn) plus the leadership succession window (engagements.end_date). No PII, no WhatsApp
-- (WS-A: group links are never public). Anon-safe (LGPD GC-162 / Key Architecture Decision #6).
-- Confidential initiatives are excluded (ADR-0105).
CREATE OR REPLACE FUNCTION public.get_operational_arms()
 RETURNS TABLE(
   initiative_id uuid,
   name_i18n jsonb,
   title text,
   description text,
   leader jsonb,
   team jsonb,
   has_openings boolean
 )
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT
    i.id,
    coalesce(i.metadata->'name_i18n',
             jsonb_build_object('pt', i.title, 'en', i.title, 'es', i.title)),
    i.title,
    i.description,
    (SELECT jsonb_build_object(
        'member_id', pm.id, 'name', pm.name, 'photo_url', pm.photo_url,
        'linkedin_url', pm.linkedin_url, 'end_date', e.end_date)
     FROM public.engagements e
     JOIN public.members mm ON mm.person_id = e.person_id
     JOIN public.public_members pm ON pm.id = mm.id
     WHERE e.initiative_id = i.id AND e.status = 'active' AND e.role = 'leader'
     ORDER BY e.start_date
     LIMIT 1),
    (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'member_id', pm.id, 'name', pm.name, 'photo_url', pm.photo_url,
        'linkedin_url', pm.linkedin_url, 'role', e.role)
        ORDER BY e.role, pm.name), '[]'::jsonb)
     FROM public.engagements e
     JOIN public.members mm ON mm.person_id = e.person_id
     JOIN public.public_members pm ON pm.id = mm.id
     WHERE e.initiative_id = i.id AND e.status = 'active' AND e.role <> 'leader'),
    coalesce((i.metadata->>'has_openings')::boolean, true)
  FROM public.initiatives i
  WHERE i.kind = 'workgroup'
    AND i.status = 'active'
    AND coalesce(i.visibility, 'standard') <> 'confidential'
    AND coalesce((i.metadata->>'landing_arm')::boolean, false) = true
  ORDER BY i.title;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_operational_arms() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_operational_arms() TO anon, authenticated, service_role;

-- Curation opt-in: flag the Hub de Comunicação as the first public operational arm.
UPDATE public.initiatives
SET metadata = jsonb_set(coalesce(metadata, '{}'::jsonb), '{landing_arm}', 'true'::jsonb, true)
WHERE id = '9ea82b09-55c6-4cc3-ab7f-178518d0ab47';
