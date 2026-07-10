-- #1256 Wave 2: extend get_my_tribe_request_context (ADDITIVE) so the researcher-facing
-- island can offer a self-service "leave tribe" action on the has_tribe empty-state.
-- Adds current_tribe_id (legacy int) + current_tribe_initiative_id (uuid) sourced from the
-- caller's ACTIVE volunteer engagement (the initiative withdraw_from_initiative requires).
-- Legacy-only tribe_id with no active engagement (e.g. liaison / stale bridge) keeps the title
-- but returns a NULL initiative_id so the FE hides the leave action and shows the fallback.
-- Body is the live 20260805000392 body verbatim except the has_tribe block + two new keys.
CREATE OR REPLACE FUNCTION public.get_my_tribe_request_context()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_person_id uuid;
  v_member_status text;
  v_is_active boolean;
  v_tribe_id integer;
  v_has_tribe_engagement boolean;
  v_eligible boolean;
  v_reason text;
  v_current_tribe_title text;
  v_current_tribe_id integer;
  v_current_tribe_initiative_id uuid;
  v_pending jsonb;
  v_tribes jsonb;
BEGIN
  SELECT m.id, m.person_id, m.member_status, m.is_active, m.tribe_id
    INTO v_member_id, v_person_id, v_member_status, v_is_active, v_tribe_id
    FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_member_id IS NULL THEN
    RETURN jsonb_build_object('eligible', false, 'ineligible_reason', 'no_member', 'current_tribe_title', NULL, 'current_tribe_id', NULL, 'current_tribe_initiative_id', NULL, 'pending', NULL, 'tribes', '[]'::jsonb);
  END IF;

  -- caller's pending research_tribe self-request (invitee == me), if any.
  -- #1255: invitation_id added so the FE can cancel this exact pending request.
  SELECT to_jsonb(p) INTO v_pending FROM (
    SELECT ii.id AS invitation_id, i.legacy_tribe_id AS tribe_id, i.title, ii.message, ii.created_at, ii.expires_at
    FROM public.initiative_invitations ii
    JOIN public.initiatives i ON i.id = ii.initiative_id AND i.kind = 'research_tribe'
    WHERE ii.invitee_member_id = v_member_id AND ii.status = 'pending'
    ORDER BY ii.created_at DESC
    LIMIT 1
  ) p;

  -- already in a tribe via an active engagement?
  v_has_tribe_engagement := EXISTS (
    SELECT 1 FROM public.engagements e
    JOIN public.initiatives i ON i.id = e.initiative_id AND i.kind = 'research_tribe'
    WHERE e.person_id = v_person_id AND e.kind = 'volunteer' AND e.status = 'active'
  );

  -- eligible to self-request: active, termed (not pre-onboarding), no tribe yet (mirrors request_tribe_assignment)
  v_eligible := v_is_active IS TRUE
    AND v_tribe_id IS NULL
    AND NOT v_has_tribe_engagement
    AND v_person_id IS NOT NULL
    AND NOT public.member_is_pre_onboarding(v_person_id, v_member_status);

  -- #1139 Item 1: surface WHY when ineligible so the FE renders an explicit empty-state instead of a
  -- blank block. Priority mirrors request_tribe_assignment's guard sequence: inactive → has-tribe → term.
  IF v_eligible THEN
    v_reason := NULL;
  ELSIF v_person_id IS NULL THEN
    v_reason := 'no_member';
  ELSIF v_is_active IS DISTINCT FROM true THEN
    v_reason := 'inactive';
  ELSIF v_tribe_id IS NOT NULL OR v_has_tribe_engagement THEN
    v_reason := 'has_tribe';
  ELSIF public.member_is_pre_onboarding(v_person_id, v_member_status) THEN
    v_reason := 'pending_term';
  ELSE
    v_reason := 'ineligible';
  END IF;

  -- #1256: for the has_tribe empty-state, prefer the initiative where the caller holds the ACTIVE
  -- volunteer engagement — withdraw_from_initiative requires an active engagement on that initiative,
  -- so the FE's "leave tribe" action targets it. Returns tribe_id + initiative_id + title together.
  IF v_reason = 'has_tribe' THEN
    SELECT i.id, i.legacy_tribe_id, i.title
      INTO v_current_tribe_initiative_id, v_current_tribe_id, v_current_tribe_title
    FROM public.initiatives i
    JOIN public.engagements e ON e.initiative_id = i.id
      AND e.person_id = v_person_id AND e.kind = 'volunteer' AND e.status = 'active'
    WHERE i.kind = 'research_tribe'
    ORDER BY (i.legacy_tribe_id = v_tribe_id) DESC NULLS LAST, e.start_date DESC, e.created_at DESC
    LIMIT 1;

    -- legacy-only fallback: tribe_id set but no active engagement (liaison / stale bridge). Keep the
    -- title for the empty-state; leave initiative_id NULL so the FE hides the self-service leave action.
    IF v_current_tribe_title IS NULL THEN
      SELECT i.title, i.legacy_tribe_id INTO v_current_tribe_title, v_current_tribe_id
      FROM public.initiatives i
      WHERE i.kind = 'research_tribe' AND i.legacy_tribe_id = v_tribe_id
      ORDER BY i.legacy_tribe_id
      LIMIT 1;
    END IF;
  END IF;

  -- selectable active research_tribe tribes (single source of truth = initiatives, not static data)
  SELECT coalesce(
    jsonb_agg(jsonb_build_object('tribe_id', i.legacy_tribe_id, 'title', i.title) ORDER BY i.legacy_tribe_id),
    '[]'::jsonb
  ) INTO v_tribes
  FROM public.initiatives i
  WHERE i.kind = 'research_tribe' AND i.status = 'active' AND i.legacy_tribe_id IS NOT NULL;

  RETURN jsonb_build_object(
    'eligible', v_eligible,
    'ineligible_reason', v_reason,
    'current_tribe_title', v_current_tribe_title,
    'current_tribe_id', v_current_tribe_id,
    'current_tribe_initiative_id', v_current_tribe_initiative_id,
    'pending', v_pending,
    'tribes', v_tribes
  );
END;
$function$;
