-- #697: get_member_comms_card — comms/divulgação card lookup for banners/posts.
-- Returns headshot, display name, LinkedIn, parsed credentials, and active roles
-- (for credits). Lawful basis for image use = Cláusula 11 do Termo de Voluntariado
-- (signed term), NOT persons.consent_status (different LGPD purpose — legal-counsel
-- 2026-06-15). Does NOT block when unsigned: returns comms_clearance=false + reason
-- so the controller (PMI-GO) decides usage. Excludes anonymized persons (LGPD Art.16).
-- Gate: manage_event OR manage_member (comms/event leaders + admin/GP).
-- Non-sensitive fields only (no email/phone/address). Name lookup disambiguates >1 match.

CREATE OR REPLACE FUNCTION public.get_member_comms_card(
  p_query text DEFAULT NULL,
  p_person_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_person_id uuid;
  v_can boolean;
  v_target uuid;
  v_match_count int;
  v_matches jsonb;
  v_member_id uuid;
  v_member_status text;
  v_clear boolean;
  v_reason text;
  v_like text;
BEGIN
  -- Auth. Resolve the caller's person_id: can() keys on auth_engagements.person_id
  -- (= persons.id), NOT auth.uid() — so the gate MUST pass a person_id.
  SELECT id INTO v_caller_person_id FROM public.persons WHERE auth_id = auth.uid();
  IF v_caller_person_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- Authority gate: comms/event leaders + admin/GP
  v_can := public.can(v_caller_person_id, 'manage_event', NULL, NULL)
        OR public.can(v_caller_person_id, 'manage_member', NULL, NULL);
  IF NOT v_can THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_event or manage_member');
  END IF;

  -- Resolve target person
  IF p_person_id IS NOT NULL THEN
    v_target := p_person_id;
  ELSIF p_query IS NOT NULL AND length(trim(p_query)) >= 2 THEN
    -- Escape LIKE wildcards so a caller cannot pass '%'/'_' to enumerate the directory.
    v_like := '%' || replace(replace(replace(trim(p_query), '\', '\\'), '%', '\%'), '_', '\_') || '%';

    SELECT count(*) INTO v_match_count
    FROM public.persons p
    WHERE p.anonymized_at IS NULL
      AND p.name ILIKE v_like ESCAPE '\';

    IF v_match_count = 0 THEN
      RETURN jsonb_build_object('error', 'No person found matching query');
    ELSIF v_match_count > 1 THEN
      SELECT jsonb_agg(jsonb_build_object(
               'person_id', p.id,
               'name', p.name,
               'has_photo', (p.photo_url IS NOT NULL)
             ) ORDER BY p.name)
        INTO v_matches
      FROM public.persons p
      WHERE p.anonymized_at IS NULL
        AND p.name ILIKE v_like ESCAPE '\';
      RETURN jsonb_build_object('ambiguous', true, 'match_count', v_match_count, 'matches', v_matches);
    ELSE
      SELECT p.id INTO v_target
      FROM public.persons p
      WHERE p.anonymized_at IS NULL
        AND p.name ILIKE v_like ESCAPE '\';
    END IF;
  ELSE
    RETURN jsonb_build_object('error', 'Provide person_id or query (min 2 chars)');
  END IF;

  -- Target must exist and not be anonymized
  IF NOT EXISTS (SELECT 1 FROM public.persons WHERE id = v_target AND anonymized_at IS NULL) THEN
    RETURN jsonb_build_object('error', 'Person not found');
  END IF;

  -- Comms clearance (Cláusula 11): signed term = NOT pre-onboarding for the linked member.
  SELECT m.id, m.member_status INTO v_member_id, v_member_status
  FROM public.members m
  JOIN public.persons p ON p.legacy_member_id = m.id
  WHERE p.id = v_target;

  IF v_member_id IS NULL THEN
    v_clear := false;
    v_reason := 'no_member_record';
  ELSIF public.member_is_pre_onboarding(v_target, v_member_status) THEN
    v_clear := false;
    v_reason := 'pre_onboarding';
  ELSE
    v_clear := true;
    v_reason := 'signed_term';
  END IF;

  -- Build the comms card
  RETURN (
    SELECT jsonb_build_object(
      'person_id', p.id,
      'display_name', p.name,
      'headshot_url', p.photo_url,
      'linkedin_url', p.linkedin_url,
      'credly_url', p.credly_url,
      'credentials', COALESCE((
        SELECT jsonb_agg(b->>'name' ORDER BY (b->>'issued_at') DESC)
        FROM jsonb_array_elements(COALESCE(p.credly_badges, '[]'::jsonb)) b
        WHERE b->>'name' IS NOT NULL
      ), '[]'::jsonb),
      'roles', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
                 'initiative', i.title,
                 'kind', e.kind,
                 'role', e.role
               ) ORDER BY e.granted_at DESC)
        FROM public.engagements e
        JOIN public.initiatives i ON i.id = e.initiative_id
        WHERE e.person_id = p.id AND e.status = 'active'
      ), '[]'::jsonb),
      'comms_clearance', v_clear,
      'clearance_reason', v_reason
    )
    FROM public.persons p
    WHERE p.id = v_target
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_member_comms_card(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_member_comms_card(text, uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.get_member_comms_card(text, uuid) IS
  '#697 Comms/divulgação card (headshot, name, LinkedIn, credentials, roles) for banners/posts. Gate: manage_event OR manage_member. Lawful basis = Cláusula 11 do Termo (signed term); comms_clearance flags unsigned without blocking. Excludes anonymized persons.';
