-- ADR-0061 W4 — Owner approval flow para Notion-style requests + pii_access_log
-- Closes loop: candidato request_to_join → owner review_initiative_request

CREATE OR REPLACE FUNCTION public.list_invitations_for_my_initiatives(
  p_initiative_id uuid DEFAULT NULL,
  p_status_filter text DEFAULT 'pending'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_member_id uuid;
  v_caller_person_id uuid;
  v_is_admin boolean;
  v_results jsonb;
  v_invitee_ids uuid[];
BEGIN
  SELECT m.id, m.person_id INTO v_caller_member_id, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_is_admin := public.can_by_member(v_caller_member_id, 'manage_member');

  WITH owned_initiatives AS (
    SELECT DISTINCT e.initiative_id
    FROM public.engagements e
    WHERE e.person_id = v_caller_person_id
      AND e.status = 'active'
      AND (e.kind LIKE '%_owner' OR e.kind LIKE '%_coordinator' OR e.role IN ('owner','coordinator','lead'))
  ),
  filtered AS (
    SELECT ii.*, i.title AS initiative_title, m.name AS invitee_name
    FROM public.initiative_invitations ii
    JOIN public.initiatives i ON i.id = ii.initiative_id
    JOIN public.members m ON m.id = ii.invitee_member_id
    WHERE (
      v_is_admin
      OR ii.initiative_id IN (SELECT initiative_id FROM owned_initiatives)
    )
    AND (p_initiative_id IS NULL OR ii.initiative_id = p_initiative_id)
    AND (p_status_filter = 'all' OR ii.status = p_status_filter)
  )
  SELECT
    jsonb_agg(jsonb_build_object(
      'invitation_id', f.id,
      'initiative_id', f.initiative_id,
      'initiative_title', f.initiative_title,
      'invitee_member_id', f.invitee_member_id,
      'invitee_name', f.invitee_name,
      'inviter_member_id', f.inviter_member_id,
      'is_self_request', (f.invitee_member_id = f.inviter_member_id),
      'kind_scope', f.kind_scope,
      'message', f.message,
      'status', f.status,
      'expires_at', f.expires_at,
      'created_at', f.created_at,
      'reviewed_at', f.reviewed_at,
      'reviewed_note', f.reviewed_note
    ) ORDER BY f.created_at DESC),
    array_agg(DISTINCT f.invitee_member_id)
  INTO v_results, v_invitee_ids
  FROM filtered f;

  IF v_invitee_ids IS NOT NULL AND array_length(v_invitee_ids, 1) > 0 THEN
    PERFORM public.log_pii_access(
      v_caller_member_id,
      ARRAY['name']::text[],
      'list_invitations_for_my_initiatives',
      format('Owner viewing %s invitation(s) for initiative_id=%s, status=%s',
        array_length(v_invitee_ids, 1), p_initiative_id, p_status_filter)
    );
  END IF;

  RETURN COALESCE(v_results, '[]'::jsonb);
END;
$$;

COMMENT ON FUNCTION public.list_invitations_for_my_initiatives(uuid, text) IS
  'ADR-0061 W4 (#88 owner approval flow): owner/coordinator (or admin) lists pending invitations for own initiatives. is_self_request flag distinguishes self-service requests from owner-initiated invites. Logs PII access via log_pii_access (#85 Onda C). p_status_filter default pending; "all" returns all statuses.';

CREATE OR REPLACE FUNCTION public.review_initiative_request(
  p_invitation_id uuid,
  p_decision text,
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
  v_is_admin boolean;
  v_invitation record;
  v_is_owner boolean;
  v_engagement_id uuid;
  v_invitee_person_id uuid;
  v_org_id uuid := '2b4f58ab-7c45-4170-8718-b77ee69ff906';
BEGIN
  SELECT m.id, m.person_id INTO v_caller_member_id, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_decision NOT IN ('approve', 'decline') THEN
    RAISE EXCEPTION 'Decision must be "approve" or "decline" (got: %)', p_decision
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT * INTO v_invitation FROM public.initiative_invitations WHERE id = p_invitation_id;
  IF v_invitation.id IS NULL THEN
    RAISE EXCEPTION 'Invitation not found' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_invitation.status <> 'pending' THEN
    RAISE EXCEPTION 'Invitation not pending (status=%)', v_invitation.status
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_invitation.expires_at < now() THEN
    UPDATE public.initiative_invitations SET status = 'expired' WHERE id = p_invitation_id;
    RAISE EXCEPTION 'Invitation has expired' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF v_invitation.invitee_member_id <> v_invitation.inviter_member_id THEN
    RAISE EXCEPTION 'Not a self-service request — invitee should respond directly via respond_to_initiative_invitation'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  v_is_admin := public.can_by_member(v_caller_member_id, 'manage_member');

  IF NOT v_is_admin THEN
    v_is_owner := EXISTS (
      SELECT 1 FROM public.engagements e
      WHERE e.person_id = v_caller_person_id
        AND e.initiative_id = v_invitation.initiative_id
        AND e.status = 'active'
        AND (e.kind LIKE '%_owner' OR e.kind LIKE '%_coordinator' OR e.role IN ('owner','coordinator','lead'))
    );
    IF NOT v_is_owner THEN
      RAISE EXCEPTION 'Unauthorized: caller is not admin nor owner/coordinator of this initiative'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  UPDATE public.initiative_invitations
  SET status = CASE WHEN p_decision = 'approve' THEN 'accepted' ELSE 'declined' END,
      reviewed_by = v_caller_member_id,
      reviewed_at = now(),
      reviewed_note = p_note,
      responded_at = now()
  WHERE id = p_invitation_id;

  IF p_decision = 'approve' THEN
    SELECT m.person_id INTO v_invitee_person_id
    FROM public.members m WHERE m.id = v_invitation.invitee_member_id;

    INSERT INTO public.engagements
      (person_id, initiative_id, kind, role, status, legal_basis, granted_by, metadata, organization_id)
    VALUES (
      v_invitee_person_id,
      v_invitation.initiative_id,
      v_invitation.kind_scope,
      'participant',
      'active',
      'consent',
      v_caller_member_id,
      jsonb_build_object(
        'source', 'self_service_request_approved',
        'invitation_id', p_invitation_id,
        'reviewed_by', v_caller_member_id,
        'review_authority', CASE WHEN v_is_admin THEN 'admin' ELSE 'initiative_owner' END,
        'requested_at', v_invitation.created_at
      ),
      v_org_id
    )
    RETURNING id INTO v_engagement_id;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'invitation_id', p_invitation_id,
    'decision', p_decision,
    'engagement_id', v_engagement_id,
    'reviewed_by', v_caller_member_id,
    'review_authority', CASE WHEN v_is_admin THEN 'admin' ELSE 'initiative_owner' END,
    'reviewed_at', now()
  );
END;
$$;

COMMENT ON FUNCTION public.review_initiative_request(uuid, text, text) IS
  'ADR-0061 W4 (#88 owner approval): owner/coordinator (or admin) reviews self-service join request. Validates: caller authority (admin OR initiative owner/coordinator), invitation pending + not expired, self-service shape (invitee==inviter). On approve: cria engagement com source=self_service_request_approved + review_authority audit. On decline: marca declined com reviewed_by/at/note.';

NOTIFY pgrst, 'reload schema';
