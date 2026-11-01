-- can(): sem recurso, o vinculo legado de tribo nao vale para view_pii e manage_member.
CREATE OR REPLACE FUNCTION public.can(
  p_person_id uuid,
  p_action text,
  p_resource_type text DEFAULT NULL,
  p_resource_id uuid DEFAULT NULL
)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.auth_engagements ae
    JOIN public.engagement_kind_permissions ekp
      ON ekp.kind = ae.kind AND ekp.role = ae.role AND ekp.action = p_action
    WHERE ae.person_id = p_person_id
      AND (
        ae.is_authoritative = true
        -- p195 carve-out: participate_in_governance_review (comment-only) does
        -- not require agreement_certificate_id; active engagement is enough.
        -- Allows PMI chapter directors, external reviewers, and leaders with
        -- pending counter-sign to comment on governance documents.
        OR (p_action = 'participate_in_governance_review' AND ae.status = 'active')
      )
      AND (
        -- Organization/global scope: always grants
        ekp.scope IN ('organization', 'global')
        -- Initiative-scoped: must match the resource
        OR (
          ekp.scope = 'initiative'
          AND ae.initiative_id IS NOT NULL
          AND (
            -- Match by initiative UUID
            ae.initiative_id = p_resource_id
            -- Match by legacy tribe_id (p_resource_id is null but engagement has tribe); not for personal-data / member-admin actions
            OR (p_resource_id IS NULL AND ae.legacy_tribe_id IS NOT NULL
                AND p_action NOT IN ('view_pii', 'manage_member'))
            -- Match by legacy tribe_id integer passed as text in resource_type
            OR (p_resource_type = 'tribe' AND ae.legacy_tribe_id = (p_resource_id::text)::integer)
          )
        )
      )
  );
$function$
