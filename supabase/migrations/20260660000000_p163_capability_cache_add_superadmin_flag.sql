-- p163 — Extend get_caller_capabilities() to include is_superadmin flag
-- Refs: ADR-0007 — superadmin is escape hatch with no engagements; canFor() must bypass.

CREATE OR REPLACE FUNCTION public.get_caller_capabilities()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_caller_person_id uuid;
  v_is_superadmin boolean;
  v_org_actions text[];
  v_initiative_actions jsonb;
  v_tribe_actions jsonb;
BEGIN
  SELECT m.id, m.person_id, COALESCE(m.is_superadmin, false)
  INTO v_caller_member_id, v_caller_person_id, v_is_superadmin
  FROM public.members m
  WHERE m.auth_id = auth.uid()
  LIMIT 1;

  IF v_caller_person_id IS NULL THEN
    RETURN jsonb_build_object(
      'caller_id', NULL,
      'person_id', NULL,
      'is_superadmin', false,
      'org_actions', '[]'::jsonb,
      'initiative_actions', '{}'::jsonb,
      'tribe_actions', '{}'::jsonb
    );
  END IF;

  SELECT COALESCE(array_agg(DISTINCT ekp.action), ARRAY[]::text[])
  INTO v_org_actions
  FROM public.auth_engagements ae
  JOIN public.engagement_kind_permissions ekp
    ON ekp.kind = ae.kind AND ekp.role = ae.role
  WHERE ae.person_id = v_caller_person_id
    AND ae.is_authoritative = true
    AND ekp.scope IN ('organization', 'global');

  SELECT COALESCE(jsonb_object_agg(initiative_id::text, actions), '{}'::jsonb)
  INTO v_initiative_actions
  FROM (
    SELECT ae.initiative_id, array_agg(DISTINCT ekp.action ORDER BY ekp.action) AS actions
    FROM public.auth_engagements ae
    JOIN public.engagement_kind_permissions ekp
      ON ekp.kind = ae.kind AND ekp.role = ae.role
    WHERE ae.person_id = v_caller_person_id
      AND ae.is_authoritative = true
      AND ekp.scope = 'initiative'
      AND ae.initiative_id IS NOT NULL
    GROUP BY ae.initiative_id
  ) sub;

  SELECT COALESCE(jsonb_object_agg(legacy_tribe_id::text, actions), '{}'::jsonb)
  INTO v_tribe_actions
  FROM (
    SELECT ae.legacy_tribe_id, array_agg(DISTINCT ekp.action ORDER BY ekp.action) AS actions
    FROM public.auth_engagements ae
    JOIN public.engagement_kind_permissions ekp
      ON ekp.kind = ae.kind AND ekp.role = ae.role
    WHERE ae.person_id = v_caller_person_id
      AND ae.is_authoritative = true
      AND ekp.scope = 'initiative'
      AND ae.legacy_tribe_id IS NOT NULL
    GROUP BY ae.legacy_tribe_id
  ) sub;

  RETURN jsonb_build_object(
    'caller_id', v_caller_member_id,
    'person_id', v_caller_person_id,
    'is_superadmin', v_is_superadmin,
    'org_actions', to_jsonb(v_org_actions),
    'initiative_actions', v_initiative_actions,
    'tribe_actions', v_tribe_actions
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
