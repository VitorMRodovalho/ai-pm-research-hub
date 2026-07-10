-- #1255 (Wave 1) — cancel_tribe_request: self-service cancel of a pending tribe request.
-- Gap F1 / caso 1a: a researcher who requested the wrong tribe is stuck until 72h expiry or a
-- leader decline, because request_tribe_assignment blocks a second pending request and there is no
-- cancel path. This RPC lets the requester (and only the requester) cancel their OWN pending
-- self-service request for a research_tribe.
--
-- Design: reuse status='declined' (avoids touching the status CHECK / every reader that filters
-- status) and mark it apart from a leader decline with reviewed_note='self_cancelled' so analytics
-- can filter leader declines via reviewed_note <> 'self_cancelled'. See
-- docs/specs/SPEC_TRIBE_SWITCH_AND_LEADER_REVIEW.md §Wave 1.
CREATE OR REPLACE FUNCTION public.cancel_tribe_request(p_invitation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_invitation record;
  v_initiative record;
BEGIN
  -- Validate caller (active member)
  SELECT m.id INTO v_caller_member_id
  FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_invitation FROM public.initiative_invitations WHERE id = p_invitation_id;
  IF v_invitation.id IS NULL THEN
    RAISE EXCEPTION 'Pedido não encontrado' USING ERRCODE = 'no_data_found';
  END IF;

  -- Only the requester can cancel their own request.
  IF v_invitation.invitee_member_id <> v_caller_member_id THEN
    RAISE EXCEPTION 'Não autorizado: você só pode cancelar o seu próprio pedido'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Must be a self-service request (invitee == inviter). A leader→researcher invite is
  -- responded to via respond_to_initiative_invitation('decline'), not cancelled here.
  IF v_invitation.inviter_member_id <> v_invitation.invitee_member_id THEN
    RAISE EXCEPTION 'Este não é um pedido self-service de tribo'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Must target a research_tribe initiative.
  SELECT * INTO v_initiative FROM public.initiatives WHERE id = v_invitation.initiative_id;
  IF v_initiative.kind IS DISTINCT FROM 'research_tribe' THEN
    RAISE EXCEPTION 'cancel_tribe_request só cancela pedidos de tribo'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF v_invitation.status <> 'pending' THEN
    RAISE EXCEPTION 'Pedido não está pendente (status=%)', v_invitation.status
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Reuse 'declined'; 'self_cancelled' distinguishes it from a leader decline in analytics.
  UPDATE public.initiative_invitations
  SET status = 'declined',
      reviewed_note = 'self_cancelled',
      reviewed_by = v_caller_member_id,
      reviewed_at = now(),
      responded_at = now()
  WHERE id = p_invitation_id;

  RETURN jsonb_build_object(
    'ok', true,
    'invitation_id', p_invitation_id,
    'status', 'declined',
    'cancelled', true
  );
END;
$function$;

-- Match the sibling tribe RPCs (request_tribe_assignment / review_tribe_request): revoke the
-- implicit PUBLIC grant so anon has no EXECUTE bit; authenticated keeps its explicit grant.
REVOKE ALL ON FUNCTION public.cancel_tribe_request(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_tribe_request(uuid) TO authenticated;

-- Additive change: expose the pending self-request's invitation_id so the researcher-facing card
-- (TribeRequestBlock ctx.pending) can call cancel_tribe_request(p_invitation_id). Every existing key
-- of the returned `pending` object is preserved; only `invitation_id` is added. Based on the LIVE
-- body (pg_get_functiondef) per docs/reference — do not reconstruct from an older migration.
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
  v_pending jsonb;
  v_tribes jsonb;
BEGIN
  SELECT m.id, m.person_id, m.member_status, m.is_active, m.tribe_id
    INTO v_member_id, v_person_id, v_member_status, v_is_active, v_tribe_id
    FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_member_id IS NULL THEN
    RETURN jsonb_build_object('eligible', false, 'ineligible_reason', 'no_member', 'current_tribe_title', NULL, 'pending', NULL, 'tribes', '[]'::jsonb);
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

  -- the current tribe title (only meaningful for the has_tribe empty-state)
  IF v_reason = 'has_tribe' THEN
    SELECT i.title INTO v_current_tribe_title
    FROM public.initiatives i
    WHERE i.kind = 'research_tribe'
      AND (
        i.legacy_tribe_id = v_tribe_id
        OR EXISTS (
          SELECT 1 FROM public.engagements e
          WHERE e.initiative_id = i.id AND e.person_id = v_person_id
            AND e.kind = 'volunteer' AND e.status = 'active'
        )
      )
    ORDER BY (i.legacy_tribe_id = v_tribe_id) DESC NULLS LAST
    LIMIT 1;
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
    'pending', v_pending,
    'tribes', v_tribes
  );
END;
$function$;
