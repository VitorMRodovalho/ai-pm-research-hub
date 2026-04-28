-- ADR-0061 W2 — Initiative invitation SECDEF RPCs
-- Wraps initiative_invitations table for mutations + optional engagement creation on accept.

CREATE OR REPLACE FUNCTION public.create_initiative_invitations(
  p_initiative_id uuid,
  p_invitee_member_ids uuid[],
  p_kind_scope text,
  p_message text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_member_id uuid;
  v_caller_person_id uuid;
  v_initiative record;
  v_kind_allows_owner boolean;
  v_is_admin boolean;
  v_is_owner boolean;
  v_invitee uuid;
  v_results jsonb := '[]'::jsonb;
  v_invitation_id uuid;
  v_skip_reason text;
BEGIN
  SELECT m.id, m.person_id INTO v_caller_member_id, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF length(p_message) < 50 THEN
    RAISE EXCEPTION 'Message must be at least 50 characters (current: %)', length(p_message)
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT i.* INTO v_initiative FROM public.initiatives i WHERE i.id = p_initiative_id;
  IF v_initiative.id IS NULL THEN
    RAISE EXCEPTION 'Initiative not found' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_initiative.status NOT IN ('active', 'draft') THEN
    RAISE EXCEPTION 'Initiative is not active' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.engagement_kinds ek
    WHERE ek.slug = p_kind_scope AND v_initiative.kind = ANY(ek.initiative_kinds_allowed)
  ) THEN
    RAISE EXCEPTION 'Engagement kind "%" not allowed for initiative kind "%"', p_kind_scope, v_initiative.kind
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  v_is_admin := public.can_by_member(v_caller_member_id, 'manage_member');

  IF NOT v_is_admin THEN
    v_is_owner := EXISTS (
      SELECT 1 FROM public.engagements e
      WHERE e.person_id = v_caller_person_id
        AND e.initiative_id = p_initiative_id
        AND e.status = 'active'
        AND (e.kind LIKE '%_owner' OR e.kind LIKE '%_coordinator' OR e.role IN ('owner','coordinator','lead'))
    );

    SELECT EXISTS (
      SELECT 1 FROM public.engagement_kinds ek
      WHERE ek.slug = p_kind_scope
        AND ('owner' = ANY(ek.created_by_role) OR 'coordinator' = ANY(ek.created_by_role))
    ) INTO v_kind_allows_owner;

    IF NOT (v_is_owner AND v_kind_allows_owner) THEN
      RAISE EXCEPTION 'Unauthorized: requires manage_member OR owner/coordinator of initiative AND kind_scope allows owner/coordinator creation'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  FOREACH v_invitee IN ARRAY p_invitee_member_ids
  LOOP
    v_invitation_id := NULL;
    v_skip_reason := NULL;

    IF NOT EXISTS (SELECT 1 FROM public.members WHERE id = v_invitee AND is_active = true) THEN
      v_skip_reason := 'invitee_not_active';
    ELSIF EXISTS (
      SELECT 1 FROM public.engagements e
      JOIN public.members m ON m.person_id = e.person_id
      WHERE m.id = v_invitee AND e.initiative_id = p_initiative_id AND e.status = 'active'
    ) THEN
      v_skip_reason := 'already_engaged';
    ELSIF EXISTS (
      SELECT 1 FROM public.initiative_invitations
      WHERE initiative_id = p_initiative_id AND invitee_member_id = v_invitee AND status = 'pending'
    ) THEN
      v_skip_reason := 'pending_invitation_exists';
    ELSE
      INSERT INTO public.initiative_invitations
        (initiative_id, invitee_member_id, inviter_member_id, kind_scope, message)
      VALUES
        (p_initiative_id, v_invitee, v_caller_member_id, p_kind_scope, p_message)
      RETURNING id INTO v_invitation_id;
    END IF;

    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'invitee_member_id', v_invitee,
      'invitation_id', v_invitation_id,
      'created', v_invitation_id IS NOT NULL,
      'skip_reason', v_skip_reason
    ));
  END LOOP;

  RETURN jsonb_build_object(
    'initiative_id', p_initiative_id,
    'kind_scope', p_kind_scope,
    'invitations', v_results,
    'authorized_as', CASE WHEN v_is_admin THEN 'admin' ELSE 'initiative_owner' END,
    'expires_at', (now() + interval '72 hours')
  );
END;
$$;

COMMENT ON FUNCTION public.create_initiative_invitations(uuid, uuid[], text, text) IS
  'ADR-0061 W2: batch invite to initiative. Validates caller (manage_member OR owner/coordinator) + kind_scope + initiative state. Skips invitees with active engagement or pending invitation. Returns per-invitee {created, skip_reason}.';

CREATE OR REPLACE FUNCTION public.respond_to_initiative_invitation(
  p_invitation_id uuid,
  p_response text,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_member_id uuid;
  v_caller_person_id uuid;
  v_invitation record;
  v_engagement_id uuid;
  v_org_id uuid := '2b4f58ab-7c45-4170-8718-b77ee69ff906';
BEGIN
  SELECT m.id, m.person_id INTO v_caller_member_id, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_response NOT IN ('accept', 'decline') THEN
    RAISE EXCEPTION 'Response must be "accept" or "decline" (got: %)', p_response
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT * INTO v_invitation FROM public.initiative_invitations WHERE id = p_invitation_id;
  IF v_invitation.id IS NULL THEN
    RAISE EXCEPTION 'Invitation not found' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_invitation.invitee_member_id <> v_caller_member_id THEN
    RAISE EXCEPTION 'Unauthorized: caller is not the invitee' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_invitation.status <> 'pending' THEN
    RAISE EXCEPTION 'Invitation is not pending (current status: %)', v_invitation.status
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_invitation.expires_at < now() THEN
    UPDATE public.initiative_invitations SET status = 'expired' WHERE id = p_invitation_id;
    RAISE EXCEPTION 'Invitation has expired' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  UPDATE public.initiative_invitations
  SET status = CASE WHEN p_response = 'accept' THEN 'accepted' ELSE 'declined' END,
      responded_at = now(),
      responded_note = p_note
  WHERE id = p_invitation_id;

  IF p_response = 'accept' THEN
    INSERT INTO public.engagements
      (person_id, initiative_id, kind, role, status, legal_basis, granted_by, metadata, organization_id)
    VALUES (
      v_caller_person_id,
      v_invitation.initiative_id,
      v_invitation.kind_scope,
      'participant',
      'active',
      'consent',
      v_invitation.inviter_member_id,
      jsonb_build_object(
        'source', 'invitation_accept',
        'invitation_id', p_invitation_id,
        'invited_by', v_invitation.inviter_member_id,
        'invited_at', v_invitation.created_at
      ),
      v_org_id
    )
    RETURNING id INTO v_engagement_id;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'invitation_id', p_invitation_id,
    'response', p_response,
    'engagement_id', v_engagement_id,
    'responded_at', now()
  );
END;
$$;

COMMENT ON FUNCTION public.respond_to_initiative_invitation(uuid, text, text) IS
  'ADR-0061 W2: invitee responds to initiative invitation. Auto-expires past expires_at on read. On accept: creates engagement with metadata.source=invitation_accept linking back to invitation_id. Caller must be invitee_member_id.';

NOTIFY pgrst, 'reload schema';
